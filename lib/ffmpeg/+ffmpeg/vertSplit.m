function [status, cmdout] = vertSplit(input, outputTop, outputBottom, kvargs)
    %%VERTSPLIT Split video vertically into two videos: Top and Bottom
    %
    %  [status, cmdout] = vertSplit(input, outputTop, outputBottom)
    %
    % Input:
    %   input - input video file path
    %   outputTop - output video file path for top half
    %   outputBottom - output video file path for bottom half
    %
    % Name-Value Pair Arguments:
    %   'Overwrite' (logical): whether to overwrite existing files (default: false == no-op if files exist)
    %   'Echo' (logical): whether to echo ffmpeg command output to command window (default: false)
    %
    % Output:
    %   status - status of the ffmpeg command (0 if successful)
    %   cmdout - command output from ffmpeg
    %
    % See also: ffmpeg.horzSplit, ffmpeg.available
    
    arguments
        input {mustBeFile}
        outputTop {ffmpeg.validator.mustBeValidFilepath}
        outputBottom {ffmpeg.validator.mustBeValidFilepath}

        kvargs.Overwrite (1,1) logical = false
        kvargs.Echo (1,1) logical = false
        kvargs.UpdateCallbackFcn (1,1) function_handle = @(varargin)[];
    end

    if ~kvargs.Overwrite
        if isfile(outputTop) && isfile(outputBottom)
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
    outputTop = string(outputTop);
    outputBottom = string(outputBottom);
    args = sprintf("-y -hwaccel auto -i ""%s"" -filter_complex ""[0]crop=iw:ih/2:0:0[top];[0]crop=iw:ih/2:0:oh[bottom]"" -map ""[top]"" ""%s"" -map ""[bottom]"" ""%s""", input, outputTop, outputBottom);
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

    [status] = ffmpeg.utils.executeSystemCommandRealTime(cmd, stdoutCallback);
    

    if status ~= 0
        error('ffmpeg:horzSplit:ExecutionFailed', 'FFmpeg horzSplit execution failed with exit code %d', status);
    end
end