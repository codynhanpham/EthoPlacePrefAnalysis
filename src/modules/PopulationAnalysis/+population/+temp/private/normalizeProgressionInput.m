function [longTbl, stimsetInfo] = normalizeProgressionInput(src, metricType, kvargs)
    %%NORMALIZEPROGRESSIONINPUT Normalize ranking input into a tidy per-animal per-bin long table
    %
    %   [longTbl, stimsetInfo] = normalizeProgressionInput(src, metricType, kvargs)
    %
    %   Accepts either:
    %     1) An exported table from plotProgressionInTab (with TimeBin_N__{x-y%} columns), or
    %     2) A standardizedTables struct array, optionally joined by joinStdTableByStim, for
    %        which runProgressionStats(...).longTable is reused (no duplicated bout/bin computation).
    %
    %   Outputs:
    %       longTbl : tidy table, one row per (subject, protocol, stim, bin) with columns
    %                   SubjectKey, StimsetIdx, StimulusProtocol, Stimulus, Group, BinIdx, BinLabel, Progression
    %       commonCols : struct with cell/numeric column vectors (one entry per unique longTbl row group):
    %                   Mouse_ID, Gene, CageNo, Gene_ID, SexDollar, GenotypeDollar, Litter, Toe_ID, DOB, Age
    %                   (one row per unique SubjectKey x StimulusProtocol x Stimulus x Group combination is
    %                    NOT stored here; instead commonCols is a table aligned with longTbl rows.)
    %       stimsetInfo : struct array, one element per protocol (stimset), with fields:
    %                   StimsetIdx, StimfileName, Stimuli (order-stable-unique Stimulus Name cellstr),
    %                   Groups (first-seen Group values per protocol)

    arguments
        src {mustBeNonempty}
        metricType (1,1) string {mustBeMember(metricType, ["state", "distance"])} = "distance"
        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
        kvargs.MeanWindowFrames (1,1) {mustBePositive, mustBeInteger} = 15
    end

    if istable(src)
        [longTbl, stimsetInfo] = fromExportedTable(src);
    elseif isstruct(src)
        [longTbl, stimsetInfo] = fromMergedTable(src, metricType, kvargs.BinWidth, kvargs.MeanWindowFrames);
    else
        error('normalizeProgressionInput:badInput', ...
            'src must be a table (exported plotProgressionInTab output) or a struct array (joinStdTableByStim output).');
    end
end

