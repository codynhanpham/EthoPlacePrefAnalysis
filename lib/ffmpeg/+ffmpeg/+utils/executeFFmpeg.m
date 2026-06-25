function [status, cmdout] = executeFFmpeg(bin, args, kvargs)
    %%EXECUTEFFMPEG Run an ffmpeg command with automatic CUDA fallback.
    %
    %   [status, cmdout] = ffmpeg.utils.executeFFmpeg(bin, args)
    %
    %   Builds and executes an ffmpeg command. If CUDA is considered
    %   usable (per ffmpeg.utils.canRunWithCuda, a single global state
    %   shared across all ffmpeg commands), the command is first attempted
    %   with the CUDA hwaccel flags (see CudaArgs) injected before the
    %   user-supplied args. On failure, a warning is issued, the global
    %   CUDA state is flipped to false, and the command is retried with
    %   the default -hwaccel auto path.
    %
    %   If CUDA is already known to be unusable, the command runs directly
    %   with -hwaccel auto (no retry overhead).
    %
    % Inputs:
    %   bin  - (string) path to the ffmpeg binary
    %   args - (string) ffmpeg arguments WITHOUT any -hwaccel flag.
    %          This function injects the appropriate hwaccel flags.
    %
    % Name-Value Pair Arguments:
    %   'CudaArgs'           (string): CUDA hwaccel flags to inject when
    %                       attempting the CUDA path. Default:
    %                       '-hwaccel cuda -hwaccel_output_format cuda'.
    %                       Use '-hwaccel cuda' (without output_format) when
    %                       the filter chain needs CPU-format frames (e.g.
    %                       crop/scale filters that lack CUDA equivalents).
    %   'Echo'              (logical): echo ffmpeg output to command window
    %   'UpdateCallbackFcn' (function_handle): progress callback
    %
    % Outputs:
    %   status - (numeric) ffmpeg exit code (0 on success)
    %   cmdout - (char) captured ffmpeg stdout
    %
    % See also: ffmpeg.utils.canRunWithCuda, ffmpeg.utils.executeSystemCommandRealTime

    arguments
        bin {mustBeTextScalar}
        args {mustBeTextScalar}
        kvargs.CudaArgs {mustBeTextScalar} = "-hwaccel cuda -hwaccel_output_format cuda"
        kvargs.Echo (1,1) logical = false
        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = []
    end

    bin = string(bin);
    args = string(args);
    cudaArgs = string(kvargs.CudaArgs);

    % Decide whether to attempt CUDA based on the global cache.
    useCuda = ffmpeg.utils.canRunWithCuda();

    if useCuda
        fullCudaArgs = cudaArgs + " " + args;
        cmd = sprintf('"%s" %s', bin, fullCudaArgs);

        [status, cmdout] = runOnce(cmd, kvargs);

        if status == 0
            % Confirmed: ffmpeg runs fine with CUDA.
            ffmpeg.utils.canRunWithCuda(true);
            return
        end

        % CUDA attempt failed. Mark ffmpeg as CUDA-incompatible globally so
        % future calls skip straight to the auto path, then warn and retry.
        ffmpeg.utils.canRunWithCuda(false);
        warning('ffmpeg:cuda:Fallback', ...
            ['FFmpeg command failed with CUDA hardware acceleration (exit code %d). ' ...
             'Falling back to -hwaccel auto. Subsequent calls will use auto directly.'], ...
            status);
    end

    % Default / fallback path: -hwaccel auto
    autoArgs = "-hwaccel auto " + args;
    cmd = sprintf('"%s" %s', bin, autoArgs);
    [status, cmdout] = runOnce(cmd, kvargs);
end


function [status, cmdout] = runOnce(cmd, kvargs)
    %RUNONCE Execute a single ffmpeg command and capture output.
    cmdout = '';

    function onLine(line, echo)
        if echo
            fprintf('[%s] %s\n', string(datetime('now'), 'HH:mm:ss'), line);
        end
        cmdout = [cmdout, line, newline];
        if ~isempty(kvargs.UpdateCallbackFcn)
            kvargs.UpdateCallbackFcn(line);
        end
    end

    if kvargs.Echo
        stdoutCallback = @(line) onLine(line, true);
    else
        stdoutCallback = @(line) onLine(line, false);
    end

    status = ffmpeg.utils.executeSystemCommandRealTime(cmd, stdoutCallback);
end
