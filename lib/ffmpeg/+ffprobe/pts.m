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

    args = sprintf('-v quiet -print_format json -show_packets -select_streams v:0 -show_entries packet=pts -i "%s"', inputFile);
    [status, cmdout] = ffprobe.run(args, 'Echo', false, 'UpdateCallbackFcn', kvargs.UpdateCallbackFcn);

    if status ~= 0
        error('ffprobe:pts:ExecutionFailed', 'FFprobe pts(_) execution failed with exit code %d', status);
    end
    data = jsondecode(cmdout);
    packets = data.packets;
    pts = zeros(length(packets), 1);
    for k = 1:length(packets)
        pts(k) = packets(k).pts;
    end

    % Also get timebase
    timebase = ffprobe.timebase(inputFile);
end