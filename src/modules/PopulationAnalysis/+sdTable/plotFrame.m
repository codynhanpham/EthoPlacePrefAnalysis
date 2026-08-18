function [f, a] = plotFrame(standardizedTables, tableIndex, subjectIndex, frameIndex, type, kvargs)
    arguments
        standardizedTables (1, :) struct {sdTable.mustBeStandardizedTable}
        tableIndex (1, 1) double {mustBeInteger, mustBePositive} = 1
        subjectIndex (1, 1) double {mustBeInteger, mustBePositive} = 1
        frameIndex (1, 1) double {mustBeInteger, mustBePositive} = 1
        type (1, 1) string {mustBeMember(type, ["centerpoint", "bodyparts"])} = "centerpoint"

        kvargs.XRange_cm (1, 2) double {mustBeFinite, mustBeIncreasingRange} = [0, 77.4]
        kvargs.YRange_cm (1, 2) double {mustBeFinite, mustBeIncreasingRange} = [0, 43.5]
    end

    if tableIndex > numel(standardizedTables)
        error('sdTable:plotFrame:InvalidTableIndex', ...
            'tableIndex must be between 1 and %d.', numel(standardizedTables));
    end

    standardizedTable = standardizedTables(tableIndex);
    if type == "centerpoint"
        data = standardizedTable.centerpointData;
        xVariable = 'X center';
        yVariable = 'Y center';
    else
        data = standardizedTable.bodyparts;
        xVariable = '';
        yVariable = '';
        if isempty(data) || width(data) <= 2
            error('sdTable:plotFrame:MissingBodyparts', ...
                'The selected standardized table does not contain body-part coordinates.');
        end
    end

    if frameIndex > height(data)
        error('sdTable:plotFrame:InvalidFrameIndex', ...
            'frameIndex must be between 1 and %d for table %d.', height(data), tableIndex);
    end

    if type == "centerpoint"
        nSubjects = size(data{:, xVariable}, 2);
    else
        xVariables = string(data.Properties.VariableNames(startsWith( ...
            data.Properties.VariableNames, 'X ')));
        pairedXVariables = xVariables(arrayfun(@(xName) ismember( ...
            char("Y " + extractAfter(xName, "X ")), data.Properties.VariableNames), xVariables));
        if isempty(pairedXVariables)
            error('sdTable:plotFrame:MissingBodypartPairs', ...
                'No paired X/Y body-part coordinate variables were found.');
        end
        nSubjects = size(data{:, char(pairedXVariables(1))}, 2);
    end

    if subjectIndex > nSubjects
        error('sdTable:plotFrame:InvalidSubjectIndex', ...
            'subjectIndex must be between 1 and %d for table %d.', nSubjects, tableIndex);
    end

    trialTime = data{frameIndex, 'Trial time'};
    stimulusName = data{frameIndex, 'Stimulus name'};
    if iscell(stimulusName)
        stimulusName = stimulusName{1};
    end
    stimulusName = string(stimulusName);

    f = figure('Name', 'Population Frame', 'NumberTitle', 'off');
    a = axes(f);
    hold(a, 'on');

    if type == "centerpoint"
        x = data{frameIndex, xVariable};
        y = data{frameIndex, yVariable};
        x = x(subjectIndex);
        y = y(subjectIndex);
        plot(a, x, y, 'o', ...
            'MarkerSize', 10, 'MarkerFaceColor', [0.1, 0.45, 0.85], ...
            'MarkerEdgeColor', 'k', 'DisplayName', 'Centerpoint');
    else
        xValues = zeros(0, 1);
        yValues = zeros(0, 1);
        labels = strings(0, 1);
        for variableIndex = 1:numel(pairedXVariables)
            xName = pairedXVariables(variableIndex);
            yName = "Y " + extractAfter(xName, "X ");
            x = data{frameIndex, char(xName)};
            y = data{frameIndex, char(yName)};
            x = x(subjectIndex);
            y = y(subjectIndex);
            if isfinite(x) && isfinite(y)
                xValues(end+1, 1) = x; %#ok<AGROW>
                yValues(end+1, 1) = y; %#ok<AGROW>
                labels(end+1, 1) = extractAfter(xName, "X "); %#ok<AGROW>
            end
        end
        if isempty(xValues)
            warning('sdTable:plotFrame:NoFiniteBodyparts', ...
                'The selected frame and subject contain no finite body-part coordinates.');
        else
            scatter(a, xValues, yValues, 55, 'filled', 'DisplayName', 'Body parts');
            text(a, xValues, yValues, "  " + labels, ...
                'VerticalAlignment', 'middle', 'Interpreter', 'none');
        end
    end

    axis(a, 'equal');
    xlim(a, kvargs.XRange_cm);
    ylim(a, kvargs.YRange_cm);
    set(a, 'YDir', 'reverse');
    xlabel(a, 'X position (cm)');
    ylabel(a, 'Y position (cm)');
    grid(a, 'on');

    metadataText = selectedMetadataText(standardizedTable, subjectIndex);
    title(a, {char(string(standardizedTable.stimfileName)), ...
        sprintf('Frame %d | Time %.3f s | %s', frameIndex, trialTime, stimulusName), ...
        char(metadataText)}, 'Interpreter', 'none');
    hold(a, 'off');
end


function mustBeIncreasingRange(value)
    if value(1) >= value(2)
        error('sdTable:plotFrame:InvalidAxisRange', ...
            'Axis range values must be strictly increasing: the first value must be less than the second.');
    end
end


function textValue = selectedMetadataText(standardizedTable, subjectIndex)
    textValue = "Subject " + string(subjectIndex);
    metadataKeys = keys(standardizedTable.animalMetadata);
    if numel(metadataKeys) < subjectIndex
        return;
    end

    metadata = standardizedTable.animalMetadata(metadataKeys(subjectIndex));
    if iscell(metadata)
        metadata = metadata{1};
    end
    if ~isstruct(metadata)
        return;
    end

    fields = fieldnames(metadata);
    values = strings(0, 1);
    for fieldIndex = 1:numel(fields)
        fieldName = fields{fieldIndex};
        value = metadata.(fieldName);
        if ischar(value) || (isstring(value) && isscalar(value)) || ...
                (isnumeric(value) && isscalar(value)) || islogical(value)
            values(end+1, 1) = string(fieldName) + "=" + string(value); %#ok<AGROW>
        end
    end
    if ~isempty(values)
        textValue = textValue + " | " + strjoin(values, ', ');
    end
end