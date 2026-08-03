function [status, elapsedTime, outputDestination] = predict(videoFiles, modelPaths, kvargs)
    %%PREDICT Run SLEAP-NN prediction on specified video files.
    %
    % Inputs:
    %   videoFiles - Cell array of paths to video files to process.
    %   modelPaths - Cell array of paths to SLEAP model files, if empty, kvargs.SleapUserConfig.model_paths will be used and required.
    %
    % Optional Name-Value Pair Arguments:
    %   'SleapUserConfig' - Struct containing user configuration options for SLEAP, this will modify the run-time behavior of SLEAP-NN. Default is an empty struct.
    %   'ProgressDialogHandle' - Handle to a MATLAB uiprogressdlg object for displaying progress. Default is empty.
    %   'UpdateCallbackFcn' - Additional callback function to be called during the execution of SLEAP-NN. Default is an empty function handle. This function must accept a single input argument, a text string, that is the stdout from the `sleap-nn predict` command for every progress update.
    %
    % Outputs:
    %   status (logical) - true if processing was successful
    %   elapsedTime (double): Time taken to process the videos
    %   outputDestination (char): Path to the output destination folder
    %       The output destination is fullfile(fileparts(videoFiles{1}), 'sleap'), i.e. a 'sleap' subfolder next to the first video file.
    %       File names will always be the video file basenames, with `.predictions.slp` appended to the end of the name.
    %       i.e `Trial 1.mp4` --> `Trial 1.predictions.slp`

    arguments
        videoFiles (1,:) {mustBeFile}
        modelPaths (1,:) cell = {}
        kvargs.SleapUserConfig (1,1) struct = struct()
        kvargs.ProgressDialogHandle (1,1) {mustBeProgressDialogHandleOrEmpty} = []
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end

    [isAvailable, ~] = io.sleap.available();
    if ~isAvailable
        error('io:sleap:runSLEAP:Unavailable', ...
            'SLEAP is not available. Please install it with io.sleap.install() first.');
    end

    % Ensure modelPaths or kvargs.SleapUserConfig.model_paths is provided, of modelPaths is empty, use kvargs.SleapUserConfig.model_paths
    % If both are provided, use modelPaths and ignore kvargs.SleapUserConfig.model_paths
    % Resolve the final modelPaths to use for the SLEAP-NN prediction
    if isempty(modelPaths)
        if isfield(kvargs.SleapUserConfig, 'model_paths') && ~isempty(kvargs.SleapUserConfig.model_paths)
            modelPaths = kvargs.SleapUserConfig.model_paths;
        else
            error('io:sleap:runSLEAP:MissingModelPaths', ...
                'No model paths provided. Please provide model paths as an input argument or in the SleapUserConfig struct.');
        end
        % Ensure that modelPaths is a list of valid directories
        for i = 1:length(modelPaths)
            if ~isfolder(modelPaths{i})
                error('io:sleap:runSLEAP:InvalidModelPath', ...
                    'Model path "%s" is not a valid directory.', modelPaths{i});
            end
        end
    end

    videoFiles = cellstr(videoFiles);
    outputDestination = fullfile(fileparts(videoFiles{1}), 'sleap');
    if ~isfolder(outputDestination)
        mkdir(outputDestination);
    end

    % Use the project-local uv executable returned by install().
    [uvpath, sleapdir] = io.sleap.install();

    confArgs = buildConfigArgs(kvargs.SleapUserConfig);

    % Initialize the dialog before querying metadata. VideoReader.NumFrames
    % can take a noticeable amount of time for a long list of videos.
    if ~isempty(kvargs.ProgressDialogHandle)
        prgdlg = kvargs.ProgressDialogHandle;
        prgdlg.Indeterminate = true;
        prgdlg.ShowPercentage = false;
        prgdlg.Message = sprintf('Querying metadata for %d videos...', numel(videoFiles));
        drawnow;
    else
        prgdlg = [];
    end

    % Scan over all video files and count the total number of frames, to estimate the total time for processing.
    nFrames = NaN(1, numel(videoFiles));
    nFramesTotalEstimate = 0;
    for i = 1:numel(videoFiles)
        try
            v = VideoReader(videoFiles{i});
            nFrames(i) = v.NumFrames;
            nFramesTotalEstimate = nFramesTotalEstimate + v.NumFrames;
        catch ME
            warning('io:sleap:runSLEAP:VideoReadError', ...
                'Could not read video file "%s": %s', videoFiles{i}, ME.message);
        end
    end

    % Switch from metadata-query status to processing status once estimates are ready.
    if ~isempty(prgdlg) && isvalid(prgdlg)
        prgdlg.Indeterminate = nFramesTotalEstimate <= 0;
        prgdlg.ShowPercentage = nFramesTotalEstimate > 0;
        prgdlg.Value = 0;
        prgdlg.Message = sprintf('Starting SLEAP processing for %d videos...', numel(videoFiles));
    end

    % For each video file, run sleap-nn predict.
    % Ensure output file is in the outputDestination folder, using the default naming convention of <video_basename>.predictions.slp
    % uv run sleap-nn predict -m <model_path> [-m <model_path>...] -i <video_file> -o <output_file> [ predefined args ] [ additional args from kvargs.SleapUserConfig.additional_args ]

    status = true;
    elapsedTime = tic;
    nProcessed = 0;
    nProcessedCurrentVideo = 0;
    currentProgressVideo = 0;
    videoFileName = '';
    for i = 1:numel(videoFiles)
        [~, videoBaseName, videoExtension] = fileparts(videoFiles{i});
        videoFileName = [videoBaseName videoExtension];
        outputFile = fullfile(outputDestination, [videoBaseName '.predictions.slp']);
        if ~isempty(prgdlg) && isvalid(prgdlg)
            prgdlg.Message = sprintf('Processing video %d of %d\n%s', ...
                i, numel(videoFiles), videoFileName);
        end
        cmd = buildPredictCommand(uvpath, modelPaths, videoFiles{i}, outputFile, confArgs);
        [exitCode, stdout] = uv.run(cmd, Project=sleapdir, UpdateCallbackFcn=@updateOutput);
        if exitCode ~= 0
            status = false;
            warning('io:sleap:runSLEAP:VideoProcessError', ...
                'SLEAP processing failed for video "%s" with exit code %d. See stdout for details:\n%s', ...
                videoFiles{i}, exitCode, stdout);
            break;
        end
        % Commit the final frame count for this video. If JSON progress was not
        % emitted, this still lets the next video's progress start correctly.
        if ~isnan(nFrames(i))
            nProcessed = nProcessed - nProcessedCurrentVideo + nFrames(i);
            nProcessedCurrentVideo = nFrames(i);
        end
    end
    elapsedTime = toc(elapsedTime);

    if ~isempty(prgdlg) && isvalid(prgdlg)
        prgdlg.Message = sprintf('SLEAP processing completed in %.2f seconds.\n\nFinalizing....', elapsedTime);
    end


    function updateOutput(line)
        lineText = char(string(line));
        try
            progress = jsondecode(strtrim(lineText));
            isProgressUpdate = isstruct(progress) && isscalar(progress) && ...
                all(isfield(progress, {'n_processed', 'n_total', 'rate', 'eta'}));
            if isProgressUpdate
                progressValues = [progress.n_processed, progress.n_total, ...
                    progress.rate, progress.eta];
                isProgressUpdate = isnumeric(progressValues) && ...
                    isscalar(progress.n_processed) && isscalar(progress.n_total) && ...
                    isscalar(progress.rate) && isscalar(progress.eta) && ...
                    all(~isnan(progressValues) & ~isinf(progressValues)) && ...
                    progress.n_processed >= 0 && progress.n_total > 0 && progress.rate >= 0;
            end
        catch
            isProgressUpdate = false;
        end

        if isProgressUpdate
            % SLEAP's n_processed is relative to the current video. Replace
            % the previous current-video value rather than adding each update.
            if currentProgressVideo ~= i
                currentProgressVideo = i;
                nProcessedCurrentVideo = 0;

                % The first JSON update contains SLEAP's actual frame count.
                % Replace the VideoReader estimate so the job-wide progress is
                % based on the same totals as SLEAP.
                if ~isnan(nFrames(i))
                    nFramesTotalEstimate = nFramesTotalEstimate - nFrames(i);
                end
                nFrames(i) = progress.n_total;
                nFramesTotalEstimate = nFramesTotalEstimate + nFrames(i);
            end

            nProcessed = nProcessed - nProcessedCurrentVideo + progress.n_processed;
            nProcessedCurrentVideo = progress.n_processed;

            if ~isempty(prgdlg) && isvalid(prgdlg)
                if nFramesTotalEstimate > 0
                    prgdlg.Indeterminate = false;
                    prgdlg.Value = min(max(nProcessed / nFramesTotalEstimate, 0), 1);
                end

                if progress.rate > 0
                    remainingFrames = max(nFramesTotalEstimate - nProcessed, 0);
                    jobEta = remainingFrames / progress.rate;
                else
                    jobEta = Inf;
                end
                progressText = sprintf('FPS=%.1f  |  Video ETA=%.1fs  |  Job ETA=%.1fs', ...
                    progress.rate, progress.eta, jobEta);
                prgdlg.Message = sprintf('Processing video %d of %d\n%s\n\n%s', ...
                    i, numel(videoFiles), videoFileName, progressText);
            end
        elseif ~isempty(prgdlg) && isvalid(prgdlg)
            % Print as plain text for non-JSON non-progress stdout lines.
            prgdlg.Message = sprintf('Processing video %d of %d\n%s\n\n%s', ...
                i, numel(videoFiles), videoFileName, lineText);
        end
        kvargs.UpdateCallbackFcn(line);
    end
