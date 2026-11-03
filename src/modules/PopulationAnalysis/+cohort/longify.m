function perAnimalLong = longify(wideStim, widePre, kvargs)
    %%LONGIFY Stack per-animal period metric tables into a long format with tier tagging and delta contrasts.
    %
    %   perAnimalLong = cohort.longify(wideStim, widePre, 'ProtocolLabels', labels, 'StimLabels', stims)
    %
    %   Inputs:
    %       wideStim - per-animal metric table from cohort.summary(..., Period='stimulus')
    %       widePre  - per-animal metric table from cohort.summary(..., Period='pre-stimulus')
    %
    %   Name-Value Pair Arguments:
    %       - 'ProtocolLabels': cell/array of the 2 stimfileNames defining the
    %         protocol ORDER. Table-1 rows carry the exploration semantics,
    %         table-2 rows the baseline semantics.
    %       - 'StimLabels': output stimulus names (from cohort.metrics.utils.getOutputStimNames)
    %         used to detect stimulus-specific metric columns.
    %
    %   Outputs:
    %       perAnimalLong - long table, one row per SubjectKey x Period x Protocol x Tier x Stimulus x Metric:
    %           Tier is one of:
    %               'exploration' - pre-stimulus rows of protocol 1 (habituation window)
    %               'baseline'    - pre-stimulus rows of protocol 2
    %               'stim_all'    - stimulus-period aggregate metric columns
    %               'per-stim'    - stimulus-period stimulus-specific metric columns
    %               'delta'       - stimulus-period value minus the subject's own
    %                               protocol-2 baseline value (paired via
    %                               cohort.internal.periodColumnName)
    %
    %   See also: cohort.summary, cohort.internal.periodColumnName

    arguments
        wideStim table {mustBeNonempty}
        widePre table {mustBeNonempty}
        kvargs.ProtocolLabels {} = {}
        kvargs.StimLabels {} = {}
    end

    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', ...
        'Litter', 'Toe_ID', 'DOB', 'Age', 'Stimulus Protocol'};
    for i = 1:numel(commonHeaders)
        if ~ismember(commonHeaders{i}, wideStim.Properties.VariableNames) || ...
                ~ismember(commonHeaders{i}, widePre.Properties.VariableNames)
            error('cohort:longify:MissingCommonHeader', ...
                'Both metric tables must contain the common header ''%s''.', commonHeaders{i});
        end
    end

    protocolLabels = coerceLabelCell(kvargs.ProtocolLabels, 'ProtocolLabels');
    if numel(protocolLabels) ~= 2
        error('cohort:longify:InvalidProtocolLabels', ...
            'ProtocolLabels must contain exactly 2 stimfileNames, got %d.', numel(protocolLabels));
    end

    stimLabels = coerceLabelCell(kvargs.StimLabels, 'StimLabels');
    stimLabels = stimLabels(strlength(strtrim(stimLabels)) > 0);
    stimLabels = stimLabels(:);
    [~, order] = sort(strlength(stimLabels), 'descend');
    stimLabels = stimLabels(order);

    stimProtocolsStim = string(wideStim{:, 'Stimulus Protocol'});
    stimProtocolsPre = string(widePre{:, 'Stimulus Protocol'});
    protocolOfStim = protocolIndexOf(stimProtocolsStim, protocolLabels);
    protocolOfPre = protocolIndexOf(stimProtocolsPre, protocolLabels);

    subjectKeyStim = subjectKeysFromTable(wideStim);
    subjectKeyPre = subjectKeysFromTable(widePre);

    % Baseline rows (protocol-2 pre-stimulus) indexed by subject for delta pairing.
    baselineRowBySubject = containers.Map('KeyType', 'char', 'ValueType', 'double');
    isBaselineRow = protocolOfPre == 2;
    for r = find(isBaselineRow(:))'
        key = char(subjectKeyPre(r));
        if isKey(baselineRowBySubject, key)
            error('cohort:longify:DuplicateBaseline', ...
                'Subject %s has more than one protocol-2 pre-stimulus row.', key);
        end
        baselineRowBySubject(key) = r;
    end
    if isempty(find(isBaselineRow(:)))
        error('cohort:longify:MissingBaselineRows', ...
            'No protocol-2 pre-stimulus rows found; cannot build baseline/delta tiers.');
    end

    % Per-stim-row baseline row (NaN when the subject has no protocol-2 row),
    % resolved once and reused by every delta column.
    baseRowForStimRow = nan(numel(subjectKeyStim), 1);
    for r = 1:numel(subjectKeyStim)
        key = char(subjectKeyStim(r));
        if isKey(baselineRowBySubject, key)
            baseRowForStimRow(r) = baselineRowBySubject(key);
        end
    end

    metricColsStim = setdiff(wideStim.Properties.VariableNames, commonHeaders, 'stable');
    metricColsPre = setdiff(widePre.Properties.VariableNames, commonHeaders, 'stable');
    metricColsStim = metricColsStim(isNumericColumn(wideStim, metricColsStim));
    metricColsPre = metricColsPre(isNumericColumn(widePre, metricColsPre));
    preVariableNames = widePre.Properties.VariableNames;

    blocks = {};

    %% Stimulus-period rows (stim_all and per-stim tiers)
    nStimRows = height(wideStim);
    for c = 1:numel(metricColsStim)
        colName = metricColsStim{c};
        stimContext = detectStimContext(colName, stimLabels);
        if strlength(stimContext) == 0
            tier = "stim_all";
            stimName = "ALL";
        else
            tier = "per-stim";
            stimName = stimContext;
        end

        thisBlock = wideStim(:, commonHeaders);
        thisBlock = addvars(thisBlock, subjectKeyStim, 'Before', 1, 'NewVariableNames', 'SubjectKey');
        thisBlock = addvars(thisBlock, stimProtocolsStim, ...
            categorical(string(protocolOfStim), ["1", "2"]), ...
            categorical(repmat("stimulus", nStimRows, 1)), ...
            categorical(repmat(tier, nStimRows, 1)), ...
            repmat(stimName, nStimRows, 1), ...
            repmat(string(colName), nStimRows, 1), ...
            wideStim.(colName), ...
            'NewVariableNames', {'ProtocolName', 'Protocol', 'Period', 'Tier', 'Stimulus', 'Metric', 'Value'});
        blocks{end+1} = thisBlock; %#ok<AGROW>

        % Delta tier: stim value minus the subject's own protocol-2 baseline value.
        preName = cohort.internal.periodColumnName(colName, stimLabels);
        if strlength(preName) > 0 && ismember(char(preName), preVariableNames)
            preCol = widePre.(char(preName));
            baseVals = nan(nStimRows, 1);
            hasBase = ~isnan(baseRowForStimRow);
            baseVals(hasBase) = preCol(baseRowForStimRow(hasBase));
            deltaVals = wideStim.(colName) - baseVals;
            hasDelta = isfinite(deltaVals);

            deltaBlock = thisBlock(hasDelta, :);
            deltaBlock.Value = deltaVals(hasDelta);
            deltaBlock.Tier = categorical(repmat("delta", height(deltaBlock), 1), ...
                ["stim_all", "per-stim", "delta"]);
            blocks{end+1} = deltaBlock; %#ok<AGROW>
        end
    end

    %% Pre-stimulus rows (exploration and baseline tiers)
    nPreRows = height(widePre);
    for c = 1:numel(metricColsPre)
        colName = metricColsPre{c};

        thisBlock = widePre(:, commonHeaders);
        thisBlock = addvars(thisBlock, subjectKeyPre, 'Before', 1, 'NewVariableNames', 'SubjectKey');
        thisBlock = addvars(thisBlock, stimProtocolsPre, ...
            categorical(string(protocolOfPre)), ...
            categorical(repmat("pre-stimulus", nPreRows, 1)), ...
            categorical(repmat("baseline", nPreRows, 1), ["exploration", "baseline", "unknown"]), ...
            repmat("ALL", nPreRows, 1), ...
            repmat(string(colName), nPreRows, 1), ...
            widePre.(colName), ...
            'NewVariableNames', {'ProtocolName', 'Protocol', 'Period', 'Tier', 'Stimulus', 'Metric', 'Value'});
        % Tier: protocol-1 pre-stimulus rows are exploration; protocol-2 rows are baseline.
        tierVals = strings(nPreRows, 1);
        tierVals(protocolOfPre == 1) = "exploration";
        tierVals(protocolOfPre == 2) = "baseline";
        tierVals(protocolOfPre == 0) = "unknown";
        thisBlock.Tier = categorical(tierVals, ["exploration", "baseline", "unknown"]);
        blocks{end+1} = thisBlock; %#ok<AGROW>
    end

    perAnimalLong = vertcat(blocks{:});
