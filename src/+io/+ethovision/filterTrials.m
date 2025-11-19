function [trialNames, trialInfo] = filterTrials(projectFolder)
    %%FILTERTRIALS Filter trials in a project folder
    %   A valid trial must have BOTH: an entry in `Media Files` and an entry in `Export Files`
    %
    %   Inputs:
    %       projectFolder - The path to the EthoVision project folder
    %
    %   Outputs:
    %       trialNames - A cell array of strings containing the names of the filtered trials (base names without extensions) in 'Media Files'
    %       trialInfo - A struct array containing the filtered trials with fields:
    %                'media' - path to the media file (in Media Files subfolder)
    %                'data'  - path to the data file (in Export Files subfolder)
    %                'trialNumeric' - last numeric part of the trial name
    %                'multipleArena' - boolean indicating if the trial XLSX export contains multiple arenas

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
    trials = struct('media', {}, 'data', {}, 'trialNumeric', [], 'multipleArena', []);

    for i = 1:numel(mediaFileBaseNames)
        matchingDataFiles = dataFileBaseNames(endsWith(dataFileBaseNames, mediaFileBaseNames{i}));
        if ~isempty(matchingDataFiles)
            % Media is either: If original, "Trial   <number>.ext", or if processed (in case of multi-arena), "Trial   <number> @ <arena name>.ext"
            % Split by " @ " and take the first part as the base name
            mediaBaseName = strsplit(mediaFileBaseNames{i}, ' @ ');
            if isscalar(mediaBaseName)
                % If no " @ " found, need to check if this is a multi-arena xlsx export
                narena = io.ethovision.narena(fullfile(exportFolder, [matchingDataFiles{1}, '.xlsx']));
                if narena > 1
                    multipleArena = true;
                else
                    multipleArena = false;
                end
            else
                % All processed trials with " @ " should be filtered for single arena already
                multipleArena = false;
            end
            mediaBaseName = mediaBaseName{1};


            % Split whitespace, trim and parse the last numeric part of the media file base name
            nameParts = strsplit(strtrim(mediaBaseName));
            lastPart = nameParts{end};
            lastPart = strtrim(lastPart);
            trialNum = str2double(lastPart);
            if isnan(trialNum)
                trialNum = [];
            end
            trials(end+1) = struct('media', fullfile(mediaFolder, mediaFileNames{i}), ...
                'data', fullfile(exportFolder, [matchingDataFiles{1}, '.xlsx']), ...
                'trialNumeric', trialNum, 'multipleArena', multipleArena); %#ok<AGROW>
        end
    end
    
    [~, basenames, ~] = cellfun(@fileparts, {trials.media}, 'UniformOutput', false);
    trialNames = cellstr(basenames);
    trialInfo = trials;
end
