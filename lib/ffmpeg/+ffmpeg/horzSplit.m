function [status, cmdout] = horzSplit(input, outputLeft, outputRight, kvargs)
    %%HORZSPLIT Split video horizontally into two videos: Left and Right
    %
    %  [status, cmdout] = horzSplit(input, outputLeft, outputRight)
    %
    % Input:
    %   input - input video file path
    %   outputLeft - output video file path for left half
    %   outputRight - output video file path for right half
    %
    % Name-Value Pair Arguments:
    %   'Overwrite' (logical): whether to overwrite existing files (default: false == no-op if files exist)
    %   'Echo' (logical): whether to echo ffmpeg command output to command window (default: false)
    %
    % Output:
    %   status - status of the ffmpeg command (0 if successful)
    %   cmdout - command output from ffmpeg
    %
    % See also: ffmpeg.vertSplit, ffmpeg.available

    arguments
        input {mustBeFile}
        outputLeft {validator.mustBeValidFilepath}
        outputRight {validator.mustBeValidFilepath}

        kvargs.Overwrite (1,1) logical = false
        kvargs.Echo (1,1) logical = false
    end

    if ~kvargs.Overwrite
        if isfile(outputLeft) && isfile(outputRight)
            status = 0;
            cmdout = 'Output files already exist and Overwrite is false. No operation performed.';
            return
        end
    end

    [s,bin] = ffmpeg.available();
    if ~s
        error('FFmpeg is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/+ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    input = string(input);
    outputLeft = string(outputLeft);
    outputRight = string(outputRight);
    
    args = sprintf("-y -y -hwaccel auto -i ""%s"" -filter_complex ""[0]crop=iw/2:ih:0:0[left];[0]crop=iw/2:ih:ow:0[right]"" -map ""[left]"" ""%s"" -map ""[right]"" ""%s""", input, outputLeft, outputRight);
    cmd = sprintf('"%s" %s', bin, args);

    if kvargs.Echo
        fprintf("\n$ %s\n", cmd);
        [status, cmdout] = system(cmd, "-echo");
    else
        [status, cmdout] = system(cmd);
    end
    if status ~= 0
        error('Error splitting video: %s', cmdout);
    end
end