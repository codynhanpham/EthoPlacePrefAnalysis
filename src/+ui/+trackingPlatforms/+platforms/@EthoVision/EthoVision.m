classdef EthoVision < ui.trackingPlatforms.TrackingProvider
    %ETHOVISION Summary of this class goes here
    %   Detailed explanation goes here

    properties (Constant)
        platform = "EthoVision";
    end

    properties
        userConfig = struct.empty();

        coordsUnit = "cm";
        px2cmFactor = NaN;
    end


    properties (Access = private)
        lastHeader = configureDictionary("string", "string"); % Store the last loadTrackingData() header to cache
        lastDatatable = table(); % Store the last loadTrackingData() datatable to cache
        lastUnits = configureDictionary("string", "string"); % Store the last loadTrackingData() units to cache

        lastFileHash = ''; % Store the last loadTrackingData() file to cache the header, datatable, and units
        lastArenaName = ''; % Last arena name used to load data, if both file hash and arena name match, return cached data
    end



    methods
        function obj = EthoVision()
            %ETHOVISION Construct an instance of this class
            %   Detailed explanation goes here
            
        end
    end


    methods (Static, Access = public)
        function filterProjectFolder(comp, kvargs)
            arguments
                comp (1,1) FolderSelectorWithDropdown
                kvargs.Options (1,1) struct = struct();
            end

            % You can set your defaults Options here
            defaultOptions = struct( ...
                ...% Don't have any options for now
            );
            % Update default options with user-provided options
            for field = fieldnames(kvargs.Options)'
                defaultOptions.(field{1}) = kvargs.Options.(field{1});
            end
            kvargs.Options = defaultOptions;

            io.ethovision.filterProjectFolder(comp);
        end

        function [trialNames, trialInfo] = filterTrials(projectFolder, kvargs)
            arguments
                projectFolder {validator.isEthovisionProjectFolder}
                kvargs.Options (1,1) struct = struct();
            end

            % You can set your defaults Options here
            defaultOptions = struct( ...
                ...% Don't have any options for now
            );
            % Update default options with user-provided options
            for field = fieldnames(kvargs.Options)'
                defaultOptions.(field{1}) = kvargs.Options.(field{1});
            end
            kvargs.Options = defaultOptions;

            [trialNames, trialInfo] = io.ethovision.filterTrials(projectFolder);
        end
    end


    methods
        function userConfig = loadConfig(obj, configs)
            %LOADCONFIG Load user configuration from the global config YAML file path or already loaded config struct
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                configs {validator.mustBeYmlOrStruct}
            end

            if ~isstruct(configs)
                configs = io.config.loadConfigYaml(configs);
            end
            
            if ~isfield(configs, 'tracking_providers') || ...
                    ~isfield(configs.tracking_providers, obj.platform)
                userConfig = struct();
                userConfig.CONFIG_ROOT = configs.CONFIG_ROOT; % Pass through the CONFIG_ROOT even if no platform-specific config is found, for potential use later
                return; % No EthoVision-specific config found
            end
            userConfig = configs.tracking_providers.(obj.platformVarnameCompat(obj.platform));
            userConfig.CONFIG_ROOT = configs.CONFIG_ROOT;

            defaults = struct();
            if isfield(configs, 'defaults')
                defaults = configs.defaults;
            end
            excludeFields = {'tracking_platform'};
            % For any config fields that are not defined in the platform-specific config, but are defined in the defaults, use the default values
            for field = fieldnames(defaults)'
                if ~isfield(userConfig, field{1}) && isfield(defaults, field{1}) && ~ismember(field{1}, excludeFields)
                    userConfig.(field{1}) = defaults.(field{1});
                end
            end

            obj.userConfig = userConfig;
            if isfield(userConfig, 'coordsUnit')
                obj.coordsUnit = userConfig.coordsUnit;
            else
                obj.coordsUnit = "cm"; % default to cm
            end
        end





        function mediaPath = mediaPathFromTrackingData(obj, trackingDataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                trackingDataFilePath (1,1) string
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'Header', configureDictionary("string", "string"), ... % must be a string-string dictionary
                'ExpectedNumVariables', 50 ... % must be scalar numeric
            );

            for field = fieldnames(kvargs.Options)'
                defaultOptions.(field{1}) = kvargs.Options.(field{1});
            end
            kvargs.Options = defaultOptions;

            validateattributes(kvargs.Options.Header, {'dictionary'}, {'scalar'});
            validateattributes(kvargs.Options.ExpectedNumVariables, {'numeric'}, {'scalar'});


            mediaPath = io.ethovision.mediaPathFromXlsx(trackingDataFilePath, ...
                Header=kvargs.Options.Header, ...
                ExpectedNumVariables=kvargs.Options.ExpectedNumVariables);
        end


        function updates = preprocess(obj, trackingDataFilePath, masterMetadata, kvargs)
            %PREPROCESS Pre-process raw data files for EthoVision platform
            %   This step handles splitting out multi-arena exports into single-arena files
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                trackingDataFilePath {mustBeFile}
                masterMetadata {validator.mustBeFileOrTable}

                % kvargs.ExpectedNumVariables (1, 1) double = 50
                % kvargs.ProgressDialogHandle {progressDlgHandleOrEmpty} = []
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'ExpectedNumVariables', 50, ...
                'ProgressDialogHandle', [] ...
            );
            for field = fieldnames(kvargs.Options)'
                defaultOptions.(field{1}) = kvargs.Options.(field{1});
            end
            kvargs.Options = defaultOptions;
            validateattributes(kvargs.Options.ExpectedNumVariables, {'numeric'}, {'scalar'});

            args = namedargs2cell(kvargs.Options);
            updates = io.ethovision.multipleArena.preprocess(trackingDataFilePath, masterMetadata, obj.userConfig, args{:});
        end


        function [status] = runTracking(obj, inputData, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                inputData
                kvargs.Options (1,1) struct = struct();
            end

            msg = sprintf("To perform tracking on the EthoVision platform, please use the EthoVision software directly.");
            
            % Find the main app either via the global handle or by searching for the figure
            if exist('PlacePreferenceGUI', 'var') && ...
                    isa(PlacePreferenceGUI, 'PlacePrefDataGUI_main')
                fig = PlacePreferenceGUI.Figure;
            else
                fig = findall(0, 'Type', 'figure', 'Name', 'PlacePref Data Analysis');
            end

            if ~isempty(fig)
                uialert(fig, msg, 'EthoVision Tracking Not Supported', 'Icon', 'warning');
            else
                msgbox(msg, 'EthoVision Tracking Not Supported', 'error');
            end
            return;
        end


        function [header, datatable, units] = loadTrackingData(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'ExpectedNumVariables', 50, ...
                'ArenaName', '', ...
                'HeaderOnly', false ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            validateattributes(kvargs.Options.ExpectedNumVariables, {'numeric'}, {'scalar'});
            validateattributes(kvargs.Options.ArenaName, {'char', 'string', 'cell'}, {'scalartext'});
            validateattributes(kvargs.Options.HeaderOnly, {'logical'}, {'scalar'});

            fileHash = obj.hashFile(dataFilePath);
            if strcmp(fileHash, obj.lastFileHash) && strcmpi(kvargs.Options.ArenaName, obj.lastArenaName)
                header = obj.lastHeader;
                if kvargs.Options.HeaderOnly
                    datatable = table();
                    units = configureDictionary("string", "string");
                    return;
                end
                if isempty(obj.lastDatatable) || (isempty(obj.lastUnits) || isempty(obj.lastUnits.keys))
                    [header, datatable, units] = io.ethovision.loadEthovisionXlsx(dataFilePath, ...
                        ExpectedNumVariables=kvargs.Options.ExpectedNumVariables, ...
                        ArenaName=kvargs.Options.ArenaName, ...
                        HeaderOnly=false);
                    
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
            if isempty(kvargs.Options.ArenaName)
                obj.lastArenaName = '';
            else
                obj.lastArenaName = kvargs.Options.ArenaName;
            end

            [header, datatable, units] = io.ethovision.loadEthovisionXlsx(dataFilePath, ...
                ExpectedNumVariables=kvargs.Options.ExpectedNumVariables, ...
                ArenaName=kvargs.Options.ArenaName, ...
                HeaderOnly=kvargs.Options.HeaderOnly);
            
            obj.lastHeader = header;
            obj.lastDatatable = datatable;
            obj.lastUnits = units;
        end



        function [timestampSec, coords, metadata] = loadTrackingCoordsPixels(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.EthoVision
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'ExpectedNumVariables', 50, ...
                'ArenaName', '' ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            validateattributes(kvargs.Options.ExpectedNumVariables, {'numeric'}, {'scalar'});
            validateattributes(kvargs.Options.ArenaName, {'char', 'string', 'cell'}, {'scalartext'});

            options = struct( ...
                'ExpectedNumVariables', kvargs.Options.ExpectedNumVariables, ...
                'ArenaName', kvargs.Options.ArenaName, ...
                'HeaderOnly', false ...
            );

            [header, datatable, ~] = obj.loadTrackingData(dataFilePath, Options=options);

            ImgWidthFOV_cm = 58.5; % default value for compat with older code
            CenterOffset_px = [0,0]; % default value for compat with older code
            
            configs = obj.userConfig;
            if isfield(configs, 'default_camera_imgwidth_fov_cm')
                ImgWidthFOV_cm = configs.('default_camera_imgwidth_fov_cm');
                if iscell(ImgWidthFOV_cm)
                    ImgWidthFOV_cm = cell2mat(ImgWidthFOV_cm);
                end
            end

            if isfield(configs, 'default_camera_center_offset_px')
                CenterOffset_px = configs.('default_camera_center_offset_px');
                CenterOffset_px = cell2mat(CenterOffset_px);
            end

            arenaName = header("Arena name");
            % Check for configs overrides for this arena
            if isfield(configs, 'arena')
                arenaConfigs = configs.arena;
                if iscell(arenaConfigs)
                    namesinconfig = cellfun(@(x) x.name, arenaConfigs, 'UniformOutput', false);
                else
                    namesinconfig = arenaConfigs.name;
                end
                namesinconfig = string(namesinconfig);
                if ismember(arenaName, namesinconfig)
                    arenaIdx = find(strcmp(namesinconfig, arenaName), 1);
                    if iscell(arenaConfigs)
                        arenaConfig = arenaConfigs{arenaIdx};
                    else
                        arenaConfig = arenaConfigs(arenaIdx);
                    end
                    if isfield(arenaConfig, 'camera_imgwidth_fov_cm')
                        ImgWidthFOV_cm = arenaConfig.camera_imgwidth_fov_cm;
                    end
                    if isfield(arenaConfig, 'camera_center_offset_px')
                        CenterOffset_px = arenaConfig.camera_center_offset_px;
                        CenterOffset_px = cell2mat(CenterOffset_px);
                    end
                end
            end

            videoPath = io.ethovision.mediaPathFromXlsx(dataFilePath, ...
                Header=header, ...
                ExpectedNumVariables=kvargs.Options.ExpectedNumVariables);
            % Calculate pixel size based on field of view
            vidObj_temp = VideoReader(videoPath);
            vidWidth = vidObj_temp.Width;
            vidHeight = vidObj_temp.Height;
            pixelSize = ImgWidthFOV_cm / vidWidth; % cm/pixel
            clear vidObj_temp;

            % Extract and transform coordinates for all body parts (optimized)
            bodyparts = {'center', 'nose', 'tail'}; % IMPORTANT: Update this list if the Ethovision config wildly change... typically, they should have all these three at least.
            
            % Pre-allocate for speed
            colNames = datatable.Properties.VariableNames;
            colNamesLower = lower(colNames); % Convert once for case-insensitive comparison
            
            % Pre-compute transformation parameters
            halfWidth = vidWidth / 2;
            halfHeight = vidHeight / 2;
            offsetX = (halfWidth * pixelSize) + (CenterOffset_px(1) * pixelSize);
            offsetY = (halfHeight * pixelSize) + (CenterOffset_px(2) * pixelSize);
            invPixelSize = 1 / pixelSize;
            
            availableBodyparts = {};
            transformedCoords = struct();
            partIndex = 1;
            
            % Vectorized extraction and transformation
            for i = 1:length(bodyparts)
                part = bodyparts{i};
                xColName = ['x ' part];
                yColName = ['y ' part];
                
                % Fast case-insensitive search using pre-computed lowercase names
                xIdx = find(strcmp(colNamesLower, xColName), 1);
                yIdx = find(strcmp(colNamesLower, yColName), 1);
                
                if ~isempty(xIdx) && ~isempty(yIdx)
                    xRaw = datatable{:, xIdx};
                    yRaw = datatable{:, yIdx};
                    
                    % Vectorized conversion from cells to numeric
                    if iscell(xRaw)
                        xRaw = str2double(xRaw); % Faster than cellfun for large arrays
                    end
                    if iscell(yRaw)
                        yRaw = str2double(yRaw);
                    end
                    
                    % Vectorized coordinate transformation (inline for speed)
                    xPixel = (xRaw + offsetX) * invPixelSize;
                    yPixel = vidHeight - ((yRaw + offsetY) * invPixelSize); % Combined flip and scale
                    
                    availableBodyparts{partIndex} = part; %#ok<AGROW>
                    transformedCoords.(part) = [xPixel, yPixel];
                    partIndex = partIndex + 1;
                end
            end

            % Format data for output
            timestampSec = datatable{:, 'Trial time'};
            fps = 1 / mean(diff(timestampSec));
            
            % Pre-allocate output array for better performance
            nFrames = length(timestampSec);
            nBodyparts = length(availableBodyparts);
            coords = zeros(nFrames, 2, nBodyparts);
            
            % Vectorized assignment of coordinates
            for i = 1:nBodyparts
                part = availableBodyparts{i};
                coords(:, :, i) = transformedCoords.(part);
            end
            
            metadata = struct( ...
                'FPS', fps, ...
                'px2cmFactor', pixelSize, ...
                'bodyparts', {availableBodyparts}, ...
                'colors', lines(nBodyparts) ...
            );
        end
        
    end
end

