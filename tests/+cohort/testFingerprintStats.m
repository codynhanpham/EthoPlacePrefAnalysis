classdef testFingerprintStats < matlab.unittest.TestCase
    methods (Test)
        function zMatchesHandComputation(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);

            wtVals = [10; 11; 12; 13; 14; 15];
            mutVals = [20; 21; 22; 23; 24; 25];
            expectedZ = (median(mutVals) - median(wtVals)) / (1.4826 * mad(wtVals, 1));

            sel = fp.cohortTable.Genotype == "MUT" & fp.cohortTable.Sex == "F" & ...
                fp.cohortTable.Metric == "Speed Mean During Stimulus (cm/s)" & ~fp.cohortTable.PooledSex;
            testCase.verifyEqual(fp.cohortTable.Z(sel), expectedZ, 'AbsTol', 1e-12);
            testCase.verifyTrue(all(fp.cohortTable.statsEligible(sel)));
        end

        function cliffsDeltaAndPermutationOnPerfectSeparation(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=200, MinCohortN=2);

            sel = st.statsTable.Genotype == "MUT" & st.statsTable.Metric == "Speed Mean During Stimulus (cm/s)";
            testCase.verifyEqual(st.statsTable.CliffDelta(sel), 1, 'AbsTol', 1e-12);
            testCase.verifyLessThan(st.statsTable.PPerm(sel), 0.01);
            testCase.verifyGreaterThanOrEqual(st.statsTable.QFDR(sel), 0);
            testCase.verifyLessThanOrEqual(st.statsTable.QFDR(sel), 1);
        end

        function minCohortNGatingExcludesSmallCohorts(testCase)
            perAnimalLong = makeLongTable();
            % Add a 1-animal genotype cohort.
            perAnimalLong = [perAnimalLong; makeRows("strainA", "HET", "F", {"x1"}, 30, 31, 2)];

            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);

            sel = fp.cohortTable.Genotype == "HET" & ~fp.cohortTable.PooledSex;
            testCase.verifyTrue(all(~fp.cohortTable.statsEligible(sel)));
            testCase.verifyTrue(all(contains(string(fp.cohortTable.Reason(sel)), "cohortBelowN")));

            % zMatrix rows contain only eligible cohorts.
            rowGenos = string(fp.rowLabels.Genotype);
            testCase.verifyFalse(ismember("HET", rowGenos));
        end

        function pooledSexRowsAreFlaggedAndExcluded(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100, IncludePooledSex=true);

            pooled = fp.cohortTable(fp.cohortTable.PooledSex, :);
            testCase.verifyEqual(unique(string(pooled.Sex)), "ALL");
            testCase.verifyTrue(all(pooled.Reason == "pooledSex"));
            testCase.verifyTrue(all(~pooled.statsEligible));
            testCase.verifyTrue(all(string(fp.rowLabels.Sex) ~= "ALL"));
        end

        function referenceGenotypeByStrainFallback(testCase)
            perAnimalLong = [makeLongTable(); makeRows("strainB", "HET", "F", {"h1", "h2", "h3", "h4", "h5", "h6"}, 10, 11, 2); ...
                makeRows("strainB", "MUT", "F", {"b1", "b2", "b3", "b4", "b5", "b6"}, 30, 31, 2)];

            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100, ...
                ReferenceGenotypeByStrain={'strainB', 'HET'});

            testCase.verifyEqual(string(fp.referenceMap.ReferenceGenotype(fp.referenceMap.Strain == "strainB")), "HET");
            testCase.verifyEqual(string(fp.referenceMap.ReferenceGenotype(fp.referenceMap.Strain == "strainA")), "WT");

            % strainB MUT uses strainB HET as reference, not strainB WT (absent).
            sel = fp.cohortTable.Strain == "strainB" & fp.cohortTable.Genotype == "MUT" & ...
                ~fp.cohortTable.PooledSex & fp.cohortTable.Metric == "Speed Mean During Stimulus (cm/s)";
            hetVals = [10; 11; 12; 13; 14; 15];
            mutVals = [30; 31; 32; 33; 34; 35]; % makeRows offsets by 0:5 from 30
            expectedZ = (median(mutVals) - median(hetVals)) / (1.4826 * mad(hetVals, 1));
            testCase.verifyEqual(fp.cohortTable.Z(sel), expectedZ, 'AbsTol', 1e-12);
        end

        function degenerateReferenceYieldsRefDegenerate(testCase)
            perAnimalLong = makeLongTable();
            % WT reference constant within this metric context.
            constRows = makeConstRows("Speed Mean During Stimulus (cm/s)");
            perAnimalLong = replaceMetricRows(perAnimalLong, constRows);

            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);

            sel = fp.cohortTable.Genotype == "MUT" & ~fp.cohortTable.PooledSex & ...
                fp.cohortTable.Metric == "Speed Mean During Stimulus (cm/s)";
            testCase.verifyTrue(all(string(fp.cohortTable.Reason(sel)) == "refDegenerate"));
            testCase.verifyTrue(all(isnan(fp.cohortTable.Z(sel))));
        end

        function perAnimalZHasSubjectsAsRows(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);

            testCase.verifyEqual(height(fp.perAnimalZ), 12);
            testCase.verifyEqual(width(fp.zMatrix), height(fp.colLabels));
            testCase.verifyEqual(height(fp.zMatrix), height(fp.rowLabels));
        end

        function qfdrMatchesReferenceBhImplementation(testCase)
            % Regression for the monotonicity-direction bug: QFDR must equal
            % a reference BH implementation, with larger p keeping larger q
            % (no collapse toward the smallest q).
            perAnimalLong = makeGradedSeparationTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=100);
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=200, MinCohortN=2);

            testCase.verifyTrue(height(st.statsTable) >= 3);
            % BH is applied per comparison group; compare within one group.
            sel = st.statsTable.Genotype == "MUT";
            q = st.statsTable.QFDR(sel);
            p = st.statsTable.PPerm(sel);
            testCase.verifyEqual(q, referenceBh(p), 'AbsTol', 1e-12);
            testCase.verifyGreaterThan(max(q), min(q));
            [pSorted, order] = sort(p, 'ascend');
            testCase.verifyTrue(all(diff(q(order)) >= -1e-12), ...
                'QFDR must be monotone non-decreasing in p');
            testCase.verifyTrue(all(q(order) >= pSorted(:) - 1e-12));
        end
    end
