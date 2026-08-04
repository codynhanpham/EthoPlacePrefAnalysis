classdef SLEAP < ui.trackingPlatforms.TrackingProvider
    %SLEAP Summary of this class goes here
    %   Detailed explanation goes here

    properties (Constant)
        platform = "SLEAP";
    end

    properties
        userConfig = struct.empty();

        coordsUnit = "px";
        px2cmFactor = NaN;
    end


    properties (Access = private)
        lastHeader = configureDictionary("string", "string"); % Store the last loadTrackingData() header to cache
        lastDatatable = table(); % Store the last loadTrackingData() datatable to cache
        lastUnits = configureDictionary("string", "string"); % Store the last loadTrackingData() units to cache

        lastFileHash = ''; % Store the last loadTrackingData() file to cache the header, datatable, and units
        lastInterpolation = "none"; % Interpolation method used for the cached table
    end



    methods
        function obj = SLEAP()
            %SLEAP Construct an instance of this class
            %   Detailed explanation goes here
            
        end

    end



    methods (Static, Access = public)
        function filterProjectFolder(comp)
            arguments
                comp (1,1) FolderSelectorWithDropdown
            end

            io.sleap.filterProjectFolder(comp);
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
                error('io:sleap:filterTrials:InvalidMetadataTable', 'A valid MetadataTable with columns "ETHOVISION_TRIAL" and "ETHOVISION_FILE" must be provided.');
            end

            [trialNames, trialInfo] = io.sleap.filterTrials(projectFolder, kvargs.Options.MetadataTable);
        end
    end


    methods
        function supported = supportsCapability(~, capability)
            arguments
                ~
                capability {mustBeTextScalar}
            end

            supported = ismember(lower(string(capability)), "__unsupported__");
        end

        function [header, datatable, units, stimulusFrameRange, animalMetadata, stimuli] = alignTrackingToStim(obj, trackingDataFilePath, stimuliDir, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
                trackingDataFilePath %#ok<INUSA>
                stimuliDir %#ok<INUSA>
                kvargs.Options (1,1) struct = struct() %#ok<INUSA>
            end

            obj.requireCapability("alignTrackingToStim");
            header = []; datatable = table(); units = [];
            stimulusFrameRange = []; animalMetadata = struct(); stimuli = struct();
        end

        function userConfig = loadConfig(obj, configs)
            %LOADCONFIG Load user configuration from the global config YAML file path or already loaded config struct
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
                configs {validator.mustBeYmlOrStruct}
            end

            if ~isstruct(configs)
                configs = io.config.loadConfigYaml(configs);
            end
            
            if ~isfield(configs, 'tracking_providers') || ...
                    ~isfield(configs.tracking_providers, obj.platformVarnameCompat(obj.platform))
                userConfig = struct();
                userConfig.CONFIG_ROOT = configs.CONFIG_ROOT;
                return; % No SLEAP-specific config found
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
            
            % Carry over any other root-level fields in the original config struct/YAML aside from defaults and tracking_providers
            otherfields = setdiff(fieldnames(configs), [{'defaults', 'tracking_providers'}, excludeFields]);
            for i = 1:length(otherfields)
                field = otherfields{i};
                % WARNING!!!
                % TODO: Handle cases where the tracking platform itself defines a field that is also present in the root level of the config YAML
                % Maybe merge struct?
                if ~isfield(userConfig, field)
                    userConfig.(field) = configs.(field);
                end
            end

            if isfield(userConfig, 'coordsUnit')
                obj.coordsUnit = userConfig.coordsUnit;
            else
                obj.coordsUnit = "px";
            end

            obj.userConfig = userConfig;
        end


        function mediaPath = mediaPathFromTrackingData(~, trackingDataFilePath, kvargs)
            arguments
                ~
                trackingDataFilePath (1,1) string
                kvargs.Options (1,1) struct = struct(); %#ok<INUSA>
            end

            % SLEAP tracking file are saved in videoFolder/sleap/<trialName>.predictions.slp
            % So we can just go up one folder and look for the video file with the same name as the tracking data file (without the .predictions.slp suffix)
            [trackingFolder, trackingFileName, ~] = fileparts(trackingDataFilePath);
            videoFileName = strrep(trackingFileName, '.predictions', '');
            
            % look in the parent folder to find the video file with matching name and known video extensions, grab the actual extension of the file
            videoExtensions = {'.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.3gp'};
            mediaPath = "";
            for i = 1:length(videoExtensions)
                candidatePath = fullfile(fileparts(trackingFolder), strcat(videoFileName, videoExtensions{i}));
                if isfile(candidatePath)
                    mediaPath = candidatePath;
                    break;
                end
            end
            mediaPath = char(mediaPath);
        end


        function [varargout] = preprocess(obj, varargin)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
            end
            arguments (Repeating)
                varargin
            end

            obj.platform;
            varargout{1} = {};

            % Find the main app either via the global handle or by searching for the figure
            if exist('PlacePreferenceGUI', 'var') && ...
                    isa(PlacePreferenceGUI, 'PlacePrefDataGUI_main')
                fig = PlacePreferenceGUI.Figure;
            else
                fig = findall(0, 'Type', 'figure', 'Name', 'PlacePref Data Analysis');
            end

            msg = sprintf("Preprocessing, for now, is not implemented here for the SLEAP platform.\nIf you collected the data on a different platform, say EthoVision, please switch to that platform to do preprocessing first, then switch back to SLEAP for tracking and/or analysis.");

            if ~isempty(fig)
                uialert(fig, msg, 'Not Implemented', 'Icon', 'info');
            else
                msgbox(msg, 'Not Implemented', 'info');
            end
            return;
        end


        function [status, output] = runTracking(obj, videoFiles, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
                videoFiles (1,:) {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'MainFigureHandle', gobjects(0), ...
                'ProgressDialogHandle', gobjects(0) ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            % Validate 'ProgressDialogHandle' option, either empty, or a valid
            % uiprogressdlg handle of class 'matlab.ui.dialog.ProgressDialog'
            % if not valid, set to empty
            if ~isempty(kvargs.Options.ProgressDialogHandle) && ...
                    ~(isvalid(kvargs.Options.ProgressDialogHandle) && ...
                    isa(kvargs.Options.ProgressDialogHandle, 'matlab.ui.dialog.ProgressDialog'))
                warning('ui:trackingPlatforms:SLEAP:runTracking:InvalidProgressDialogHandle', ...
                    'The provided ProgressDialogHandle is not a valid uiprogressdlg handle. It will be ignored.');
                kvargs.Options.ProgressDialogHandle = gobjects(0);
            end
            % The provided MainFigureHandle must exist, otherwise, set to empty
            if ~isempty(kvargs.Options.MainFigureHandle) && ...
                    ~(isvalid(kvargs.Options.MainFigureHandle) && ...
                    isa(kvargs.Options.MainFigureHandle, 'matlab.ui.Figure'))
                warning('ui:trackingPlatforms:SLEAP:runTracking:InvalidMainFigureHandle', ...
                    'The provided MainFigureHandle is not a valid uifigure handle. It will be ignored.');
                kvargs.Options.MainFigureHandle = gobjects(0);
            end
            
            % If the MainFigureHandle is empty, try to find the main app figure by heuristics
            % Find the main app either via the global handle or by searching for the figure
            if ~isempty(kvargs.Options.MainFigureHandle) && isvalid(kvargs.Options.MainFigureHandle)
                fig = kvargs.Options.MainFigureHandle;
            else
                if exist('PlacePreferenceGUI', 'var') && ...
                        isa(PlacePreferenceGUI, 'PlacePrefDataGUI_main')
                    fig = PlacePreferenceGUI.Figure;
                else
                    fig = findall(0, 'Type', 'figure', 'Name', 'PlacePref Data Analysis');
                    if isempty(fig) || ~all(isvalid(fig))
                        fig = gobjects(0);
                    else
                        fig = fig(1); % Take the first valid figure found
                    end
                end
            end

            try
                modelPaths = validateSLEAPModelPaths(obj.userConfig);
            catch ME
                texErrorMessage = strrep(ME.message, '_', '\_');
                msg = sprintf(['\\fontname{Helvetica}%s\n\n\\fontname{Helvetica}Please update the SLEAP ' ...
                    '{\\bf model\\_paths} entries in your config YAML file before running tracking.'], ...
                    texErrorMessage);
                if ~isempty(fig) && isvalid(fig)
                    uialert(fig, msg, 'Invalid SLEAP Model Paths', ...
                        'Icon', 'warning', 'Interpreter', 'tex');
                else
                    warningDialog = warndlg(msg, 'Invalid SLEAP Model Paths', 'modal');
                    warningText = findall(warningDialog, 'Type', 'text');
                    set(warningText, 'Interpreter', 'tex', 'FontName', 'Helvetica');
                end
                status = false;
                output = '';
                warning('io:sleap:runTracking:InvalidModelPaths', 'SLEAP model paths are invalid. Please check your config YAML file.\n\n%s', getReport(ME, 'extended'));
                return;
            end

            videoFiles = cellstr(videoFiles);

            % Create a progress dialog if a valid handle is not provided,
            % otherwise, use the provided handle to update the progress message
            % ProgressDialog only applies when fig is a valid uifigure handle
            
            if ~isempty(kvargs.Options.ProgressDialogHandle) && isvalid(kvargs.Options.ProgressDialogHandle)
                prgdlg = kvargs.Options.ProgressDialogHandle;
            else
                if ~isempty(fig) && isvalid(fig)
                    prgdlg = uiprogressdlg(fig, 'Title', 'SLEAPing...', ...
                        'Message', 'Initializing...', ...
                        'Cancelable', false, 'Indeterminate', 'on');
                        clenaupObj = onCleanup(@() delete(prgdlg));
                else
                    prgdlg = [];
                end
            end


            % Ensure io.sleap.available() first,
            % If not, we can handle io.sleap.install() here with Verbose and progress
            % Set prg to "Checking SLEAP installation functionality..." and then call io.sleap.available()
            prgdlg.Message = 'Checking SLEAP installation functionality...';
            prgdlg.Title = 'Ensure SLEAP...';
            [isAvailable, ~] = io.sleap.available();
            if ~isAvailable
                prgdlg.Message = 'SLEAP is not available. Attempting to install SLEAP. See the MATLAB Command Window for details...';
                prgdlg.Title = 'Installing SLEAP...';
                try
                    [uvpath, sleapdir] = io.sleap.install('Verbose', true);
                    fprintf('SLEAP installation completed successfully.\n\nUV path: %s\nSLEAP directory: %s\n\n', uvpath, sleapdir);
                catch ME
                    delete(prgdlg);
                    texErrorMessage = strrep(ME.message, '_', '\_');
                    msg = sprintf(['\\fontname{Helvetica}%s\n\n\\fontname{Helvetica}Please ensure that SLEAP is installed via io.sleap.install() and available in your MATLAB environment before running tracking.'], ...
                        texErrorMessage);
                    if ~isempty(fig) && isvalid(fig)
                        uialert(fig, msg, 'SLEAP Installation Failed', ...
                            'Icon', 'error', 'Interpreter', 'tex');
                    else
                        error('io:sleap:runTracking:SLEAPInstallationFailed', ...
                            'SLEAP installation failed. Please ensure that SLEAP is installed via io.sleap.install() and available in your MATLAB environment before running tracking.\n\n%s', getReport(ME, 'extended'));
                    end
                    status = false;
                    output = '';
                    return;
                end
            end
            % At this point, SLEAP is available
            % We can get the canonical path to the SLEAP directory and the uv path for reporting
            [uvpath, sleapdir] = io.sleap.install(); % no-op if already installed, only to get the paths

            % Report uv path and sleapdir to prgdlg.Message
            prgdlg.Message = sprintf('SLEAP is available.\n\nUV path: %s\n\nSLEAP directory: %s\n\n\nRunning SLEAP tracking on %d video(s)...', uvpath, sleapdir, numel(videoFiles));
            prgdlg.Title = 'Running SLEAP Tracking...';

            [status, ~, output] = io.sleap.predict( ...
                videoFiles, ...
                modelPaths, ...
                'SleapUserConfig', obj.userConfig, ...
                'ProgressDialogHandle', prgdlg ...
            );

            close(prgdlg);
        end


        function [header, datatable, units] = loadTrackingData(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                'HeaderOnly', false, ...
                'Interpolation', 'pchip' ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;  

            validateattributes(kvargs.Options.HeaderOnly, {'logical'}, {'scalar'});
            validateattributes(kvargs.Options.Interpolation, {'char', 'string'}, {'scalartext'});
            interpolation = string(kvargs.Options.Interpolation);
            validInterpolations = ["none", "linear", "nearest", "spline", "makima", "pchip", "cubic"];
            if ~ismember(lower(interpolation), validInterpolations)
                error('ui:trackingPlatforms:SLEAP:loadTrackingData:InvalidInterpolation', ...
                    'Interpolation must be one of: %s.', strjoin(validInterpolations, ', '));
            end

            fileHash = ui.trackingPlatforms.TrackingProvider.hashFile(dataFilePath);
            if strcmp(fileHash, obj.lastFileHash) && strcmpi(interpolation, obj.lastInterpolation)
                header = obj.lastHeader;
                if kvargs.Options.HeaderOnly
                    datatable = table();
                    units = configureDictionary("string","string");
                    return;
                end

                if isempty(obj.lastDatatable) || (isempty(obj.lastUnits) || isempty(obj.lastUnits.keys))
                    [header, datatable, units] = io.sleap.loadTrackingSlp( ...
                        dataFilePath, 'HeaderOnly', false, 'Interpolation', interpolation);
                    obj.lastHeader = header;
                    obj.lastDatatable = datatable;
                    obj.lastUnits = units;
                    obj.lastInterpolation = interpolation;
                    
                    return;
                end
                datatable = obj.lastDatatable;
                units = obj.lastUnits;
                return;
            end

            obj.lastFileHash = fileHash;
            [header, datatable, units] = io.sleap.loadTrackingSlp( ...
                dataFilePath, ...
                'HeaderOnly', kvargs.Options.HeaderOnly, ...
                'Interpolation', interpolation);
            obj.lastHeader = header;
            obj.lastDatatable = datatable;
            obj.lastUnits = units;
            obj.lastInterpolation = interpolation;
        end



        function [timestampSec, coords, metadata] = loadTrackingCoordsPixels(obj, dataFilePath, kvargs)
            arguments
                obj (1,1) ui.trackingPlatforms.platforms.SLEAP
                dataFilePath {mustBeFile}
                kvargs.Options (1,1) struct = struct();
            end

            defaultOptions = struct( ...
                 'Interpolation', 'pchip' ...
            );
            for f = fieldnames(kvargs.Options)'
                defaultOptions.(f{1}) = kvargs.Options.(f{1});
            end
            kvargs.Options = defaultOptions;

            options = kvargs.Options;
            options.HeaderOnly = false;

            [header, datatable, ~] = obj.loadTrackingData(dataFilePath, Options=options);


            ImgWidthFOV_cm = NaN;


            videoFilePath = string(header('Video file'));
            if strlength(videoFilePath) == 0 || ~isfile(videoFilePath)
                error('io:sleap:loadTrackingCoordsPixels:MissingVideoFile', ...
                    'The source video file could not be resolved from the SLEAP file.');
            end

            vidObj_temp = VideoReader(char(videoFilePath));
            vidWidth = vidObj_temp.Width;
            pixelSize = ImgWidthFOV_cm / vidWidth; % cm/pixel
            FPS = vidObj_temp.FrameRate;

            sleapDataHeader = jsondecode(header('SLEAP data header jsonencode'));
            if ~isfield(sleapDataHeader, 'bodyparts') || ~isfield(sleapDataHeader, 'coords')
                error('io:sleap:loadTrackingCoordsPixels:InvalidSLEAPHeader', 'SLEAP data header does not contain bodyparts information. Either double-check the SLEAP CSV file, update the SLEAP toolbox, or check the loadSLEAPTrackingCSV() implementation.');
            end

            bodyparts = string(sleapDataHeader.bodyparts);

            % In datatable, the bodyparts are flatten as {{bodypart} |> {coordLabel}}, e.g., {'Center |> x', 'Center | y', 'Center | likelihood', ...}
            % We need to extract the x and y coordinates for each bodypart and store them in coords 3D matrix
            nBodyparts = numel(bodyparts);
            nFrames = height(datatable);
            coords = NaN(nFrames, 2, nBodyparts);

            datatableVars = datatable.Properties.VariableNames;
            for b = 1:nBodyparts
                bodypart = char(bodyparts(b));
                xColName = sprintf('%s |> %s', bodypart, 'x');
                yColName = sprintf('%s |> %s', bodypart, 'y');

                xColIdx = find(strcmp(datatableVars, xColName), 1);
                yColIdx = find(strcmp(datatableVars, yColName), 1);
                if isempty(xColIdx) || isempty(yColIdx)
                    error('io:sleap:loadTrackingCoordsPixels:MissingColumns', 'SLEAP tracking data table is missing expected columns for bodypart "%s".', bodypart);
                end

                coords(:, 1, b) = datatable{:, xColIdx}; % x
                coords(:, 2, b) = datatable{:, yColIdx}; % y
            end

            % Use presentation timestamps rather than frame/FPS arithmetic so
            % variable-frame-rate videos retain their actual timing.
            [pts, timebase] = ffprobe.pts(char(videoFilePath));
            timestampSec = double(pts(:)) * double(timebase);
            if numel(timestampSec) ~= nFrames
                error('io:sleap:loadTrackingCoordsPixels:TimestampCountMismatch', ...
                    'ffprobe returned %d timestamps for %d tracking rows.', ...
                    numel(timestampSec), nFrames);
            end
            if nFrames > 1
                validDiffs = diff(timestampSec);
                validDiffs = validDiffs(isfinite(validDiffs) & validDiffs > 0);
                if ~isempty(validDiffs)
                    FPS = 1 / mean(validDiffs);
                end
            end

            metadata = struct();
            metadata.FPS = FPS;
            metadata.px2cmFactor = pixelSize;
            metadata.bodyparts = cellstr(bodyparts);
            metadata.colors = lines(nBodyparts);
            metadata.edges = localSleapEdges(header, nBodyparts);
        end

    end
end

function edges = localSleapEdges(header, nBodyparts)
    edges = {};
    if ~isKey(header, "SLEAP metadata jsonencode")
        return;
    end

    slpMetadata = jsondecode(header("SLEAP metadata jsonencode"));
    if ~isfield(slpMetadata, 'skeletons') || isempty(slpMetadata.skeletons) || ...
            ~isfield(slpMetadata.skeletons, 'links')
        return;
    end

    links = slpMetadata.skeletons(1).links;
    if isempty(links)
        return;
    end
    edges = repmat(struct('source', 0, 'target', 0), 1, numel(links));
    for edgeIdx = 1:numel(links)
        source = double(links(edgeIdx).source) + 1;
        target = double(links(edgeIdx).target) + 1;
        if ~isscalar(source) || ~isscalar(target) || ...
                source < 1 || source > nBodyparts || ...
                target < 1 || target > nBodyparts || ...
                source ~= fix(source) || target ~= fix(target)
            error('ui:sleap:loadTrackingCoordsPixels:InvalidEdge', ...
                'SLEAP edge %d references an invalid bodypart index.', edgeIdx);
        end
        edges(edgeIdx).source = source;
        edges(edgeIdx).target = target;
    end
end


function modelPaths = validateSLEAPModelPaths(userConfig)
    if ~isstruct(userConfig) || ~isfield(userConfig, 'model_paths') || isempty(userConfig.model_paths)
        error('ui:trackingPlatforms:SLEAP:MissingModelPath', ...
            ['For SLEAP tracking, ensure a SLEAP entry exists in the ' ...
            'tracking_providers field of your config YAML file. Next, make sure ' ...
            'the model_paths field for SLEAP points to the correct SLEAP model folder(s).']);
    end

    modelPaths = string(userConfig.model_paths);
    modelPaths = modelPaths(:);
    modelPaths = modelPaths(strlength(strtrim(modelPaths)) > 0);
    if isempty(modelPaths)
        error('ui:trackingPlatforms:SLEAP:MissingModelPath', ...
            ['For SLEAP tracking, ensure a SLEAP entry exists in the ' ...
            'tracking_providers field of your config YAML file. Next, make sure ' ...
            'the model_paths field for SLEAP points to the correct SLEAP model folder(s).']);
    end

    configRoot = "";
    if isfield(userConfig, 'CONFIG_ROOT') && ~isempty(userConfig.CONFIG_ROOT)
        configRoot = string(userConfig.CONFIG_ROOT);
    end

    resolvedPaths = strings(size(modelPaths));
    for i = 1:numel(modelPaths)
        modelPath = modelPaths(i);
        if ~isfolder(modelPath) && strlength(configRoot) > 0
            modelPath = fullfile(configRoot, modelPath);
        end
        if ~isfolder(modelPath)
            error('ui:trackingPlatforms:SLEAP:InvalidModelPath', ...
                'SLEAP model_paths entry is not a valid folder: %s', modelPaths(i));
        end

        files = dir(fullfile(modelPath, '*'));
        fileNames = string({files(~[files.isdir]).name});
        hasConfig = any(endsWith(lower(fileNames), [".yml", ".yaml"]));
        hasModel = any(endsWith(lower(fileNames), [".ckpt", ".trt", ".onnx"]));
        if ~hasConfig || ~hasModel
            error('ui:trackingPlatforms:SLEAP:InvalidModelPath', ...
                ['SLEAP model folder "%s" must contain at least one .yml or .yaml ' ...
                'file and at least one .ckpt, .trt, or .onnx file.'], modelPath);
        end
        resolvedPaths(i) = string(utils.path.canonicalize(modelPath));
    end
    modelPaths = cellstr(resolvedPaths);
end