end

function confArgs = buildConfigArgs(userConfig)
    %BUILDCONFIGARGS Convert SLEAP user configuration to CLI arguments.
    %   Predefined fields are emitted using SLEAP-NN's underscore options.
    %   additional_args is emitted after the predefined fields and supports
    %   logical flags, scalar values, strings, and cell-array values.

    confArgs = strings(0, 1);
    predefined = {
        'runtime',      '--runtime'
        'device',       '--device'
        'batch_size',   '--batch_size'
        'tracking',     '--tracking'
        'max_instances','--max_instances'
    };

    for i = 1:size(predefined, 1)
        name = predefined{i, 1};
        if ~isfield(userConfig, name) || isempty(userConfig.(name))
            continue;
        end
        confArgs = appendCliValue(confArgs, predefined{i, 2}, userConfig.(name));
    end

    if isfield(userConfig, 'additional_args') && ~isempty(userConfig.additional_args)
        additional = userConfig.additional_args;
        names = fieldnames(additional);
        for i = 1:numel(names)
            option = ['--' names{i}];
            confArgs = appendCliValue(confArgs, option, additional.(names{i}));
        end
    end

    confArgs = strjoin(confArgs, ' ');
end

function args = appendCliValue(args, option, value)
    if islogical(value)
        if value
            args(end+1, 1) = string(option);
        end
        return;
    end

    if iscell(value)
        for i = 1:numel(value)
            args = appendCliValue(args, option, value{i});
        end
        return;
    end

    if ~(isnumeric(value) || isstring(value) || ischar(value)) || ~isscalar(value)
        error('io:sleap:InvalidCliArgument', ...
            'CLI argument values must be logical, numeric, text, or cell arrays of these types.');
    end

    args(end+1, 1) = string(option);
    args(end+1, 1) = quoteCliArg(value);
