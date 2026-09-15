classdef testExcludeBaselineSubjects < matlab.unittest.TestCase
    % Tests for outlier.excludeBaselineSubjects.
    %
    % Builds synthetic standardizedTables for a baseline (WT) group with known
    % structure, then verifies:
    %   - OutlierMethod "none" is a passthrough (report schema only, no drops)
    %   - "multivariate" excludes an extreme subject via LOO D2 and keeps >= 4
    %     baseline subjects
    %   - "mixedquality" excludes subjects with blanked features (no valid
    %     progression bins) and frozen (near-zero locomotion) subjects
    %   - "baselinelocomotion" excludes frozen subjects below the auto/fixed
    %     pre-stimulus distance threshold
    %   - excluded subjects are actually removed from the standardizedTables
    %     (animal columns + animalMetadata), via consistent composite keys
    %   - integration: population.temp.rankSubjectSimilarityToBaseline forwards
    %     the outlier options and reports exclusions in info

    methods (TestClassSetup)
        function addPaths(testCase)
            % Package folders are skipped by addpath(genpath(...)); add the parent
            % of the top-level +package instead. Walk up until the folder that
            % contains 'src' is found (robust to test nesting depth).
            root = fileparts(mfilename('fullpath'));
            while ~isempty(root) && ~isfolder(fullfile(root, 'src'))
                root = fileparts(root);
            end
            addPathIfMissing(root);                                     % repo root
            addPathIfMissing(fullfile(root, 'src'));                    % +validator, +utils, etc.
            addPathIfMissing(fullfile(root, 'src', 'modules', 'PopulationAnalysis'));
            testCase.verifyTrue(isfolder(fullfile(root, 'src', 'modules', 'PopulationAnalysis')));
        end
    end

    methods (Test)
        function noneMethodIsPassthrough(testCase)
            wt = makeSyntheticGroup(6, "WT", 0);
            [filtered, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'none', 'Verbose', false);

            testCase.verifyEmpty(reportTbl);
            testCase.verifyEqual(numel(filtered), numel(wt));
            testCase.verifyEqual(size(filtered(1).centerpointData{:, 'X center'}, 2), 6);
        end

        function defaultInvocationIsPassthrough(testCase)
            wt = makeSyntheticGroup(6, "WT", 0);
            [filtered, reportTbl] = outlier.excludeBaselineSubjects(wt);
            testCase.verifyEmpty(reportTbl);
            testCase.verifyEqual(numel(filtered), numel(wt));
        end

        function multivariateExcludesExtremeSubject(testCase)
            wt = makeSyntheticGroup(12, "WT", 0);
            % Make WT_1 an extreme outlier on Arena Grid Score across both stimsets.
            wt = shiftAnimal(wt, 1, 3.0);

            [filtered, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'multivariate', 'Verbose', false);

            testCase.verifyEqual(height(reportTbl), 12);
            testCase.verifyTrue(all(isfinite(reportTbl.OutlierScore)), ...
                'Every subject should receive a finite LOO D2 score');

            % At least one subject excluded, and every excluded subject must
            % carry the maximum observed LOO D2 (most baseline-dissimilar).
            nExcluded = sum(reportTbl.Excluded);
            testCase.verifyTrue(nExcluded >= 1, 'The extreme shifted subject should be excluded');
            maxScore = max(reportTbl.OutlierScore);
            testCase.verifyTrue(all(reportTbl.OutlierScore(reportTbl.Excluded) == maxScore), ...
                'Excluded subjects must be the maximum-D2 subjects');

            % Excluded subjects must be removed from the standardizedTables.
            testCase.verifyEqual(size(filtered(1).centerpointData{:, 'X center'}, 2), 12 - nExcluded);
            metaIds = string(filtered(1).animalMetadata.keys());
            excludedIdList = string(reportTbl.Mouse_ID(reportTbl.Excluded));
            testCase.verifyFalse(any(ismember(excludedIdList, metaIds)), ...
                'Excluded subjects must be removed from animalMetadata');
            testCase.verifyTrue(height(reportTbl) - nExcluded >= 4, ...
                'At least 4 baseline subjects must remain');
        end

        function multivariateCapsExclusionsToKeepFourSubjects(testCase)
            wt = makeSyntheticGroup(10, "WT", 0);
            % Make most subjects extreme so the raw cutoff would exclude > n-4.
            for a = 1:7
                wt = shiftAnimal(wt, a, 3.0 + 0.1 * a);
            end

            [filtered, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'multivariate', 'Verbose', false);

            testCase.verifyTrue(sum(reportTbl.Excluded) <= 6, ...
                'Exclusions must be capped so at least 4 subjects remain');
            testCase.verifyEqual(size(filtered(1).centerpointData{:, 'X center'}, 2) + sum(reportTbl.Excluded), 10);
        end

        function mixedqualityExcludesBlankedAndFrozenSubjects(testCase)
            wt = makeSyntheticGroup(8, "WT", 0);
            wt = blankFeatureForSubject(wt, 1, 'Arena Grid Score');   % no valid bins
            wt = freezeAnimal(wt, 2);                                 % near-zero locomotion

            % MinValidBins = 1: the fixture yields a single progression bin per
            % stimulus, so only the fully blanked subject fails the bins check.
            [~, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'mixedquality', 'MinValidBins', 1, 'Verbose', false);

            % Exactly two subjects excluded: one for progression bins, one for
            % locomotion (subject IDs are not assumed: dictionary key order is
            % not guaranteed to match the centerpointData column order).
            excludedIds = string(reportTbl.Mouse_ID(reportTbl.Excluded));
            testCase.verifyEqual(numel(excludedIds), 2, ...
                'Exactly the blanked and frozen subjects should be excluded');
            excludedReasons = string(reportTbl.Reason(reportTbl.Excluded));
            testCase.verifyEqual(nnz(contains(excludedReasons, 'progression bins')), 1);
            testCase.verifyEqual(nnz(contains(excludedReasons, 'locomotion')), 1);
        end

        function baselinelocomotionExcludesFrozenSubject(testCase)
            wt = makeSyntheticGroupWithPreStim(8, "WT", 0);
            wt = freezeAnimal(wt, 1);   % frozen subject travels ~0 pre-stimulus

            [~, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'baselinelocomotion', 'Verbose', false);

            testCase.verifyTrue(all(isfinite(reportTbl.OutlierScore)), ...
                'All subjects should have finite pre-stimulus distances');
            testCase.verifyEqual(sum(reportTbl.Excluded), 1, ...
                'Exactly the frozen subject should be excluded by the auto distance threshold');
            testCase.verifyTrue(contains(string(reportTbl.Reason(reportTbl.Excluded)), 'Pre-stimulus distance'));
            testCase.verifyFalse(any(reportTbl.Excluded & contains(string(reportTbl.Reason), 'No pre-stimulus data')));
        end

        function baselinelocomotionFixedThreshold(testCase)
            wt = makeSyntheticGroupWithPreStim(8, "WT", 0);
            wt = freezeAnimal(wt, 2);

            [~, reportTbl] = outlier.excludeBaselineSubjects(wt, ...
                'OutlierMethod', 'baselinelocomotion', ...
                'MinPreStimDistanceCm', 1e6, 'Verbose', false);

            % A huge fixed threshold excludes every subject with data.
            testCase.verifyTrue(all(reportTbl.Excluded));
            testCase.verifyEqual(unique(reportTbl.Threshold), 1e6);
        end

        function similarityIntegrationForwardsOutlierOptions(testCase)
            [wt, ko] = makeSyntheticGroups(12, 6, 1.5);
            wt = shiftAnimal(wt, 1, 3.0);

            [rankedTbl, ~, info] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'OutlierMethod', 'multivariate', 'Verbose', false);

            testCase.verifyEqual(height(rankedTbl), 6, ...
                'Test subjects must never be excluded');
            testCase.verifyTrue(info.NBaselineExcluded >= 1);
            testCase.verifyTrue(all(string(info.ExcludedBaselineSubjects.Method) == "multivariate"));
            testCase.verifyEqual(string(info.OutlierMethod), "multivariate");

            % Default call must exclude nobody.
            [~, ~, infoNone] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, 'Verbose', false);
            testCase.verifyEqual(infoNone.NBaselineExcluded, 0);
            testCase.verifyEqual(string(infoNone.OutlierMethod), "none");
        end

        function exclusionDoesNotChangeTestSubjectCount(testCase)
            [wt, ko] = makeSyntheticGroups(12, 6, 1.5);
            [rankedNoExcl, ~, infoNoExcl] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, 'Verbose', false);
            [rankedExcl, ~, infoExcl] = population.temp.rankSubjectSimilarityToBaseline(wt, ko, ...
                'OutlierMethod', 'multivariate', 'Verbose', false);

            testCase.verifyEqual(height(rankedExcl), height(rankedNoExcl));
            if infoNoExcl.NBaselineExcluded == 0 && infoExcl.NBaselineExcluded > 0
                % Baseline reference changed, so scores may differ; only the
                % test-subject row count must be preserved (verified above).
                testCase.verifyTrue(true);
            end
        end
    end
