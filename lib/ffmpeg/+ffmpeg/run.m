function [status, cmdout] = run(args, kvargs)
    %%RUN Run ffmpeg command with specified arguments
    %
    %  [status, cmdout] = run(args)
    %
    % Input:
    %   args - string or char array of ffmpeg command-line arguments (excluding 'ffmpeg' itself)
    %
    % Name-Value Pair Arguments:
    %   'Echo' (logical): whether to echo ffmpeg command output to command window (default: false)
    %   'UpdateCallbackFcn' (function handle): callback function to run when progress updates occur (default: none)
    %
    % Output:
    %   status - status of the ffmpeg command (0 if successful)
    %   cmdout - command output from ffmpeg
    %
    % Example:
    %   [status, cmdout] = ffmpeg.run('-i input.mp4 -c:v libx264 output.mp4', 'Echo', true);
    %
    % See also: ffmpeg.available, ffmpeg.horzSplit, ffmpeg.vertSplit

    arguments
        args {mustBeText}
        kvargs.Echo (1,1) logical = false
        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = []
    end

    [s,bin] = ffmpeg.available();
    if ~s
        error('FFmpeg is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    % Keep the shim alive through the direct execution path. The helper also
    % protects executeFFmpeg and its CUDA fallback process launches.
    libraryPathCleanup = ffmpeg.utils.clearLinuxLibraryPath(); %#ok<NASGU>
    cleanup = onCleanup(@() clear('libraryPathCleanup'));

    args = string(args);
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

    % If the caller already specified a -hwaccel flag, respect it as-is and
    % do not inject cuda/auto logic (the user is taking explicit control).
    if contains(args, "-hwaccel", 'IgnoreCase', true)
        cmd = sprintf('"%s" %s', bin, args);
        if kvargs.Echo
            stdoutCallback = @(line) onLine(line, true);
        else
            stdoutCallback = @(line) onLine(line, false);
        end
        status = ffmpeg.utils.executeSystemCommandRealTime(cmd, stdoutCallback);
    else
        % No explicit hwaccel: let executeFFmpeg handle cuda/auto with
        % per-command fallback. Use 'run' as the commandKey.
        [status, cmdout] = ffmpeg.utils.executeFFmpeg(bin, args, ...
            'Echo', kvargs.Echo, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);
    end

    if status ~= 0
        error('ffmpeg:run:ExecutionFailed', 'FFmpeg run(_) execution failed with exit code %d', status);
    end
end