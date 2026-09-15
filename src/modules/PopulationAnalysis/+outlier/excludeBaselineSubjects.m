function [filteredStdTables, reportTbl] = excludeBaselineSubjects(baselineStdTables, kvargs)
    %%EXCLUDEBASELINESUBJECTS Detect and optionally exclude baseline outlier subjects.
    %
    %   [filteredStdTables, reportTbl] = ...
    %       outlier.excludeBaselineSubjects(baselineStdTables, Name=Value)
    %
    %   Screens the BASELINE (reference) population for outlier subjects and
    %   drops them from the returned standardizedTables so downstream analyses
    %   (e.g. population.temp.rankSubjectSimilarityToBaseline) calibrate
    %   against a clean reference. Test subjects are NOT touched by this
    %   function; pass only the baseline group's standardizedTables.
    %
    %   OutlierMethod options:
    %       "none"              (default) passthrough: no detection, no exclusion.
    %                           reportTbl is an empty table with the report schema.
    %       "multivariate"      Leave-one-out (LOO) shrinkage Mahalanobis D2 per
    %                           baseline subject on the same metric feature set used
    %                           by rankSubjectSimilarityToBaseline (preference index,
    %                           rate of stay, progression components). A subject is
    %                           excluded when its LOO D2 exceeds a robust cutoff,
    %                           median(LOO_D2) + OutlierThresholdK * 1.4826 * MAD(LOO_D2).
    %                           If the MAD is degenerate (zero spread), only the most
    %                           extreme subject is excluded. Exclusions are capped so
    %                           at least 4 baseline subjects remain.
    %       "mixedquality"      Data-quality screening: excludes subjects with
    %                           fewer than MinValidBins valid progression bins,
    %                           a missing (NaN) locomotion covariate, or mean
    %                           stimulus locomotion below MinMeanSpeedCmS.
    %       "baselinelocomotion" Excludes subjects whose pre-stimulus distance
    %                           traveled (cohort.metrics.distanceTravel,
    %                           'Distance During Pre-Stimulus (cm)') on the FIRST
    %                           stimset (standardizedTables(1)) falls below
    %                           MinPreStimDistanceCm. When MinPreStimDistanceCm is
    %                           NaN (default), the threshold is auto-derived as
    %                           median - OutlierThresholdK * 1.4826 * MAD of the
    %                           observed distances. Subjects without pre-stimulus
    %                           data are kept (not judged).
    %
    %   Name-Value Pair Arguments:
    %       OutlierMethod               : "none" (default) | "multivariate" |
    %                                     "mixedquality" | "baselinelocomotion"
    %       OutlierThresholdK           : robust MAD multiplier for the
    %                                     multivariate and auto-thresholded
    %                                     baselinelocomotion methods (default 3.5)
    %       MinValidBins                : mixedquality minimum valid progression
    %                                     bins per subject (default 2)
    %       MinPreStimDistanceCm        : baselinelocomotion fixed threshold in
    %                                     cm; NaN = auto MAD-based (default NaN)
    %       MinMeanSpeedCmS             : mixedquality near-zero locomotion
    %                                     threshold (default 0.1 cm/s)
    %       LocomotionCovariateColumn   : speed column used as the locomotion
    %                                     covariate (default
    %                                     "Speed Mean During Stimulus (cm/s)")
    %       MinShrinkageLambda          : starting shrinkage lambda for the
    %                                     multivariate D2 fit (default 0.1)
    %       ProgressionMetricType       : "state" (default) | "distance"
    %       BinWidth                    : bouts per progression bin (default 6)
    %       MeanWindowFrames            : smoothing window frames (default 30)
    %       StimulusIncludesTrailingISI : passed to cohort metrics (default true)
    %       Verbose                     : print the exclusion summary (default true)
    %
    %   Outputs:
    %       filteredStdTables : baseline standardizedTables with excluded
    %                           subjects removed (animal columns of
    %                           centerpointData/bodyparts and animalMetadata
    %                           entries dropped, matching the
    %                           sdTable.subsetByMetadata filtering convention).
    %       reportTbl         : one row per baseline subject with columns:
    %                           SubjectKey, Mouse_ID, Group, Method, OutlierScore,
    %                           Threshold, Excluded (logical), Reason.
    %                           Empty (schema only) when OutlierMethod = "none".
    %
    %   Examples:
    %       % Multivariate outlier exclusion before similarity ranking
    %       [wtClean, report] = outlier.excludeBaselineSubjects(wt, ...
    %           OutlierMethod="multivariate", OutlierThresholdK=3.5);
    %
    %       % Fixed pre-stimulus hypoactivity cutoff
    %       [wtClean, report] = outlier.excludeBaselineSubjects(wt, ...
    %           OutlierMethod="baselinelocomotion", MinPreStimDistanceCm=50);
    %
    %   See also: population.temp.rankSubjectSimilarityToBaseline,
    %             outlier.internal.buildExclusionFeatures,
    %             outlier.internal.looBaselineD2, sdTable.subsetByMetadata,
    %             cohort.metrics.distanceTravel

    arguments
        baselineStdTables struct {sdTable.mustBeStandardizedTable}
        kvargs.OutlierMethod (1,1) string {mustBeMember(kvargs.OutlierMethod, ["none", "multivariate", "mixedquality", "baselinelocomotion"])} = "none"
        kvargs.OutlierThresholdK (1,1) double {mustBePositive} = 3.5
        kvargs.MinValidBins (1,1) double {mustBePositive, mustBeInteger} = 2
        kvargs.MinPreStimDistanceCm (1,1) double {mustBeReal} = NaN
        kvargs.MinMeanSpeedCmS (1,1) double {mustBeNonnegative} = 0.1
        kvargs.LocomotionCovariateColumn (1,1) string {mustBeTextScalar} = "Speed Mean During Stimulus (cm/s)"
        kvargs.MinShrinkageLambda (1,1) double {mustBeNonnegative, mustBeLessThanOrEqual(kvargs.MinShrinkageLambda, 1)} = 0.1
        kvargs.ProgressionMetricType (1,1) string {mustBeMember(kvargs.ProgressionMetricType, ["state", "distance"])} = "state"
        kvargs.BinWidth (1,1) double {mustBePositive, mustBeInteger} = 6
        kvargs.MeanWindowFrames (1,1) double {mustBePositive, mustBeInteger} = 30
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.Verbose (1,1) logical = true
    end

    filteredStdTables = baselineStdTables;
    reportTbl = makeEmptyReport();

    method = lower(string(kvargs.OutlierMethod));
    if strcmp(method, "none") || isempty(baselineStdTables)
        return;
    end

    % One cohort.metrics pass provides features + quality info for all methods.
    feat = outlier.internal.buildExclusionFeatures(baselineStdTables, ...
        'ProgressionMetricType', kvargs.ProgressionMetricType, ...
        'BinWidth', kvargs.BinWidth, ...
        'MeanWindowFrames', kvargs.MeanWindowFrames, ...
        'StimulusIncludesTrailingISI', kvargs.StimulusIncludesTrailingISI, ...
        'LocomotionCovariateColumn', kvargs.LocomotionCovariateColumn);

    nSub = height(feat.meta);
    if nSub == 0
        warning('outlier:excludeBaselineSubjects:noSubjects', ...
            'No baseline subjects found in the provided standardizedTables; nothing to screen.');
        return;
    end

    score = nan(nSub, 1);
    threshold = NaN;
    excluded = false(nSub, 1);
    reasons = repmat({''}, nSub, 1);

    switch method
        case "multivariate"
            featureNames = feat.featWide.Properties.VariableNames(2:end);   % skip SubjectKey
            X = featureMatrix(feat.featWide, featureNames);
            if isempty(featureNames)
                error('outlier:excludeBaselineSubjects:noFeatures', ...
                    'Multivariate outlier detection requires at least one metric feature.');
            end
            if nSub < 4
                warning('outlier:excludeBaselineSubjects:tooFewBaseline', ...
                    ['Only %d baseline subjects; multivariate outlier detection needs at least 4. ' ...
                    'No exclusions applied.'], nSub);
                reasons = repmat({'Insufficient baseline subjects for multivariate detection'}, nSub, 1);
            else
                looD2 = outlier.internal.looBaselineD2(X, kvargs.MinShrinkageLambda);
                score = looD2;
                [threshold, excluded] = robustD2Threshold(looD2, kvargs.OutlierThresholdK, nSub);
                for i = 1:nSub
                    if excluded(i)
                        reasons{i} = sprintf('LOO D2 %.4g exceeds robust cutoff %.4g (k = %.3g)', ...
                            looD2(i), threshold, kvargs.OutlierThresholdK);
                    end
                end
            end

        case "mixedquality"
            failed = false(nSub, 1);
            failReasons = repmat({''}, nSub, 1);
            for i = 1:nSub
                fails = {};
                if feat.MinValidBins(i) < kvargs.MinValidBins
                    fails{end+1} = sprintf('too few valid progression bins (%d < %d)', ...
                        feat.MinValidBins(i), kvargs.MinValidBins); %#ok<AGROW>
                end
                if ~isfinite(feat.cov(i))
                    fails{end+1} = 'missing locomotion covariate'; %#ok<AGROW>
                elseif feat.cov(i) < kvargs.MinMeanSpeedCmS
                    fails{end+1} = sprintf('near-zero locomotion (%.3g cm/s < %.3g cm/s)', ...
                        feat.cov(i), kvargs.MinMeanSpeedCmS); %#ok<AGROW>
                end
                failed(i) = ~isempty(fails);
                failReasons{i} = strjoin(fails, '; ');
            end
            excluded = failed;
            % Score = number of failed criteria; threshold = 0 (any failure excludes).
            score = double(cellfun(@(s) numel(strsplit(s, '; ')), failReasons));
            score(~failed) = 0;
            threshold = 0;
            reasons(failed) = failReasons(failed);

        case "baselinelocomotion"
            dist = preStimDistanceForSubjects(baselineStdTables, feat.meta.SubjectKey, ...
                kvargs.StimulusIncludesTrailingISI);
            score = dist;
            finiteScore = isfinite(dist);
            if isnan(kvargs.MinPreStimDistanceCm)
                threshold = autoLowerThreshold(dist(finiteScore), kvargs.OutlierThresholdK);
                excluded(finiteScore) = dist(finiteScore) < threshold;
            else
                threshold = kvargs.MinPreStimDistanceCm;
                excluded(finiteScore) = dist(finiteScore) < threshold;
            end
            for i = 1:nSub
                if excluded(i)
                    reasons{i} = sprintf('Pre-stimulus distance %.4g cm below threshold %.4g cm', ...
                        dist(i), threshold);
                elseif ~finiteScore(i)
                    reasons{i} = 'No pre-stimulus data (distance NaN); kept';
                end
            end

        otherwise
            error('outlier:excludeBaselineSubjects:badMethod', ...
                'Unsupported OutlierMethod: %s', string(kvargs.OutlierMethod));
    end

    reportTbl = assembleReport(feat.meta, char(method), score, threshold, excluded, reasons);

    excludedKeys = feat.meta.SubjectKey(excluded);
    if any(excluded)
        [filteredStdTables, nMatched] = dropSubjects(baselineStdTables, cellstr(excludedKeys));
        unmatched = excludedKeys(~ismember(cellstr(excludedKeys), nMatched));
        if ~isempty(unmatched)
            warning('outlier:excludeBaselineSubjects:unmatchedSubjects', ...
                ['Could not find animalMetadata entries for %d excluded subject(s); ' ...
                'they were not removed from the standardizedTables.'], numel(unmatched));
        end
    end

    if kvargs.Verbose
        printSummary(method, score, threshold, reportTbl);
    end
