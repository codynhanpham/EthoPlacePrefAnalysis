function [rankedTbl, componentsLongTbl, info, baselineData] = rankSubjectSimilarityToBaseline(baselineStdTables, testStdTables, kvargs)
    %%RANKSUBJECTSIMILARITYTOBASELINE Rank test subjects by similarity to a baseline population
    %
    %   [rankedTbl, componentsLongTbl, info, baselineData] = ...
    %       population.temp.rankSubjectSimilarityToBaseline(baselineStdTables, testStdTables)
    %   [rankedTbl, componentsLongTbl, info] = rankSubjectSimilarityToBaseline(..., Name=Value)
    %
    %   Ranks each subject in testStdTables (e.g., MECP2 KO) by multivariate
    %   similarity to the baseline population in baselineStdTables (e.g., C57 WT).
    %   Both inputs are standardizedTables struct arrays (population.stats.populationPositionOverTime
    %   output), pre-filtered per group by the caller (e.g., via sdTable.subsetByMetadata).
    %
    %   Feature vector per subject (computed per group via cohort.metrics so both
    %   groups go through IDENTICAL processing; plot sign conventions are kept):
    %       - Preference index during all-stim and per-stim active periods
    %         (cohort.metrics.preferenceIndex)
    %       - Percent time on each stimulus side during active stimulus
    %         (cohort.metrics.rateofstay)
    %       - Progression components per (protocol, stim): DeltaEndStart,
    %         TheilSenSlope, KendallTau, ProgressEfficiency
    %         (cohort.metrics.binnedProgression + cohort.metrics.progressionComponents)
    %   A locomotion covariate (default: mean speed during stimulus from
    %   cohort.metrics.speed) is NOT a feature; it is used only to residualize
    %   features for the "adjusted" (motor-covariate-controlled) scoring layer.
    %
    %   Scoring layers:
    %       1. Robust z per feature vs baseline (median / 1.4826*MAD; falls back
    %          to mean/SD, then to a degenerate-flagged z=0).
    %       2. Mahalanobis D2 to the baseline centroid using shrinkage covariance
    %          (Ledoit-Wolf-style blend toward scaled identity; lambda auto-raised
    %          from MinShrinkageLambda until well-conditioned). Pairwise-complete:
    %          subjects with NaN features are scored on their observed features.
    %       3. Leave-one-out (LOO) baseline null: each baseline subject is scored
    %          against the other n-1 baseline subjects; the empirical p-value of a
    %          test subject is the fraction of LOO D2 values it exceeds
    %          (add-one smoothing). This calibrates the score to the small-n
    %          baseline reference.
    %       4. Adjusted layer: each feature is residualized on the locomotion
    %          covariate using a baseline-only OLS fit, then layers 1-3 are
    %          repeated (columns suffixed _Adj).
    %       5. Trajectory layer: per (protocol, stim) RMSE of the subject's binned
    %          progression curve vs the baseline mean curve (raw + adjusted).
    %
    %   Name-Value Pair Arguments:
    %       ProgressionMetricType       : "state" (default) | "distance" - metric for
    %                                     binned progression features.
    %       BinWidth                    : bouts per progression bin (default 6).
    %       MeanWindowFrames            : smoothing window frames (default 30).
    %       StimulusIncludesTrailingISI : passed to cohort metrics (default true).
    %       LocomotionCovariateColumn   : column of cohort.metrics.speed output used
    %                                     as the covariate (default
    %                                     "Speed Mean During Stimulus (cm/s)").
    %       AdjustmentLabel             : human-readable label for the adjusted
    %                                     scoring layer (default
    %                                     "Locomotion covariate-controlled").
    %       WTEnvelopePct               : [lo hi] empirical percentile envelope of the
    %                                     baseline used for the OutsideWT flags
    %                                     (default [5 95]).
    %       MinShrinkageLambda          : starting shrinkage lambda in [0,1]
    %                                     (default 0.1; auto-raised as needed).
    %       OutlierMethod               : baseline outlier screening method:
    %                                     "none" (default) | "multivariate" |
    %                                     "mixedquality" | "baselinelocomotion".
    %                                     Excluded baseline subjects are removed
    %                                     BEFORE feature computation (see
    %                                     outlier.excludeBaselineSubjects). Test
    %                                     subjects are never excluded.
    %       OutlierThresholdK           : robust MAD multiplier for outlier
    %                                     detection (default 3.5).
    %       MinValidBins                : "mixedquality" minimum valid progression
    %                                     bins per baseline subject (default 2).
    %       MinPreStimDistanceCm        : "baselinelocomotion" pre-stimulus distance
    %                                     threshold in cm; NaN = auto MAD-based
    %                                     (default NaN).
    %       MinMeanSpeedCmS             : "mixedquality" near-zero locomotion
    %                                     threshold (default 0.1 cm/s).
    %       OutputDir                   : if non-empty, export TSVs here (default "").
    %       FilePrefix                  : export filename prefix (default "similarity").
    %       RunStamp                    : optional run stamp included in filenames
    %                                     (default "").
    %       Verbose                     : print summary (default true).
    %
    %   Outputs:
    %       rankedTbl : one row per TEST subject, sorted most-baseline-like first
    %           (ascending MahalanobisD2; NaN scores last). Columns:
    %           - 8 common headers + Group (strain)
    %           - Z__{feature}, Pctile__{feature}, OutsideWT__{feature} per feature
    %           - MahalanobisD2, EmpiricalP, Rank_Similarity (1 = most similar)
    %           - NOutsideWT, MaxAbsZ, MeanAbsZ, NMetricFeaturesUsed, NMetricFeaturesNaN
    %           - Adjusted layer: MahalanobisD2_Adj, EmpiricalP_Adj, Rank_Similarity_Adj
    %           - Trajectory: TrajRMSE__{stim}, TrajRMSE_Adj__{stim}, MeanTrajRMSE,
    %             MeanTrajRMSE_Adj
    %       componentsLongTbl : tidy long table, one row per (subject, feature):
    %           SubjectKey, Group, Feature, Value, WTMedian, WTScale, Z, Pctile,
    %           OutsideWT, ResidualAdj
    %       info : struct with diagnostics: FeatureNames, ShrinkageLambda,
    %           LOO_D2 (baseline leave-one-out D2), LOO_P, LocomotionCovariateColumn,
    %           ProgressionMetricType, WTEnvelopePct, OutlierMethod,
    %           OutlierThresholdK, ExcludedBaselineSubjects (exclusion report
    %           table, one row per baseline subject), NBaselineExcluded,
    %           ExportedFiles
    %       baselineData : post-filter baseline representation for visualization,
    %           including FeatureMatrix, ZMatrix, adjusted matrices, robust
    %           centers/scales, trajectory tables, metadata, and covariate.
    %
    %   See also: population.temp.rankSubjectProgression, cohort.metrics.progressionComponents,
    %             cohort.metrics.binnedProgression, cohort.metrics.preferenceIndex,
    %             cohort.metrics.rateofstay, cohort.metrics.speed

    arguments
        baselineStdTables struct {sdTable.mustBeStandardizedTable}
        testStdTables struct {sdTable.mustBeStandardizedTable}
        kvargs.ProgressionMetricType (1,1) string {mustBeMember(kvargs.ProgressionMetricType, ["state", "distance"])} = "state"
        kvargs.BinWidth (1,1) double {mustBePositive, mustBeInteger} = 6
        kvargs.MeanWindowFrames (1,1) double {mustBePositive, mustBeInteger} = 30
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.LocomotionCovariateColumn (1,1) string {mustBeTextScalar} = "Speed Mean During Stimulus (cm/s)"
        kvargs.AdjustmentLabel (1,1) string {mustBeTextScalar} = ""
        kvargs.WTEnvelopePct (1,2) double {mustBeInRange(kvargs.WTEnvelopePct, 0, 100), mustBeEnvelopeSorted(kvargs.WTEnvelopePct)} = [5 95]
        kvargs.MinShrinkageLambda (1,1) double {mustBeNonnegative, mustBeLessThanOrEqual(kvargs.MinShrinkageLambda, 1)} = 0.1
        kvargs.OutlierMethod (1,1) string {mustBeMember(kvargs.OutlierMethod, ["none", "multivariate", "mixedquality", "baselinelocomotion"])} = "none"
        kvargs.OutlierThresholdK (1,1) double {mustBePositive} = 3.5
        kvargs.MinValidBins (1,1) double {mustBePositive, mustBeInteger} = 2
        kvargs.MinPreStimDistanceCm (1,1) double {mustBeReal} = NaN
        kvargs.MinMeanSpeedCmS (1,1) double {mustBeNonnegative} = 0.1
        kvargs.OutputDir (1,1) string {mustBeTextScalar} = ""
        kvargs.FilePrefix (1,1) string {mustBeTextScalar} = "similarity"
        kvargs.RunStamp (1,1) string {mustBeTextScalar} = ""
        kvargs.Verbose (1,1) logical = true
    end

    %% Baseline outlier pre-filter (baseline group only; test subjects always ranked)
    [baselineStdTables, exclusionReport] = outlier.excludeBaselineSubjects(baselineStdTables, ...
        'OutlierMethod', kvargs.OutlierMethod, ...
        'OutlierThresholdK', kvargs.OutlierThresholdK, ...
        'MinValidBins', kvargs.MinValidBins, ...
        'MinPreStimDistanceCm', kvargs.MinPreStimDistanceCm, ...
        'MinMeanSpeedCmS', kvargs.MinMeanSpeedCmS, ...
        'LocomotionCovariateColumn', kvargs.LocomotionCovariateColumn, ...
        'MinShrinkageLambda', kvargs.MinShrinkageLambda, ...
        'ProgressionMetricType', kvargs.ProgressionMetricType, ...
        'BinWidth', kvargs.BinWidth, ...
        'MeanWindowFrames', kvargs.MeanWindowFrames, ...
        'StimulusIncludesTrailingISI', kvargs.StimulusIncludesTrailingISI, ...
        'Verbose', kvargs.Verbose);

    %% Per-group feature computation
    [baseData, testData] = deal(buildGroupData(baselineStdTables, kvargs), buildGroupData(testStdTables, kvargs));

    % Align feature sets across groups (identical processing requirement).
    [featureNames, baseFeat, testFeat] = alignFeatures(baseData.featWide, testData.featWide);
    [trajNames, ~, testTraj] = alignFeatureTables(baseData.trajWide, testData.trajWide);

    nWT = height(baseData.meta);
    nTe = height(testData.meta);
    if nWT < 4
        error('rankSubjectSimilarityToBaseline:tooFewBaseline', ...
            'Baseline group has only %d subjects; at least 4 are required for LOO-calibrated scoring.', nWT);
    end

    covWt = baseData.cov;
    covTe = testData.cov;

    %% Layer 1+2+3: raw scoring
    [zTe, pctTe, outTe, degenerate, wtMed, wtScale] = zLayer(baseFeat, testFeat, kvargs.WTEnvelopePct);
    [d2Te, lamTe] = outlier.internal.mahalanobisScores(baseFeat, testFeat, kvargs.MinShrinkageLambda);
    looD2 = outlier.internal.looBaselineD2(baseFeat, kvargs.MinShrinkageLambda);
    empP = empiricalPFromLOO(d2Te, looD2);

    %% Layer 4: adjusted (locomotion-residualized) scoring
    [baseAdj, testAdj, ~, ~, adjFitOk] = residualizeOnCovariate(baseFeat, testFeat, covWt, covTe);
    [~, ~, outTeAdj, ~, ~, ~] = zLayer(baseAdj, testAdj, kvargs.WTEnvelopePct);
    [d2TeAdj, lamTeAdj] = outlier.internal.mahalanobisScores(baseAdj, testAdj, kvargs.MinShrinkageLambda);
    looD2Adj = outlier.internal.looBaselineD2(baseAdj, kvargs.MinShrinkageLambda);
    empPAdj = empiricalPFromLOO(d2TeAdj, looD2Adj);

    % Residualize progression curves before recomputing trajectory RMSE. RMSE
    % itself must remain nonnegative; residualizing already-computed RMSE
    % columns does not preserve that property.
    [baseProgressionAdj, testProgressionAdj] = residualizeProgressionOnCovariate( ...
        baseData.progressionLongTable, testData.progressionLongTable, ...
        covWt, covTe, baseData.meta.SubjectKey, testData.meta.SubjectKey);
    baseTrajAdj = trajRmseWide(baseProgressionAdj, baseProgressionAdj, ...
        baseData.meta.SubjectKey, numel(unique(string(baseProgressionAdj.StimulusProtocol))) > 1);
    testTrajAdj = trajRmseWide(baseProgressionAdj, testProgressionAdj, ...
        testData.meta.SubjectKey, numel(unique(string(baseProgressionAdj.StimulusProtocol))) > 1);

    % Expose the post-filter baseline representation for aggregate-reference plots.
    [baseZ, ~, ~, ~, ~, ~] = zLayer(baseFeat, baseFeat, kvargs.WTEnvelopePct);
    [baseZAdj, ~, ~, ~, ~, ~] = zLayer(baseAdj, baseAdj, kvargs.WTEnvelopePct);
    baselineData = baseData;
    baselineData.FeatureNames = featureNames;
    baselineData.FeatureMatrix = baseFeat;
    baselineData.FeatureMatrixAdj = baseAdj;
    baselineData.ZMatrix = baseZ;
    baselineData.ZMatrixAdj = baseZAdj;
    baselineData.WTMedian = wtMed;
    baselineData.WTScale = wtScale;
    baselineData.TrajectoryFeatureNames = trajNames;
    baselineData.progressionLongTableAdj = baseProgressionAdj;
    baselineData.TrajectoryTableAdj = baseTrajAdj;

    %% Assemble ranked table (test subjects, most-baseline-like first)
    rankedTbl = assembleRankedTable(testData.meta, featureNames, trajNames, ...
        zTe, pctTe, outTe, d2Te, empP, ...
        outTeAdj, d2TeAdj, empPAdj, ...
        testTraj, testTrajAdj);

    %% Tidy long components table
    componentsLongTbl = assembleLongTable(testData.meta, featureNames, ...
        testFeat, wtMed, wtScale, zTe, pctTe, outTe, testAdj);

    %% Diagnostics info
    info = struct();
    info.FeatureNames = {featureNames};
    info.TrajectoryFeatureNames = {trajNames};
    info.ShrinkageLambda = struct('RawMax', max(lamTe), 'RawMin', min(lamTe), ...
        'AdjMax', max(lamTeAdj), 'AdjMin', min(lamTeAdj));
    info.LOO_D2 = looD2;
    info.LOO_D2_Adj = looD2Adj;
    info.LOO_P = empiricalPFromLOO(looD2, looD2);   % each WT vs the LOO null
    info.LocomotionCovariateColumn = kvargs.LocomotionCovariateColumn;
    adjustmentLabel = kvargs.AdjustmentLabel;
    if strlength(adjustmentLabel) == 0
        adjustmentLabel = "Locomotion covariate-controlled";
    end
    info.Adjustment = struct( ...
        'Label', adjustmentLabel, ...
        'Method', "Baseline-only OLS residualization", ...
        'CovariateColumns', kvargs.LocomotionCovariateColumn, ...
        'Description', "Features residualized against the baseline-only locomotion covariate fit");
    info.ProgressionMetricType = kvargs.ProgressionMetricType;
    info.WTEnvelopePct = kvargs.WTEnvelopePct;
    info.OutlierMethod = kvargs.OutlierMethod;
    info.OutlierThresholdK = kvargs.OutlierThresholdK;
    info.ExcludedBaselineSubjects = exclusionReport;
    info.NBaselineExcluded = sum(exclusionReport.Excluded);
    info.DegenerateFeatures = featureNames(degenerate);
    info.AdjustedFitOK = adjFitOk;
    info.ExportedFiles = {};

    %% Export
    exportedFiles = strings(0, 1);
    if strlength(string(kvargs.OutputDir)) > 0
        outputDir = char(kvargs.OutputDir);
        if ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
        nameBase = strtrim(sprintf('%s %s', kvargs.FilePrefix, kvargs.RunStamp));
        nameBase = regexprep(nameBase, '\s+', '_');
        rankedPath = fullfile(outputDir, [nameBase '_similarity_ranked.tsv']);
        longPath = fullfile(outputDir, [nameBase '_similarity_components_long.tsv']);
        writetable(rankedTbl, rankedPath, 'Delimiter', '\t');
        writetable(componentsLongTbl, longPath, 'Delimiter', '\t');
        exportedFiles = [string(rankedPath), string(longPath)]; %#ok<AGROW>
        if ~isempty(exclusionReport) && any(exclusionReport.Excluded)
            exclPath = fullfile(outputDir, [nameBase '_similarity_excluded_baseline.tsv']);
            writetable(exclusionReport, exclPath, 'Delimiter', '\t');
            exportedFiles = [exportedFiles, string(exclPath)]; %#ok<AGROW>
        end
        info.ExportedFiles = {exportedFiles};
    end

    %% Verbose summary
    if kvargs.Verbose
        fprintf('\n========== Similarity-to-baseline ranking ==========\n');
        fprintf('Baseline subjects: %d | Test subjects: %d | Features: %d\n', nWT, nTe, numel(featureNames));
        if info.NBaselineExcluded > 0
            fprintf('Baseline outliers excluded (%s): %d\n', kvargs.OutlierMethod, info.NBaselineExcluded);
        end
        fprintf('Progression metric: %s | Covariate: "%s"\n', kvargs.ProgressionMetricType, kvargs.LocomotionCovariateColumn);
        if ~isempty(info.DegenerateFeatures)
            fprintf('WARNING: degenerate (constant) baseline features flagged: %s\n', ...
                strjoin(info.DegenerateFeatures, ', '));
        end
        fprintf('Shrinkage lambda (raw): %.2f..%.2f | (adj): %.2f..%.2f\n', ...
            info.ShrinkageLambda.RawMin, info.ShrinkageLambda.RawMax, ...
            info.ShrinkageLambda.AdjMin, info.ShrinkageLambda.AdjMax);
        fprintf('LOO baseline null D2: min %.3f | median %.3f | max %.3f\n', ...
            min(looD2), median(looD2), max(looD2));
        fprintf('Test subjects outside WT envelope on >= 1 feature: %d of %d\n', ...
            nnz(rankedTbl.NOutsideWT > 0), nTe);
        headCols = {'Mouse_ID', 'Group', 'MahalanobisD2', 'EmpiricalP', 'Rank_Similarity', ...
            'MahalanobisD2_Adj', 'NOutsideWT'};
        headCols = headCols(ismember(headCols, rankedTbl.Properties.VariableNames));
        disp(rankedTbl(:, headCols));
        if ~isempty(exportedFiles)
            fprintf('Saved similarity exports to:\n  %s\n', strjoin(cellstr(exportedFiles), newline + '  '));
        end
    end
