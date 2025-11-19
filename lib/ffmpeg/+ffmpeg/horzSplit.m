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
        outputLeft {ffmpeg.validator.mustBeValidFilepath}
        outputRight {ffmpeg.validator.mustBeValidFilepath}

        kvargs.Overwrite (1,1) logical = false
        kvargs.Echo (1,1) logical = false
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin)[];
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
    
    args = sprintf("-y -hwaccel auto -i ""%s"" -filter_complex ""[0]crop=iw/2:ih:0:0[left];[0]crop=iw/2:ih:ow:0[right]"" -map ""[left]"" ""%s"" -map ""[right]"" ""%s""", input, outputLeft, outputRight);
    cmd = sprintf('"%s" %s', bin, args);

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