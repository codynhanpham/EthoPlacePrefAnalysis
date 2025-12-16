function [pts, timebase] = pts(inputFile, kvargs)
    %%PTS Extract presentation timestamps (PTS) of video frames using ffprobe
    %
    % pts = ffprobe.pts(inputFile)
    %
    % Input:
    %   inputFile - path to the input video file
    %
    % Output:
    %   pts - array of presentation timestamps (in timebase units) for each video frame
    %
    % Example:
    %   pts = ffprobe.pts('input.mp4');
    %
    % See also: ffprobe.available, ffprobe.run

    arguments
        inputFile {mustBeText, mustBeFile(inputFile)}

        kvargs.UpdateCallbackFcn {ffmpeg.validator.mustBeFunctionHandleOrEmpty} = []
    end

    args = sprintf('-v 0 -select_streams V:0 -show_entries packet=pts -of default=noprint_wrappers=1:nokey=1 "%s"', inputFile);
    [status, cmdout] = ffprobe.run(args, 'Echo', false, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);

    if status ~= 0
        error('ffprobe:pts:ExecutionFailed', 'FFprobe pts(_) execution failed with exit code %d', status);
    end
    
    % Parse output
    data = textscan(cmdout, '%f', 'TreatAsEmpty', 'N/A');
    pts = data{1};
    
    % Filter out NaNs if any
    pts = pts(~isnan(pts));
    
    pts = sort(pts);  % Ensure sorted order
    % Also get timebase
    timebase = ffprobe.timebase(inputFile);
end