function [trialNames, trialInfo] = filterTrials(projectFolder, metadataTable, kvargs)
    %%FILTERTRIALS Filter trials in a project folder (dlc)
    %   A valid trial is any valid video file entry in the project folder
    %
    %   Inputs:
    %       projectFolder - The path to the root project folder (as returned by io.dlc.filterProjectFolder)
    %
    %   Name-Value Pair Arguments (kvargs):
    %       'SearchDepth' (double): Depth of subfolder search for video files (default: 2)
    %       'VideoExtensions' (cell array of char): Video file extensions to look for (default: {'mp4', 'avi', 'mov'})
    %       'ExcludedDirectories' (cell array of char): Relative paths from projectFolder to exclude (default: {'raw'})
    %
    %   Outputs:
    %       trialNames - A cell array of strings containing the video (media) file names of the filtered trials (without extensions)
    %       trialInfo - A struct array containing the filtered trials with fields:
    %                'media' - path to the media file
    %                'data'  - path to the data file (tracking CSV file)
    %                'trialNumeric' - last numeric part of the trial name
    %                'multipleArena' - boolean indicating if the trial XLSX export contains multiple arenas

    arguments
        projectFolder {mustBeFolder, mustBeTextScalar}
        metadataTable table

        kvargs.SearchDepth (1,1) double {mustBePositive, mustBeInteger} = 2
        kvargs.VideoExtensions (1,:) {mustBeText} = {'mp4', 'avi', 'mov'}
        kvargs.ExcludedDirectories (1,:) {mustBeText} = {'./Export Files/raw', './Media Files/raw'}
    end

    % Metadata table should have these columns if provided
    requiredMetadataCols = {'ETHOVISION_TRIAL', 'ETHOVISION_FILE'};
    missingCols = setdiff(requiredMetadataCols, metadataTable.Properties.VariableNames);
    if ~isempty(missingCols)
        error('The provided metadata table is missing required columns: { "%s" }', strjoin(missingCols, '", "'));
    end

    % Convert excluded directories to full paths
    excludedPaths = {};
    for i = 1:length(kvargs.ExcludedDirectories)
        excludedPaths{end+1} = fullfile(projectFolder, kvargs.ExcludedDirectories{i}); %#ok<AGROW>
    end
    
    % Recursively find all video files
    videoFiles = findVideoFiles(projectFolder, kvargs.VideoExtensions, kvargs.SearchDepth, excludedPaths);
    
    % Extract trial names (without extensions)
    trialNames = cell(length(videoFiles), 1);
    toberemovedIndices = false(length(videoFiles), 1);
    trialNums = -1 * ones(length(videoFiles), 1);
    multipleArenaFlags = false(length(videoFiles), 1);
    dataFilesList = cell(length(videoFiles), 1);
    arenaNames = cell(length(videoFiles), 1);

    for i = 1:length(videoFiles)
        [~, trialName, ~] = fileparts(videoFiles(i).name);
        trialNames{i} = trialName;

        mediaBaseName = strsplit(trialName, ' @ ');
        mediaBaseName = mediaBaseName{1};
        % Split whitespace, trim and parse the last numeric part of the media file base name
        nameParts = strsplit(strtrim(mediaBaseName));
        lastPart = nameParts{end};
        lastPart = strtrim(lastPart);
        trialNum = str2double(lastPart);
        if ~isnan(trialNum)
            trialNums(i) = trialNum;
        else
            % If trial number cannot be parsed, mark for removal
            toberemovedIndices(i) = true;
            continue;
        end

        mediaBaseName = strsplit(trialName, ' @ ');
        if ~isscalar(mediaBaseName)
            % All processed trials with " @ " should be filtered for single arena already
            multipleArenaFlags(i) = false;
            arenaNames{i} = mediaBaseName{2};
        else
            [~, experimentName] = fileparts(fileparts((videoFiles(i).folder)));
            % If no " @ " found, need to check if this is a multi-arena trial by looking up the metadata table
            trialMask = (metadataTable.ETHOVISION_TRIAL == trialNum) & ...
            (metadataTable.ETHOVISION_FILE == string(experimentName));
            trialRowIdx = find(trialMask);
            if isempty(trialRowIdx)
                % This trial does not have matching metadata; remove from list all together
                toberemovedIndices(i) = true;
                continue;
            else
                if length(trialRowIdx) > 1
                    multipleArenaFlags(i) = true;
                    arenaNames{i} = '!multiple!';
                else
                    multipleArenaFlags(i) = false;
                    arenaNames{i} = metadataTable.ETHOVISION_ARENA(trialRowIdx);
                end
            end
        end

        % Data file is the first CSV file that matches:
        % parent/<trialName>DLC*_filtered.csv
        dataFilePattern = fullfile(videoFiles(i).folder, 'dlc', sprintf('%sDLC*_filtered.csv', trialName));
        dataFiles = dir(dataFilePattern);
        if ~isempty(dataFiles)
            dataFilesList{i} = fullfile(dataFiles(1).folder, dataFiles(1).name);
        end
    end
    % Remove trials that were marked for removal
    trialNames(toberemovedIndices) = [];
    trialNums(toberemovedIndices) = [];
    multipleArenaFlags(toberemovedIndices) = [];
    dataFilesList(toberemovedIndices) = [];
    arenaNames(toberemovedIndices) = [];

    % Construct trialInfo struct array
    trialInfo = struct('media', {}, 'data', {}, 'trialNumeric', [], 'multipleArena', []);
    for i = 1:length(trialNames)
        trialInfo(end+1) = struct( ...
            'media', fullfile(videoFiles(i).folder, videoFiles(i).name), ...
            'data', dataFilesList{i}, ...
            'trialNumeric', trialNums(i), ...
            'multipleArena', multipleArenaFlags(i), ...
            'arena', arenaNames{i} ...
        ); %#ok<AGROW>
    end
end

function videoFiles = findVideoFiles(rootDir, extensions, maxDepth, excludedPaths)
    %FINDVIDEOFILES Recursively find video files while respecting depth and exclusions
    videoFiles = struct.empty();
    
    % Helper function to recursively search directories
    function searchDir(currentDir, currentDepth)
        % Skip if we've exceeded max depth
        if currentDepth > maxDepth
            return;
        end
        
        % Skip if current directory is in excluded paths
        for j = 1:length(excludedPaths)
            if strcmp(currentDir, excludedPaths{j}) || ...
                (length(currentDir) > length(excludedPaths{j}) && ...
                strcmp(currentDir(1:length(excludedPaths{j})+1), [excludedPaths{j} filesep]))
                return;
            end
        end
        
        % Get directory contents
        dirContents = dir(currentDir);
        
        for k = 1:length(dirContents)
            item = dirContents(k);
            
            % Skip . and .. entries
            if strcmp(item.name, '.') || strcmp(item.name, '..')
                continue;
            end
            
            itemPath = fullfile(currentDir, item.name);
            
            if item.isdir
                % Recursively search subdirectories
                searchDir(itemPath, currentDepth + 1);
            else
                % Check if file has a valid video extension
                [~, ~, ext] = fileparts(item.name);
                if ~isempty(ext) && any(strcmpi(ext(2:end), extensions))
                    if isempty(videoFiles)
                        videoFiles = item;
                    else
                        videoFiles(end+1) = item; %#ok<AGROW>
                    end
                end
            end
        end
    end
    
    % Start recursive search from root directory
    searchDir(rootDir, 0);
end