end

%% ==================================================================
%% Detection helpers
%% ==================================================================
function [threshold, excluded] = robustD2Threshold(looD2, k, nSub)
    % Robust cutoff median + k * 1.4826 * MAD; on degenerate spread, fall back
    % to excluding only the most extreme subject. Exclusions are capped so at
    % least 4 baseline subjects remain (most extreme excluded first).
    excluded = false(size(looD2));
    s = looD2(isfinite(looD2));
    if isempty(s)
        threshold = NaN;
        return;
    end
    med = median(s);
    sc = 1.4826 * median(abs(s - med));
    if isfinite(sc) && sc > 0
        threshold = med + k * sc;
        excluded(isfinite(looD2)) = looD2(isfinite(looD2)) > threshold;
    else
        % Degenerate spread: exclude only the most extreme subject.
        threshold = max(s);
        excluded(isfinite(looD2)) = looD2(isfinite(looD2)) == threshold;
    end

    % Cap exclusions so at least 4 baseline subjects remain.
    maxExclusions = nSub - 4;
    if nnz(excluded) > maxExclusions
        [~, order] = sort(looD2, 'descend');
        keep = false(size(looD2));
        keptCount = 0;
        for i = 1:numel(order)
            if excluded(order(i)) && keptCount < maxExclusions
                keep(order(i)) = true;
                keptCount = keptCount + 1;
            end
        end
        excluded = keep;
    end
