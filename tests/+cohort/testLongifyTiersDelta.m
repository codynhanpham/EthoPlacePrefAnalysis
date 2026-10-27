classdef testLongifyTiersDelta < matlab.unittest.TestCase
    methods (Test)
        function tiersAndDeltaAreTaggedCorrectly(testCase)
            [wideStim, widePre] = makeWideFixture();

            long = cohort.longify(wideStim, widePre, ...
                ProtocolLabels={"p1.flac", "p2.flac"}, StimLabels=["A", "B"]);

            requiredCols = {'SubjectKey', 'Tier', 'Protocol', 'Period', 'Stimulus', 'Metric', 'Value', 'Gene'};
            for i = 1:numel(requiredCols)
                testCase.verifyTrue(ismember(requiredCols{i}, long.Properties.VariableNames), ...
                    ['Missing column: ' requiredCols{i}]);
            end

            tiers = categories(long.Tier);
            testCase.verifyTrue(ismember('exploration', tiers));
            testCase.verifyTrue(ismember('baseline', tiers));
            testCase.verifyTrue(ismember('stim_all', tiers));
            testCase.verifyTrue(ismember('per-stim', tiers));
            testCase.verifyTrue(ismember('delta', tiers));

            % Exploration = pre-stim rows of protocol 1 only; baseline = protocol 2 only.
            exploration = long(long.Tier == 'exploration', :);
            testCase.verifyEqual(unique(exploration.Protocol), categorical("1"));
            testCase.verifyEqual(unique(string(exploration.Period)), "pre-stimulus");
            baseline = long(long.Tier == 'baseline', :);
            testCase.verifyEqual(unique(baseline.Protocol), categorical("2"));

            % Per-stim classification: 'Speed Mean During A' is per-stim A.
            speedA = long(string(long.Metric) == "Speed Mean During A (cm/s)" & long.Tier == 'per-stim', :);
            testCase.verifyEqual(height(speedA), 4); % 2 subjects x 2 protocols
            testCase.verifyEqual(unique(string(speedA.Stimulus)), "A");

            % Delta arithmetic: stim value minus the subject's OWN protocol-2
            % baseline value (M1 baseline = 2, M2 baseline = 4).
            delta = long(string(long.Metric) == "Speed Mean During Stimulus (cm/s)" & long.Tier == 'delta', :);
            testCase.verifyEqual(height(delta), 4);
            testCase.verifyEqual(delta.Value(delta.SubjectKey == "strainA|WT|F|C1|M1" & delta.Protocol == categorical("1")), 5 - 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(delta.Value(delta.SubjectKey == "strainA|WT|F|C1|M1" & delta.Protocol == categorical("2")), 6 - 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(delta.Value(delta.SubjectKey == "strainA|MUT|F|C1|M2" & delta.Protocol == categorical("1")), 7 - 4, 'AbsTol', 1e-12);
            testCase.verifyEqual(delta.Value(delta.SubjectKey == "strainA|MUT|F|C1|M2" & delta.Protocol == categorical("2")), 9 - 4, 'AbsTol', 1e-12);

            % Bout columns get no delta rows; Min columns stay in the raw layer.
            testCase.verifyFalse(any(string(long.Metric) == "Speed Min During First A Bout (cm/s)" & long.Tier == 'delta'));
            testCase.verifyTrue(any(string(long.Metric) == "Speed Min During Stimulus (cm/s)"));

            % Side-occupancy per-stim columns pair with their pre-stim counterparts.
            deltaStay = long(string(long.Metric) == "Percent Time on A Side During Active Stimulus (%)" & long.Tier == 'delta', :);
            testCase.verifyEqual(height(deltaStay), 4);

            % Aggregate preference-index columns must classify stim_all (not
            % per-stim via the reference-stim label) and pair with the
            % aggregate pre-stimulus baseline.
            prefAgg = long(string(long.Metric) == "A Preference Index During Active Stimulus" & long.Tier == 'stim_all', :);
            testCase.verifyEqual(height(prefAgg), 4);
            prefDelta = long(string(long.Metric) == "A Preference Index During Active Stimulus" & long.Tier == 'delta', :);
            testCase.verifyEqual(height(prefDelta), 4);
            testCase.verifyEqual(prefDelta.Value(prefDelta.SubjectKey == "strainA|WT|F|C1|M1" & prefDelta.Protocol == categorical("1")), 0.25 - 0.1, 'AbsTol', 1e-12);
        end

        function longifyRejectsMissingBaseline(testCase)
            [wideStim, widePre] = makeWideFixture();
            keep = widePre.('Stimulus Protocol') ~= "p2.flac";
            widePre = widePre(keep, :);

            testCase.verifyError(@() cohort.longify(wideStim, widePre, ...
                ProtocolLabels={"p1.flac", "p2.flac"}, StimLabels=["A", "B"]), ...
                'cohort:longify:MissingBaselineRows');
        end
    end
end


function [wideStim, widePre] = makeWideFixture()
    % 2 subjects x 2 protocols (4 rows each).
    ids = {'M1'; 'M1'; 'M2'; 'M2'};
    genes = {'strainA'; 'strainA'; 'strainA'; 'strainA'};
    cages = {'C1'; 'C1'; 'C1'; 'C1'};
    geneIds = {'G1'; 'G1'; 'G2'; 'G2'};
    sexes = {'F'; 'F'; 'F'; 'F'};
    genotypes = {'WT'; 'WT'; 'MUT'; 'MUT'};
    litters = {'L1'; 'L1'; 'L2'; 'L2'};
    toes = {'T1'; 'T1'; 'T2'; 'T2'};
    dobs = {'2020-01-01'; '2020-01-01'; '2020-01-02'; '2020-01-02'};
    ages = [10; 10; 10; 10];
    protocols = {'p1.flac'; 'p2.flac'; 'p1.flac'; 'p2.flac'};

    wideStim = makeWideTable(ids, genes, cages, geneIds, sexes, genotypes, litters, toes, dobs, ages, protocols, ...
        'Speed Mean During Stimulus (cm/s)', [5; 6; 7; 9], ...
        'Speed Mean During A (cm/s)', [4; 5; 6; 8], ...
        'Percent Time on A Side During Active Stimulus (%)', [60; 58; 56; 54]);

    widePre = makeWideTable(ids, genes, cages, geneIds, sexes, genotypes, litters, toes, dobs, ages, protocols, ...
        'Speed Mean During Pre-Stimulus (cm/s)', [1; 2; 3; 4], ...
        'Speed Mean During A (cm/s)', [10; 10; 10; 10], ... % intentionally absent counterpart name
        'Percent Time on A Side During Pre-Stimulus (%)', [50; 50; 50; 52]);
    widePre.('A Preference Index During Pre-Stimulus') = [0.1; 0.1; 0.1; 0.1];

    wideStim.('A Preference Index During Active Stimulus') = [0.25; 0.3; 0.35; 0.4];
end


function t = makeWideTable(ids, genes, cages, geneIds, sexes, genotypes, litters, toes, dobs, ages, protocols, metricName1, metricVals1, metricName2, metricVals2, metricName3, metricVals3)
    t = table();
    t.('Mouse_ID') = ids;
    t.('Gene') = genes;
    t.('Cage #') = cages;
    t.('Gene_ID') = geneIds;
    t.('Sex$') = sexes;
    t.('Genotype$') = genotypes;
    t.('Litter') = litters;
    t.('Toe_ID') = toes;
    t.('DOB') = dobs;
    t.('Age') = ages;
    t.('Stimulus Protocol') = protocols;

    t.(metricName1) = metricVals1;
    t.('Speed Min During Stimulus (cm/s)') = metricVals1 - 1;
    t.(metricName2) = metricVals2;
    t.('Speed Min During First A Bout (cm/s)') = metricVals1 - 2;
    t.('Speed Mean Last-First During A Bouts (cm/s)') = metricVals1 - 3;
    t.(metricName3) = metricVals3;
    t.('Distance During Pre-Stimulus (cm)') = [120; 130; 140; 150];
end
