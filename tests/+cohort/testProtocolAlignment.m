classdef testProtocolAlignment < matlab.unittest.TestCase
    methods (Test)
        function stimfileNameVariantsHandlesJoinedTables(testCase)
            v1 = cohort.internal.stimfileNameVariants('a.flac');
            testCase.verifyEqual(v1, string("a.flac"));

            v2 = cohort.internal.stimfileNameVariants({'20260204_a_v3d.flac'; '20260204_a_v3.flac'});
            testCase.verifyEqual(numel(v2), 2);
            testCase.verifyEqual(v2(2), "20260204_a_v3.flac");

            % 1x1 nested cells unwrap; string arrays pass through.
            v3 = cohort.internal.stimfileNameVariants({{'nested.flac'}; "plain.flac"});
            testCase.verifyEqual(v3, ["nested.flac"; "plain.flac"]);

            testCase.verifyError(@() cohort.internal.stimfileNameVariants(42), ...
                'cohort:internal:stimfileNameVariants:NotText');
        end

        function protocolKeyCollapsesVariationsToDateAndVersion(testCase)
            k1 = cohort.internal.protocolKey('20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac');
            k2 = cohort.internal.protocolKey('20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac');
            testCase.verifyEqual(k1, k2);
            testCase.verifyEqual(k1, "normal-whitenoise_27x_[5-10s]isi");

            % Different dates and versions of the same family still collapse.
            k3 = cohort.internal.protocolKey('20260312_Normal-WhiteNoise_27x_[5-10s]ISI_v3e.flac');
            testCase.verifyEqual(k3, k1);

            % A different protocol stays distinct.
            k4 = cohort.internal.protocolKey('20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac');
            testCase.verifyNotEqual(k4, k1);
            testCase.verifyEqual(k4, "normal-inverted_27x_[5-10s]isi");
        end

        function levenshteinRatioBasics(testCase)
            testCase.verifyEqual(cohort.internal.levenshteinRatio("abc", "abc"), 1);
            % kitten -> sitting: distance 3 over length 7.
            testCase.verifyEqual(cohort.internal.levenshteinRatio("kitten", "sitting"), 1 - 3/7, 'AbsTol', 1e-12);
            testCase.verifyEqual( ...
                cohort.internal.levenshteinRatio("sitting", "kitten"), ...
                cohort.internal.levenshteinRatio("kitten", "sitting"));
            testCase.verifyEqual(cohort.internal.levenshteinRatio("abc", ""), 0);
        end

        function alignProtocolSlotsSwapsFlippedGroups(testCase)
            pairA = makeNamedPair("strainA", ...
                '20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac', ...
                {'20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac'; '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac'});
            pairB = makeNamedPair("strainB", ...
                '20260312_Normal-WhiteNoise_27x_[5-10s]ISI_v3e.flac', ...   % flipped: baseline family first
                '20260202_Normal-Inverted_27x_[5-10s]ISI_v2b.flac');

            groups = {struct('tables', pairA, 'strainLabel', "strainA"), ...
                struct('tables', pairB, 'strainLabel', "strainB")};

            [aligned, report] = cohort.internal.alignProtocolSlots(groups);

            testCase.verifyTrue(report.Swapped(2));
            testCase.verifyFalse(report.Swapped(1));
            testCase.verifyEqual(report.Slot1Similarity(2), 1, 'AbsTol', 1e-12);
            testCase.verifyEqual(report.Slot2Similarity(2), 1, 'AbsTol', 1e-12);

            % After alignment, strain B slot 1 is the Inverted-family protocol.
            slot1Name = cohort.internal.stimfileNameVariants(aligned{2}.tables(1).stimfileName);
            testCase.verifyTrue(contains(slot1Name(1), "Inverted", 'IgnoreCase', true));
        end

        function alignProtocolSlotsWarnsOnDissimilarProtocols(testCase)
            pairA = makeNamedPair("strainA", ...
                '20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac', ...
                '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac');
            pairB = makeNamedPair("strainB", ...
                '20260131_totally_other_protocol_x9.flac', ...
                '20260131_yet_another_unrelated_z8.flac');

            groups = {struct('tables', pairA, 'strainLabel', "strainA"), ...
                struct('tables', pairB, 'strainLabel', "strainB")};

            testCase.verifyWarning(@() cohort.internal.alignProtocolSlots(groups), ...
                'cohort:internal:alignProtocolSlots:LowSimilarity');
        end

        function validateProtocolTablesAcceptsJoinedStimfileName(testCase)
            pair = makeNamedPair("strainA", ...
                '20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac', ...
                {'20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac'; '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac'});

            labels = cohort.internal.validateProtocolTables(pair);
            testCase.verifyEqual(labels{1}, "20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac");
            testCase.verifyEqual(labels{2}, ...
                "20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac + 20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac");
        end

        function pipelineAlignsFlippedStrainGroupsEndToEnd(testCase)
            pairA = makeNamedPair("strainA", ...
                '20260130_Normal-Inverted_27x_[5-10s]ISI_v2.flac', ...
                {'20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac'; '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac'});
            pairB = makeNamedPair("strainB", ...
                '20260312_Normal-WhiteNoise_27x_[5-10s]ISI_v3e.flac', ...   % flipped order
                '20260202_Normal-Inverted_27x_[5-10s]ISI_v2b.flac');

            out = cohort.fingerprintPipeline({pairA, pairB}, ...
                MinCohortN=2, NPerm=50, NBoot=50, MakeFigures=false);

            testCase.verifyTrue(out.protocolAlignment.Swapped(2));

            % Exploration tier (protocol 1) is the Inverted family for BOTH strains.
            exploration = out.perAnimalLong(out.perAnimalLong.Tier == 'exploration', :);
            geneCol = string(exploration.Gene);
            protoCol = string(exploration.ProtocolName);
            for s = unique(geneCol)'
                thisProto = unique(protoCol(geneCol == s));
                testCase.verifyTrue(contains(thisProto(1), "Inverted", 'IgnoreCase', true), ...
                    'Exploration protocol should be the Inverted family for every strain');
            end
        end
    end
