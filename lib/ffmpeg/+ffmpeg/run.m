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
    end

    [s,bin] = ffmpeg.available();
    if ~s
        error('FFmpeg is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/+ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    args = string(args);
    cmd = sprintf('"%s" -y %s', bin, args);

    if kvargs.Echo
        fprintf("\n$ %s\n", cmd);
        [status, cmdout] = system(cmd, "-echo");
    else
        [status, cmdout] = system(cmd);
    end
    if status ~= 0
        error('Error running ffmpeg command: %s', cmdout);
    end

end