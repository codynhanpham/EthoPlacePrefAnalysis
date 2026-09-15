function out = buildExclusionFeatures(stdTables, kvargs)
    %%BUILDEXCLUSIONFEATURES Per-subject metric features + data-quality info for outlier detection.
    %
    %   out = outlier.internal.buildExclusionFeatures(stdTables, Name=Value)
    %
    %   Computes the same per-subject metric feature set used by
    %   population.temp.rankSubjectSimilarityToBaseline's group data builder
    %   (preference index, rate of stay, progression components), via the same
    %   cohort.metrics pipeline, so that multivariate outlier detection runs on
    %   features identical to the similarity scoring features.
    %
    %   The locomotion covariate is NOT a feature; it is returned separately
    %   together with per-subject data-quality counters for the "mixedquality"
    %   outlier method.
    %
    %   Name-Value Pair Arguments:
    %       ProgressionMetricType       : "state" (default) | "distance"
    %       BinWidth                    : bouts per progression bin (default 6)
    %       MeanWindowFrames            : smoothing window frames (default 30)
    %       StimulusIncludesTrailingISI : passed to cohort metrics (default true)
    %       LocomotionCovariateColumn   : column of cohort.metrics.speed output
    %                                     used as the locomotion covariate
    %                                     (default "Speed Mean During Stimulus (cm/s)")
    %
    %   Output struct fields:
    %       featWide     - table, one row per subject: SubjectKey + one column
    %                      per metric feature (NaN where unavailable)
    %       meta         - table, one row per subject: SubjectKey + common
    %                      headers + Group (see outlier.internal.pivotEntries)
    %       cov          - [nSubjects x 1] locomotion covariate value (NaN if missing)
    %       MinValidBins - [nSubjects x 1] minimum NValidBins across the
    %                      subject's progression components rows (Inf if the
    %                      subject has no progression rows at all)

    arguments
        stdTables struct {sdTable.mustBeStandardizedTable}
        kvargs.ProgressionMetricType (1,1) string {mustBeMember(kvargs.ProgressionMetricType, ["state", "distance"])} = "state"
        kvargs.BinWidth (1,1) double {mustBePositive, mustBeInteger} = 6
        kvargs.MeanWindowFrames (1,1) double {mustBePositive, mustBeInteger} = 30
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.LocomotionCovariateColumn (1,1) string {mustBeTextScalar} = "Speed Mean During Stimulus (cm/s)"
    end

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
    longTbl = meltBinnedProgression(tProg);
    progComp = cohort.metrics.progressionComponents(longTbl);

    outputStimNames = cohort.metrics.utils.getOutputStimNames(stdTables, []);
    nStims = numel(outputStimNames);
    labels = cell(1, nStims);
    for g = 1:nStims
        labels{g} = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
    end

    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'};

    % ---- Preference index features (from tPref rows) ----
    prefAllCol = findColumn(tPref, 'Preference Index During Active Stimulus');
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

    % ---- Locomotion covariate (not a feature) ----
    if ~ismember(char(kvargs.LocomotionCovariateColumn), tSpeed.Properties.VariableNames)
        speedCols = tSpeed.Properties.VariableNames(contains(tSpeed.Properties.VariableNames, 'Speed'));
        error('outlier:internal:buildExclusionFeatures:badCovariateColumn', ...
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
    minValidBins = minValidBinsPerSubject(progComp, meta.SubjectKey);

    out = struct('featWide', {featWide}, 'meta', {meta}, 'cov', cov, ...
        'MinValidBins', minValidBins);
end

%% ==================================================================
%% Local helpers
%% ==================================================================
function longTbl = meltBinnedProgression(tProg)
    % Melts the binnedProgression output (TimeBin_N__{label} columns, one row
    % per animal x stimset x stimulus) into the tidy long form expected by
    % cohort.metrics.progressionComponents: one row per
    % (subject, protocol, stim, bin) with a finite Progression value. NaN bins
    % are skipped, matching the normalizeProgressionInput convention.
    % 'cellstr' preallocates cell arrays of char vectors (the warning-free
    % equivalent of the deprecated 'char' table VariableType).
    emptyTypes = {'cellstr', 'double', 'cellstr', 'cellstr', 'cellstr', 'double', 'double'};
    emptyNames = {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', 'Stimulus', ...
        'Group', 'BinIdx', 'Progression'};
    if isempty(tProg)
        longTbl = table('Size', [0 7], 'VariableTypes', emptyTypes, 'VariableNames', emptyNames);
        return;
    end

    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', 'Litter', 'Toe_ID'};
    varNames = tProg.Properties.VariableNames;
    binMask = strncmp(varNames, 'TimeBin_', 8);
    binNames = varNames(binMask);
    if isempty(binNames)
        error('outlier:internal:buildExclusionFeatures:noTimeBinColumns', ...
            'binnedProgression output has no TimeBin_N__ columns to melt.');
    end

    % Bin index from column name: TimeBin_{i}__{label}
    binIdxFromName = zeros(numel(binNames), 1);
    for bi = 1:numel(binNames)
        parts = split(binNames{bi}, '__');
        tok = strrep(parts{1}, 'TimeBin_', '');
        binIdxFromName(bi) = str2double(tok);
    end
    if any(isnan(binIdxFromName))
        error('outlier:internal:buildExclusionFeatures:badTimeBinNames', ...
            'Could not parse bin indices from TimeBin column names.');
    end
    [~, order] = sort(binIdxFromName);
    binNames = binNames(order);
    binIdxFromName = binIdxFromName(order);

    keys = outlier.internal.subjectKeysFromTable(tProg, commonHeaders);
    protoCol = string(tProg.('Stimulus Protocol'));
    stimCol = string(tProg.('Stimulus Name'));
    groupCol = string(tProg.('Group'));
    stimsetIdxCol = tProg.StimsetIdx;

    nRows = height(tProg);
    nBins = numel(binNames);
    maxRows = nRows * nBins;
    subjKeyCol = repmat({''}, maxRows, 1);
    stimsetCol = zeros(maxRows, 1);
    protocolCol = repmat({''}, maxRows, 1);
    stimNameCol = repmat({''}, maxRows, 1);
    groupOutCol = repmat({''}, maxRows, 1);
    binIdxCol = zeros(maxRows, 1);
    progressCol = nan(maxRows, 1);

    outRow = 0;
    for r = 1:nRows
        for bi = 1:nBins
            v = tProg.(binNames{bi})(r);
            if ~isfinite(v)
                continue;   % skip NaN bins (normalizeProgressionInput convention)
            end
            outRow = outRow + 1;
            subjKeyCol{outRow} = keys{r};
            stimsetCol(outRow) = stimsetIdxCol(r);
            protocolCol{outRow} = char(protoCol(r));
            stimNameCol{outRow} = char(stimCol(r));
            groupOutCol{outRow} = char(groupCol(r));
            binIdxCol(outRow) = binIdxFromName(bi);
            progressCol(outRow) = v;
        end
    end

    keep = 1:outRow;
    longTbl = table(subjKeyCol(keep), stimsetCol(keep), protocolCol(keep), ...
        stimNameCol(keep), groupOutCol(keep), binIdxCol(keep), progressCol(keep), ...
        'VariableNames', emptyNames);
end

function entries = appendEntry(entries, subjKey, featName, value)
    entries(end+1, :) = {subjKey, featName, value}; %#ok<AGROW>
end

function colName = findColumn(T, pattern)
    hits = T.Properties.VariableNames(contains(T.Properties.VariableNames, pattern, 'IgnoreCase', false));
    if isempty(hits)
        error('outlier:internal:buildExclusionFeatures:missingColumn', ...
            'Could not find a ''%s'' column in the cohort metrics output table.', pattern);
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

function minValidBins = minValidBinsPerSubject(progComp, subjKeys)
    % Minimum NValidBins across a subject's progression component rows.
    % Subjects with no progression rows at all get 0 (a data-quality failure
    % for the mixedquality method). When NO subject has progression rows
    % (e.g. single-bout sessions), the criterion is neutralized with Inf so
    % it does not exclude the entire baseline.
    n = numel(subjKeys);
    minValidBins = zeros(n, 1);
    if isempty(progComp)
        minValidBins = inf(n, 1);
        return;
    end
    allKeys = string(progComp.SubjectKey);
    allN = progComp.NValidBins;
    for si = 1:n
        m = allKeys == string(subjKeys{si});
        if any(m)
            minValidBins(si) = min(allN(m));
        end
    end
end
