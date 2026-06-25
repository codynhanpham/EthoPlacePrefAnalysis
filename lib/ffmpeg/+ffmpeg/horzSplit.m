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
        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = [];
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
        error('FFmpeg is not available on the system. Either install FFmpeg system-wide, or place the binaries in the ffmpeg/bin/ folder. https://ffmpeg.org/download.html');
    end

    input = string(input);
    outputLeft = string(outputLeft);
    outputRight = string(outputRight);

    % NOTE: do NOT include any -hwaccel flag here; ffmpeg.utils.executeFFmpeg
    % injects the appropriate one (cuda or auto) based on per-command state.
    args = sprintf("-y -i ""%s"" -filter_complex ""[0]crop=iw/2:ih:0:0[left];[0]crop=iw/2:ih:ow:0[right]"" -map ""[left]"" ""%s"" -map ""[right]"" ""%s""", input, outputLeft, outputRight);

    [status, cmdout] = ffmpeg.utils.executeFFmpeg(bin, args, ...
        'CudaArgs', '-hwaccel cuda', ...
        'Echo', kvargs.Echo, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);

    if status ~= 0
        error('ffmpeg:horzSplit:ExecutionFailed', 'FFmpeg horzSplit execution failed with exit code %d', status);
    end
end