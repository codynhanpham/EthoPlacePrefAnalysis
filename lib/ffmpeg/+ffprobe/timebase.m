% ffprobe -v 0 -of compact=p=0:nk=1 -show_entries stream=time_base -select_streams v:0 -i input.mp4

function timebase = timebase(inputFile, kvargs)
    %%TIMEBASE Extract timebase of the first video stream using ffprobe
    %
    % timebase = ffprobe.timebase(inputFile)
    %
    % Input:
    %   inputFile - path to the input video file
    %
    % Output:
    %   timebase - timebase of the first video stream as a rational number (e.g., 1/30)
    %
    % Example:
    %   tb = ffprobe.timebase('input.mp4');
    %
    % See also: ffprobe.available, ffprobe.run

    arguments
        inputFile {mustBeText, mustBeFile(inputFile)}

        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = []
    end

    args = sprintf('-v 0 -of compact=p=0:nk=1 -show_entries stream=time_base -select_streams v:0 -i "%s"', inputFile);
    [status, cmdout] = ffprobe.run(args, 'Echo', false, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);

    if status ~= 0
        error('ffprobe:timebase:ExecutionFailed', 'FFprobe timebase(_) execution failed with exit code %d', status);
    end

    data = string(cmdout);
    timebaseStr = strtrim(data);
    % Split newline and only get the last line (in case of warnings)
    timebaseLines = strsplit(timebaseStr, newline);
    timebaseStr = timebaseLines{end};
    % Convert to numeric value
    timebaseParts = strsplit(timebaseStr, '/');
    numerator = str2double(timebaseParts{1});
    denominator = str2double(timebaseParts{2});
    timebase = numerator / denominator;
end