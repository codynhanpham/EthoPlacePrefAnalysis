function formatted = mustBeStimuliSortedDisplayOverride(standardizedTables, override)
    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        override {validator.mustBeTextOrEmpty} = {}
    end

    if isempty(override)
        formatted = {};
        return
    end

    % Ensure standardizedTables itself is non-empty when an override is supplied.
    if isempty(standardizedTables)
        error('Cannot validate StimuliSortedColumnNameDisplayOverride with empty standardizedTables.');
    end

    if ischar(override) || isstring(override)
        formatted = normalizeLabelVector(override);
        validateSharedOverride(formatted, standardizedTables);
        return;
    end

    if ~iscell(override)
        error('StimuliSortedColumnNameDisplayOverride must be text, a cell array of text, or a per-table cell array of text vectors.');
    end

    % Case 1: shared label vector for all tables (legacy behavior).
    if all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), override))
        formatted = normalizeLabelVector(override);
        validateSharedOverride(formatted, standardizedTables);
        return;
    end

    % Case 2: per-table labels, one vector per standardized table.
    if numel(override) ~= numel(standardizedTables)
        error('Per-table StimuliSortedColumnNameDisplayOverride must contain one label vector per standardized table (%d expected, %d provided).', ...
            numel(standardizedTables), numel(override));
    end

    formatted = cell(numel(standardizedTables), 1);
    for i = 1:numel(standardizedTables)
        labelsI = normalizeLabelVector(override{i});
        localStimNames = string(standardizedTables(i).stimuliSorted);
        if numel(labelsI) ~= numel(localStimNames)
            error('StimuliSortedColumnNameDisplayOverride{%d} must have the same number of labels as standardizedTables(%d).stimuliSorted (%d expected, %d provided).', ...
                i, i, numel(localStimNames), numel(labelsI));
        end
        if numel(unique(lower(string(labelsI)))) ~= numel(labelsI)
            error('StimuliSortedColumnNameDisplayOverride{%d} labels must be distinct within that table.', i);
        end
        formatted{i} = labelsI;
    end
end


function labels = normalizeLabelVector(raw)
    if ischar(raw) || isstring(raw)
        labels = cellstr(string(raw(:)));
        labels = strtrim(labels);
        if any(cellfun(@isempty, labels))
            error('StimuliSortedColumnNameDisplayOverride cannot contain empty labels.');
        end
        return;
    end

    if ~iscell(raw)
        error('Each override entry must be text or a text cell array.');
    end

    if ~all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), raw))
        error('StimuliSortedColumnNameDisplayOverride must contain only text values.');
    end

    labels = cellstr(string(raw(:)));
    labels = strtrim(labels);
    if any(cellfun(@isempty, labels))
        error('StimuliSortedColumnNameDisplayOverride cannot contain empty labels.');
    end
end


function validateSharedOverride(labels, standardizedTables)
    for i = 1:numel(standardizedTables)
        localStimNames = string(standardizedTables(i).stimuliSorted);
        if numel(labels) ~= numel(localStimNames)
            error('StimuliSortedColumnNameDisplayOverride must have the same number of labels as standardizedTables(%d).stimuliSorted (%d expected, %d provided).', ...
                i, numel(localStimNames), numel(labels));
        end
    end

    if numel(unique(lower(string(labels)))) ~= numel(labels)
        error('StimuliSortedColumnNameDisplayOverride labels must be distinct within a table.');
    end
end