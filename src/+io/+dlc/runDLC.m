function [status, elapsedTime, outputDestination] = runDLC(dlcConfig, videoFiles, videoType, kvargs)
    %%RUNDLC Run DeepLabCut on specified video files with given configuration
    %
    %   [status, elapsedTime] = io.dlc.runDLC(dlcConfig, videoFiles, videoType, kvargs)
    %
    %   Inputs:
    %       dlcConfig (char): Path to the DLC config file
    %       videoFiles (cell array of char): List of video file paths to process
    %       videoType (char): Type of videos (e.g., 'mp4', 'avi')
    %
    %   Name-Value Pair Arguments (kvargs):
    %       'CSV' (logical): Whether to save output as CSV (default: true). You should always set this to TRUE to ensure compatibility with downstream analysis.
    %       'CreateLabeledVideo' (logical): Whether to create labeled videos with detected keypoints (default: false)
    %       'UpdateCallbackFcn' (function handle): Callback function to run when progress updates occur (default: none)
    %           A single input argument is passed when the callback is invoked: the newest stdout line from the system (DLC) process
    %           Example: @(line) disp(line)
    %           If not provided, the callback is @(varargin) [], i.e., does nothing.
    %
    %   Outputs:
    %       status (logical): true if processing was successful
    %       elapsedTime (double): Time taken to process the videos
    %       outputDestination (char): Path to the output destination folder
    %           The output destination is fullfile(fileparts(videoFiles{1}), 'dlc'), i.e. a 'dlc' subfolder next to the first video file.

    arguments
        dlcConfig {mustBeFile}
        videoFiles (1,:) {mustBeFile}
        videoType {mustBeTextScalar}
        % destinationFolder {validator.mustBeValidFolderpath}

        kvargs.CSV (1,1) logical = true
        kvargs.CreateLabeledVideo (1,1) logical = false
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end

    % Persistent state of DLC availability and binary path
    persistent isDLCAvailable dlcBinaryPath
    if isempty(isDLCAvailable) || isempty(dlcBinaryPath) || ~isDLCAvailable
        [isDLCAvailable, dlcBinaryPath] = io.dlc.available();
    end

    if ~isDLCAvailable
        error('DLC toolbox is not available. Please ensure it is installed correctly.');
    end

    videoFiles = cellstr(videoFiles);
    % Ensure quoting of video file paths
    quotedVideoFiles = cellfun(@(f) sprintf('"%s"', f), videoFiles, 'UniformOutput', false);
    videoFilesStr = strjoin(quotedVideoFiles, ' ');

    % Define output destination folder based on first video file
    outputDestination = fullfile(fileparts(videoFiles{1}), 'dlc');

    cmd = sprintf('"%s" inference --config "%s" --videofile %s --videotype "%s" --destfolder "%s"', dlcBinaryPath, dlcConfig, videoFilesStr, videoType, outputDestination);
    if kvargs.CSV
        cmd = sprintf('%s --csv', cmd);
    end
    if kvargs.CreateLabeledVideo
        cmd = sprintf('%s --create_labeled_video', cmd);
    end
    
    startTime = tic;
    [exitCode] = io.dlc.system.execute(cmd, kvargs.UpdateCallbackFcn);
    elapsedTime = toc(startTime);
    
    status = (exitCode == 0);
    
    if exitCode ~= 0
        error('io:dlc:runDLC:ExecutionFailed', 'DeepLabCut execution failed with exit code %d (elapsed time: %.2f seconds)', exitCode, elapsedTime);
    end
end