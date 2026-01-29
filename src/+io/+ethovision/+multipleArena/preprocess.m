function updates = preprocess(ethovisionXlsx, masterMetadata, configs, kvargs)
    %%PREPROCESS Preprocess multiple-arena EthoVision data based on master metadata and configurations
    %   This function splits EthoVision multiple-arena data into single-arena files, each arena with its own media (video) and exported tracked data.
    %
    %   Inputs:
    %       ethovisionXlsx - Path to the EthoVision XLSX file containing multiple-arena data
    %       masterMetadata - A path to the master metadata XLSX file or a table loaded via io.metadata.loadMasterMetadata()
    %       configs - A struct array of configuration settings for preprocessing, loaded via io.config.loadConfigYaml()
    %
    %   Name-Value Pair Arguments:
    %       'ExpectedNumVariables' (optional): The number of data columns in the table to expect in EthoVision exported XLSX file. Default max is 50, with empty columns removed.
    %       'ProgressDialogHandle' (optional): A handle to a MATLAB uiprogressdlg object for displaying progress. If not provided, no progress dialog is updated.
    %
    %
    %   Outputs:
    %       updates: A scalar struct with the following fields:
    %           - data:
    %               + original (scalar): Path to the original EthoVision XLSX file
    %               + processed (1 x <NumberArena>): Paths to the processed single-arena EthoVision XLSX files
    %           - media:
    %               + original (scalar): Path to the original media (video) file
    %               + processed (1 x <NumberArena>): Paths to the processed single-arena media (video) files
    %
    %   See also: io.ethovision.narena, io.metadata.loadMasterMetadata, io.metadata.mediaPathFromXlsx

    arguments
        ethovisionXlsx {mustBeFile}
        masterMetadata {validator.mustBeFileOrTable}
        configs (1, :) struct

        kvargs.ExpectedNumVariables (1, 1) double = 50
        kvargs.ProgressDialogHandle {progressDlgHandleOrEmpty} = []

    end

    if ~ffmpeg.available()
        error('io:ethovision:multipleArena:preprocess:FFMPEGNOTFOUND', 'FFMPEG is required for preprocessing multiple-arena EthoVision data, but it is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/+ffmpeg/bin/ folder. https://ffmpeg.org/download.html.');
    end

    if ~isempty(kvargs.ProgressDialogHandle)
        loaderShowPercentage = kvargs.ProgressDialogHandle.ShowPercentage;
        kvargs.ProgressDialogHandle.ShowPercentage = true;
    end

    updateProgressDialog(kvargs.ProgressDialogHandle, 'Checking number of arenas in EthoVision data...', 0.05);
    [numArena, arenaNames] = io.ethovision.narena(ethovisionXlsx);
    if numArena == 1
        updates = struct();
        updates.data.original = ethovisionXlsx;
        updates.data.processed = ethovisionXlsx;
        mediaPath = io.ethovision.mediaPathFromXlsx(ethovisionXlsx);
        updates.media.original = mediaPath;
        updates.media.processed = mediaPath;
        return;
    elseif numArena > 2
        error('io:ethovision:multipleArena:preprocess:NOTIMPLEMENTED', 'NotImplemented: Preprocessing for more than 2 arenas is not yet implemented.');
    end
    updateProgressDialog(kvargs.ProgressDialogHandle, sprintf('EthoVision data contains %d arenas. Loading metadata table...', numArena), 0.09);

    metadata = table();
    if istable(masterMetadata) && io.metadata.isMasterMetadataTable(masterMetadata)
        metadata = masterMetadata;
    elseif ~isempty(masterMetadata)
        metadata = io.metadata.loadMasterMetadata(masterMetadata);
    else
        error('masterMetadata must be a valid metadata table (loaded via io.metadata.loadMasterMetadata()) or a path to a master metadata file.');
    end

    updateProgressDialog(kvargs.ProgressDialogHandle, 'Splitting tracked data for multiple arenas...', 0.1);


    updates = struct();
    updates.data.original = ethovisionXlsx;
    mediaPathOG = io.ethovision.mediaPathFromXlsx(ethovisionXlsx);
    updates.media.original = mediaPathOG;
    
    [dataFolder, dataName, dataExt] = fileparts(ethovisionXlsx);
    [mediaFolder, mediaName, mediaExt] = fileparts(mediaPathOG);

    ethovisiondata = struct.empty();
    preprocessProgress = 0;
    if ~isempty(kvargs.ProgressDialogHandle)
        preprocessProgress = kvargs.ProgressDialogHandle.Value;
    end
    thisprogresstotal = 0.4; % the total progress allocated for loading each arena data
    for i = 1:numArena
        updateProgressDialog(kvargs.ProgressDialogHandle, sprintf('Splitting tracking data for arena: %s...', arenaNames{i}), preprocessProgress + (i-1)*(thisprogresstotal/numArena));

        arenaName = arenaNames{i};
        [headers, datatable, units] = io.ethovision.loadEthovisionXlsx(ethovisionXlsx, 'ExpectedNumVariables', kvargs.ExpectedNumVariables, 'ArenaName', arenaName);
        ethovisiondata(i).arenaName = arenaName;
        ethovisiondata(i).headers = headers;
        ethovisiondata(i).datatable = datatable;
        ethovisiondata(i).units = units;

        ethovisiondata(i).arenaId = str2double(headers('Arena ID'));

        leftTerm = "Left"; % Default search term for left zone column
        rightTerm = "Right"; % Default search term for right zone column
        zoneMatchMethod = "startsWith"; % Default matching method
        
        zonematchconfigkey = {'tracking_providers', 'EthoVision', 'default_zone_match_method'};
        if validator.nestedStructFieldExists(configs, zonematchconfigkey)
            zoneMatchMethod = getfield(configs, zonematchconfigkey{:});
        end
        % Check if this arenaName is specified in the config
        arenaConfigKey = {'arena'};
        if validator.nestedStructFieldExists(configs, arenaConfigKey)
            arenas = getfield(configs, arenaConfigKey{:});
            arenaIdx = find(cellfun(@(x) strcmp(x.name, arenaName), arenas), 1);
            if ~isempty(arenaIdx)
                % arena.zone should always exists and have left and right fields as per config validation in loadConfigYaml()
                leftTerm = arenas{arenaIdx}.zone.left;
                rightTerm = arenas{arenaIdx}.zone.right;
                if isfield(arenas{arenaIdx}, 'zone_match_method')
                    zoneMatchMethod = arenas{arenaIdx}.zone_match_method;
                end
            end
        else
            % Error that this arena name is not found in the config
            error('io:ethovision:multipleArena:preprocess:ARENANOTINCONFIG', 'Arena name "%s" not found in the configuration for EthoVision multiple-arena preprocessing.', arenaName);
        end

        % All potential "In zone(...)" columns
        inzones = datatable.Properties.VariableNames(startsWith(datatable.Properties.VariableNames, "In zone("));
        % Find columns matching left and right zone names based on config
        datazonenames = cellfun(@(x) parseInZoneText(x), inzones, 'UniformOutput', false);

        


        % Remove other inzone columns that do not match either left/right zone names
        % Also, keep hidden zones assigned to left/right for this arena
        % As well as marked neutral zones
        nonmatchedIdx = true(length(inzones), 1);
        for z = 1:length(datazonenames)
            zoneName = datazonenames{z}{1};
            isMatchLR = matchedZoneName(zoneName, leftTerm, zoneMatchMethod) || matchedZoneName(zoneName, rightTerm, zoneMatchMethod);
            isHiddenMatch = false;
            if ~isempty(arenaIdx) && isfield(arenas{arenaIdx}, 'hidden_zones_assignment') && ~isempty(arenas{arenaIdx}.hidden_zones_assignment)
                hiddenZones = arenas{arenaIdx}.hidden_zones_assignment;
                if iscell(hiddenZones)
                    isHiddenMatch = any(cellfun(@(hz) matchedZoneName(zoneName, string(hz.name), "exact"), hiddenZones));
                else
                    isHiddenMatch = any(arrayfun(@(hz) matchedZoneName(zoneName, string(hz.name), "exact"), hiddenZones));
                end
            end
            % Also check for neutral zones
            isNeutralMatch = false;
            if ~isempty(arenas{arenaIdx}) && isfield(arenas{arenaIdx}, 'neutral_zones') && ~isempty(arenas{arenaIdx}.neutral_zones)
                neutralZones = arenas{arenaIdx}.neutral_zones;
                if iscell(neutralZones)
                    isNeutralMatch = any(cellfun(@(nz) matchedZoneName(zoneName, string(nz.name), "exact"), neutralZones));
                else
                    isNeutralMatch = any(arrayfun(@(nz) matchedZoneName(zoneName, string(nz.name), "exact"), neutralZones));
                end
            end
            if isMatchLR || isHiddenMatch || isNeutralMatch
                nonmatchedIdx(z) = false;
            end
        end
        datatablevars = datatable.Properties.VariableNames;
        tobeincludedVars = datatablevars(~ismember(datatablevars, inzones(nonmatchedIdx)));
        ethovisiondata(i).datatable = datatable(:, tobeincludedVars);

        % Filter for keys in units that exist in the new datatable
        [newUnitsKeys, newUnitsIdx] = intersect(keys(ethovisiondata(i).units), ethovisiondata(i).datatable.Properties.VariableNames, "stable");
        
        % Keep only units that correspond to the new datatable columns
        uvalues = values(ethovisiondata(i).units);
        newUnitsValues = uvalues(newUnitsIdx);
        ethovisiondata(i).units = dictionary(newUnitsKeys, newUnitsValues);


        % Update headers('Video file') with ' @ <arena name>' suffix before the extension
        originalVideoFile = headers('Video file');
        [vidPath, vidName, vidExt] = fileparts(originalVideoFile);
        newVideoFile = fullfile(vidPath, sprintf('%s @ %s%s', vidName, arenaName, vidExt));
        ethovisiondata(i).headers('Video file') = newVideoFile;
    end

    % Reorder the struct array based on arenaId
    [~, sortedIdx] = sort([ethovisiondata.arenaId]);
    ethovisiondata = ethovisiondata(sortedIdx);

    % Assert that from this point onwards, there are exactly 2 arenas (unless implemented later, then please remove this comment)
    assert(length(ethovisiondata) == 2, 'After preprocessing, there should be exactly 2 arenas in the EthoVision data. More than 2 arenas is not yet implemented.');

    
    arenaNames = {ethovisiondata.arenaName};

    updateProgressDialog(kvargs.ProgressDialogHandle, 'Backing up original tracking data...', preprocessProgress + thisprogresstotal);

    % Move the original data to its ./raw/ subfolder
    rawDataFolder = fullfile(dataFolder, 'raw');
    if ~isfolder(rawDataFolder)
        mkdir(rawDataFolder);
    end
    movefile(char(ethovisionXlsx), char(fullfile(rawDataFolder, sprintf("%s%s", dataName, dataExt))));

    updateProgressDialog(kvargs.ProgressDialogHandle, 'Writing splitted tracking data for each arena...', preprocessProgress + thisprogresstotal + 0.1);
    % Write the split data and media files for each arena
    for i = 1:length(arenaNames)
        arenaDataFileName = sprintf("%s @ %s%s", dataName, arenaNames{i}, dataExt);
        io.ethovision.writeEthovisionXlsx(fullfile(dataFolder, arenaDataFileName), ethovisiondata(i).headers, ethovisiondata(i).datatable, ethovisiondata(i).units, 'Overwrite', true);
        updates.data.processed{i} = fullfile(dataFolder, arenaDataFileName);
    end
    
    updateProgressDialog(kvargs.ProgressDialogHandle, 'Splitting media file for each arena using FFmpeg...', preprocessProgress + thisprogresstotal + 0.15);
    leftArenaMediaName = sprintf("%s @ %s%s", mediaName, arenaNames{1}, mediaExt);
    rightArenaMediaName = sprintf("%s @ %s%s", mediaName, arenaNames{2}, mediaExt);

    function ffmpegProgressUpdate(line)
        updateProgressDialog(kvargs.ProgressDialogHandle, sprintf('FFmpeg:\n%s', line), preprocessProgress, 'Indeterminate', true);
    end
    callbackFcn = @(line) ffmpegProgressUpdate(line);

    [status, cmdout] = ffmpeg.horzSplit(mediaPathOG, fullfile(mediaFolder, leftArenaMediaName), fullfile(mediaFolder, rightArenaMediaName), 'UpdateCallbackFcn', callbackFcn);
    if status ~= 0
        error('io:ethovision:multipleArena:preprocess:FFMPEGFAILED', 'FFMPEG failed to split the media file into two arenas. FFMPEG output: %s', cmdout);
    end
    updates.media.processed = {fullfile(mediaFolder, leftArenaMediaName), fullfile(mediaFolder, rightArenaMediaName)};
    
    updateProgressDialog(kvargs.ProgressDialogHandle, 'Backing up original media file...', 0.98, 'Indeterminate', false);
    % Move the original media to its ./raw/ subfolder
    rawMediaFolder = fullfile(mediaFolder, 'raw');
    if ~isfolder(rawMediaFolder)
        mkdir(rawMediaFolder);
    end
    movefile(char(mediaPathOG), char(fullfile(rawMediaFolder, sprintf("%s%s", mediaName, mediaExt))));

    updateProgressDialog(kvargs.ProgressDialogHandle, 'Preprocessing completed.', 1.0);

    if ~isempty(kvargs.ProgressDialogHandle)
        kvargs.ProgressDialogHandle.ShowPercentage = loaderShowPercentage;
    end
