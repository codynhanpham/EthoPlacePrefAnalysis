function [status, cmdout] = run(args, kvargs)
    %%RUN Run ffmpeg command with specified arguments
    % Note that this function automatically prepends '-y' to the arguments to skip confirmation prompts.
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
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin)[]
    end

    [s,bin] = ffmpeg.available();
    if ~s
        error('FFmpeg is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/+ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    args = string(args);
    cmd = sprintf('"%s" -y %s', bin, args);

    cmdout = '';
    
    function ffmpegProgressUpdate(line, echo)
        if echo
            fprintf('[%s] %s\n', string(datetime('now'), 'HH:mm:ss'), line);
        end
        
        % Append line to cmdout with newline
        cmdout = [cmdout, line, newline];
        
        kvargs.UpdateCallbackFcn(line);
    end

    if kvargs.Echo
        stdoutCallback = @(line) ffmpegProgressUpdate(line, true);
    else
        stdoutCallback = @(line) ffmpegProgressUpdate(line, false);
    end

    [status] = utils.executeSystemCommandRealTime(cmd, stdoutCallback);
    

    if status ~= 0
        error('ffmpeg:horzSplit:ExecutionFailed', 'FFmpeg horzSplit execution failed with exit code %d', status);
    end
end