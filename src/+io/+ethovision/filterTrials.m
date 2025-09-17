function [trialNames, trialInfo] = filterTrials(projectFolder)
    %%FILTERTRIALS Filter trials in a project folder
    %   A valid trial must have BOTH: an entry in `Media Files` and an entry in `Export Files`
    %
    %   Inputs:
    %       projectFolder - The path to the EthoVision project folder
    %
    %   Outputs:
    %       trialNames - A cell array of strings containing the names of the filtered trials (base names without extensions) in 'Media Files'
    %       trialsData - A struct array containing the filtered trials with 2 fields:
    %                'media' - path to the media file (in Media Files subfolder)
    %                'data'  - path to the data file (in Export Files subfolder)
    %                'trialNumeric' - l
    % ast numeric part of the trial name

    arguments
        projectFolder {validator.isEthovisionProjectFolder}
    end
    mediaFolder = fullfile(projectFolder, 'Media Files');
    exportFolder = fullfile(projectFolder, 'Export Files');
    
    % Collect the media file names and paths
    mediaFiles = dir(fullfile(mediaFolder, '*.*'));
    mediaFiles = mediaFiles(~[mediaFiles.isdir]); % Exclude directories
    mediaFileNames = {mediaFiles.name};
    [~, mediaFileBaseNames, ~] = cellfun(@fileparts, mediaFileNames, 'UniformOutput', false);

    % Collect the data file names and paths
    dataFiles = dir(fullfile(exportFolder, '*.xlsx'));
    dataFiles = dataFiles(~[dataFiles.isdir]); % Exclude directories
    dataFileNames = {dataFiles.name};
    [~, dataFileBaseNames, ~] = cellfun(@fileparts, dataFileNames, 'UniformOutput', false);

    % For each media file, check for a matching data file whose name ends with the base name
    trials = struct('media', {}, 'data', {}, 'trialNumeric', []);

    for i = 1:numel(mediaFileBaseNames)
        matchingDataFiles = dataFileBaseNames(endsWith(dataFileBaseNames, mediaFileBaseNames{i}));
        if ~isempty(matchingDataFiles)
            % Split whitespace, trim and parse the last numeric part of the media file base name
            nameParts = strsplit(strtrim(mediaFileBaseNames{i}));
            lastPart = nameParts{end};
            lastPart = strtrim(lastPart);
            trialNum = str2double(lastPart);
            if isnan(trialNum)
                trialNum = [];
            end
            trials(end+1) = struct('media', fullfile(mediaFolder, mediaFileNames{i}), ...
                'data', fullfile(exportFolder, [matchingDataFiles{1}, '.xlsx']), ...
                'trialNumeric', trialNum); %#ok<AGROW>
        end
    end
    
    [~, basenames, ~] = cellfun(@fileparts, {trials.media}, 'UniformOutput', false);
    trialNames = cellstr(basenames);
    trialInfo = trials;
end
