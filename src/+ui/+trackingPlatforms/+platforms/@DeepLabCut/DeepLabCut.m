classdef DeepLabCut < ui.trackingPlatforms.TrackingProvider
    %DEEPLABCUT Summary of this class goes here
    %   Detailed explanation goes here

    properties (Constant)
        platform = "DeepLabCut";
    end

    properties
        userConfig = struct.empty();

        coordsUnit = "px";
        px2cmFactor = NaN;

        dlcConfigFile = ''; % Path to the DLC config file (YAML)
    end


    properties (Access = private)
        lastHeader = configureDictionary("string", "string"); % Store the last loadTrackingData() header to cache
        lastDatatable = table(); % Store the last loadTrackingData() datatable to cache
        lastUnits = configureDictionary("string", "string"); % Store the last loadTrackingData() units to cache

        lastFileHash = ''; % Store the last loadTrackingData() file to cache the header, datatable, and units
    end



    methods
        function obj = DeepLabCut()
            %DEEPLABCUT Construct an instance of this class
            %   Detailed explanation goes here
            
        end

    end



    methods (Static, Access = public)
        function filterProjectFolder(comp)
            arguments
                comp (1,1) FolderSelectorWithDropdown
            end

            io.dlc.filterProjectFolder(comp);
        end

        function [trialNames, trialInfo] = filterTrials(projectFolder, kvargs)
            arguments
                projectFolder {validator.isEthovisionProjectFolder}
                kvargs.Options (1,1) struct = struct();
            end

            % You can set your defaults Options here
            defaultOptions = struct( ...
                'MetadataTable', table() ... % Must be provided by user
            );
            % Update default options with user-provided options
            for field = fieldnames(kvargs.Options)'
                defaultOptions.(field{1}) = kvargs.Options.(field{1});
            end
            kvargs.Options = defaultOptions;

            if isempty(kvargs.Options.MetadataTable) || ...
                    ~all(ismember({'ETHOVISION_TRIAL', 'ETHOVISION_FILE'}, kvargs.Options.MetadataTable.Properties.VariableNames))
                error('io:dlc:filterTrials:InvalidMetadataTable', 'A valid MetadataTable with columns "ETHOVISION_TRIAL" and "ETHOVISION_FILE" must be provided.');
            end

            [trialNames, trialInfo] = io.dlc.filterTrials(projectFolder, kvargs.Options.MetadataTable);
        end


    end


    methods
        function userConfig = loadConfig(obj, configs)
            %LOADCONFIG Load user configuration from the global config YAML file path or already loaded config struct
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.DeepLabCut
                configs {validator.mustBeYmlOrStruct}
            end

            if ~isstruct(configs)
                configs = io.config.loadConfigYaml(configs);
            end
            
            if ~isfield(configs, 'tracking_providers') || ...
                    ~isfield(configs.tracking_providers, obj.platform)
                userConfig = struct();
                return; % No DLC-specific config found
            end
            userConfig = configs.tracking_providers.(obj.platformVarnameCompat(obj.platform));
            obj.userConfig = userConfig;
            if isfield(userConfig, 'coordsUnit')
                obj.coordsUnit = userConfig.coordsUnit;
            else
                obj.coordsUnit = "px";
            end

            ymlroot = configs.CONFIG_ROOT;
            if isfield(userConfig, 'config_file')
                obj.dlcConfigFile = utils.path.canonicalize(fullfile(ymlroot, userConfig.config_file));
            else
                obj.dlcConfigFile = '';
            end
        end


        function mediaPath = mediaPathFromTrackingData(~, trackingDataFilePath, kvargs)
            arguments
                ~
                trackingDataFilePath (1,1) string
                kvargs.Options (1,1) struct = struct(); %#ok<INUSA>
            end

            [parent, thisCSVname, ~] = fileparts(trackingDataFilePath);
                thisCSVname = char(thisCSVname);
                % This csv file name can be split at the last "DLC_" occurrence to get the video file name
                dlcIdx = strfind(thisCSVname, 'DLC_');
                if isempty(dlcIdx)
                    videoFileName = thisCSVname;
                else
                    videoFileName = thisCSVname(1:dlcIdx(end)-1);
                end
                % look in the csv ../ folder to find the video file with matching name and known video extensions, grab the actual extension of the file
                videoExtensions = {'.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.3gp'};
                mediaPath = "";
                for i = 1:length(videoExtensions)
                    candidatePath = fullfile(fileparts(parent), strcat(videoFileName, videoExtensions{i}));
                    if isfile(candidatePath)
                        mediaPath = candidatePath;
                        break;
                    end
                end
                mediaPath = char(mediaPath);
        end


        function preprocess(obj, varargin)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.DeepLabCut
            end
            arguments (Repeating)
                varargin
            end

            % Find the main app either via the global handle or by searching for the figure
            if exist('PlacePreferenceGUI', 'var') && ...
                    isa(PlacePreferenceGUI, 'PlacePrefDataGUI_main')
                fig = PlacePreferenceGUI.Figure;
            else
                fig = findall(0, 'Type', 'figure', 'Name', 'PlacePref Data Analysis');
            end

            msg = sprintf("Preprocessing, for now, is not implemented here for the DeepLabCut platform.\nIf you collected the data on a different platform, say EthoVision, please switch to that platform to do preprocessing first, then switch back to DeepLabCut for tracking and/or analysis.");

            if ~isempty(fig)
                uialert(fig, msg, 'Not Implemented', 'Icon', 'info');
            else
                msgbox(msg, 'Not Implemented', 'info');
            end
            return;
        end


        function [status, output] = runTracking(obj, videoFiles, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.DeepLabCut
                videoFiles (1,:) {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct(...
                'CSV', true, ...
                'CreateLabeledVideo', false, ...
                'ConfigFile', obj.dlcConfigFile ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            videoFiles = cellstr(videoFiles);
            % Check that all input videoFiles have the same extension
            [~, ~, exts] = cellfun(@fileparts, videoFiles, 'UniformOutput', false);
            uniqueExts = unique(exts);
            if ~isscalar(uniqueExts)
                error('All input video files must have the same extension.');
            end
            uniqueExts = char(uniqueExts);

            % Find the main app either via the global handle or by searching for the figure
            if exist('PlacePreferenceGUI', 'var') && ...
                    isa(PlacePreferenceGUI, 'PlacePrefDataGUI_main')
                fig = PlacePreferenceGUI.Figure;
            else
                fig = findall(0, 'Type', 'figure', 'Name', 'PlacePref Data Analysis');
            end


            % Make sure that the DLC config file is set
            cfg = obj.dlcConfigFile;
            cfg = char(cfg);
            if isempty(cfg) || ~isfile(cfg)
                if ~isempty(kvargs.Options.ConfigFile) && isfile(kvargs.Options.ConfigFile)
                    cfg = kvargs.Options.ConfigFile;
                end
            end
            if isempty(cfg) || ~isfile(cfg)
                % Prompt user to select DLC config file: notif with Select DLC Config YAML or Cancel
                if ~isempty(fig) && isvalid(fig)
                    selection = uiconfirm(fig, 'Please select the DeepLabCut configuration YAML file to proceed with tracking.', ...
                        'Select DLC Config File', ...
                        'Options', {'Select File', 'Cancel'}, ...
                        'Icon', 'warning', ...
                        'DefaultOption', 1, ...
                        'CancelOption', 2);
                else
                    selection = questdlg('Please select the DeepLabCut configuration YAML file to proceed with tracking.', ...
                        'Select DLC Config File', ...
                        'Select File', 'Cancel', 'Select File');
                end
                    if ~strcmp(selection, 'Select File')
                        status = false;
                        output = '';
                        warning('ui:trackingPlatforms:DeepLabCut:NoConfigFile', 'No DeepLabCut configuration file selected. Tracking aborted.');
                        return;
                    end
                [file, path] = uigetfile({'*.yaml;*.yml', 'YAML Files (*.yaml, *.yml)'}, 'Select DeepLabCut Configuration File');
                if isequal(file, 0) || isequal(path, 0)
                    status = false;
                    output = '';
                    warning('ui:trackingPlatforms:DeepLabCut:NoConfigFile', 'No DeepLabCut configuration file selected. Tracking aborted.');
                    return;
                end
                cfg = fullfile(path, file);
            end

            dlcConfig = utils.path.canonicalize(cfg);
            obj.dlcConfigFile = dlcConfig;

            prgdlg = gobjects(0);
            if ~isempty(fig) && isvalid(fig)
                prgdlg = uiprogressdlg(fig,'Title', 'Running DeepLabCut Tracking', ...
                    'Message', 'Initializing...', ...
                    'Cancelable', false, 'Indeterminate', 'on');
                cleanupObj = onCleanup(@() close(prgdlg));
                drawnow;
            end

            function updateCallback(line)
                if ~isempty(prgdlg) && isvalid(prgdlg)
                    prgdlg.Message = line;
                else
                    fprintf('%s\n', line);
                end
            end

            [status, elapsedTime, output] = io.dlc.runDLC( ...
                dlcConfig, ...
                videoFiles, ...
                uniqueExts(2:end), ... % videoType without the dot
                'CSV', kvargs.Options.CSV, ...
                'CreateLabeledVideo', kvargs.Options.CreateLabeledVideo, ...
                'UpdateCallbackFcn', @updateCallback ...
            );

            close(prgdlg);
        end


        function [header, datatable, units] = loadTrackingData(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.DeepLabCut
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'HeaderOnly', false ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;  

            validateattributes(kvargs.Options.HeaderOnly, {'logical'}, {'scalar'});

            fileHash = ui.trackingPlatforms.TrackingProvider.hashFile(dataFilePath);
            if strcmp(fileHash, obj.lastFileHash)
                header = obj.lastHeader;
                if kvargs.Options.HeaderOnly
                    datatable = table();
                    units = configureDictionary("string","string");
                    return;
                end

                if isempty(obj.lastDatatable) || (isempty(obj.lastUnits) || isempty(obj.lastUnits.keys))
                    [header, datatable, units] = io.dlc.loadDLCTrackingCSV(dataFilePath, 'HeaderOnly', false);
                    obj.lastHeader = header;
                    obj.lastDatatable = datatable;
                    obj.lastUnits = units;
                    
                    return;
                end
                datatable = obj.lastDatatable;
                units = obj.lastUnits;
                return;
            end

            obj.lastFileHash = fileHash;
            [header, datatable, units] = io.dlc.loadDLCTrackingCSV(dataFilePath, 'HeaderOnly', kvargs.Options.HeaderOnly);
            obj.lastHeader = header;
            obj.lastDatatable = datatable;
            obj.lastUnits = units;
        end



        function [timestampSec, coords, metadata] = loadTrackingCoordsPixels(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.DeepLabCut
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                ...% No options for now
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            options = kvargs.Options;
            options.HeaderOnly = false;

            [header, datatable, ~] = obj.loadTrackingData(dataFilePath, Options=options);


            ImgWidthFOV_cm = NaN;


            vidObj_temp = VideoReader(header('Video file'));
            vidWidth = vidObj_temp.Width;
            vidHeight = vidObj_temp.Height;
            pixelSize = ImgWidthFOV_cm / vidWidth; % cm/pixel
            FPS = vidObj_temp.FrameRate;

            dlcDataHeader = jsondecode(header('DLC data header jsonencode'));
            if ~isfield(dlcDataHeader, 'bodyparts') || ~isfield(dlcDataHeader, 'coords')
                error('io:dlc:loadTrackingCoordsPixels:InvalidDLCHeader', 'DLC data header does not contain bodyparts information. Either double-check the DLC CSV file, update the DLC toolbox, or check the loadDLCTrackingCSV() implementation.');
            end

            bodyparts = dlcDataHeader.bodyparts;
            coordLabels = dlcDataHeader.coords; % e.g., {'x', 'y', 'likelihood'}

            % In datatable, the bodyparts are flatten as {{bodypart} |> {coordLabel}}, e.g., {'Center |> x', 'Center | y', 'Center | likelihood', ...}
            % We need to extract the x and y coordinates for each bodypart and store them in coords 3D matrix
            nBodyparts = length(bodyparts);
            nFrames = height(datatable);
            coords = NaN(nFrames, 2, nBodyparts);

            datatableVars = datatable.Properties.VariableNames;
            for b = 1:nBodyparts
                bodypart = bodyparts{b};
                xColName = sprintf('%s |> %s', bodypart, 'x');
                yColName = sprintf('%s |> %s', bodypart, 'y');

                % Check if the columns exist (whether the datatable endsWith the re-constructed x/y column names)
                xColIdx = find(endsWith(datatableVars, xColName), 1);
                yColIdx = find(endsWith(datatableVars, yColName), 1);
                if isempty(xColIdx) || isempty(yColIdx)
                    error('io:dlc:loadTrackingCoordsPixels:MissingColumns', 'DLC tracking data table is missing expected columns for bodypart "%s".', bodypart);
                end

                coords(:, 1, b) = datatable.(xColName); % x
                coords(:, 2, b) = datatable.(yColName); % y
            end

            % timestampSec = (0:(nFrames-1))' / FPS; % This assumes constant FPS!!!
            % Slightly slower (need to extract PTS first), but more reliable for variable frame rate videos. The timestamps will reflect the actual real world frame times
            [pts, timebase] = ffprobe.pts(header('Video file'));
            timestampSec = double(pts) * double(timebase);

            metadata = struct();
            metadata.FPS = FPS;
            metadata.px2cmFactor = pixelSize;
            metadata.bodyparts = [cellstr(bodyparts)];
            metadata.colors = lines(nBodyparts);
        end

    end
end