end

%% ==================================================================
%% Group data building
%% ==================================================================
function data = buildGroupData(stdTables, kvargs)
    % Computes all per-subject features for ONE group's standardizedTables.

    tPref = cohort.metrics.preferenceIndex(stdTables, ...
        'StimulusIncludesTrailingISI', kvargs.StimulusIncludesTrailingISI);
    tStay = cohort.metrics.rateofstay(stdTables, ...
        'StimulusIncludesTrailingISI', kvargs.StimulusIncludesTrailingISI);
    tSpeed = cohort.metrics.speed(stdTables, ...
        'StimulusIncludesTrailingISI', kvargs.StimulusIncludesTrailingISI);
    tProg = cohort.metrics.binnedProgression(stdTables, ...
        'MetricType', kvargs.ProgressionMetricType, ...
        'BinWidth', kvargs.BinWidth, ...
        'MeanWindowFrames', kvargs.MeanWindowFrames);

    % Melt binned progression into the tidy long form and score components.
    longTbl = normalizeProgressionInput(tProg, kvargs.ProgressionMetricType);
    progComp = cohort.metrics.progressionComponents(longTbl);

    outputStimNames = cohort.metrics.utils.getOutputStimNames(stdTables, []);
    nStims = numel(outputStimNames);
    labels = cell(1, nStims);
    for g = 1:nStims
        labels{g} = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
    end

    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'};

    % ---- Preference index features (from tPref rows) ----
    prefAllCol = findColumn(tPref, 'Preference Index During Active Stimulus', 'preferenceIndex');
    stim1Label = extractBefore(prefAllCol, ' Preference Index During Active Stimulus');
    keysPref = outlier.internal.subjectKeysFromTable(tPref, commonHeaders);
    entries = cell(0, 3);
    for r = 1:height(tPref)
        entries = appendEntry(entries, keysPref{r}, 'PrefIdx__All', tPref.(prefAllCol)(r));
        for g = 1:nStims
            colName = sprintf('%s Preference Index During %s', stim1Label, labels{g});
            if ismember(colName, tPref.Properties.VariableNames)
                entries = appendEntry(entries, keysPref{r}, sprintf('PrefIdx__%s', labels{g}), tPref.(colName)(r));
            end
        end
    end

    % ---- Rate-of-stay features (matched by subject key) ----
    keysStay = outlier.internal.subjectKeysFromTable(tStay, commonHeaders);
    for g = 1:nStims
        colName = sprintf('Percent Time on %s Side During Active Stimulus (%%)', labels{g});
        if ~ismember(colName, tStay.Properties.VariableNames)
            continue;
        end
        for r = 1:height(tStay)
            entries = appendEntry(entries, keysStay{r}, sprintf('StayPct__%s', labels{g}), tStay.(colName)(r));
        end
    end

    % ---- Progression component features ----
    protocols = unique(string(progComp.StimulusProtocol), 'stable');
    multiProto = numel(protocols) > 1;
    components = {'DeltaEndStart', 'TheilSenSlope', 'KendallTau', 'ProgressEfficiency'};
    for r = 1:height(progComp)
        stimTag = char(progComp.Stimulus(r));
        if multiProto
            stimTag = sprintf('%s @%s', stimTag, char(progComp.StimulusProtocol(r)));
        end
        for c = 1:numel(components)
            entries = appendEntry(entries, char(progComp.SubjectKey(r)), ...
                sprintf('%s__%s', components{c}, stimTag), progComp.(components{c})(r));
        end
    end

    % ---- Locomotion covariate ----
    if ~ismember(char(kvargs.LocomotionCovariateColumn), tSpeed.Properties.VariableNames)
        speedCols = tSpeed.Properties.VariableNames(contains(tSpeed.Properties.VariableNames, 'Speed'));
        error('rankSubjectSimilarityToBaseline:badCovariateColumn', ...
            ['LocomotionCovariateColumn ''%s'' not found in cohort.metrics.speed output. ' ...
            'Available speed columns: %s'], kvargs.LocomotionCovariateColumn, strjoin(speedCols, ', '));
    end
    keysSpeed = outlier.internal.subjectKeysFromTable(tSpeed, commonHeaders);
    covEntries = cell(0, 3);
    for r = 1:height(tSpeed)
        covEntries = appendEntry(covEntries, keysSpeed{r}, 'LocomotionCovariate', ...
            tSpeed.(char(kvargs.LocomotionCovariateColumn))(r));
    end

    % ---- Aggregate per subject (mean omitnan across stimset rows) ----
    [featWide, meta] = outlier.internal.pivotEntries(entries, tPref, commonHeaders);
    cov = pivotCovariate(covEntries, meta.SubjectKey);

    % ---- Trajectory RMSE features (curves from this group's long table) ----
    trajWide = trajRmseWide(longTbl, longTbl, meta.SubjectKey, multiProto);

    data = struct('featWide', {featWide}, 'trajWide', {trajWide}, ...
        'progressionLongTable', {longTbl}, 'meta', {meta}, 'cov', cov);
end

function entries = appendEntry(entries, subjKey, featName, value)
    entries(end+1, :) = {subjKey, featName, value}; %#ok<AGROW>
end

function colName = findColumn(T, pattern, metricName)
    hits = T.Properties.VariableNames(contains(T.Properties.VariableNames, pattern, 'IgnoreCase', false));
    if isempty(hits)
        error('rankSubjectSimilarityToBaseline:missingColumn', ...
            'Could not find a ''%s'' column in the %s output table.', pattern, metricName);
    end
    colName = hits{1};
end

function cov = pivotCovariate(covEntries, subjKeys)
    cov = nan(numel(subjKeys), 1);
    for si = 1:numel(subjKeys)
        m = strcmp(covEntries(:, 1), subjKeys{si});
        if any(m)
            cov(si) = mean(cell2mat(covEntries(m, 3)), 'omitnan');
        end
    end
end

function trajWide = trajRmseWide(longTblWt, longTblEval, evalSubjectKeys, multiProto)
    % Per (protocol, stim) RMSE of each eval subject's binned progression curve
    % vs the mean curve of the WT (longTblWt) subjects.
    trajWide = table(evalSubjectKeys, 'VariableNames', {'SubjectKey'});

    wtPairs = unique(longTblWt(:, {'StimulusProtocol', 'Stimulus'}), 'stable');
    protoCol = string(longTblWt.StimulusProtocol);
    stimCol = string(longTblWt.Stimulus);
    for pi = 1:height(wtPairs)
        proto = string(wtPairs.StimulusProtocol(pi));
        stim = string(wtPairs.Stimulus(pi));
        pairMask = protoCol == proto & stimCol == stim;
        evalPairMask = string(longTblEval.StimulusProtocol) == proto & ...
            string(longTblEval.Stimulus) == stim;
        wtRows = longTblWt(pairMask, :);
        wtRows = wtRows(isfinite(wtRows.Progression), :);
        if isempty(wtRows)
            continue;
        end
        grid = unique(wtRows.BinIdx)';
        wtMean = arrayfun(@(b) mean(wtRows.Progression(wtRows.BinIdx == b), 'omitnan'), grid);

        stimTag = char(stim);
        if multiProto
            stimTag = sprintf('%s @%s', stimTag, char(proto));
        end
        featName = sprintf('TrajRMSE__%s', stimTag);

        vals = nan(numel(evalSubjectKeys), 1);
        for si = 1:numel(evalSubjectKeys)
            rows = longTblEval(evalPairMask & strcmp(longTblEval.SubjectKey, evalSubjectKeys{si}), :);
            if isempty(rows)
                continue;
            end
            subjVals = nan(size(grid));
            for gi = 1:numel(grid)
                hit = rows.BinIdx == grid(gi);
                if any(hit)
                    subjVals(gi) = rows.Progression(hit);
                end
            end
            d = subjVals - wtMean;
            d = d(isfinite(d));
            if ~isempty(d)
                vals(si) = sqrt(mean(d.^2));
            end
        end
        trajWide.(featName) = vals;
    end
end

%% ==================================================================
%% Feature alignment
%% ==================================================================
function [names, Xwt, Xte] = alignFeatures(wtWide, teWide)
    wtNames = wtWide.Properties.VariableNames(2:end);   % skip SubjectKey
    teNames = teWide.Properties.VariableNames(2:end);
    onlyWt = setdiff(wtNames, teNames, 'stable');
    onlyTe = setdiff(teNames, wtNames, 'stable');
    if ~isempty(onlyWt) || ~isempty(onlyTe)
        error('rankSubjectSimilarityToBaseline:featureMismatch', ...
            ['Baseline and test groups have mismatched feature sets.\n' ...
            'Only in baseline: %s\nOnly in test: %s\n' ...
            'Both groups must share the same stimulus protocols and stimuli.'], ...
            strjoin(onlyWt, ', '), strjoin(onlyTe, ', '));
    end
    names = wtNames;

    % Align subject rows: match test subjects by SubjectKey into wtWide order is
    % not needed (groups are disjoint); just extract matrices in each table's order.
    Xwt = featureMatrix(wtWide, names);
    Xte = featureMatrix(teWide, names);
end

function X = featureMatrix(wide, names)
    X = nan(height(wide), numel(names));
    for j = 1:numel(names)
        X(:, j) = wide.(names{j});
    end
end

function [names, wtT, teT] = alignFeatureTables(wtWide, teWide)
    % Same alignment contract as alignFeatures, but returns the aligned tables
    % (needed when downstream consumers expect table inputs).
    wtNames = wtWide.Properties.VariableNames(2:end);   % skip SubjectKey
    teNames = teWide.Properties.VariableNames(2:end);
    onlyWt = setdiff(wtNames, teNames, 'stable');
    onlyTe = setdiff(teNames, wtNames, 'stable');
    if ~isempty(onlyWt) || ~isempty(onlyTe)
        error('rankSubjectSimilarityToBaseline:featureMismatch', ...
            ['Baseline and test groups have mismatched feature sets.\n' ...
            'Only in baseline: %s\nOnly in test: %s\n' ...
            'Both groups must share the same stimulus protocols and stimuli.'], ...
            strjoin(onlyWt, ', '), strjoin(onlyTe, ', '));
    end
    names = wtNames;
    wtT = wtWide(:, [{'SubjectKey'}, names]);
    teT = teWide(:, [{'SubjectKey'}, names]);
end

%% ==================================================================
%% Layer 1: robust z / percentile / envelope
%% ==================================================================
function [zMat, pctMat, outMat, degenerateMask, wtMed, wtScale] = zLayer(Xwt, Xte, envPct)
    [nTe, p] = size(Xte);
    zMat = nan(nTe, p);
    pctMat = nan(nTe, p);
    outMat = false(nTe, p);
    degenerateMask = false(1, p);
    wtMed = nan(1, p);
    wtScale = nan(1, p);

    for j = 1:p
        w = Xwt(:, j);
        w = w(isfinite(w));
        med = median(w);
        sc = 1.4826 * median(abs(w - med));
        if ~(isfinite(sc) && sc > 0)
            sc = std(w);   % fall back to mean/SD scaling (median kept for centering)
        end
        if ~(isfinite(sc) && sc > 0)
            degenerateMask(j) = true;   % constant baseline feature -> z = 0
            sc = 1;
        end
        wtMed(j) = med;
        wtScale(j) = sc;

        v = Xte(:, j);
        zMat(:, j) = (v - med) ./ sc;
        for i = 1:nTe
            if isfinite(v(i)) && ~isempty(w)
                pctMat(i, j) = 100 * (nnz(w < v(i)) + 0.5 * nnz(w == v(i))) / numel(w);
                outMat(i, j) = pctMat(i, j) < envPct(1) || pctMat(i, j) > envPct(2);
            end
        end
    end
end

%% ==================================================================
%% Layer 2+3: shrinkage Mahalanobis D2 and LOO null
%% (moved to outlier.internal for reuse by outlier.excludeBaselineSubjects)
%% ==================================================================
%% ==================================================================
%% Layer 3: leave-one-out baseline null
%% ==================================================================
function p = empiricalPFromLOO(d2Targets, looD2)
    nWT = numel(looD2);
    p = nan(size(d2Targets));
    for i = 1:numel(d2Targets)
        if isfinite(d2Targets(i))
            p(i) = (nnz(looD2 >= d2Targets(i)) + 1) / (nWT + 1);
        end
    end
end

%% ==================================================================
%% Layer 4: locomotion residualization
%% ==================================================================
function [XwtR, XteR, covWtC, covTeC, fitOk] = residualizeOnCovariate(Xwt, Xte, covWt, covTe)
    % Per-feature OLS on baseline subjects only; residuals re-centered so the
    % baseline centroid stays at the baseline mean level.
    [nWt, p] = size(Xwt);
    nTe = size(Xte, 1);
    XwtR = nan(nWt, p);
    XteR = nan(nTe, p);
    fitOk = true(1, p);

    meanCovWt = mean(covWt(isfinite(covWt)), 'omitnan');
    covWtC = covWt - meanCovWt;
    covTeC = covTe - meanCovWt;

    for j = 1:p
        ok = isfinite(Xwt(:, j)) & isfinite(covWt);
        if nnz(ok) >= 3 && std(covWt(ok), 'omitnan') > 0
            b = corrCoefSlope(covWt(ok), Xwt(ok, j));
            a = mean(Xwt(ok, j), 'omitnan') - b * mean(covWt(ok), 'omitnan');
            XwtR(:, j) = Xwt(:, j) - (a + b * covWt) + mean(Xwt(ok, j), 'omitnan');
            XteR(:, j) = Xte(:, j) - (a + b * covTe) + mean(Xwt(ok, j), 'omitnan');
        else
            % Degenerate covariate fit: center-only residualization.
            fitOk(j) = false;
            mu = mean(Xwt(:, j), 'omitnan');
            XwtR(:, j) = Xwt(:, j) - mu;
            XteR(:, j) = Xte(:, j) - mu;
        end
    end
end

function b = corrCoefSlope(x, y)
    % OLS slope of y on x (both finite by caller contract).
    xm = mean(x); ym = mean(y);
    dx = x - xm;
    denom = sum(dx.^2);
    if denom > 0
        b = sum(dx .* (y - ym)) / denom;
    else
        b = 0;
    end
end

function [wtR, teR] = residualizeProgressionOnCovariate(wtLong, teLong, covWt, covTe, wtKeys, teKeys)
    % Fit one baseline-only locomotion slope per protocol/stimulus, with bin
    % effects preserved. This is more stable than fitting a separate slope at
    % every bin and keeps the baseline mean trajectory at each bin unchanged.
    wtR = wtLong;
    teR = teLong;
    wtSubjectKeys = string(wtKeys);
    teSubjectKeys = string(teKeys);
    wtRowKeys = string(wtLong.SubjectKey);
    teRowKeys = string(teLong.SubjectKey);
    pairs = unique(wtLong(:, {'StimulusProtocol', 'Stimulus'}), 'stable');

    for pi = 1:height(pairs)
        protocol = string(pairs.StimulusProtocol(pi));
        stimulus = string(pairs.Stimulus(pi));
        wtMask = string(wtLong.StimulusProtocol) == protocol & string(wtLong.Stimulus) == stimulus;
        teMask = string(teLong.StimulusProtocol) == protocol & string(teLong.Stimulus) == stimulus;
        if ~any(wtMask)
            continue;
        end

        wtCovRows = covariateForSubjects(wtRowKeys(wtMask), wtSubjectKeys, covWt);
        wtValues = wtLong.Progression(wtMask);
        fitOK = isfinite(wtValues) & isfinite(wtCovRows);
        nSubjects = numel(unique(wtRowKeys(fitOK)));
        if nSubjects >= 3 && std(wtCovRows(fitOK), 'omitnan') > 0
            meanCov = mean(wtCovRows(fitOK), 'omitnan');
            binMeans = binMeansForRows(wtLong.BinIdx(wtMask), wtValues);
            centeredValues = wtValues - binMeans;
            fitOK = fitOK & isfinite(centeredValues);
            centeredCov = wtCovRows - meanCov;
            slope = sum(centeredCov(fitOK) .* centeredValues(fitOK)) / ...
                sum(centeredCov(fitOK) .^ 2);
            wtR.Progression(wtMask) = wtValues - slope * centeredCov;

            if any(teMask)
                teCovRows = covariateForSubjects(teRowKeys(teMask), teSubjectKeys, covTe);
                teValues = teLong.Progression(teMask);
                teR.Progression(teMask) = teValues - slope * (teCovRows - meanCov);
            end
        else
            % No stable locomotion fit: retain the raw curve rather than
            % creating an artificial adjusted trajectory.
        end
    end
end

function means = binMeansForRows(binIdx, values)
    means = nan(size(values));
    bins = unique(binIdx, 'stable');
    for i = 1:numel(bins)
        mask = binIdx == bins(i);
        means(mask) = mean(values(mask), 'omitnan');
    end
end

function covRows = covariateForSubjects(subjectKeys, referenceKeys, referenceCov)
    covRows = nan(size(subjectKeys));
    for i = 1:numel(subjectKeys)
        hit = find(referenceKeys == subjectKeys(i), 1, 'first');
        if ~isempty(hit)
            covRows(i) = referenceCov(hit);
        end
    end
end

%% ==================================================================
%% Output assembly
%% ==================================================================
function rankedTbl = assembleRankedTable(meta, featureNames, trajNames, ...
    zTe, pctTe, outTe, d2Te, empP, outTeAdj, d2TeAdj, empPAdj, ...
    testTraj, testTrajAdj)

    nTe = height(meta);
    rankedTbl = meta(:, [{'SubjectKey'}, {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', ...
        'Sex$', 'Genotype$', 'Litter', 'Toe_ID', 'Group'}]);

    for j = 1:numel(featureNames)
        rankedTbl.(sprintf('Z__%s', featureNames{j})) = zTe(:, j);
        rankedTbl.(sprintf('Pctile__%s', featureNames{j})) = pctTe(:, j);
        rankedTbl.(sprintf('OutsideWT__%s', featureNames{j})) = outTe(:, j);
    end

    rankedTbl.('MahalanobisD2') = d2Te;
    rankedTbl.('EmpiricalP') = empP;

    % Rank: 1 = most baseline-like (smallest D2); NaN scores get NaN rank.
    rankSim = nan(nTe, 1);
    finiteIdx = find(isfinite(d2Te));
    [~, order] = sort(d2Te(finiteIdx), 'ascend');
    rankSim(finiteIdx(order)) = 1:numel(finiteIdx);
    rankedTbl.('Rank_Similarity') = rankSim;

    rankedTbl.('NOutsideWT') = sum(outTe, 2);
    absz = abs(zTe);
    rankedTbl.('MaxAbsZ') = max(absz, [], 2, 'omitnan');
    rankedTbl.('MeanAbsZ') = mean(absz, 2, 'omitnan');
    rankedTbl.('NMetricFeaturesUsed') = sum(isfinite(zTe), 2);
    rankedTbl.('NMetricFeaturesNaN') = sum(~isfinite(zTe), 2);

    rankedTbl.('MahalanobisD2_Adj') = d2TeAdj;
    rankedTbl.('EmpiricalP_Adj') = empPAdj;
    for j = 1:numel(featureNames)
        rankedTbl.(sprintf('OutsideWT_Adj__%s', featureNames{j})) = outTeAdj(:, j);
    end
    rankAdj = nan(nTe, 1);
    finiteIdxAdj = find(isfinite(d2TeAdj));
    [~, orderAdj] = sort(d2TeAdj(finiteIdxAdj), 'ascend');
    rankAdj(finiteIdxAdj(orderAdj)) = 1:numel(finiteIdxAdj);
    rankedTbl.('Rank_Similarity_Adj') = rankAdj;

    % Trajectory RMSE columns (raw + adjusted).
    for j = 1:numel(trajNames)
        rankedTbl.(trajNames{j}) = testTraj.(trajNames{j});
        adjName = strrep(trajNames{j}, 'TrajRMSE__', 'TrajRMSE_Adj__');
        rankedTbl.(adjName) = testTrajAdj.(trajNames{j});
    end
    trajVals = featureMatrix(testTraj, trajNames);
    trajValsAdj = featureMatrix(testTrajAdj, trajNames);
    rankedTbl.('MeanTrajRMSE') = mean(trajVals, 2, 'omitnan');
    rankedTbl.('MeanTrajRMSE_Adj') = mean(trajValsAdj, 2, 'omitnan');

    % Sort: most baseline-like first; NaN D2 last.
    [~, sortOrd] = sort(isnan(d2Te), 'ascend');   % NaNs (1) after finite (0)...
    [~, tieOrd] = sort(d2Te(sortOrd), 'ascend');  % ...then ascending D2 within groups
    sortOrd = sortOrd(tieOrd);
    rankedTbl = rankedTbl(sortOrd, :);
    if any(isnan(d2Te))
        % Keep NaN-scored subjects at the bottom with NaN ranks.
        nanRows = isnan(rankedTbl.MahalanobisD2);
        rankedTbl.Rank_Similarity(nanRows) = NaN;
        rankedTbl.Rank_Similarity_Adj(isnan(rankedTbl.MahalanobisD2_Adj)) = NaN;
    end
end

function componentsLongTbl = assembleLongTable(meta, featureNames, testFeat, wtMed, wtScale, zTe, pctTe, outTe, testAdj)
    nRows = height(meta) * numel(featureNames);
    subjKeyCol = repmat({''}, nRows, 1);
    groupCol = repmat({''}, nRows, 1);
    featCol = repmat({''}, nRows, 1);
    valueCol = nan(nRows, 1);
    wtMedCol = nan(nRows, 1);
    wtScaleCol = nan(nRows, 1);
    zCol = nan(nRows, 1);
    pctCol = nan(nRows, 1);
    outCol = false(nRows, 1);
    adjCol = nan(nRows, 1);

    subjKeys = meta.SubjectKey;
    groups = meta.Group;
    r = 0;
    for si = 1:height(meta)
        for j = 1:numel(featureNames)
            r = r + 1;
            subjKeyCol{r} = char(subjKeys(si));
            groupCol{r} = char(groups(si));
            featCol{r} = featureNames{j};
            valueCol(r) = testFeat(si, j);
            wtMedCol(r) = wtMed(j);
            wtScaleCol(r) = wtScale(j);
            zCol(r) = zTe(si, j);
            pctCol(r) = pctTe(si, j);
            outCol(r) = outTe(si, j);
            adjCol(r) = testAdj(si, j);
        end
    end
    componentsLongTbl = table(subjKeyCol, groupCol, featCol, valueCol, wtMedCol, ...
        wtScaleCol, zCol, pctCol, outCol, adjCol, 'VariableNames', ...
        {'SubjectKey', 'Group', 'Feature', 'Value', 'WTMedian', 'WTScale', ...
        'Z', 'Pctile', 'OutsideWT', 'ResidualAdj'});
end

function mustBeEnvelopeSorted(v)
    if ~(v(1) <= v(2))
        error('rankSubjectSimilarityToBaseline:badEnvelopePct', ...
            'WTEnvelopePct must be [lo hi] with lo <= hi.');
    end
end