end

%% ==================================================================
%% Synthetic group builders (mirror tests/+population/+temp fixtures)
%% ==================================================================
function [wt, ko] = makeSyntheticGroups(nWT, nKO, shift)
    wt = makeSyntheticGroup(nWT, "WT", 0);
    ko = makeSyntheticGroup(nKO, "KO", 0);
    ko = shiftOddAnimals(ko, shift);
end

function stdTables = makeSyntheticGroup(nAnimals, strain, valueOffset)
    % Two stimsets x 2 stimuli, deterministic per-animal signals.
    stimsets = makeSyntheticGroupWithPreStim(nAnimals, strain, valueOffset, 0);
    % Strip pre-stimulus rows to keep the plain fixture identical to the
    % established similarity-test fixtures.
    for si = 1:numel(stimsets)
        cp = stimsets(si).centerpointData;
        sn = string(cp{:, 'Stimulus name'});
        cp = cp(~strcmpi(sn, "NONE | Pre-Stimulus"), :);
        stimsets(si).centerpointData = cp;
    end
    stdTables = stimsets;
end

function stdTables = makeSyntheticGroupWithPreStim(nAnimals, strain, valueOffset, varargin)
    % Two stimsets x 2 stimuli, deterministic per-animal signals, with an
    % optional pre-stimulus block prepended (for baselinelocomotion tests).
    if nargin >= 4
        nPreRows = varargin{1};
    else
        nPreRows = 10;
    end
    fps = 10;
    nStimRows = 40;
    stimsets = struct('stimfileName', {}, 'stimuliSorted', {}, 'animalMetadata', {}, ...
        'fps', {}, 'px2cm', {}, 'centerpointData', {}, 'bodyparts', {});
    stimProtos = ["protoA.flac", "protoB.flac"];
    stimNames = ["Normal", "Inverted"];

    for si = 1:2
        nRows = nPreRows + nStimRows;
        trialTime = (0:nRows-1)' / fps;
        stimulusName = [repmat("NONE | Pre-Stimulus", nPreRows, 1); ...
            reshape(repmat(stimNames, nStimRows/2, 1), [], 1)];
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
            % Pre-stimulus path length differs slightly per animal (~2% per
            % index) so the auto MAD threshold is not degenerate.
            preStep = 0.02 * (1 + 0.02 * a);
            x(1:nPreRows, a) = x(1:nPreRows, a) + preStep * (0:nPreRows-1)';
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

