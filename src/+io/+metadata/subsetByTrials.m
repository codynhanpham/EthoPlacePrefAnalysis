function tableSubset = subsetByTrials(masterMetadataTable, trialInfoList)
    %%SUBSETBYTRIALS Subset the master metadata table to include only specified trials
    %   This function subsets the provided master metadata table to include only the trials specified in trialInfoList.
    %
    %   Inputs:
    %       masterMetadataTable - A table containing metadata about all trials, loaded via io.metadata.loadMasterMetadata()
    %       trialInfoList - A struct array containing trial information, obtained from io.ethovision.filterTrials()
    %
    %   Outputs:
    %       tableSubset - A table containing only the rows corresponding to the specified trials
    %
    %   Example:
    %       masterMetadata = io.metadata.loadMasterMetadata('path/to/master_metadata.csv');
    %       trialInfo = io.ethovision.filterTrials('path/to/project/folder');
    %       subsetTable = io.metadata.subsetByTrials(masterMetadata, trialInfo);
    %
    %   See also: io.metadata.loadMasterMetadata, io.ethovision.filterTrials

    arguments
        masterMetadataTable table
        trialInfoList (:, 1) struct
    end

    [isValidTable, missingHeaders] = io.metadata.isMasterMetadataTable(masterMetadataTable);
    if ~isValidTable
        error('The provided masterMetadataTable is missing required headers: %s', strjoin(missingHeaders, ', '));
    end

    tableSubsetMask = false(height(masterMetadataTable), 1);

    % The Ethovision Media folder is in: */<ExperimentName>/Media Files/<TrialName>.<ext>
    trialMediaFiles = {trialInfoList.media};
    [folder, ~, ~] = cellfun(@fileparts, trialMediaFiles, 'UniformOutput', false);
    [folder, ~, ~] = cellfun(@fileparts, folder, 'UniformOutput', false);
    [~, experimentNames, ~] = cellfun(@fileparts, folder, 'UniformOutput', false);
    
    % For each trial, experimentName and trialInfoList.trialNumeric
    % must match a row somewhere in masterMetadataTable, both ETHOVISION_FILE and ETHOVISION_TRIAL, respectively
    for i = 1:length(trialInfoList)
        matchesExperiment = strcmp(masterMetadataTable.ETHOVISION_FILE, experimentNames{i});
        if ~isempty(trialInfoList(i).trialNumeric) && isnumeric(trialInfoList(i).trialNumeric)
            matchesTrialNumeric = masterMetadataTable.ETHOVISION_TRIAL == trialInfoList(i).trialNumeric;
        else
            matchesTrialNumeric = false(height(masterMetadataTable), 1);
        end
        tableSubsetMask = tableSubsetMask | (matchesExperiment & matchesTrialNumeric);
    end
    tableSubset = masterMetadataTable(tableSubsetMask, :);
end