end

function cmd = buildPredictCommand(~, modelPaths, inputVideo, outputFile, confArgs)
    %BUILDPREDICTCOMMAND Build the command portion accepted by uv.run().
    %   The first input is intentionally ignored: uv.run() prepends its own
    %   executable path. It remains in the interface to make the builder's
    %   inputs explicit and to allow future executable-selection logic.

    parts = ["sleap-nn", "predict" , "--gui"]; % Always use the --gui flag to get JSON progress output
    for i = 1:numel(modelPaths)
        parts(end+1:end+2) = ["-m", quoteCliArg(modelPaths{i})];
    end
    parts(end+1:end+2) = ["-i", quoteCliArg(inputVideo)];
    parts(end+1:end+2) = ["-o", quoteCliArg(outputFile)];
    if strlength(string(confArgs)) > 0
        parts(end+1) = string(confArgs);
    end
    cmd = char(strjoin(parts, ' '));
end

function value = quoteCliArg(value)
    value = char(string(value));
    value = strrep(value, '"', '\\"');
    value = ['"' value '"'];
end

function mustBeProgressDialogHandleOrEmpty(value)
    if isempty(value)
        return;
    end
    if ~isscalar(value) || ~isvalid(value) || ~isa(value, 'matlab.ui.dialog.ProgressDialog')
        error('Value must be a scalar valid matlab.ui.dialog.ProgressDialog handle or empty.');
    end    
end