end

function threshold = autoLowerThreshold(values, k)
    % Lower-tail robust cutoff: median - k * 1.4826 * MAD of finite values.
    if isempty(values)
        threshold = NaN;
        return;
    end
    med = median(values);
    sc = 1.4826 * median(abs(values - med));
    if isfinite(sc) && sc > 0
        threshold = med - k * sc;
    else
        threshold = min(values);   % degenerate spread: no auto exclusion
    end
end

function [dist, keys] = preStimDistanceForSubjects(stdTables, subjectKeys, trailingISI)
    % Pre-stimulus distance traveled on the FIRST stimset per requested subject.
    tDist = cohort.metrics.distanceTravel(stdTables, ...
        'StimulusIncludesTrailingISI', trailingISI);
    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'};
    keys = outlier.internal.subjectKeysFromTable(tDist, commonHeaders);

    firstProto = char(string(stdTables(1).stimfileName));
    protoMask = strcmpi(tDist.('Stimulus Protocol'), firstProto);
    distCol = tDist.('Distance During Pre-Stimulus (cm)');

    n = numel(subjectKeys);
    dist = nan(n, 1);
    for i = 1:n
        hit = find(protoMask & strcmp(keys, char(subjectKeys(i))), 1);
        if ~isempty(hit)
            dist(i) = distCol(hit);
        end
    end
