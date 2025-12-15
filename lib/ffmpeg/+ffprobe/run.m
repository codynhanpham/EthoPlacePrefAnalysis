function [status, cmdout] = run(args, kvargs)
    %%RUN Run ffprobe command with specified arguments
    %
    %  [status, cmdout] = run(args)
    %
    % Input:
    %   args - string or char array of ffprobe command-line arguments (excluding 'ffprobe' itself)
    %
    % Name-Value Pair Arguments:
    %   'Echo' (logical): whether to echo ffprobe command output to command window (default: false)
    %   'UpdateCallbackFcn' (function handle): callback function to run when progress updates occur (default: none)
    %
    % Output:
    %   status - status of the ffprobe command (0 if successful)
    %   cmdout - command output from ffprobe
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

    [s,bin] = ffprobe.available();
    if ~s
        error('FFprobe is not available on the system. Either install FFprobe system-wide (typically, it should be installed alongside FFmpeg), or place the binaries in the ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    args = string(args);
    cmd = sprintf('"%s" %s', bin, args);

    cmdout = '';
    
    function ffmpegProgressUpdate(line, echo)
        if echo
            fprintf('[%s] %s\n', string(datetime('now'), 'HH:mm:ss'), line);
        end
        
        % Append line to cmdout with newline
        cmdout = [cmdout, line, newline];
        if ~isempty(kvargs.UpdateCallbackFcn)
            kvargs.UpdateCallbackFcn(line);
        end
    end

    if kvargs.Echo
        stdoutCallback = @(line) ffmpegProgressUpdate(line, true);
    else
        stdoutCallback = @(line) ffmpegProgressUpdate(line, false);
    end

    [status] = ffmpeg.utils.executeSystemCommandRealTime(cmd, stdoutCallback);
    

    if status ~= 0
        error('ffprobe:run:ExecutionFailed', 'FFprobe run(_) execution failed with exit code %d.\n%s', status, cmdout);
    end
end