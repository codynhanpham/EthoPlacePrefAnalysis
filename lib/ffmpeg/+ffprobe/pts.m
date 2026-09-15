function [pts, timebase, startTime] = pts(inputFile, kvargs)
    %%PTS Extract presentation timestamps (PTS) of video frames using ffprobe
    %
    % pts = ffprobe.pts(inputFile)
    % [pts, timebase, startTime] = ffprobe.pts(inputFile)
    %
    % Input:
    %   inputFile - path to the input video file
    %
    % Output:
    %   pts - array of presentation timestamps (in timebase units) for each video frame
    %   timebase - timebase of the first video stream in seconds (e.g., 1/15360)
    %   startTime - start_time of the first video stream in seconds. PTS values
    %               are relative to this offset; consumers that need times in
    %               VideoReader's 0-based CFR domain should subtract it:
    %               tSeconds = pts * timebase - startTime.
    %
    % Example:
    %   [pts, timebase, startTime] = ffprobe.pts('input.mp4');
    %   frameTimestamps = double(pts(:)) * double(timebase) - double(startTime);
    %
    % See also: ffprobe.available, ffprobe.run, ffprobe.timebase

    arguments
        inputFile {mustBeText, mustBeFile(inputFile)}

        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = []
    end

    % Single ffprobe invocation returning both packet PTS values and the
    % stream-level start_time and time_base. Keeps the subprocess count and
    % runtime identical to the previous implementation (which made a second
    % call via ffprobe.timebase).
    args = sprintf('-v 0 -select_streams V:0 -show_entries packet=pts:stream=start_time,time_base -of default=noprint_wrappers=1:nokey=1 "%s"', inputFile);
    [status, cmdout] = ffprobe.run(args, 'Echo', false, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);

    if status ~= 0
        error('ffprobe:pts:ExecutionFailed', 'FFprobe pts(_) execution failed with exit code %d', status);
    end

    % Parse output. ffprobe prints all packet pts lines first, then the
    % stream-level entries (time_base, start_time) at the end:
    %   1..N) packet pts values in timebase units (integers, or N/A)
    %   N+1)  stream time_base (e.g. "1/15360")
    %   N+2)  stream start_time in seconds (e.g. "0.066667" or "N/A")
    % Scan from the end so stream lines are identified first. Whitespace
    % splitting is robust to \n vs \r\n line endings.
    textStr = regexprep(char(cmdout), '\r', '');
    rawLines = regexp(textStr, '\s+', 'split');
    rawLines = rawLines(~cellfun(@isempty, rawLines));

    timebase = [];
    startTime = 0;

    % Stream time_base line: rational "num/den" (search from the end)
    timebaseLineIdx = find(contains(rawLines, '/') & ~contains(rawLines, '.'), 1, 'last');
    if ~isempty(timebaseLineIdx)
        timebaseParts = strsplit(rawLines{timebaseLineIdx}, '/');
        numerator = str2double(timebaseParts{1});
        denominator = str2double(timebaseParts{2});
        if isfinite(numerator) && isfinite(denominator) && denominator ~= 0
            timebase = numerator / denominator;
        end
        rawLines(timebaseLineIdx) = [];
    end

    % Stream start_time line: last decimal number in seconds (may be "N/A").
    % Packet pts are integers in timebase units; start_time is in seconds and
    % always printed with a fractional part by ffprobe.
    startLineIdx = find(contains(rawLines, '.') & ~contains(rawLines, '/'), 1, 'last');
    if ~isempty(startLineIdx)
        startVal = str2double(rawLines{startLineIdx});
        if isfinite(startVal)
            startTime = startVal;
        end
        rawLines(startLineIdx) = [];
    end

    % Remaining lines are packet PTS values.
    pts = str2double(rawLines);

    % Filter out NaNs if any
    pts = pts(~isnan(pts));

    pts = sort(pts);  % Ensure sorted order

    % Fallback: if the combined invocation did not yield a timebase (older
    % ffprobe builds or unexpected output), fall back to the dedicated call.
    if isempty(timebase) || ~isfinite(timebase) || timebase <= 0
        timebase = ffprobe.timebase(inputFile);
    end
end