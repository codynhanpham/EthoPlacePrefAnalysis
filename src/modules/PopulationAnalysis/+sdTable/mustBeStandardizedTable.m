function mustBeStandardizedTable(standardizedTable)
    %%MUSTBESTANDARDIZEDTABLE Validate that the input is a standardizedTable struct
    % 
    % A standardizedTable struct array must have the following fields (see population.stats.populationPositionOverTime for reference):
    %   - stimfileName: a string representing the name of the stimulus file
    %   - stimuliSorted: a string array representing the sorted stimuli
    %   - animalMetadata: a dict(string, struct) containing metadata for each animal
    %   - fps: the standardized sampling rate
    %   - px2cm: the pixels-to-centimeters conversion factor
    %   - centerpointData: a table with at least these columns: 'Trial time', 'Stimulus name', 'X center', 'Y center'
    %   - bodyparts: a table with standardized body-part coordinates, or an empty table

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', ...
        'fps', 'px2cm', 'centerpointData', 'bodyparts'};
    stdFields = fieldnames(standardizedTable);
    missingFields = setdiff(requiredFields, stdFields);
    if ~isempty(missingFields)
        error('Input standardizedTable is missing required fields: %s', strjoin(missingFields, ', '));
    end

    requiredCenterpointCols = {'Trial time', 'Stimulus name', 'X center', 'Y center', 'Distance from Midline', 'Arena Grid Score'};
    requiredBodypartKeyCols = {'Trial time', 'Stimulus name'};
    for tableIndex = 1:numel(standardizedTable)
        if ~isscalar(standardizedTable(tableIndex).fps) || ...
                ~isnumeric(standardizedTable(tableIndex).fps) || ...
                (~isfinite(standardizedTable(tableIndex).fps) && ~isnan(standardizedTable(tableIndex).fps))
            error('standardizedTable(%d).fps must be a numeric scalar, finite or NaN.', tableIndex);
        end
        if ~isscalar(standardizedTable(tableIndex).px2cm) || ...
                ~isnumeric(standardizedTable(tableIndex).px2cm) || ...
                (~isfinite(standardizedTable(tableIndex).px2cm) && ~isnan(standardizedTable(tableIndex).px2cm))
            error('standardizedTable(%d).px2cm must be a numeric scalar, finite or NaN.', tableIndex);
        end

        if ~istable(standardizedTable(tableIndex).centerpointData)
            error('standardizedTable(%d).centerpointData must be a table.', tableIndex);
        end
        centerpointCols = standardizedTable(tableIndex).centerpointData.Properties.VariableNames;
        missingCenterpointCols = setdiff(requiredCenterpointCols, centerpointCols);
        if ~isempty(missingCenterpointCols)
            error('standardizedTable(%d).centerpointData is missing required columns: %s', ...
                tableIndex, strjoin(missingCenterpointCols, ', '));
        end

        if ~istable(standardizedTable(tableIndex).bodyparts)
            error('standardizedTable(%d).bodyparts must be a table.', tableIndex);
        end
        if ~isempty(standardizedTable(tableIndex).bodyparts)
            bodypartCols = standardizedTable(tableIndex).bodyparts.Properties.VariableNames;
            missingBodypartCols = setdiff(requiredBodypartKeyCols, bodypartCols);
            if ~isempty(missingBodypartCols)
                error('standardizedTable(%d).bodyparts is missing required columns: %s', ...
                    tableIndex, strjoin(missingBodypartCols, ', '));
            end
        end
    end
end