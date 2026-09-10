classdef testRankSubjectSimilarityToBaseline < matlab.unittest.TestCase
    % Tests for population.temp.rankSubjectSimilarityToBaseline.
    %
    % Builds synthetic standardizedTables for a baseline (WT) group and a test
    % (KO) group with known feature structure, then verifies:
    %   - shifted KO subjects rank as LESS similar to WT than KO subjects at the
    %     WT centroid (Rank ordering)
    %   - LOO null produces valid empirical p-values in (0, 1]
    %   - NaN features are handled (pairwise-complete scoring, no crash)
    %   - degenerate (constant) baseline features are flagged, not crashed
    %   - sign invariance: flipping a feature's sign in BOTH groups leaves D2 unchanged
    %   - cohort.metrics.progressionComponents matches the legacy scoring semantics

    methods (TestClassSetup)
        function addPaths(testCase)
            % Package folders are skipped by addpath(genpath(...)); add the parent
            % of the top-level +package instead.
            root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
            addPathIfMissing(root);                                     % repo root
            addPathIfMissing(fullfile(root, 'src'));                    % +validator, +utils, etc.
            addPathIfMissing(fullfile(root, 'src', 'modules', 'PopulationAnalysis'));
            testCase.verifyTrue(isfolder(root));
        end
    end

    methods (Test)
        function shiftedKoRanksLessSimilar(testCase)
            [wt, ko] = makeSyntheticGroups(15, 6, 1.5);
            [rankedTbl, ~, info] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'Verbose', false);

            testCase.verifyEqual(height(rankedTbl), 6);
            testCase.verifyTrue(all(isfinite(rankedTbl.MahalanobisD2)));
            testCase.verifyTrue(all(rankedTbl.EmpiricalP > 0 & rankedTbl.EmpiricalP <= 1));

            % Shifted KOs (odd subject index) should be less WT-like than
            % unshifted KOs (even index). IDs are "KO_1".."KO_6".
            subjNum = sscanf2(rankedTbl.Mouse_ID);
            isShifted = mod(subjNum, 2) == 1;
            d2Shifted = rankedTbl.MahalanobisD2(isShifted);
            d2Unshifted = rankedTbl.MahalanobisD2(~isShifted);
            testCase.verifyTrue(median(d2Shifted) > median(d2Unshifted), ...
                'Shifted KO subjects should have larger D2 than unshifted KO subjects');

            % Most-similar subject should be an unshifted KO.
            testCase.verifyEqual(mod(subjNum(1), 2), 0);

            % Ranks must be 1..n with no ties.
            testCase.verifyEqual(sort(rankedTbl.Rank_Similarity), (1:6)');

            % LOO null must be finite and positive.
            testCase.verifyTrue(all(isfinite(info.LOO_D2) & info.LOO_D2 >= 0));
        end

        function nanFeaturesHandledPairwiseComplete(testCase)
            [wt, ko] = makeSyntheticGroups(15, 6, 1.5);
            % Blank out one feature for one KO subject.
            ko = blankFeatureForFirstSubject(ko, 'Arena Grid Score');

            [rankedTbl, ~, ~] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'Verbose', false);

            testCase.verifyEqual(height(rankedTbl), 6);
            testCase.verifyTrue(all(isfinite(rankedTbl.MahalanobisD2)), ...
                'All subjects should still score via pairwise-complete handling');
            testCase.verifyTrue(rankedTbl.NMetricFeaturesNaN(1) > 0, ...
                'First subject should have at least 1 NaN feature');
            testCase.verifyTrue(rankedTbl.NMetricFeaturesUsed(1) > 0, ...
                'First subject should still use its observed features');
        end

        function degenerateFeatureFlagged(testCase)
            [wt, ko] = makeSyntheticGroups(15, 6, 1.5);
            % Make one WT feature constant (degenerate).
            wt = constantizeFeature(wt, 'Arena Grid Score');

            [rankedTbl, ~, info] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'Verbose', false);

            testCase.verifyTrue(~isempty(info.DegenerateFeatures), ...
                'Constant baseline features should be flagged as degenerate');
            testCase.verifyTrue(all(isfinite(rankedTbl.MahalanobisD2)));
        end

        function signInvarianceOfMahalanobis(testCase)
            [wt, ko] = makeSyntheticGroups(15, 6, 1.5);
            [~, ~, info1] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'Verbose', false);

            % Flip the sign of one feature in BOTH groups.
            wtFlip = flipFeatureSign(wt, 'Arena Grid Score');
            koFlip = flipFeatureSign(ko, 'Arena Grid Score');
            [~, ~, info2] = population.temp.rankSubjectSimilarityToBaseline(wtFlip, koFlip, ...
                'Verbose', false);

            testCase.verifyEqual(info1.LOO_D2, info2.LOO_D2, 'AbsTol', 1e-9, ...
                'D2 must be invariant to a joint sign flip of a feature');
        end

        function progressionComponentsMatchLegacyScoring(testCase)
            % Verify cohort.metrics.progressionComponents reproduces the
            % documented component semantics on a hand-checkable series.
            longTbl = table( ...
                ["A|s"; "A|s"; "A|s"; "A|s"], [1; 1; 1; 1], ...
                ["proto.flac"; "proto.flac"; "proto.flac"; "proto.flac"], ...
                ["Stim1"; "Stim1"; "Stim1"; "Stim1"], ["WT"; "WT"; "WT"; "WT"], ...
                [1; 2; 3; 5], [0.0; 0.1; 0.2; 0.4], ...
                'VariableNames', {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', ...
                'Stimulus', 'Group', 'BinIdx', 'Progression'});

            comp = cohort.metrics.progressionComponents(longTbl);

            testCase.verifyEqual(height(comp), 1);
            testCase.verifyEqual(comp.NValidBins(1), 4);
            % DeltaEndStart = 0.4 - 0.0
            testCase.verifyEqual(comp.DeltaEndStart(1), 0.4, 'AbsTol', 1e-12);
            % Theil-Sen: median of all pairwise slopes vs ACTUAL bin gaps.
            % Pairs (bins, values): (1,2)->0.1/1, (1,3)->0.2/2, (1,5)->0.4/4,
            % (2,3)->0.1/1, (2,5)->0.3/3, (3,5)->0.2/2 -> all 0.1
            testCase.verifyEqual(comp.TheilSenSlope(1), 0.1, 'AbsTol', 1e-12);
            % Kendall tau of a perfectly monotonic series = 1
            testCase.verifyEqual(comp.KendallTau(1), 1.0, 'AbsTol', 1e-12);
            % Efficiency: net 0.4 / gross 0.4 = 1
            testCase.verifyEqual(comp.ProgressEfficiency(1), 1.0, 'AbsTol', 1e-12);
        end

        function progressionComponentsHandlesNanGaps(testCase)
            % Valid bins [1 2 3 5] must NOT be collapsed (positions 1..5).
            longTbl = table( ...
                ["A|s"; "A|s"; "A|s"; "A|s"], [1; 1; 1; 1], ...
                ["proto.flac"; "proto.flac"; "proto.flac"; "proto.flac"], ...
                ["Stim1"; "Stim1"; "Stim1"; "Stim1"], ["WT"; "WT"; "WT"; "WT"], ...
                [1; 2; 3; 5], [0.0; 0.1; 0.2; 0.4], ...
                'VariableNames', {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', ...
                'Stimulus', 'Group', 'BinIdx', 'Progression'});

            comp = cohort.metrics.progressionComponents(longTbl);
            testCase.verifyEqual(comp.NValidBins(1), 4);
            testCase.verifyEqual(comp.TheilSenSlope(1), 0.1, 'AbsTol', 1e-12, ...
                'Slope must use actual bin gaps (bin 5 is 2 apart from bin 3)');
        end

        function mismatchedStimSetsError(testCase)
            [wt, ko] = makeSyntheticGroups(15, 6, 1.5);
            ko = renameStimulus(ko, "Inverted", "InvertedX");
            testCase.verifyError(...
                @() population.temp.rankSubjectSimilarityToBaseline(wt, ko, 'Verbose', false), ...
                'rankSubjectSimilarityToBaseline:featureMismatch');
        end
    end
