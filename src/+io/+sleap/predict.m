function [status, elapsedTime, outputDestination] = predict(videoFiles, modelPaths, kvargs)
    %%PREDICT Run SLEAP-NN prediction on specified video files.
    %
    % Inputs:
    %   videoFiles - Cell array of paths to video files to process.
    %   modelPaths - Cell array of paths to SLEAP model files, if empty, kvargs.SleapUserConfig.model_paths will be used and required.
    %
    % Optional Name-Value Pair Arguments:
    %   'SleapUserConfig' - Struct containing user configuration options for SLEAP, this will modify the run-time behavior of SLEAP-NN. Default is an empty struct.
    %   'Workers' - Number of videos to process in parallel, each in its own `sleap-nn predict` OS process. Default is 1.
    %       Resolution order: an explicit 'Workers' value greater than 1 takes precedence; otherwise SleapUserConfig.workers is used when the field exists and is non-empty; otherwise 1.
    %       The resolved value is clamped to the number of input videos. This is an app-side option and is never passed to the sleap-nn CLI.
    %       GPU memory usage scales roughly with workers x batch_size, so consider lowering batch_size when raising workers.
    %   'ProgressDialogHandle' - Handle to a MATLAB uiprogressdlg object for displaying progress. Default is empty.
    %   'UpdateCallbackFcn' - Additional callback function to be called during the execution of SLEAP-NN. Default is an empty function handle. This function must accept TWO input arguments: the index of the video in videoFiles, and a text string that is one stdout line from the corresponding `sleap-nn predict` process. (Breaking change from the previous single-argument contract.)
    %
    %   Failure policy: with Workers == 1, processing stops at the first failed video (fail-fast, previous behavior). With Workers > 1, all videos are attempted (finish-all); status is false if any video failed, and a summary warning listing the failures is issued at the end.
    %
    %   Cancellation: press Ctrl+C in the MATLAB Command Window or close the progress dialog to abort; all running sleap-nn process trees (including the python grandchildren that hold the GPU) are killed as soon as possible. Videos in flight may leave incomplete .predictions.slp files; re-run them to regenerate. status is false when a run is canceled.
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
        modelPaths (1,:) {mustBeText} = {}
        kvargs.SleapUserConfig (1,1) struct = struct()
        kvargs.Workers (1,1) double {mustBeInteger, mustBePositive} = 1
        kvargs.ProgressDialogHandle {mustBeProgressDialogHandleOrEmpty} = []
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin) []
    end

    [isAvailable, ~] = io.sleap.available();
    if ~isAvailable
        error('io:sleap:runSLEAP:Unavailable', ...
            'SLEAP is not available. Please install it with io.sleap.install() first.');
    end

    modelPaths = cellstr(modelPaths);

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
    workers = io.sleap.resolveWorkers(kvargs.Workers, kvargs.SleapUserConfig, numel(videoFiles));
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

    % A dialog that was closed mid-run counts as a cancel request. The Cancel
    % button is intentionally NOT enabled: its CancelRequested state does not
    % sync reliably while the engine is busy, so Ctrl+C or closing the dialog
    % are the supported abort paths.
    isCancelRequested = @() ~isempty(prgdlg) && (~isvalid(prgdlg) || prgdlg.CancelRequested);

    % Scan over all video files and count the total number of frames, to estimate the total time for processing.
    % FFprobe scan is preferred as it is significantly faster than native VideoReader
    nFrames = NaN(1, numel(videoFiles));
    nFramesTotalEstimate = 0;
    hasFFmpeg = ~isempty(matlab.metadata.Namespace.fromName('ffmpeg'));
    for i = 1:numel(videoFiles)
        if isCancelRequested()
            warning('io:sleap:runSLEAP:Canceled', ...
                'SLEAP processing canceled by user during the metadata scan; no videos were processed.');
            status = false;
            elapsedTime = 0;
            return;
        end
        drawnow; % full drawnow: 'limitrate' can skip event processing, leaving Cancel dead
        try
            if hasFFmpeg
                nFrames(i) = countFramesWithFFmpeg(videoFiles{i});
            else
                v = VideoReader(videoFiles{i});
                nFrames(i) = v.NumFrames;
            end
        catch MEFFmpeg
            if hasFFmpeg
                % A failed FFmpeg probe indicates it is not usable for this scan.
                % Fall back for the current file and avoid retrying it for later files.
                hasFFmpeg = false;
                try
                    v = VideoReader(videoFiles{i});
                    nFrames(i) = v.NumFrames;
                catch MEVideoReader
                    warning('io:sleap:runSLEAP:VideoReadError', ...
                        'Could not read video file "%s" with FFmpeg (%s) or VideoReader (%s).\n\nFull reports:\nFFmpeg: %s\n\nVideoReader: %s', ...
                        videoFiles{i}, MEFFmpeg.message, MEVideoReader.message, getReport(MEFFmpeg), getReport(MEVideoReader));
                end
            else
                warning('io:sleap:runSLEAP:VideoReadError', ...
                    'Could not read video file "%s": %s\n\nFull reports:\n%s', videoFiles{i}, MEFFmpeg.message, getReport(MEFFmpeg));
            end
        end
        if ~isnan(nFrames(i))
            nFramesTotalEstimate = nFramesTotalEstimate + nFrames(i);
        end
    end

    % Switch from metadata-query status to processing status once estimates are ready.
    if ~isempty(prgdlg) && isvalid(prgdlg)
        prgdlg.Indeterminate = nFramesTotalEstimate <= 0;
        prgdlg.ShowPercentage = nFramesTotalEstimate > 0;
        prgdlg.Value = 0;
        if workers > 1
            prgdlg.Message = sprintf('Starting SLEAP processing for %d videos with %d workers...', numel(videoFiles), workers);
        else
            prgdlg.Message = sprintf('Starting SLEAP processing for %d videos...', numel(videoFiles));
        end
    end

    % For each video file, run sleap-nn predict.
    % Ensure output file is in the outputDestination folder, using the default naming convention of <video_basename>.predictions.slp
    % uv run sleap-nn predict -m <model_path> [-m <model_path>...] -i <video_file> -o <output_file> [ predefined args ] [ additional args from kvargs.SleapUserConfig.additional_args ]

    status = true;
    canceledByUser = false;
    elapsedTime = tic;
    if workers == 1
        % Sequential path: one video at a time, fail-fast on first error.
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
            [exitCode, stdout] = uv.run(cmd, Project=sleapdir, UpdateCallbackFcn=@updateOutput, ...
                CancelCheckFcn=isCancelRequested);
            if exitCode == -15
                % Canceled by user: the in-flight sleap-nn process tree was killed.
                status = false;
                canceledByUser = true;
                warning('io:sleap:runSLEAP:Canceled', ...
                    'SLEAP processing canceled by user during video %d of %d ("%s"). Its output may be incomplete.', ...
                    i, numel(videoFiles), videoFileName);
                break;
            end
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
    else
        % Parallel path: up to `workers` concurrent sleap-nn predict processes,
        % finish-all (every video is attempted even if some fail).
        nVideos = numel(videoFiles);
        poolCmds = cell(1, nVideos);
        videoFileNames = cell(1, nVideos);
        for i = 1:nVideos
            [~, videoBaseName, videoExtension] = fileparts(videoFiles{i});
            videoFileNames{i} = [videoBaseName videoExtension];
            outputFile = fullfile(outputDestination, [videoBaseName '.predictions.slp']);
            poolCmds{i} = buildPredictCommand(uvpath, modelPaths, videoFiles{i}, outputFile, confArgs);
        end

        poolProcessed = zeros(1, nVideos); % committed frame count per video
        poolRate = zeros(1, nVideos);      % latest reported FPS per video
        poolStarted = false(1, nVideos);   % video has produced any stdout
        poolDone = false(1, nVideos);      % process has exited
        poolHasActual = false(1, nVideos); % SLEAP's own n_total has replaced the estimate

        [poolExitCodes, poolStdouts] = uv.runMany(poolCmds, Project=sleapdir, Workers=workers, ...
            LineCallbackFcn=@onPoolLine, ProcessDoneFcn=@onPoolDone, ...
            CancelCheckFcn=isCancelRequested);

        poolCanceled = poolExitCodes == -15;
        poolFailed = poolExitCodes ~= 0 & ~poolCanceled;
        canceledByUser = any(poolCanceled);
        status = ~any(poolFailed) && ~canceledByUser;
        if canceledByUser
            warning('io:sleap:runSLEAP:Canceled', ...
                'SLEAP processing canceled by user. %d of %d videos completed. In-flight videos were killed and may have incomplete outputs: %s', ...
                nnz(poolExitCodes == 0), nVideos, strjoin(videoFileNames(poolCanceled & poolStarted), ', '));
        end
        if any(poolFailed)
            failIdx = find(poolFailed);
            failReport = '';
            for k = failIdx
                failReport = [failReport, sprintf('  - "%s" (exit code %d):\n%s\n', ...
                    videoFiles{k}, poolExitCodes(k), indentText(getStdoutTail(poolStdouts(k), 20), '    '))]; %#ok<AGROW>
            end
            warning('io:sleap:runSLEAP:VideoProcessError', ...
                'SLEAP processing failed for %d of %d videos:\n%s', numel(failIdx), nVideos, failReport);
        end
    end
    elapsedTime = toc(elapsedTime);

    if ~isempty(prgdlg) && isvalid(prgdlg)
        if canceledByUser
            prgdlg.Message = sprintf('SLEAP processing canceled by user after %.2f seconds.', elapsedTime);
        else
            prgdlg.Message = sprintf('SLEAP processing completed in %.2f seconds.\n\nFinalizing....', elapsedTime);
        end
    end


    function updateOutput(line)
        lineText = char(string(line));
        [isProgressUpdate, progress] = parseSleapProgressLine(lineText);

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
        kvargs.UpdateCallbackFcn(i, line);
    end

    function onPoolLine(idx, line)
        %ONPOOLLINE Handle one stdout line from a pooled sleap-nn process (parallel path).
        lineText = char(string(line));
        poolStarted(idx) = true;
        [isProgressUpdate, progress] = parseSleapProgressLine(lineText);
        if isProgressUpdate
            % The first JSON update from a video contains SLEAP's actual frame
            % count. Replace the metadata-scan estimate so the job-wide progress
            % is based on the same totals as SLEAP.
            if ~poolHasActual(idx)
                poolHasActual(idx) = true;
                if ~isnan(nFrames(idx))
                    nFramesTotalEstimate = nFramesTotalEstimate - nFrames(idx);
                end
                nFrames(idx) = progress.n_total;
                nFramesTotalEstimate = nFramesTotalEstimate + nFrames(idx);
            end

            poolProcessed(idx) = progress.n_processed;
            poolRate(idx) = progress.rate;
            updatePoolDialog();
        end
        % Plain (non-JSON) lines are forwarded to the caller only: echoing
        % interleaved lines from multiple videos into the dialog would be noise.
        kvargs.UpdateCallbackFcn(idx, line);
    end

    function onPoolDone(idx, exitCode)
        %ONPOOLDONE Handle exit of a pooled sleap-nn process (parallel path).
        poolDone(idx) = true;
        poolRate(idx) = 0;
        % Commit the final frame count for this video, unless it was canceled
        % mid-flight (-15). If JSON progress was not emitted, this still lets
        % aggregate progress settle correctly.
        if exitCode ~= -15 && ~isnan(nFrames(idx))
            poolProcessed(idx) = nFrames(idx);
        end
        updatePoolDialog();
    end

    function updatePoolDialog()
        %UPDATEPOOLDIALOG Refresh aggregate progress for the parallel path.
        if isempty(prgdlg) || ~isvalid(prgdlg)
            return;
        end
        if nFramesTotalEstimate > 0
            prgdlg.Indeterminate = false;
            prgdlg.Value = min(max(sum(poolProcessed) / nFramesTotalEstimate, 0), 1);
        else
            prgdlg.Indeterminate = true;
        end

        activeIdx = find(poolStarted & ~poolDone);
        totalRate = sum(poolRate(activeIdx));
        remainingFrames = 0;
        for k = 1:nVideos
            if ~poolDone(k) && ~isnan(nFrames(k))
                remainingFrames = remainingFrames + max(nFrames(k) - poolProcessed(k), 0);
            end
        end
        if totalRate > 0
            etaText = sprintf('%.0fs', remainingFrames / totalRate);
        else
            etaText = 'estimating...';
        end

        msgLines = {sprintf('%d of %d videos done  |  %.1f FPS  |  Job ETA %s', ...
            nnz(poolDone), nVideos, totalRate, etaText)};
        maxShown = 6;
        shownIdx = activeIdx(1:min(maxShown, numel(activeIdx)));
        nShown = numel(shownIdx);
        % The [j] prefix is a visual worker label only; it does not
        % correspond to any underlying pool slot or process index. Labels are
        % right-aligned so the brackets line up (e.g. ' [9]' sits above '[10]').
        labelWidth = strlength(string(nShown)) + 2; % digits + the two brackets
        for j = 1:nShown
            k = shownIdx(j);
            % Pad with U+2007 FIGURE SPACE (digit-width) so the labels align
            % even in the dialog's proportional font (uiprogressdlg does not
            % render HTML and offers no monospace option).
            paddedLabel = strrep(sprintf('%*s', labelWidth, sprintf('[%d]', j)), ' ', char(8199));
            if ~isnan(nFrames(k)) && nFrames(k) > 0
                msgLines{end+1} = sprintf('%s %s - %.0f%%  |  %.1f FPS', ...
                    paddedLabel, videoFileNames{k}, 100 * poolProcessed(k) / nFrames(k), poolRate(k)); %#ok<AGROW>
            else
                msgLines{end+1} = sprintf('%s %s - starting...', paddedLabel, videoFileNames{k}); %#ok<AGROW>
            end
        end
        if numel(activeIdx) > maxShown
            msgLines{end+1} = sprintf('... and %d more', numel(activeIdx) - maxShown);
        end
        prgdlg.Message = strjoin(msgLines, newline);
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