end


function [zoneName, option] = parseInZoneText(text)
    % Parse text in format: "In zone(<ZoneName> / <Option>)"
    pattern = 'In zone\(([^'']+)\s*/\s*(.+)\)';
    tokens = regexp(text, pattern, 'tokens', 'once');
    
    if ~isempty(tokens)
        zoneName = strtrim(string(tokens{1}));
        option = strtrim(string(tokens{2}));
    else
        zoneName = "";
        option = "";
        warning('Text does not match expected format: %s', text);
    end
end

function bool = matchedZoneName(input, matchedTo, method)
    switch method
        case "exact"
            bool = strcmp(input, matchedTo);
        case "startsWith"
            bool = startsWith(input, matchedTo);
        case "endsWith"
            bool = endsWith(input, matchedTo);
        case "contains"
            bool = contains(input, matchedTo);
        otherwise
            error('Unknown zone match method: %s', method);
    end
end



function progressDlgHandleOrEmpty(input)
    if isempty(input)
        return;
    end

    if ~isa(input, 'matlab.ui.dialog.ProgressDialog')
        error('ProgressDialogHandle must be a valid uiprogressdlg handle.');
    end
    if numel(input) ~= 1
        error('ProgressDialogHandle must be a scalar uiprogressdlg handle.');
    end
end


function updateProgressDialog(progressDlg, message, value, kvargs)
    arguments
        progressDlg {progressDlgHandleOrEmpty}
        message {mustBeTextScalar}
        value (1,1) double

        kvargs.Indeterminate (1,1) logical = false
    end

    if isempty(progressDlg)
        return;
    end

    progressDlg.Message = message;
    progressDlg.Value = value;
    progressDlg.Indeterminate = kvargs.Indeterminate;
end