end

%% ==================================================================
%% Synthetic group builders
%% ==================================================================
function [wt, ko] = makeSyntheticGroups(nWT, nKO, shift)
    % WT group: 2 stimsets, 2 stimuli each, nWT animals.
    % KO group: same structure, nKO animals; subjects with odd index get their
    % 'Arena Grid Score' shifted by +shift (simulating an atypical phenotype).
    wt = makeSyntheticGroup(nWT, "WT", 0);
    ko = makeSyntheticGroup(nKO, "KO", 0);
    % Shift odd-indexed KO animals on the Arena Grid Score column.
    cp = ko(1).centerpointData;
    ags = cp{:, 'Arena Grid Score'};
    for a = 1:size(ags, 2)
        if mod(a, 2) == 1
            ags(:, a) = ags(:, a) + shift;
        end
    end
    ko(1).centerpointData{:, 'Arena Grid Score'} = ags;
    cp2 = ko(2).centerpointData;
    ags2 = cp2{:, 'Arena Grid Score'};
    for a = 1:size(ags2, 2)
        if mod(a, 2) == 1
            ags2(:, a) = ags2(:, a) + shift;
        end
    end
    ko(2).centerpointData{:, 'Arena Grid Score'} = ags2;
end

function stdTables = makeSyntheticGroup(nAnimals, strain, valueOffset)
    % Two stimsets x 2 stimuli, deterministic per-animal signals.
    fps = 10;
    nRows = 40;
    stimsets = struct('stimfileName', {}, 'stimuliSorted', {}, 'animalMetadata', {}, ...
        'fps', {}, 'px2cm', {}, 'centerpointData', {}, 'bodyparts', {});
    stimProtos = ["protoA.flac", "protoB.flac"];
    stimNames = ["Normal", "Inverted"];

    for si = 1:2
        trialTime = (0:nRows-1)' / fps;
        % Alternating stimulus blocks: Normal, Inverted, Normal, Inverted...
        stimulusName = repmat(stimNames, nRows/2, 1);
        stimulusName = stimulusName(:);

        % Per-animal deterministic signals with animal-specific offsets.
        ags = repmat((1:nRows)', 1, nAnimals) / nRows - 0.5;   % in [-0.5, 0.5)
        dfm = repmat((1:nRows)', 1, nAnimals) / nRows - 0.5;
        x = repmat((1:nRows)', 1, nAnimals) / nRows;
        y = repmat((1:nRows)', 1, nAnimals) / nRows;
        for a = 1:nAnimals
            phase = 0.05 * a + valueOffset;
            ags(:, a) = ags(:, a) + phase * sin(2 * pi * (1:nRows)' / nRows);
            dfm(:, a) = dfm(:, a) + phase * cos(2 * pi * (1:nRows)' / nRows);
            x(:, a) = x(:, a) + 0.01 * a;
        end

        centerpointData = table(trialTime, stimulusName, x, y, dfm, ags, ...
            'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
            'Y center', 'Distance from Midline', 'Arena Grid Score'});

        metadata = configureDictionary("string", "struct");
        for a = 1:nAnimals
            metadata(strain + "_" + a) = struct( ...
                'id', char(strain + "_" + a), ...
                'sex', "M", ...
                'strain', strain, ...
                'genotype', char(strain), ...
                'cagecode', char("C" + mod(a, 3) + 1), ...
                'age', 90 + a);
        end

        stimsets(si) = struct( ...
            'stimfileName', stimProtos(si), ...
            'stimuliSorted', stimNames, ...
            'animalMetadata', metadata, ...
            'fps', fps, ...
            'px2cm', 0.5, ...
            'centerpointData', centerpointData, ...
            'bodyparts', table());
    end
    stdTables = stimsets;
end

function stdTables = blankFeatureForFirstSubject(stdTables, colName)
    cp = stdTables(1).centerpointData;
    vals = cp{:, colName};
    vals(:, 1) = NaN;
    stdTables(1).centerpointData{:, colName} = vals;
end

function stdTables = constantizeFeature(stdTables, colName)
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        vals = cp{:, colName};
        vals(:) = 0.25;
        stdTables(si).centerpointData{:, colName} = vals;
    end
end

function stdTables = flipFeatureSign(stdTables, colName)
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        cp{:, colName} = -cp{:, colName};
        stdTables(si).centerpointData{:, colName} = cp{:, colName};
    end
end

function stdTables = renameStimulus(stdTables, oldName, newName)
    for si = 1:numel(stdTables)
        stdTables(si).stimuliSorted = replace(stdTables(si).stimuliSorted, oldName, newName);
        cp = stdTables(si).centerpointData;
        sn = cp{:, 'Stimulus name'};
        cp{:, 'Stimulus name'} = replace(sn, oldName, newName);
        stdTables(si).centerpointData = cp;
    end
end

function addPathIfMissing(p)
    if ~contains(path, p)
        addpath(p);
    end
end

function n = sscanf2(idStrs)
    % Extract the trailing integer from "KO_12"-style ID strings.
    n = zeros(numel(idStrs), 1);
    for k = 1:numel(idStrs)
        tok = regexp(char(idStrs(k)), '(\d+)$', 'tokens', 'once');
        if ~isempty(tok)
            n(k) = str2double(tok{1});
        end
    end
end