function nFrames = countFramesWithFFmpeg(videoFile)
    %COUNTFRAMESWITHFFMPEG Count video frames using FFprobe metadata.
    args = sprintf('-v error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "%s"', ...
        strrep(videoFile, '"', '\\"'));
    [~, output] = ffprobe.run(args, 'Echo', false);
    nFrames = str2double(strtrim(output));
    if isnan(nFrames) || nFrames < 0
        error('io:sleap:runSLEAP:FFmpegFrameCountError', ...
            'FFprobe did not return a valid frame count for video file "%s".', videoFile);
    end
end

function [isProgress, progress] = parseSleapProgressLine(lineText)
    %PARSESLEAPPROGRESSLINE Validate and decode one SLEAP-NN JSON progress line.
    %   Returns isProgress = false and progress = [] for any line that is not a
    %   well-formed SLEAP JSON progress update.

    isProgress = false;
    progress = [];
    try
        decoded = jsondecode(strtrim(lineText));
        isProgress = isstruct(decoded) && isscalar(decoded) && ...
            all(isfield(decoded, {'n_processed', 'n_total', 'rate', 'eta'}));
        if isProgress
            progressValues = [decoded.n_processed, decoded.n_total, ...
                decoded.rate, decoded.eta];
            isProgress = isnumeric(progressValues) && ...
                isscalar(decoded.n_processed) && isscalar(decoded.n_total) && ...
                isscalar(decoded.rate) && isscalar(decoded.eta) && ...
                all(~isnan(progressValues) & ~isinf(progressValues)) && ...
                decoded.n_processed >= 0 && decoded.n_total > 0 && decoded.rate >= 0;
        end
        if isProgress
            progress = decoded;
        end
    catch
        isProgress = false;
    end
end

function tail = getStdoutTail(stdoutText, maxLines)
    %GETSTDOUTTAIL Return the last maxLines lines of a captured stdout string.
    lines = strsplit(char(stdoutText), '\n', 'CollapseDelimiters', false);
    if numel(lines) > maxLines
        lines = lines(end - maxLines + 1:end);
    end
    tail = strjoin(lines, '\n');
end

function out = indentText(txt, prefix)
    %INDENTTEXT Prefix every line of txt with prefix.
    lines = strsplit(char(txt), '\n', 'CollapseDelimiters', false);
    lines = strcat(prefix, lines);
    out = strjoin(lines, '\n');
end