classdef testFingerprintFigures < matlab.unittest.TestCase
    methods (Test)
        function figuresRenderFromSmallFingerprint(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=50, MinCohortN=2);

            figH = graphics.fingerprintHeatmap(fp, st.statsTable);
            testCase.verifyTrue(isgraphics(figH, 'figure'));
            close(figH);

            figD = graphics.fingerprintDotPlots(fp);
            testCase.verifyTrue(isgraphics(figD, 'figure'));
            close(figD);

            figR = graphics.fingerprintRadar(fp);
            testCase.verifyTrue(isgraphics(figR, 'figure'));
            close(figR);
        end

        function heatmapContextCapKeepsFigureValid(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=50, MinCohortN=2);

            fig = graphics.fingerprintHeatmap(fp, st.statsTable, MaxContexts=1);
            testCase.verifyTrue(isgraphics(fig, 'figure'));
            close(fig);
        end

        function radarResolvesFemaleMaleSexLabels(testCase)
            % Real metadata may label sexes "Female"/"Male"; the radar must
            % resolve them and produce the same effects as with "F"/"M".
            perAnimalLong = makeSexedGenotypeTable("long");
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);

            [~, d] = graphics.fingerprintRadar(fp, InteractionThreshold=1);

            scaleW = 1.4826 * mad(10:15, 1);
            sexEffect = d(d.Kind == "sex", :);
            testCase.verifyEqual(sexEffect.Effect(1), "WT Female/Male");
            testCase.verifyEqual(sexEffect.Value, (12.5 - 22.5) / scaleW, 'AbsTol', 1e-9);

            genoHom = d(d.Kind == "genotype" & d.Effect == "HOM/WT", :);
            zHomF = (62.5 - 12.5) / scaleW;
            zHomM = (66.5 - 22.5) / scaleW;
            testCase.verifyEqual(genoHom.Value, (zHomF + zHomM) / 2, 'AbsTol', 1e-9);
            testCase.verifyTrue(all(isfinite(d.Value(d.Kind == "interaction"))));
        end

        function radarCliffsDeltaUnitMatchesHandComputation(testCase)
            % Delta mode reads effects from statsTable (genotype and
            % interaction) and computes the sex effect from per-animal
            % values. Fixture: HET F overlaps WT F so its delta is fractional.
            wtF = 10:15; wtM = 20:25; hetF = 13:18; hetM = 44:49;
            homF = 60:65; homM = 64:69;
            % makeRows values are baseValue + (0:5)', matching the vectors above.
            perAnimalLong = vertcat( ...
                makeRows("strainA", "WT", "F", {"w1","w2","w3","w4","w5","w6"}, 10, 1), ...
                makeRows("strainA", "WT", "M", {"x1","x2","x3","x4","x5","x6"}, 20, 1), ...
                makeRows("strainA", "HET", "F", {"h1","h2","h3","h4","h5","h6"}, 13, 1), ...
                makeRows("strainA", "HET", "M", {"y1","y2","y3","y4","y5","y6"}, 44, 1), ...
                makeRows("strainA", "HOM", "F", {"o1","o2","o3","o4","o5","o6"}, 60, 1), ...
                makeRows("strainA", "HOM", "M", {"z1","z2","z3","z4","z5","z6"}, 64, 1));

            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=50, MinCohortN=2);

            [~, d] = graphics.fingerprintRadar(fp, StatsTable=st.statsTable, ...
                PerAnimalLong=perAnimalLong, RadialUnit="cliffsDelta", InteractionThreshold=0.25);

            testCase.verifyTrue(all(d.Unit == "cliffsDelta"));

            dHetF = sum(sign(hetF(:) - wtF(:)'), 'all') / 36;  % 0.75 (3 ties on 13/14/15)
            genoHet = d(d.Kind == "genotype" & d.Effect == "HET/WT", :);
            testCase.verifyEqual(genoHet.Value, (dHetF + 1) / 2, 'AbsTol', 1e-12);
            genoHom = d(d.Kind == "genotype" & d.Effect == "HOM/WT", :);
            testCase.verifyEqual(genoHom.Value, 1, 'AbsTol', 1e-12);

            sexEffect = d(d.Kind == "sex", :);
            testCase.verifyEqual(sexEffect.Value, -1, 'AbsTol', 1e-12);

            intHet = d(d.Kind == "interaction" & d.Effect == "HET x sex", :);
            testCase.verifyEqual(intHet.Value, dHetF - 1, 'AbsTol', 1e-12);
            intHom = d(d.Kind == "interaction" & d.Effect == "HOM x sex", :);
            testCase.verifyEqual(intHom.Value, 0, 'AbsTol', 1e-12);
        end

        function radarEverythingHasOneSpokePerContext(testCase)
            perAnimalLong = makeLongTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);

            fig = graphics.fingerprintRadarEverything(fp);
            testCase.verifyTrue(isgraphics(fig, 'figure'));
            close(fig);

            [~, d] = graphics.fingerprintRadarEverything(fp);

            % Two contexts -> two spokes; Family column carries metric names.
            expectedCtx = ["Distance During Stimulus (cm)", "Speed Mean During Stimulus (cm/s)"];
            testCase.verifyEqual(sort(unique(d.Family)), sort(expectedCtx).');

            % No family aggregation: MUT genotype values are the per-context z.
            scaleW = 1.4826 * mad(10:15, 1);
            genoMut = d(d.Kind == "genotype", :);
            zSpeed = (22.5 - 12.5) / scaleW;
            zDist = (152.5 - 102.5) / scaleW;
            testCase.verifyEqual(sort(genoMut.Value), sort([zSpeed, zDist]).', 'AbsTol', 1e-9);

            % Delta mode also works in everything mode.
            st = cohort.fingerprintStats(perAnimalLong, fp, NPerm=50, MinCohortN=2);
            [~, dDelta] = graphics.fingerprintRadarEverything(fp, ...
                StatsTable=st.statsTable, PerAnimalLong=perAnimalLong, RadialUnit="cliffsDelta");
            testCase.verifyTrue(all(dDelta.Unit == "cliffsDelta"));
            testCase.verifyEqual(height(dDelta), height(d));
        end

        function radarFamilyModeAggregatesSameFamilyContexts(testCase)
            % Two contexts, one family: family mode must average their z.
            % (Regression: the group mask once compared groups to groups
            % instead of mapping groups to contexts, which only surfaced
            % when family count != context count.)
            mk = @(g, pfx, base) makeRows("strainA", g, "F", ...
                arrayfun(@(k) sprintf('%s%d', pfx, k), 1:6, 'UniformOutput', false), base, 1);
            perAnimalLong = vertcat( ...
                mk("WT", "w", 10), mk("MUT", "m", 20), ...
                mk("WT", "x", 10), mk("MUT", "y", 30));
            perAnimalLong.Metric(1:12) = "Speed Mean During Stimulus (cm/s)";
            perAnimalLong.Metric(13:24) = "Speed Mean During Pre-Stimulus (cm/s)";

            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);
            fig = graphics.fingerprintRadar(fp);
            testCase.verifyTrue(isgraphics(fig, 'figure'));
            close(fig);

            [~, d] = graphics.fingerprintRadar(fp);
            testCase.verifyEqual(unique(d.Family), "Speed Mean");
            scaleW = 1.4826 * mad(10:15, 1);
            zStim = (22.5 - 12.5) / scaleW;
            zPre = (32.5 - 12.5) / scaleW;
            genoMut = d(d.Kind == "genotype", :);
            testCase.verifyEqual(genoMut.Value(:), mean([zStim, zPre]), 'AbsTol', 1e-9);
        end

        function radarDeltaWithoutStatsTableFallsBackToZ(testCase)
            perAnimalLong = makeSexedGenotypeTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);

            testCase.verifyWarning(@() graphics.fingerprintRadar(fp, RadialUnit="cliffsDelta"), ...
                'graphics:fingerprintRadar:MissingStatsTable');

            [~, d] = graphics.fingerprintRadar(fp, RadialUnit="cliffsDelta", ...
                InteractionThreshold=0); % silence: values asserted in z-mode test
            testCase.verifyTrue(all(d.Unit == "z"));
        end

        function radarReportsGenotypeSexAndInteractionEffects(testCase)
            perAnimalLong = makeSexedGenotypeTable();
            fp = cohort.fingerprint(perAnimalLong, MinCohortN=2, NBoot=50);

            fig = graphics.fingerprintRadar(fp, InteractionThreshold=1);
            testCase.verifyTrue(isgraphics(fig, 'figure'));
            close(fig);

            [~, d] = graphics.fingerprintRadar(fp, InteractionThreshold=1);
            testCase.verifyEqual(unique(d.Strain), "strainA");
            testCase.verifyEqual(unique(d.Family), "Speed Mean");
            testCase.verifyTrue(all(ismember(["genotype", "sex", "interaction"], unique(d.Kind))));

            % Hand-computed effects. WT F 10:15 (median 12.5), WT M 20:25
            % (median 22.5); both robust scales = 1.4826 * mad = 2.2239.
            scaleW = 1.4826 * mad(10:15, 1);
            zHetF = (42.5 - 12.5) / scaleW;
            zHetM = (46.5 - 22.5) / scaleW;
            zHomF = (62.5 - 12.5) / scaleW;
            zHomM = (66.5 - 22.5) / scaleW;

            genoHom = d(d.Kind == "genotype" & d.Effect == "HOM/WT", :);
            testCase.verifyEqual(genoHom.Value, (zHomF + zHomM) / 2, 'AbsTol', 1e-9);
            genoHet = d(d.Kind == "genotype" & d.Effect == "HET/WT", :);
            testCase.verifyEqual(genoHet.Value, (zHetF + zHetM) / 2, 'AbsTol', 1e-9);

            sexEffect = d(d.Kind == "sex", :);
            testCase.verifyEqual(sexEffect.Effect(1), "WT F/M");
            testCase.verifyEqual(sexEffect.Value, (12.5 - 22.5) / scaleW, 'AbsTol', 1e-9);

            % Interactions exceed the threshold of 1: HET 2.698, HOM 2.698.
            intHet = d(d.Kind == "interaction" & d.Effect == "HET x sex", :);
            testCase.verifyEqual(intHet.Value, zHetF - zHetM, 'AbsTol', 1e-9);
            intHom = d(d.Kind == "interaction" & d.Effect == "HOM x sex", :);
            testCase.verifyEqual(intHom.Value, zHomF - zHomM, 'AbsTol', 1e-9);
        end
    end
end


function perAnimalLong = makeLongTable()
    wtIds = {"w1", "w2", "w3", "w4", "w5", "w6"};
    mutIds = {"m1", "m2", "m3", "m4", "m5", "m6"};

    speedWt = makeRows("strainA", "WT", "F", wtIds, 10, 1);
    speedMut = makeRows("strainA", "MUT", "F", mutIds, 20, 1);
    distWt = makeRows("strainA", "WT", "F", wtIds, 100, 1);
    distMut = makeRows("strainA", "MUT", "F", mutIds, 150, 1);
    distWt.Metric = repmat("Distance During Stimulus (cm)", height(distWt), 1);
    distMut.Metric = repmat("Distance During Stimulus (cm)", height(distMut), 1);

    perAnimalLong = vertcat(speedWt, speedMut, distWt, distMut);
end


function rows = makeRows(strainName, genotype, sex, ids, baseValue, protocol)
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
    rows.Value = baseValue + (0:n-1)';
end


function perAnimalLong = makeSexedGenotypeTable(sexStyle)
    % One strain, {WT, HET, HOM} x {F, M}, 6 animals each, single context:
    %   WT F 10:15, WT M 20:25, HET F 40:45, HET M 44:49,
    %   HOM F 60:65, HOM M 64:69 (median = base + 2.5).
    % sexStyle "long" labels the sexes "Female"/"Male" instead of "F"/"M".
    if nargin < 1
        sexStyle = "short";
    end
    if sexStyle == "long"
        sexF = "Female";
        sexM = "Male";
    else
        sexF = "F";
        sexM = "M";
    end
    spec = { ...
        "WT", sexF, "w", 10; ...
        "WT", sexM, "x", 20; ...
        "HET", sexF, "h", 40; ...
        "HET", sexM, "y", 44; ...
        "HOM", sexF, "o", 60; ...
        "HOM", sexM, "z", 64};
    parts = cell(size(spec, 1), 1);
    for r = 1:size(spec, 1)
        ids = arrayfun(@(k) sprintf('%s%d', spec{r, 3}, k), 1:6, 'UniformOutput', false);
        parts{r} = makeRows("strainA", spec{r, 1}, spec{r, 2}, ids, spec{r, 4}, 1);
    end
    perAnimalLong = vertcat(parts{:});
end