end

function X = featureMatrix(wide, names)
    X = nan(height(wide), numel(names));
    for j = 1:numel(names)
        X(:, j) = wide.(names{j});
    end
end

%% ==================================================================
%% Report assembly
%% ==================================================================
function reportTbl = makeEmptyReport()
    % 'cellstr' preallocates cell arrays of char vectors (the warning-free
    % equivalent of the deprecated 'char' table VariableType).
    reportTbl = table('Size', [0 8], ...
        'VariableTypes', {'cellstr', 'cellstr', 'cellstr', 'cellstr', 'double', 'double', 'logical', 'cellstr'}, ...
        'VariableNames', {'SubjectKey', 'Mouse_ID', 'Group', 'Method', ...
        'OutlierScore', 'Threshold', 'Excluded', 'Reason'});
end

function reportTbl = assembleReport(meta, method, score, threshold, excluded, reasons)
    n = height(meta);
    reportTbl = table(...
        cellstr(string(meta.SubjectKey)), ...
        cellstr(string(meta.Mouse_ID)), ...
        cellstr(string(meta.Group)), ...
        repmat({method}, n, 1), ...
        score, ...
        repmat(threshold, n, 1), ...
        excluded, ...
        reasons, ...
        'VariableNames', {'SubjectKey', 'Mouse_ID', 'Group', 'Method', ...
        'OutlierScore', 'Threshold', 'Excluded', 'Reason'});
end

%% ==================================================================
%% Subject removal (mirrors sdTable.subsetByMetadata mechanics)
%% ==================================================================
function [stdTables, matchedKeys] = dropSubjects(stdTables, dropKeys)
    % Removes the given subjects (by composite animalSubjectKey) from every
    % standardizedTable: subsets per-animal columns of centerpointData and
    % bodyparts, and removes the corresponding animalMetadata entries.
    matchedKeys = {};
    for tableIndex = 1:numel(stdTables)
        metadata = stdTables(tableIndex).animalMetadata;
        keys = metadata.keys();
        n = numel(keys);
        keep = true(n, 1);
        for c = 1:n
            k = outlier.internal.animalSubjectKey(metadata(keys{c}));
            if any(strcmp(k, dropKeys))
                keep(c) = false;
                matchedKeys{end+1, 1} = k; %#ok<AGROW>
            end
        end
        if all(keep)
            continue;
        end

        vars = stdTables(tableIndex).centerpointData.Properties.VariableNames;
        for varI = 1:numel(vars)
            varName = vars{varI};
            varData = stdTables(tableIndex).centerpointData.(varName);
            if size(varData, 2) == n
                stdTables(tableIndex).centerpointData.(varName) = varData(:, keep);
            end
        end

        bodypartTable = stdTables(tableIndex).bodyparts;
        if ~isempty(bodypartTable)
            vars = bodypartTable.Properties.VariableNames;
            for varI = 1:numel(vars)
                varName = vars{varI};
                varData = bodypartTable.(varName);
                if size(varData, 2) == n
                    bodypartTable.(varName) = varData(:, keep);
                end
            end
            stdTables(tableIndex).bodyparts = bodypartTable;
        end

        stdTables(tableIndex).animalMetadata = remove(metadata, keys(~keep));
    end
    matchedKeys = unique(matchedKeys);
end

%% ==================================================================
%% Verbose summary
%% ==================================================================
function printSummary(method, score, threshold, reportTbl)
    fprintf('\n========== Baseline outlier screening (method: %s) ==========\n', method);
    if all(isnan(score))
        fprintf('No scores computed; no exclusions applied.\n');
        return;
    end
    nExcluded = sum(reportTbl.Excluded);
    fprintf('Screened subjects: %d | Excluded: %d | Threshold: %.4g\n', ...
        height(reportTbl), nExcluded, threshold);
    if nExcluded > 0
        exclRows = reportTbl(reportTbl.Excluded, :);
        fprintf('Excluded subjects:\n');
        for i = 1:height(exclRows)
            fprintf('  - %s (score %.4g): %s\n', exclRows.Mouse_ID{i}, exclRows.OutlierScore(i), exclRows.Reason{i});
        end
    end
end