end


function labels = coerceLabelCell(inputValue, argName)
    % Normalize a cell/string array of labels to a string column vector,
    % coercing each element with cohort.internal.textScalar (handles char,
    % string, and 1x1 cell wrapping per element).
    if ischar(inputValue)
        inputValue = {inputValue};
    elseif isstring(inputValue)
        inputValue = num2cell(inputValue(:));
    elseif iscell(inputValue)
        inputValue = inputValue(:);
    else
        error('cohort:longify:InvalidLabels', ...
            '%s must be a cell array or string array of labels.', argName);
    end
    labels = cellfun(@(x) cohort.internal.textScalar(x, argName), inputValue, ...
        'UniformOutput', false);
    labels = string(labels);
    labels = labels(:);
end


function tf = isNumericColumn(t, cols)
    tf = false(1, numel(cols));
    for i = 1:numel(cols)
        v = t.(cols{i});
        tf(i) = isnumeric(v) || islogical(v);
    end
end


function protocolIdx = protocolIndexOf(stimProtocols, protocolLabels)
    n = numel(stimProtocols);
    protocolIdx = zeros(n, 1);
    % Slot labels may be ' + '-joined displays of merged protocol variations
    % (population.temp.joinStdTableByStim); metric-table rows carry the
    % individual variation names, so match on any variant of a slot.
    slotVariants = cell(1, numel(protocolLabels));
    for slot = 1:numel(protocolLabels)
        variants = split(string(protocolLabels(slot)), " + ");
        slotVariants{slot} = strtrim(variants);
    end
    for i = 1:n
        rowProtocol = strtrim(string(stimProtocols(i)));
        for slot = 1:numel(protocolLabels)
            if any(rowProtocol == slotVariants{slot})
                protocolIdx(i) = slot;
                break;
            end
        end
    end
end


function keysOut = subjectKeysFromTable(t)
    parts = [ ...
        string(t{:,'Gene'}), ...
        string(t{:,'Genotype$'}), ...
        string(t{:,'Sex$'}), ...
        string(t{:,'Cage #'}), ...
        string(t{:,'Mouse_ID'})];
    keysOut = join(parts, "|");
    keysOut = keysOut(:);
end


function label = detectStimContext(colName, stimLabels)
    % Thin wrapper over the shared matcher: any stim-context column (period
    % slot or embedded slot) is per-stim; aggregate columns return "".
    [label, ~] = cohort.internal.stimContextInColumn(colName, stimLabels);
end
