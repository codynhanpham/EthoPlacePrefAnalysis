function mustBeStandardizedTable(standardizedTable)
    %%MUSTBESTANDARDIZEDTABLE Validate that the input is a standardizedTable struct
    % 
    % A standardizedTable struct array must have the following fields (see population.stats.populationPositionOverTime for reference):
    %   - stimfileName: a string representing the name of the stimulus file
    %   - stimuliSorted: a cell array of strings representing the sorted stimuli
    %   - animalMetadata: a dict(string, struct) containing metadata for each animal
    %   - centerpointData: a table with at least these columns: 'Trial time', 'Stimulus name', 'X center', 'Y center'

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', 'centerpointData'};
    stdFields = fieldnames(standardizedTable);
    missingFields = setdiff(requiredFields, stdFields);
    if ~isempty(missingFields)
        error('Input standardizedTable is missing required fields: %s', strjoin(missingFields, ', '));
    end

    % Check centerpointData has required columns
    requiredCenterpointCols = {'Trial time', 'Stimulus name', 'X center', 'Y center', 'Distance from Midline', 'Arena Grid Score'};
    centerpointCols = standardizedTable(1).centerpointData.Properties.VariableNames;
    missingCenterpointCols = setdiff(requiredCenterpointCols, centerpointCols);
    if ~isempty(missingCenterpointCols)
        error('centerpointData is missing required columns: %s', strjoin(missingCenterpointCols, ', '));
    end
end