end


function rows = makeRows(strainName, genotype, sex, ids, value1, value2, protocol)
    n = numel(ids);
    rows = table();
    rows.SubjectKey = compose("%s|%s|%s|C1|%s", repmat(string(strainName), n, 1), repmat(string(genotype), n, 1), repmat(string(sex), n, 1), string(ids)');
    rows.Gene = repmat(string(strainName), n, 1);
    rows.('Genotype$') = repmat(string(genotype), n, 1);
    rows.('Sex$') = repmat(string(sex), n, 1);
    rows.Litter = repmat("L1", n, 1);
    rows.('Cage #') = repmat("C1", n, 1);
    rows.Age = ones(n, 1) * 10;
    rows.Tier = repmat(categorical("stim_all"), n, 1);
    rows.Protocol = repmat(categorical(string(protocol)), n, 1);
    rows.Stimulus = repmat("ALL", n, 1);
    rows.Metric = repmat("Speed Mean During Stimulus (cm/s)", n, 1);
    rows.Value = value1 + (0:n-1)';
end


function perAnimalLong = makeLongTable()
    wtIds = {"w1", "w2", "w3", "w4", "w5", "w6"};
    mutIds = {"m1", "m2", "m3", "m4", "m5", "m6"};

    speedWt = makeRows("strainA", "WT", "F", wtIds, 10, 0, 1);
    speedMut = makeRows("strainA", "MUT", "F", mutIds, 20, 0, 1);

    distWt = makeRows("strainA", "WT", "F", wtIds, 100, 0, 1);
    distWt.Metric = repmat("Distance During Stimulus (cm)", height(distWt), 1);
    distMut = makeRows("strainA", "MUT", "F", mutIds, 150, 0, 1);
    distMut.Metric = repmat("Distance During Stimulus (cm)", height(distMut), 1);

    perAnimalLong = vertcat(speedWt, speedMut, distWt, distMut);
end


function rows = makeConstRows(metricName)
    ids = {"w1", "w2", "w3", "w4", "w5", "w6"};
    rows = makeRows("strainA", "WT", "F", ids, 7, 0, 1);
    rows.Metric = repmat(string(metricName), height(rows), 1);
    rows.Value = ones(height(rows), 1) * 7;
end


function perAnimalLong = makeGradedSeparationTable()
    % One strain, WT vs MUT, four metric contexts with graded separations so
    % the permutation p-values span a wide range.
    wtIds = {"w1", "w2", "w3", "w4", "w5", "w6"};
    mutIds = {"m1", "m2", "m3", "m4", "m5", "m6"};
    metricNames = ["Speed Mean During Stimulus (cm/s)"; "Distance During Stimulus (cm)"; ...
        "Tortuosity During Stimulus (path/net)"; "Occupancy Entropy During Stimulus (bits)"];
    offsets = [0, 1, 3, 8];

    parts = {};
    for k = 1:numel(metricNames)
        wtRows = makeRows("strainA", "WT", "F", wtIds, 10, 0, 1);
        wtRows.Metric = repmat(metricNames(k), height(wtRows), 1);
        mutRows = makeRows("strainA", "MUT", "F", mutIds, 10 + offsets(k), 0, 1);
        mutRows.Metric = repmat(metricNames(k), height(mutRows), 1);
        parts{end+1} = wtRows; %#ok<AGROW>
        parts{end+1} = mutRows; %#ok<AGROW>
    end
    perAnimalLong = vertcat(parts{:});
end


function q = referenceBh(p)
    % Independent reference BH implementation used only for verification.
    p = p(:);
    valid = isfinite(p);
    q = nan(size(p));
    if ~any(valid)
        return;
    end

    pv = p(valid);
    m = numel(pv);
    [pvSorted, order] = sort(pv, 'ascend');
    qRaw = pvSorted .* m ./ (1:m)';
    qValid = nan(m, 1);
    for i = m:-1:1
        if i == m
            qValid(i) = qRaw(i);
        else
            qValid(i) = min(qRaw(i), qValid(i+1));
        end
    end
    qValid = min(qValid, 1);
    qRef = nan(m, 1);
    qRef(order) = qValid;
    q(valid) = qRef;
end


function perAnimalLong = replaceMetricRows(perAnimalLong, constRows)
    metricName = constRows.Metric(1);
    perAnimalLong = perAnimalLong(string(perAnimalLong.Metric) ~= metricName, :);
    perAnimalLong = [perAnimalLong; constRows];
end