%% ==================================================================
%% Fixture mutators
%% ==================================================================
function stdTables = shiftAnimal(stdTables, animalIdx, amount)
    % Adds a constant offset to one animal's Arena Grid Score in all stimsets.
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        ags = cp{:, 'Arena Grid Score'};
        ags(:, animalIdx) = ags(:, animalIdx) + amount;
        cp{:, 'Arena Grid Score'} = ags;
        stdTables(si).centerpointData = cp;
    end
end

function stdTables = shiftOddAnimals(stdTables, shift)
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        ags = cp{:, 'Arena Grid Score'};
        for a = 1:size(ags, 2)
            if mod(a, 2) == 1
                ags(:, a) = ags(:, a) + shift;
            end
        end
        cp{:, 'Arena Grid Score'} = ags;
        stdTables(si).centerpointData = cp;
    end
end

function stdTables = blankFeatureForSubject(stdTables, animalIdx, colName)
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        vals = cp{:, colName};
        vals(:, animalIdx) = NaN;
        cp{:, colName} = vals;
        stdTables(si).centerpointData = cp;
    end
end

function stdTables = freezeAnimal(stdTables, animalIdx)
    % Makes one animal motionless (constant X/Y) in all stimsets.
    for si = 1:numel(stdTables)
        cp = stdTables(si).centerpointData;
        x = cp{:, 'X center'};
        y = cp{:, 'Y center'};
        x(:, animalIdx) = 0.5;
        y(:, animalIdx) = 0.5;
        cp{:, 'X center'} = x;
        cp{:, 'Y center'} = y;
        stdTables(si).centerpointData = cp;
    end
end

function addPathIfMissing(p)
    if ~contains(path, p)
        addpath(p);
    end
end
