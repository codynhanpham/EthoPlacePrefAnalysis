classdef (Abstract) TrackingProvider < handle
    %TRACKINGPROVIDER An abstract base class for tracking providers
    %   To implement a new tracking provider, create a subclass that
    %   defines the required Abstract properties and methods.

    properties (Abstract, Constant)
        %% ALL SUBCLASSES MUST DEFINE THEIR PLATFORM NAME
        platform {mustBeTextScalar}
    end


    properties (Abstract)
        %% ALL SUBCLASSES MUST DEFINE THESE PROPERTIES

        userConfig % User configuration specific to the tracking platform and/or experiment. This is usually a scalar struct or object.

        coordsUnit {mustBeTextScalar} % Unit of the tracked coordinates, e.g., 'pixels', 'cm', etc.
        px2cmFactor (1,1) double % Conversion factor from pixels to centimeters

    end


    methods (Static, Sealed)
        function obj = initPlatform(platform)
            %%INITPLATFORM Initialize a new USV platform processor based on the platform name
            arguments
                platform {mustBeTextScalar}
            end

            [availablePlatforms, platformClasses] = ui.trackingPlatforms.TrackingProvider.listAvailablePlatforms();
            idx = find(strcmpi(availablePlatforms, platform), 1);

            if isempty(idx)
                error('TrackingProvider:InvalidPlatform', 'Platform "%s" is not recognized. Available platforms are: { ''%s'' }', platform, strjoin(availablePlatforms, ''', '''));
            end

            
            platformClass = platformClasses(idx).Name;
            platformObjClassConstructor = str2func(platformClass);
            obj = platformObjClassConstructor();
        end

        function [platforms, platformClasses] = listAvailablePlatforms()
            %%LISTAVAILABLEPLATFORMS List all available tracking providers
            platformNamespace = matlab.metadata.Namespace.fromName('ui.trackingPlatforms.platforms');
            platformClasses = platformNamespace.ClassList;
            platforms = strings(1, numel(platformClasses));
            for k = 1:numel(platformClasses)
                cls = platformClasses(k);
                metaClass = meta.class.fromName(cls.Name);
                superclassNames = superclasses(metaClass.Name);
                if ismember({'ui.trackingPlatforms.TrackingProvider'}, superclassNames)
                    platformProp = metaClass.PropertyList(strcmp({metaClass.PropertyList.Name}, 'platform'));
                    if ~isempty(platformProp) && platformProp.Constant
                        platforms(k) = platformProp.DefaultValue;
                    end
                end
            end
            % remove empty entries and duplicates
            [platforms, uniqueIdx] = unique(platforms);
            platformClasses = platformClasses(uniqueIdx);
            nonEmptyIdx = platforms ~= "";
            platforms = platforms(nonEmptyIdx);
            platformClasses = platformClasses(nonEmptyIdx);
        end

        function str = platformVarnameCompat(platformName)
            %%PLATFORMVARNAMECOMPAT Convert platform name to a valid MATLAB variable name via matlab.lang.makeValidName
            arguments
                platformName {mustBeTextScalar}
            end

            str = matlab.lang.makeValidName(platformName);
        end

        function str = hashFile(filePath)
            %%HASHFILE Compute a SHA-256 hash of the file contents for caching purposes
            %   A convenient function to hash a file's contents given a file path
            arguments
                filePath {mustBeFile}
            end

            str = DataHash(char(filePath), 'SHA-256', 'file');
        end

        function extractAndSaveTriggerEvents(videoFilePath, kvargs)
            %%EXTRACTANDSAVETRIGGEREVENTS Extract LED trigger pulses and persist to sibling .ref.json.
            %
            % Requires: triggerExtract.ledPulses(videoFilePath) to extract the LED trigger events from the video file

            arguments
                videoFilePath {mustBeTextScalar, mustBeFile}
                kvargs.ProgressDialogHandle {progressDlgHandleOrEmpty} = []
            end

            [videoDir, videoBaseName, ~] = fileparts(videoFilePath);
            referenceFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

            % Keep reference metadata in a single JSON format before trigger I/O.
            try
                graphics.migrateLegacyCSVRefs2JSON(videoDir);
            catch ME
                warning('ui:trackingPlatforms:TrackingProvider:LegacyRefMigrationFailed', ...
                    'Could not auto-migrate legacy CSV reference files in "%s":\n%s', videoDir, ME.message);
            end

            [refData, isLoaded, parseErrorMessage] = readReferenceJson(referenceFilePath);
            if ~isLoaded
                warning('ui:trackingPlatforms:TrackingProvider:RefJsonReadFailed', ...
                    ['Could not parse reference JSON, skipping trigger extraction to avoid ' ...
                    'overwriting existing fields: %s\n%s'], referenceFilePath, parseErrorMessage);
                return;
            end

            if ~isempty(refData) && ~isstruct(refData)
                warning('ui:trackingPlatforms:TrackingProvider:RefJsonReadFailed', ...
                    'Reference JSON root is not an object, skipping trigger extraction: %s', referenceFilePath);
                return;
            end

            if isstruct(refData) && isfield(refData, 'trigger_events') && ~isempty(refData.trigger_events)
                [existingPairsCell, isCanonical, isUsable] = canonicalizeTriggerEvents(refData.trigger_events);
                if isUsable
                    if ~isCanonical
                        refData.trigger_events = existingPairsCell;
                        writeReferenceJson(referenceFilePath, refData);
                    end
                    return;
                end
                % Requirement: skip detection whenever trigger_events is present and non-empty.
                return;
            end

            if ~isempty(kvargs.ProgressDialogHandle)
                currentIndeterminateState = kvargs.ProgressDialogHandle.Indeterminate;
                currentProgressMessage = kvargs.ProgressDialogHandle.Message;
                kvargs.ProgressDialogHandle.Indeterminate = true;
                kvargs.ProgressDialogHandle.Message = 'Extracting trigger events...';
                progressCleanup = onCleanup(@() restoreProgressDialogState(kvargs.ProgressDialogHandle, currentIndeterminateState, currentProgressMessage));
            end

            % triggerExtract should be pre-installed
            % The repo ships with a prebuilt binary for x64 Windows and Linux,
            % though you might also need a system dependency for OpenCV
            % https://github.com/twistedfall/opencv-rust/blob/master/INSTALL.md
            % For other platforms, you will need to build the binary from source
            %   1. Ensure you have Rust installed (https://www.rust-lang.org/tools/install)
            %   2. Go to /lib/trigger-extract/private/trigger-extract (see the Cargo.toml file)
            %   3. Run `cargo build --release` to build the binary
            eventTable = triggerExtract.ledPulses(videoFilePath);
            if isempty(eventTable)
                triggerEvents = cell(1, 0);
            else
                requiredCols = {'onFrame', 'offFrame'};
                if ~all(ismember(requiredCols, eventTable.Properties.VariableNames))
                    error('ui:trackingPlatforms:TrackingProvider:InvalidLedEventsTable', ...
                        'LED event table is missing required columns: onFrame, offFrame.');
                end
                [triggerEvents, ~, ~] = canonicalizeTriggerEvents(double([eventTable.onFrame, eventTable.offFrame]));
            end

            refData.trigger_events = triggerEvents;
            refData.trigger_events_start_validated = false;  % Auto-detected, not yet manually validated
            writeReferenceJson(referenceFilePath, refData);
        end

        function extractAndSaveArenaGridVertices(videoFilePath, kvargs)
            %%EXTRACTANDSAVEARENAGRIDVERTICES Extract arena grid vertices and persist to sibling .ref.json.
            %
            % Requires: owlv2-detect lib - owlv2.blackmarks(_)
            % For optimal performance when running inference on multiple videos, batch the videos into a single list and call the function once with the entire list of video file paths, rather than calling it separately for each video file.
            % Ideally, this is often called after preprocessing (splitting and trigger event extraction), when all videos are split and ready for batch processing.

            arguments
                videoFilePath
                kvargs.ProgressDialogHandle {progressDlgHandleOrEmpty} = []
            end

            videoFilePaths = string(videoFilePath);
            videoFilePaths = videoFilePaths(:);
            videoFilePaths = videoFilePaths(videoFilePaths ~= "");
            if isempty(videoFilePaths)
                return;
            end

            if any(~isfile(videoFilePaths))
                missingVideoFilePaths = videoFilePaths(~isfile(videoFilePaths));
                error('ui:trackingPlatforms:TrackingProvider:InvalidVideoFilePath', ...
                    'One or more video files do not exist: %s', strjoin(missingVideoFilePaths, ', '));
            end

            videoFilePaths = unique(videoFilePaths, 'stable');

            videoDirs = strings(numel(videoFilePaths), 1);
            for ii = 1:numel(videoFilePaths)
                [videoDirs(ii), ~, ~] = fileparts(videoFilePaths(ii));
            end

            uniqueVideoDirs = unique(videoDirs, 'stable');
            for ii = 1:numel(uniqueVideoDirs)
                try
                    graphics.migrateLegacyCSVRefs2JSON(char(uniqueVideoDirs(ii)));
                catch ME
                    warning('ui:trackingPlatforms:TrackingProvider:LegacyRefMigrationFailed', ...
                        'Could not auto-migrate legacy CSV reference files in "%s":\n%s', uniqueVideoDirs(ii), ME.message);
                end
            end

            pendingVideoFilePaths = strings(0, 1);
            pendingReferenceFilePaths = strings(0, 1);
            pendingReferenceData = cell(0, 1);

            for ii = 1:numel(videoFilePaths)
                videoFile = videoFilePaths(ii);
                [videoDir, videoBaseName, ~] = fileparts(videoFile);
                referenceFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

                [refData, isLoaded, parseErrorMessage] = readReferenceJson(referenceFilePath);
                if ~isLoaded
                    warning('ui:trackingPlatforms:TrackingProvider:RefJsonReadFailed', ...
                        ['Could not parse reference JSON, skipping arena grid extraction for this video to avoid ' ...
                        'overwriting existing fields: %s\n%s'], referenceFilePath, parseErrorMessage);
                    continue;
                end

                if ~isempty(refData) && ~isstruct(refData)
                    warning('ui:trackingPlatforms:TrackingProvider:RefJsonReadFailed', ...
                        'Reference JSON root is not an object, skipping arena grid extraction: %s', referenceFilePath);
                    continue;
                end

                if isstruct(refData) && isfield(refData, 'arena_grid') && isstruct(refData.arena_grid) && isfield(refData.arena_grid, 'vertices')
                    [existingVertices, hasExistingVertices] = normalizeArenaGridVertices(refData.arena_grid.vertices);
                    if hasExistingVertices && size(existingVertices, 1) >= 4
                        continue;
                    end
                end

                pendingVideoFilePaths(end+1, 1) = videoFile; %#ok<AGROW>
                pendingReferenceFilePaths(end+1, 1) = referenceFilePath; %#ok<AGROW>
                pendingReferenceData{end+1, 1} = refData; %#ok<AGROW>
            end

            if isempty(pendingVideoFilePaths)
                return;
            end

            if ~isempty(kvargs.ProgressDialogHandle)
                currentIndeterminateState = kvargs.ProgressDialogHandle.Indeterminate;
                currentProgressMessage = kvargs.ProgressDialogHandle.Message;
                kvargs.ProgressDialogHandle.Indeterminate = true;
                kvargs.ProgressDialogHandle.Message = 'Extracting arena grid vertices...';
                progressCleanup = onCleanup(@() restoreProgressDialogState(kvargs.ProgressDialogHandle, currentIndeterminateState, currentProgressMessage));
            end

            try
                % Ensure the installation is done before trying to run the blackmarks command, in case the user has not installed it yet
                % This is no-op if already installed
                owlv2.install();
            catch ME
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'Could not install OWLv2-Detector Utility:\n%s', ME.message);
                return;
            end

            try
                [exitCode, stdout] = owlv2.blackmarks(pendingVideoFilePaths, TopNMarks=4, LogLevel='quiet', BatchSize=21);
            catch ME
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'Could not run arena grid vertex extraction:\n%s', ME.message);
                return;
            end

            if exitCode ~= 0
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'OWLv2 black-marks exited with code %d. Skipping arena grid vertex extraction for pending videos.', exitCode);
                return;
            end

            try
                jsonResults = jsondecode(stdout);
            catch
                stdoutLines = splitlines(strtrim(string(stdout)));
                stdoutLines = stdoutLines(strlength(stdoutLines) > 0);
                if isempty(stdoutLines)
                    warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                        'OWLv2 black-marks did not return JSON output. Leaving the reference JSON untouched.');
                    return;
                end

                try
                    jsonResults = jsondecode(stdoutLines(end));
                catch ME
                    warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                        'Could not parse OWLv2 black-marks JSON output. Leaving the reference JSON untouched.\n%s', ME.message);
                    return;
                end
            end

            if ~isstruct(jsonResults)
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'OWLv2 black-marks returned an unexpected JSON shape. Leaving the reference JSON untouched.');
                return;
            end

            if isempty(jsonResults)
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'OWLv2 black-marks returned no arena grid results. Leaving the reference JSON untouched.');
                return;
            end

            if ~isfield(jsonResults, 'file') || ~isfield(jsonResults, 'markers')
                warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractFailed', ...
                    'OWLv2 black-marks JSON is missing required file/markers fields. Leaving the reference JSON untouched.');
                return;
            end

            resultFiles = strings(numel(jsonResults), 1);
            for ii = 1:numel(jsonResults)
                resultFiles(ii) = string(jsonResults(ii).file);
            end

            for ii = 1:numel(pendingVideoFilePaths)
                videoFile = pendingVideoFilePaths(ii);
                resultIdx = find(strcmpi(resultFiles, videoFile), 1);
                if isempty(resultIdx)
                    warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractMissingResult', ...
                        'OWLv2 black-marks did not return arena grid vertices for %s. Leaving the reference JSON untouched.', videoFile);
                    continue;
                end

                [arenaVertices, isUsable] = canonicalizeArenaGridVertices(jsonResults(resultIdx).markers);
                if ~isUsable
                    warning('ui:trackingPlatforms:TrackingProvider:ArenaGridExtractInvalidMarkers', ...
                        'OWLv2 black-marks returned malformed or incomplete arena grid markers for %s. Leaving the reference JSON untouched.', videoFile);
                    continue;
                end

                refData = pendingReferenceData{ii};
                refData.arena_grid.vertices = arenaVertices;

                try
                    writeReferenceJson(pendingReferenceFilePaths(ii), refData);
                catch ME
                    warning('ui:trackingPlatforms:TrackingProvider:ArenaGridWriteFailed', ...
                        'Could not write arena grid vertices to %s:\n%s', pendingReferenceFilePaths(ii), ME.message);
                end
            end
        end
    end

    methods
        function obj = TrackingProvider()
            %TRACKINGPROVIDER Construct an instance of this class
            %   In this abstract, initialize common properties as needed

        end

        function supported = supportsCapability(~, capability)
            %%SUPPORTSCAPABILITY Report whether a provider supports an optional operation.
            %   Subclasses should override this method when they implement a
            %   capability such as stimulus alignment or preprocessing.
            arguments
                ~
                capability {mustBeTextScalar} %#ok<INUSA>
            end

            supported = false;
        end

        function requireCapability(obj, capability)
            %%REQUIRECAPABILITY Raise a consistent error for unsupported operations.
            arguments
                obj (1,1) ui.trackingPlatforms.TrackingProvider
                capability {mustBeTextScalar}
            end

            if ~obj.supportsCapability(capability)
                error('ui:trackingPlatforms:TrackingProvider:UnsupportedCapability', ...
                    'Tracking provider "%s" does not support capability "%s".', ...
                    obj.platform, capability);
            end
        end

    end



    methods (Abstract, Static, Access = public)
        %% ALL SUBCLASSES MUST IMPLEMENT THE FOLLOWING STATIC METHODS

        filterProjectFolder(comp, Options); % comp is a FolderSelectorWithDropdown component
        %%FILTERPROJECTFOLDER
        % A callback to list out 'Project' folders given a SelectedParent inside of a FolderSelectorWithDropdown component
        % This function is used for updating the GUI with available project folders for the tracking platform
        %   Provide this function handle and its {2:end} arguments to FolderSelectorWithDropdown.DropdownItemsFilterFcn
        %   {@filterProjectFolder}



        [trialNames, trialInfo] = filterTrials(varargin, Options);
        %%FILTERTRIALS Filter trials in a project folder
        %   A valid trial must have BOTH: a raw media file and a corresponding tracked data file
        %   Inputs:
        %       projectFolder - The path to the project folder
        %   Outputs:
        %       trialNames - A cell array of strings containing the names of the filtered trials (typically, base file names without extensions)
        %       trialInfo - A struct array containing the filtered trials with fields:
        %                'media' - path to the raw media file
        %                'data'  - path to the tracking data file
        %                'trialNumeric' - numeric part of the trial name
        %                'multipleArena' - boolean indicating if the trial tracking/raw data export contains multiple arenas
        %                'arena' - name of the arena, or '!multiple!' if multiple arenas


    end


    methods (Abstract, Access = public)
        %% ALL SUBCLASSES MUST IMPLEMENT THE FOLLOWING METHODS

        % If your platform already has processed the data at some stage, simply skip the relevant functions and return null outputs;
        % but the function signatures must be defined in the subclass

        % For compatibility, it is strongly discouraged to use platform-specific named arguments in these methods
        % as the function would error out when called using arbitrary input name-value pairs from higher-level functions
        % Instead, specify a single 'Options' named argument that takes in a struct of the platform-specific name-value arguments
        % Then, parse the struct within the function as needed

        % Here is an example template for the methods to be implemented:
        % function result = exampleMethod(obj, input1, input2, kvargs)
        %     arguments
        %         obj (1,1) ui.trackingPlatforms.platforms.YourPlatformName
        %         input1
        %         input2
        %
        %         % Instead of specifying multiple name-value pairs, collect them into a single struct and pass in as 'Options' for cross-compatibility
        %         kvargs.Options (1,1) struct = struct();
        %     end
        %
        %     % You can set your defaults Options here
        %     defaultOptions = struct( ...
        %         'Option1', value1,
        %         'Option2', value2,
        %         ...
        %     );
        %     % Update default options with user-provided options
        %     for field = fieldnames(kvargs.Options)'
        %         defaultOptions.(field{1}) = kvargs.Options.(field{1});
        %     end
        %     kvargs.Options = defaultOptions;
        %
        %     % Your implementation here
        %
        %     result = []; % Replace with actual output
        % end
        %
        % Of course, as long as the Options named argument is defined as a struct (to match the generic type),
        % you can create your own validators and parsing logic as needed

        % When implementing these methods, note that the GUI will always call with the following base options:
        %   - 'MetadataTable': the master metadata table selected in the GUI, loaded via io.metadata.loadMetadataTable
        %       Note that the MetadataTable may be empty if no metadata file is loaded in the GUI, so handle this properly
        %   - ...add more here




        [varargout] = loadConfig(varargin, Options);
        %%LOADCONFIG Load user-defined configuration for the tracking platform from the global config YAML file or already loaded config struct
        % Load your platform-specific configurations, if any, from the general user config.yml file
        % The platform specific config is expected to be under tracking_providers.<PlatformName> in the config struct
        % The config typically defines the user's setup (units, arena size, etc.) and tracking parameters
        % At the same time!! Save the original CONFIG_ROOT from the original config struct/YAML in case the config file needs to be referenced later!
        % Keep values in config.defaults, override the fields if equilvalent ones are defined in tracking_providers.<PlatformName> in the config struct/YAML file
        % Any other root level fields in the config YAML are preserved and returned, wrapped in their original struct form, e.g., configs.preferences, configs.arena_grid

        % If there are obj.Props related to the config, they should be set here as well, immediately after loading the config





        [varargout] = preprocess(varargin, Options);
        %%PREPROCESS Pre-process raw data files for your platform
        % A function to pre-process the raw data files for your platform
        % This can include converting video formats, splitting multiple-arenas/subjects, extracting frames, etc.
        % Output a mapping to show what raw data files were processed into what output files, e.g., an 'updates' struct array with fields:
        %   'data' - tracking/trial metadata related file
        %       + 'original' - (scalar) - original raw data file path
        %       + 'processed' - (1xN) cell array of processed data file paths
        %   'media' - media files
        %       + 'original' - (scalar) - original raw media file path
        %       + 'processed' - (1xN) cell array of processed media file paths
        %
        % If there is no pre-processing needed/implemented for a platform, return an empty {} cell with warning notice logged to console and ui message box



        [header, data, units, stimulusFrameRange, animalMetadata, stimuli] = alignTrackingToStim(obj, trackingDataFilePath, stimuliDir, Options);
        %%ALIGNTRACKINGTOSTIM Align tracking data to stimulus events for analysis
        %   The initial contract preserves the six outputs of the legacy
        %   EthoVision alignment function. Options must contain at least
        %   MasterMetadataTable and Config.



        [status, varargout] = runTracking(varargin, Options);
        %%RUNTRACKING Run the subject tracking for your platform
        % The main tracking function, typically takes in some folder/video file paths and config options,
        % then returns tracking results as a path to an output folder or data structure



        [header, data, varargout] = loadTrackingData(obj, trackingDataFilePath, varargin, Options);
        %%LOADTRACKINGDATA Load the full / raw tracking data from a file or folder for your platform
        % Load tracking data from a file or folder, perhaps given some configs
        % The first output must be a metadata/header string-string dictionary that describes the data and/or associated files
        %   - To speed up the pre-loading of tracking data, implement a 'HeaderOnly' name-value argument that only returns the header info
        % The second output must be the actual tracking data table
        %   - The table must at least contains: 'Time' (in seconds), 'X', 'Y' (center points, in the specified coordsUnit)



        [timestampSec, coords, metadata, varargout] = loadTrackingCoordsPixels(obj, trackingDataFilePath, varargin, Options);
        %%LOADTRACKINGCOORDSPIXELS Load the tracking coordinates in pixel units from a file or folder for your platform
        % This is a proxy over loadTrackingData, but will returns the data in a more standardized format:
        %   - timestampSec: (Nx1) double array of timestamps in seconds
        %   - coords: (Nx2xM) double matrix of X,Y coordinates in pixels for each N timepoint and M bodyparts
        %       If there is only one bodypart tracked, M=1, MATLAB should be be able to handle (Nx2) the same way as (Nx2x1)
        %   - metadata: a struct containing any additional metadata about the tracking data. The following fields are REQUIRED, though extras can be added:
        %       'FPS' - frames per second of the tracking data, typically, either the mean diff of timestampSec or derived from the raw video file and/or header info
        %       'px2cmFactor' - conversion factor from pixels to centimeters, if available, otherwise NaN. This is strongly recommended.
        %       'bodyparts' - a cell array of strings/char arrays indicating the names of the tracked bodyparts, e.g., {'Center', 'Nose', 'TailBase'}, etc.
        %           The order of bodyparts must match the 3rd dimension of the coords output
        %           If only one bodypart is tracked, typically it is {'Center'} or similar
        %       'colors' - an (Mx3) numeric array of RGB colors (0-1) for each bodypart for visualization purposes
        %           If your platform does not have specific colors generated, simply assign using the default colors = colororder; and repeat/truncate as needed to match M bodyparts


        rawVideoPath = mediaPathFromTrackingData(obj, trackingDataFilePath, Options);
        %%MEDIAPATHFROMTRACKINGDATA
        % A way to get the original raw video path from the processed tracking data file


    end

end


%% OTHER HELPER FUNCTIONS

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