%% ------------------------------------------------------------------
function [longTbl, stimsetInfo] = fromExportedTable(T)
    % Path 1: exported plotProgressionInTab table.
    % Columns: 11 common + 'Stimulus Name' + StimsetIdx + Group + TimeBin_N__{label}

    varNames = T.Properties.VariableNames;
    commonVars = struct();
    commonVars.Mouse_ID = resolveTableVar(varNames, {'Mouse_ID'});
    commonVars.Gene = resolveTableVar(varNames, {'Gene'});
    commonVars.Cage = resolveTableVar(varNames, {'Cage #', 'Cage_'});
    commonVars.Gene_ID = resolveTableVar(varNames, {'Gene_ID'});
    commonVars.Sex = resolveTableVar(varNames, {'Sex$', 'Sex_'});
    commonVars.Genotype = resolveTableVar(varNames, {'Genotype$', 'Genotype_'});
    commonVars.Litter = resolveTableVar(varNames, {'Litter'});
    commonVars.Toe_ID = resolveTableVar(varNames, {'Toe_ID'});
    commonVars.DOB = resolveTableVar(varNames, {'DOB'});
    commonVars.Age = resolveTableVar(varNames, {'Age'});
    commonVars.Protocol = resolveTableVar(varNames, {'Stimulus Protocol', 'StimulusProtocol'});
    commonVars.Stimulus = resolveTableVar(varNames, {'Stimulus Name', 'StimulusName'});
    commonVars.StimsetIdx = resolveTableVar(varNames, {'StimsetIdx'});
    commonVars.Group = resolveTableVar(varNames, {'Group'});
    missing = fieldnames(commonVars);
    missing = missing(cellfun(@(f) isempty(commonVars.(f)), missing));
    if ~isempty(missing)
        error('normalizeProgressionInput:missingColumns', ...
            'Exported table is missing required columns: %s', strjoin(missing, ', '));
    end

    binColMask = startsWith(varNames, 'TimeBin_');
    binColNames = varNames(binColMask);
    if isempty(binColNames)
        error('normalizeProgressionInput:noTimeBinColumns', ...
            'Exported table has no TimeBin_N__ columns.');
    end

    % Bin index from column name: TimeBin_{i}__{label}
    binIdxFromName = zeros(numel(binColNames), 1);
    for bi = 1:numel(binColNames)
        parts = split(binColNames{bi}, '__');
        tok = parts{1};
        tok = strrep(tok, 'TimeBin_', '');
        binIdxFromName(bi) = str2double(tok);
    end
    if any(isnan(binIdxFromName))
        error('normalizeProgressionInput:badTimeBinNames', ...
            'Could not parse bin indices from TimeBin column names.');
    end
    [~, order] = sort(binIdxFromName);
    binColNames = binColNames(order);
    binIdxFromName = binIdxFromName(order);

    % Bin labels (from first row's naming scheme; same across rows by construction)
    binLabels = cell(numel(binColNames), 1);
    for bi = 1:numel(binColNames)
        parts = split(binColNames{bi}, '__');
        if numel(parts) >= 2
            binLabels{bi} = char(parts{2});
        else
            binLabels{bi} = sprintf('Bin %d', binIdxFromName(bi));
        end
    end

    % Melt TimeBin columns into long form.
    nRows = height(T);
    nBins = numel(binColNames);
    subjectKey = makeSubjectKey(T, commonVars);

    subjKeyCol   = repmat({''}, nRows * nBins, 1);
    stimsetCol   = zeros(nRows * nBins, 1);
    protocolCol  = repmat({''}, nRows * nBins, 1);
    stimNameCol  = repmat({''}, nRows * nBins, 1);
    groupCol     = repmat({''}, nRows * nBins, 1);
    binIdxCol    = zeros(nRows * nBins, 1);
    binLabelCol  = repmat({''}, nRows * nBins, 1);
    progressCol  = nan(nRows * nBins, 1);

    outRow = 0;
    for r = 1:nRows
        for bi = 1:nBins
            v = T.(binColNames{bi})(r);
            if isnan(v)
                continue;
            end
            outRow = outRow + 1;
            subjKeyCol{outRow}  = subjectKey{r};
            stimsetCol(outRow)  = T.(commonVars.StimsetIdx)(r);
            protocolCol{outRow} = char(string(T.(commonVars.Protocol)(r)));
            stimNameCol{outRow} = char(string(T.(commonVars.Stimulus)(r)));
            groupCol{outRow}    = char(string(T.(commonVars.Group)(r)));
            binIdxCol(outRow)   = binIdxFromName(bi);
            binLabelCol{outRow} = binLabels{bi};
            progressCol(outRow) = v;
        end
    end

    keep = 1:outRow;
    longTbl = table(subjKeyCol(keep), stimsetCol(keep), protocolCol(keep), ...
        stimNameCol(keep), groupCol(keep), binIdxCol(keep), binLabelCol(keep), ...
        progressCol(keep), ...
        'VariableNames', {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', ...
        'Stimulus', 'Group', 'BinIdx', 'BinLabel', 'Progression'});

    % stimsetInfo: per-protocol order-stable-unique stimuli, and first-seen groups
    stimsetIdxs = unique(T.(commonVars.StimsetIdx), 'stable')';
    stimsetInfo = struct('StimsetIdx', {}, 'StimfileName', {}, 'StimfileNames', {}, 'Stimuli', {}, 'Groups', {});
    for si = 1:numel(stimsetIdxs)
        idx = stimsetIdxs(si);
        sub = T(T.(commonVars.StimsetIdx) == idx, :);
        stimNames = unique(sub.(commonVars.Stimulus), 'stable')';
        groups = unique(sub.(commonVars.Group), 'stable')';
        stimsetInfo(end+1) = struct( ...
            'StimsetIdx', idx, ...
            'StimfileName', char(string(sub.(commonVars.Protocol)(1))), ...
            'StimfileNames', {cellstr(unique(string(sub.(commonVars.Protocol))))}, ...
            'Stimuli', {cellstr(stimNames)}, ...
            'Groups', {cellstr(groups)}); %#ok<AGROW>
    end
end

%% ------------------------------------------------------------------
function [longTbl, stimsetInfo] = fromMergedTable(mergedTable, metricType, binWidth, meanWindowFrames)
    % Path 2: merged standardizedTables struct - reuse runProgressionStats longTable.

    stats = runProgressionStats(mergedTable, metricType, ...
        'BinWidth', binWidth, 'MeanWindowFrames', meanWindowFrames, ...
        'IncludeMovementCovariate', false, 'RandomSlope', false, 'Verbose', false);
    srcLong = stats.longTable;

    nRows = height(srcLong);
    subjectKeyCol = repmat({''}, nRows, 1);
    protocolCol   = repmat({''}, nRows, 1);

    stimSets = {mergedTable.stimuliSorted};
    for r = 1:nRows
        si = srcLong.StimsetIdx(r);
        animalKey = char(srcLong.Animal(r));
        md = mergedTable(si).animalMetadata(animalKey);
        subjectKeyCol{r} = makeSubjectKeyFromMeta(md);
        % Use the first source protocol, matching fillCommonColumns/textToChar in the
        % exported plot table.  StimfileNames retains all source aliases for validation.
        protocolNames = normalizeTextList(mergedTable(si).stimfileName);
        protocolCol{r} = protocolNames{1};
    end

    longTbl = table(subjectKeyCol, srcLong.StimsetIdx, protocolCol, ...
        cellstr(srcLong.Stimulus), cellstr(srcLong.Group), srcLong.BinIdx, ...
        cellstr(srcLong.BinLabel), srcLong.Progression, ...
        'VariableNames', {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', ...
        'Stimulus', 'Group', 'BinIdx', 'BinLabel', 'Progression'});

    % stimsetInfo per protocol
    stimsetInfo = struct('StimsetIdx', {}, 'StimfileName', {}, 'StimfileNames', {}, 'Stimuli', {}, 'Groups', {});
    for si = 1:numel(mergedTable)
        stimNames = stimSets{si};
        protocolNames = normalizeTextList(mergedTable(si).stimfileName);
        stimsetInfo(si) = struct( ...
            'StimsetIdx', si, ...
            'StimfileName', protocolNames{1}, ...
            'StimfileNames', {protocolNames}, ...
            'Stimuli', {cellstr(string(stimNames))}, ...
            'Groups', {unique(cellstr(string(srcLong.Group(srcLong.StimsetIdx == si))), 'stable')});
    end
end

%% ------------------------------------------------------------------
function sk = makeSubjectKey(T, commonVars)
    % Build subject key from the 8 common headers of the exported table.
    n = height(T);
    sk = repmat({''}, n, 1);
    for r = 1:n
        parts = { ...
            valueToChar(T.(commonVars.Mouse_ID)(r)), ...
            valueToChar(T.(commonVars.Gene)(r)), ...
            valueToChar(T.(commonVars.Cage)(r)), ...
            valueToChar(T.(commonVars.Gene_ID)(r)), ...
            valueToChar(T.(commonVars.Sex)(r)), ...
            valueToChar(T.(commonVars.Genotype)(r)), ...
            valueToChar(T.(commonVars.Litter)(r)), ...
            valueToChar(T.(commonVars.Toe_ID)(r))};
        sk{r} = strjoin(parts, '|');
    end
end

function names = normalizeTextList(value)
    if iscell(value)
        names = cellstr(string(value(:)));
    elseif isstring(value)
        names = cellstr(value(:));
    elseif ischar(value)
        names = {value};
    else
        names = cellstr(string(value(:)));
    end
end

function varName = resolveTableVar(varNames, candidates)
    hit = candidates(ismember(candidates, varNames));
    if isempty(hit)
        varName = '';
    else
        varName = hit{1};
    end
end

function out = valueToChar(value)
    if isempty(value) || (isscalar(value) && ismissing(value))
        out = '<EMPTY>';
    else
        out = char(string(value));
    end
end

function sk = makeSubjectKeyFromMeta(md)
    % Build the same subject key from animalMetadata struct (mergedTable path).
    getf = @(f) valueToChar(cohort.metrics.utils.getFieldOr(md, f, ''));
    parts = { ...
        getf('id'), ...       % Mouse_ID
        getf('strain'), ...   % Gene
        getf('cagecode'), ... % Cage #
        '<EMPTY>', ...        % Gene_ID (filled by parseMouseId below)
        getf('sex'), ...      % Sex$
        getf('genotype'), ... % Genotype$
        '<EMPTY>', ...        % Litter (filled by parseMouseId below)
        '<EMPTY>'};           % Toe_ID (filled by parseMouseId below)

    thisMouseId = getf('id');
    thisStrain = getf('strain');
    [geneId, litterId, mouseNumber] = cohort.metrics.utils.parseMouseId(thisMouseId, thisStrain);
    parts{4} = valueToChar(geneId);
    parts{7} = valueToChar(litterId);
    parts{8} = valueToChar(mouseNumber);

    sk = strjoin(parts, '|');
end