end


function standardizedTables = makeNamedPair(strainName, stimfileName1, stimfileName2)
    nRows = 14;
    animals = [ ...
        struct('id', "M01", 'strain', string(strainName), 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M02", 'strain', string(strainName), 'genotype', "WT", 'sex', "F", 'cagecode', "C1", 'dob', "", 'age', 10); ...
        struct('id', "M03", 'strain', string(strainName), 'genotype', "MUT", 'sex', "F", 'cagecode', "C2", 'dob', "", 'age', 10); ...
        struct('id', "M04", 'strain', string(strainName), 'genotype', "MUT", 'sex', "F", 'cagecode', "C2", 'dob', "", 'age', 10)];
    nAnimals = numel(animals);

    xData = zeros(nRows, nAnimals);
    for a = 1:nAnimals
        if strcmp(animals(a).genotype, "MUT")
            base = 3 * (a - 1) + 6;
        else
            base = 3 * (a - 1);
        end
        xData(:, a) = [base, base+1, base+2, repmat(base+2, 1, nRows-3)]';
    end
    yData = zeros(nRows, nAnimals);
    distFromMidline = xData - 1.5;
    arenaGrid = 0.5 * sign(distFromMidline);

    metadata = configureDictionary("string", "struct");
    for a = 1:nAnimals
        metadata(char(sprintf('k%d', a))) = animals(a);
    end

    standardizedTables = [makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, stimfileName1), ...
        makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, stimfileName2)];
end


function stdTable = makeOneProtocolTable(metadata, xData, yData, distFromMidline, arenaGrid, stimfileName)
    nRows = size(xData, 1);
    trialTime = (0:nRows-1)' / 10;
    stimulusName = [ ...
        "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; "NONE | Pre-Stimulus"; ...
        "A"; "A"; "B"; "B"; "A"; "A"; "B"; "B"; "A"; "A"; "NONE | Post-Stimulus"];
    centerpointData = table(trialTime, stimulusName, ...
        xData, yData, distFromMidline, arenaGrid, ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
        'Y center', 'Distance from Midline', 'Arena Grid Score'});
    % Wrap stimfileName in a cell so struct() keeps cell values (joined
    % variations) as the field content instead of building a struct array.
    stdTable = struct( ...
        'stimfileName', {stimfileName}, ...
        'stimuliSorted', ["A", "B"], ...
        'animalMetadata', metadata, ...
        'fps', 10, ...
        'px2cm', 0.5, ...
        'centerpointData', centerpointData, ...
        'bodyparts', table());
end
