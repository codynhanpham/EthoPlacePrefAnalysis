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

        coordsUnit (1,1) double % Unit of the tracked coordinates, e.g., 'pixels', 'cm', etc.
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
    end

    methods
        function obj = TrackingProvider()
            %TRACKINGPROVIDER Construct an instance of this class
            %   In this abstract, initialize common properties as needed

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
        % If there are obj.Props related to the config, they should be set here as well, immediately after loading the config





        [varargout] = preprocess(varargin, Options);
        %%PREPROCESS Pre-process raw data files for your platform
        % A function to pre-process the raw data files for your platform
        % This can include converting video formats, splitting multiple-arenas/subjects, extracting frames, etc.



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