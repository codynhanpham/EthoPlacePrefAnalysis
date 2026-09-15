function fig = trialMediaPlayer(kvargs)
%%TRIALMEDIAPLAYER - Launch a simple video player with optional Ethovision tracking overlay
% It includes a progress slider, a play/pause toggle, and a frame number display,
% Keyboard controls: Arrow keys (frame navigation), Space (play/pause),
% T (toggle tracking), F (fast mode), R (toggle FPS), J (jump to start frame),
% M then M quickly (mark start frame).
%
% Optional tracking overlay:
%   When TrackingDataFile is provided, the function will overlay animal tracking
%   data on the video frames. The coordinate conversion follows the same logic
%   as trialHeatmap.m, converting Ethovision coordinates to pixel coordinates
%   using ImgWidthFOV_cm and CenterOffset_px parameters.

arguments
    kvargs.VideoFile {mustBeFile}
    kvargs.TrackingDataFile {mustBeFile}
    kvargs.TrackingProvider {validator.mustBeTrackingProviderOrEmpty} = []
    kvargs.MasterMetadataTable {validator.mustBeFileTableOrEmpty} = []
end


if isfield(kvargs, 'VideoFile') && ~isempty(kvargs.VideoFile) && isfile(kvargs.VideoFile)
    fullPath = kvargs.VideoFile;
else
    [fileName, pathName] = uigetfile('*.mp4', 'Select an MP4 video file');
    if isequal(fileName, 0)
        return;
    end
    fullPath = fullfile(pathName, fileName);
end

% Upgrade legacy midpoint/midline CSV refs before any .ref.json interactions.
try
    graphics.migrateLegacyCSVRefs2JSON(fileparts(fullPath));
catch ME
    warning('graphics:trialMediaPlayer:LegacyRefMigrationFailed', ...
        'Could not auto-migrate legacy CSV reference files in "%s":\n%s', fileparts(fullPath), ME.message);
end

% Try to load tracking data if TrackingDataFile is provided
trackData = [];
trackDataTime = [];
pixelSize = [];
bpColors = [];
trackingEdges = struct('source', {}, 'target', {});
bodypartNames = strings(0);
centerPointBodyPartIndex = [];

if isfield(kvargs, 'TrackingDataFile') && ~isempty(kvargs.TrackingDataFile) && isfile(kvargs.TrackingDataFile) && ~isempty(kvargs.TrackingProvider)
    try
        [timestampSec, coords, metadata] = kvargs.TrackingProvider.loadTrackingCoordsPixels(kvargs.TrackingDataFile);
        % Assign outputs
        trackData = coords; % Nx2xM
        trackDataTime = timestampSec;
        
        % Tracking timestamps are kept separate from the video timeline.
        % Video PTS are loaded below and are authoritative for navigation.
        
        % Bodypart names and center detection
        if isfield(metadata, 'bodyparts') && ~isempty(metadata.bodyparts)
            try
                bodypartNames = string(metadata.bodyparts);
            catch
                % Fallback to strings if conversion fails
                if iscell(metadata.bodyparts)
                    bodypartNames = string(metadata.bodyparts);
                else
                    bodypartNames = string({metadata.bodyparts});
                end
            end
            % The first bodypart which contains 'center' in its name (case-insensitive) is considered the center point
            centerPointBodyPartIndex = find(contains(lower(bodypartNames), 'center'), 1, 'first');
        end

        if isfield(metadata, 'px2cmFactor') && ~isnan(metadata.px2cmFactor)
            pixelSize = metadata.px2cmFactor; % cm/pixel
        end

        % Colors per bodypart
        if isfield(metadata, 'colors') && ~isempty(metadata.colors)
            bpColors = metadata.colors;
        end

        % Optional skeleton edges. Each edge connects bodypart indices and
        % uses the source bodypart's color when rendered.
        if isfield(metadata, 'edges') && ~isempty(metadata.edges)
            trackingEdges = metadata.edges;
            % For skeleton data, use the most-connected bodypart as the
            % tracing point rather than relying on a bodypart named Center.
            nBodyparts = size(trackData, 3);
            connectionCounts = zeros(nBodyparts, 1);
            for edgeConnectionIdx = 1:numel(trackingEdges)
                source = double(trackingEdges(edgeConnectionIdx).source);
                target = double(trackingEdges(edgeConnectionIdx).target);
                if isscalar(source) && isscalar(target) && ...
                        source >= 1 && source <= nBodyparts && ...
                        target >= 1 && target <= nBodyparts && ...
                        source == fix(source) && target == fix(target)
                    connectionCounts([source, target]) = connectionCounts([source, target]) + 1;
                end
            end
            [~, centerPointBodyPartIndex] = max(connectionCounts);
        end

        % Ensure we have a color for each bodypart; generate fallback if needed
        if ~isempty(trackData)
            numParts = size(trackData, 3);
            if isempty(bpColors) || size(bpColors, 1) ~= numParts
                % Fallback to distinct colors if not provided or mismatched
                try
                    bpColors = lines(numParts);
                catch
                    % Minimal fallback if lines() unavailable
                    bpColors = hsv(numParts);
                end
            end
        end


    catch ME
        warning('graphics:trialMediaPlayer:TrackingLoadFailed', ...
            'Could not load tracking data:\n%s', getReport(ME));
    end
end


try
    videoObj = VideoReader(fullPath);
    frameRate = videoObj.FrameRate;
    vidWidth = videoObj.Width;
    vidHeight = videoObj.Height;
catch
    uialert(uifigure, 'Error: Could not read the video file. Please check the file format and permissions.', 'Error');
    return;
end

% Always build the navigation timeline from the video's presentation
% timestamps. Tracking timestamps may have a different length and/or sampling
% interval, so they must never determine the video frame count.
try
    % ffprobe.pts returns one PTS per decoded video frame, its timebase, and
    % the stream start_time. Subtracting start_time converts the timestamps
    % to VideoReader's 0-based domain so seeks land on the labeled frame.
    [pts, timebase, streamStartTime] = ffprobe.pts(fullPath);
    frameTimestamps = double(pts(:)) * double(timebase) - double(streamStartTime);
catch
    % Fallback only when ffprobe is unavailable. This is not exact for VFR
    % media, but preserves compatibility with installations without ffprobe.
    warning('graphics:trialMediaPlayer:FFprobeFailed', ...
        'Could not get PTS from ffprobe. Falling back to constant frame rate.');
    frameTimestamps = (0:videoObj.NumFrames-1)' / frameRate;
end

frameTimestamps = frameTimestamps(isfinite(frameTimestamps));
if isempty(frameTimestamps)
    warning('graphics:trialMediaPlayer:NoVideoTimestamps', ...
        'The video has no usable presentation timestamps.');
    return;
end
totalFrames = numel(frameTimestamps);


% Extract the stimulus trigger event time from {videoBaseName}.ref.json in the "trigger_events" field, if it exists
% Priority: STIM_START_FRAME from metadata > trigger_events from ref.json
triggerStartFrame = []; % this must be scalar!
triggerStartFrameValidated = false; % Flag tracking manual validation status
[~, videoBaseName, ~] = fileparts(fullPath);
refJsonPath = fullfile(fileparts(fullPath), [videoBaseName, '.ref.json']);

% Try to load STIM_START_FRAME from metadata (highest priority)
metadataStimStartFrame = [];
metadataTable = table();
trackingDataHeader = [];
if isfield(kvargs, 'MasterMetadataTable') && ~isempty(kvargs.MasterMetadataTable)
    try
        if istable(kvargs.MasterMetadataTable)
            [bool, missingHeaders] = io.metadata.isMasterMetadataTable(kvargs.MasterMetadataTable);
            if ~bool
                warning('graphics:trialMediaPlayer:InvalidMetadataTable', ...
                    'The provided MasterMetadataTable does not contain a valid master metadata table. Missing headers: {'' %s ''}', strjoin(missingHeaders, ''', '''));
            else
                metadataTable = kvargs.MasterMetadataTable;
            end
        elseif ~isempty(kvargs.MasterMetadataTable)
            metadataTable = io.metadata.loadMasterMetadata(kvargs.MasterMetadataTable);
        end

        % Metadata matching requires tracking header information from
        % the parent function context.
        if isfield(kvargs, 'TrackingDataFile') && ~isempty(kvargs.TrackingDataFile) && isfile(kvargs.TrackingDataFile) && ...
                isfield(kvargs, 'TrackingProvider') && ~isempty(kvargs.TrackingProvider)
            try
                [trackingDataHeader, ~, ~] = kvargs.TrackingProvider.loadTrackingData(kvargs.TrackingDataFile, Options=struct('HeaderOnly', true));
            catch
                trackingDataHeader = [];
            end
        end
        
        if ~isempty(metadataTable) && istable(metadataTable)
            metadataStimStartFrame = extractMetadataStimStartFrame(trackingDataHeader, metadataTable);
        end
    catch ME
        % Silently fail - will fall back to ref.json
        warning('graphics:trialMediaPlayer:MetadataLoadFailed', ...
            'Could not load STIM_START_FRAME from metadata:\n%s', getReport(ME));
    end
end

% If metadata has STIM_START_FRAME, use it and update ref.json
if ~isempty(metadataStimStartFrame) && ~isnan(metadataStimStartFrame)
    triggerStartFrame = metadataStimStartFrame;
    triggerStartFrameValidated = true; % Metadata-sourced frames are considered validated
    % Synchronize ref.json with metadata value
    synchronizeTriggerEventsWithMetadata(refJsonPath, triggerStartFrame);
elseif isfile(refJsonPath)
    % Fallback: extract from ref.json if metadata not available
    try
        refData = jsondecode(fileread(refJsonPath));
        if isfield(refData, 'trigger_events') && ~isempty(refData.trigger_events)
            triggerEvents = refData.trigger_events;
            % Safely extract first event start frame from possible JSON shapes:
            % legacy [on off], numeric Nx2, or cell-like list of [on off].
            firstStart = [];

            if isnumeric(triggerEvents)
                vals = double(triggerEvents);
                if isvector(vals)
                    if ~isempty(vals) && isfinite(vals(1))
                        firstStart = vals(1);
                    end
                elseif ismatrix(vals)
                    if ~isempty(vals) && isfinite(vals(1,1))
                        firstStart = vals(1,1);
                    end
                end
            elseif iscell(triggerEvents)
                if ~isempty(triggerEvents)
                    firstEvent = triggerEvents{1};
                    if isnumeric(firstEvent)
                        firstEvent = double(firstEvent);
                        if ~isempty(firstEvent) && isfinite(firstEvent(1))
                            firstStart = firstEvent(1);
                        end
                    elseif iscell(firstEvent) && ~isempty(firstEvent) && isnumeric(firstEvent{1})
                        nested = double(firstEvent{1});
                        if ~isempty(nested) && isfinite(nested(1))
                            firstStart = nested(1);
                        end
                    end
                end
            end

            if ~isempty(firstStart)
                triggerStartFrame = max(1, round(firstStart));
            end

            % Read validation flag (default to false if missing)
            if isfield(refData, 'trigger_events_start_validated')
                triggerStartFrameValidated = logical(refData.trigger_events_start_validated);
            end
        end
    catch ME
        warning('graphics:trialMediaPlayer:RefJsonFailed', ...
            'Could not read or parse ref.json for trigger events:\n%s', getReport(ME));
    end
end


[screensize, videoaspect] = deal(get(0, 'ScreenSize'), vidWidth / vidHeight);
extendHeight = 118; % controller offset
[figW, figH] = ui.dynamicFigureSize(videoaspect, extendHeight);

% Center the figure on the primary screen
figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];
[folder, name, ~] = fileparts(fullPath);
[~, folder] = fileparts(fileparts(folder));
fig = uifigure('Name', sprintf("%s - %s", folder, name), 'Position', figPos, ...
    'CloseRequestFcn', @(src, event) closeFigure(src, event));

mainGrid = uigridlayout(fig, [4 3]);
% Main video, frame label, play button, slider+nav buttons
mainGrid.RowHeight = {'1x', "fit", 32, 42};
mainGrid.ColumnWidth = {'1x', 'fit', 'fit'};
mainGrid.Padding = [5 5 5 5];
mainGrid.RowSpacing = 5;
mainGrid.ColumnSpacing = 5;

videoAxes = uiaxes(mainGrid);
videoAxes.Layout.Row = 1;
videoAxes.Layout.Column = [1, 3];
videoAxes.Interactions = [];
videoAxes.Visible = 'off';
videoAxes.Toolbar.Visible = 'Off';
disableDefaultInteractivity(videoAxes);
videoAxes.BusyAction='cancel';
videoAxes.Interruptible='on';
videoAxes.HitTest='off';
videoAxes.PickableParts="none";

frameLabel = uieditfield(mainGrid, 'numeric', 'Value', 1);
frameLabel.Layout.Row = 2;
frameLabel.Layout.Column = 1;
frameLabel.HorizontalAlignment = 'center';
frameLabel.Limits = [1 totalFrames];
frameLabel.RoundFractionalValues = 'on';
frameLabel.ValueDisplayFormat = 'Frame: %d';
frameLabel.ValueChangedFcn = @(src, event) jumpToFrame(round(event.Value));

stimStartFrameButton = uibutton(mainGrid, 'Text', 'Jump to Stimulus Start Frame', 'ButtonPushedFcn', @(btn, event) jumpToStartFrame, 'Tooltip', 'Jump to start frame of first trigger event in *.ref.json (Shortcut: J)');
stimStartFrameButton.Enable = ~isempty(triggerStartFrame);
stimStartFrameButton.Layout.Row = 2;
stimStartFrameButton.Layout.Column = 2;

markCheckedStartFrameButton = uibutton(mainGrid, 'Text', 'Mark Start Frame', 'ButtonPushedFcn', @(btn, event) markStartFrame, 'Tooltip', sprintf('Click to mark the current frame as the new stimulus start frame. This will update the ref.json file with the new trigger event time based on the current video timestamp.\n\nThis button is slight red if the current start frame was detected programmatically before any human input. The first time you manually validate or mark a start frame with this button, it will turn green and update the ref.json file to indicate that the start frame as been manually validated. (Shortcut: Double-M key press)'));
% Keep manual marking available even when no start frame was detected. This
% allows the user to create the first trigger event in the ref.json file.
markCheckedStartFrameButton.Enable = 'on';
% Set button color based on validation status: red (auto-detected) or green (manually validated)
if triggerStartFrameValidated
    markCheckedStartFrameButton.BackgroundColor = [240, 255, 242]/255; % Light green for validated
else
    markCheckedStartFrameButton.BackgroundColor = [255, 242, 240]/255; % Light red for auto-detected
end
markCheckedStartFrameButton.Layout.Row = 2;
markCheckedStartFrameButton.Layout.Column = 3;

playButton = uibutton(mainGrid, 'Text', 'Play', 'ButtonPushedFcn', @(btn, event) togglePlayback);
playButton.Layout.Row = 3;
playButton.Layout.Column = [1, 3];
controlsGrid = uigridlayout(mainGrid, [1 3]);
controlsGrid.Layout.Row = 4;
controlsGrid.Layout.Column = [1, 3];
controlsGrid.ColumnWidth = {35, '1x', 35};
controlsGrid.ColumnSpacing = 4;
controlsGrid.Padding = [0 0 0 0];
prevButton = uibutton(controlsGrid, 'Text', '<', 'FontSize', 18, 'ButtonPushedFcn', @(btn, event) prevFrame);
prevButton.Layout.Row = 1;
prevButton.Layout.Column = 1;

slider = uislider(controlsGrid);
slider.Layout.Row = 1;
slider.Layout.Column = 2;
slider.Limits = [1, totalFrames];
slider.Value = 1;
slider.MajorTicksMode = 'manual';
sliderTicks = unique(round(linspace(1, totalFrames, 12)));
slider.MajorTicks = sliderTicks;
slider.MajorTickLabels = arrayfun(@(n) sprintf('%d', n), sliderTicks, 'UniformOutput', false);
slider.MinorTicksMode = 'manual';
slider.MinorTicks = [];

nextButton = uibutton(controlsGrid, 'Text', '>', 'FontSize', 18, 'ButtonPushedFcn', @(btn, event) nextFrame);
nextButton.Layout.Row = 1;
nextButton.Layout.Column = 3;


appData = struct('videoObj', videoObj, 'slider', slider, 'frameLabel', frameLabel, ...
    'videoAxes', videoAxes, 'isPlaying', false, 'currentFrame', 1, 'timer', [], ...
    'trackData', trackData, 'trackDataTime', trackDataTime, 'pixelSize', pixelSize, 'lastFrameTime', tic, ...
    'showTracking', true, 'fastMode', false, 'showFps', false, ...
    'fpsHistory', [repmat(frameRate, 1, round(frameRate))], 'fpsTextHandle', [], 'frameCount', 0, 'startTime', tic, ...
    'imgHandle', [], 'colors', bpColors, 'bodypartNames', bodypartNames, 'centerPointBodyPartIndex', centerPointBodyPartIndex, ...
    'trackingEdges', trackingEdges, ...
    'frameTimestamps', frameTimestamps, 'overlayHandles', gobjects(0), ...
    'videoFrameIndex', 0, ...
    'playbackClock', [], 'playbackStartPTS', NaN, ...
    'videoFile', fullPath, 'lastMKeyPressTime', NaT, 'doubleMWindowSec', 0.3, ...
    'refillTimer', [], ...
    'readerFramePos', [], ...
    'frameBuffer', struct('data', uint8([]), 'head', 1, 'len', 0, 'startIndex', 1, 'capacity', 0));

% Frame buffer sizing: adaptive capacity under a pixel budget (default
% 100 MB). Frames are held in a PREALLOCATED ring buffer: refills write
% into existing slots, so appending never copies the whole buffer array
% (a cat(4) of ~100 MB per refill was the main-thread bottleneck).
bufferBudgetBytes = 100e6;
bytesPerFrame = double(vidHeight) * double(vidWidth) * 3; % uint8 RGB
bufferCapacity = min(totalFrames, max(2, floor(bufferBudgetBytes / max(bytesPerFrame, 1))));
appData.frameBuffer.capacity = bufferCapacity;
appData.frameBuffer.data = zeros(vidHeight, vidWidth, 3, bufferCapacity, 'uint8');


% Set up a keyboard listener on the figure
set(fig, 'WindowKeyPressFcn', @keyPressCallback);

% Slider behavior:
% - While stopped: drag updates label only; release seeks once.
% - While playing: first drag pauses; release seeks.
slider.ValueChangingFcn = @(source, event) slider_valueChanging(event.Value);
slider.ValueChangedFcn = @(source, event) slider_callback(source.Value);

showFrameAtIndex(1); % Show first frame with tracking overlay
togglePlayback();
startRefillTimer();


%% Helper functions
function updateFpsDisplay()
    if ~appData.showFps
        return;
    end

    currentTime = toc(appData.startTime);
    appData.frameCount = appData.frameCount + 1;

    if appData.frameCount > 24
        avgFps = appData.frameCount / currentTime;

        % Keep a rolling average of last 10 FPS measurements
        appData.fpsHistory = [appData.fpsHistory, avgFps];
        if length(appData.fpsHistory) > 10
            appData.fpsHistory = appData.fpsHistory(end-9:end);
        end

        smoothedFps = mean(appData.fpsHistory);

        % Create or update FPS text overlay
        if isempty(appData.fpsTextHandle) || ~isvalid(appData.fpsTextHandle)
            xlims = xlim(appData.videoAxes);
            ylims = ylim(appData.videoAxes);

            xPos = xlims(1) + 0.02 * (xlims(2) - xlims(1));
            yPos = ylims(1) + 0.02 * (ylims(2) - ylims(1));

            appData.fpsTextHandle = text(appData.videoAxes, xPos, yPos, '', ...
                'Color', 'yellow', 'FontSize', 12, 'FontWeight', 'bold', ...
                'BackgroundColor', 'black', 'EdgeColor', 'white', ...
                'Margin', 2, 'VerticalAlignment', 'top', ...
                'HorizontalAlignment', 'left');
        end

        % Update FPS text with color coding based on performance
        targetFps = frameRate;
        if smoothedFps >= targetFps * 0.9
            color = 'green';
        elseif smoothedFps >= targetFps * 0.7
            color = 'yellow';
        else
            color = 'red';
        end

        fpsText = sprintf('FPS: %.1f/%.0f', smoothedFps, targetFps);
        set(appData.fpsTextHandle, 'String', fpsText, 'Color', color);
    end
end

function actualFrameNum = displayFrameWithTrack(frameNum, ~)
    %%DISPLAYFRAMEWITHTRACK - Display a video frame with optional tracking overlay
    % Inputs:
    %   frameNum - Video frame number to display (1-based index)
    % Output:
    %   actualFrameNum - Index of the frame rendered ([] on failure).
    %
    % Frames are decoded with VideoReader.read([start end]), which addresses
    % frames by exact 1-based index. CurrentTime-based seeking is never used:
    % its time->frame mapping is unreliable for this media.
    actualFrameNum = [];

    if frameNum < 1 || frameNum > totalFrames
        return;
    end

    frame = getBufferedFrame(frameNum);
    if isempty(frame)
        return;
    end

    appData.videoFrameIndex = frameNum;
    actualFrameNum = frameNum;
    renderFrameWithTrack(frame, frameNum);
end

function bufferEnsure(startFrame, endFrame)
    %%BUFFERENSURE Have [startFrame endFrame] (inclusive) buffered.
    % PERFORMANCE-CRITICAL. Ring-buffer backed:
    % - Covered range -> no-op.
    % - Forward extension -> decode only the missing tail, write each frame
    %   directly into its ring slot (no array copies).
    % - Backward extension / disjoint jump -> decode the head window, write
    %   into slots (memcpy of the whole buffer is never needed).
    % Logical window is [startIndex, startIndex+len-1]; ring slot for frame
    % f is mod(f-1, capacity) + 1.
    fb = appData.frameBuffer;
    startFrame = max(1, min(round(startFrame), totalFrames));
    endFrame = max(startFrame, min(round(endFrame), totalFrames));

    % Already covered?
    if fb.len > 0 && fb.startIndex <= startFrame && (fb.startIndex + fb.len - 1) >= endFrame
        return;
    end

    cap = fb.capacity;
    if endFrame - startFrame + 1 > cap
        startFrame = endFrame - cap + 1;
    end

    % Case 1: forward extension of the current window -> sequential decode
    % when the reader is already positioned at the tail start (O(1) per
    % frame, no keyframe restart); otherwise one range read to resync.
    if fb.len > 0 && startFrame <= fb.startIndex + fb.len && endFrame > fb.startIndex + fb.len - 1
        tailStart = fb.startIndex + fb.len;
        if isequal(appData.readerFramePos, tailStart - 1)
            tail = localDecodeSequential(tailStart, endFrame);
        else
            tail = localDecodeRange(tailStart, endFrame);
        end
        if ~isempty(tail)
            ringAppend(tailStart, tail);
        end
        return;
    end

    % Case 2/3: backward extension or disjoint jump -> decode the requested
    % window and install it as the new logical window (slot math preserves
    % the ring layout; overlapping frames are re-decoded only on jumps).
    windowEnd = min(endFrame, startFrame + cap - 1);
    frames = localDecodeRange(startFrame, windowEnd);
    if isempty(frames)
        return;
    end
    nNew = size(frames, 4);
    fb.startIndex = startFrame;
    fb.len = nNew;
    writeStartSlot = mod(startFrame - 1, cap) + 1;
    % Wrap-safe write of the decoded window into the ring.
    firstPart = min(nNew, cap - writeStartSlot + 1);
    fb.data(:, :, :, writeStartSlot:writeStartSlot + firstPart - 1) = frames(:, :, :, 1:firstPart);
    if nNew > firstPart
        fb.data(:, :, :, 1:nNew - firstPart) = frames(:, :, :, firstPart+1:nNew);
    end
    appData.frameBuffer = fb;
end

function ringAppend(startFrame, frames)
    % Append decoded tail frames into the ring starting at frame startFrame,
    % writing each directly into its slot. Trims the logical window from the
    % front when capacity would be exceeded.
    fb = appData.frameBuffer;
    cap = fb.capacity;
    nNew = size(frames, 4);

    newLen = fb.len + nNew;
    if newLen > cap
        drop = newLen - cap;
        fb.startIndex = fb.startIndex + drop;
        fb.len = fb.len - drop;
    end

    for k = 1:nNew
        f = startFrame + k - 1;
        slot = mod(f - 1, cap) + 1;
        fb.data(:, :, :, slot) = frames(:, :, :, k);
        fb.len = max(fb.len, f - fb.startIndex + 1);
    end
    appData.frameBuffer = fb;
end

function frames = localDecodeSequential(startFrame, endFrame)
    %%LOCALDECODESEQUENTIAL Decode [startFrame endFrame] frame by frame.
    % Assumes the reader is at or before startFrame. Sequential readFrame
    % calls cost O(1) each (no keyframe restart), unlike read([s e]) which
    % re-seeks from the preceding keyframe on every call.
    frames = [];
    startFrame = max(1, round(startFrame));
    endFrame = max(startFrame, min(round(endFrame), totalFrames));
    if startFrame > totalFrames
        return;
    end

    nWant = endFrame - startFrame + 1;
    collected = cell(1, nWant);
    nGot = 0;
    try
        for k = 1:nWant
            if ~hasFrame(appData.videoObj)
                break;
            end
            collected{k} = readFrame(appData.videoObj);
            nGot = nGot + 1;
        end
    catch
        % Reader desynced mid-sequence; fall back to a range decode of the
        % remainder (rare path, acceptable one-off cost).
        appData.readerFramePos = [];
        frames = localDecodeRange(startFrame, startFrame + nGot - 1);
        return;
    end

    appData.readerFramePos = startFrame + nGot - 1;
    if nGot == 0
        frames = [];
        return;
    end
    frames = cat(4, collected{1:nGot});
end

function frames = localDecodeRange(startFrame, endFrame)
    % Decode [startFrame endFrame] by exact frame index via read([s e]).
    % The reader is recreated once on failure as a fallback.
    frames = [];
    startFrame = max(1, round(startFrame));
    endFrame = max(startFrame, min(round(endFrame), totalFrames));
    if startFrame > totalFrames
        return;
    end
    try
        frames = read(appData.videoObj, [startFrame, endFrame]);
    catch
        try
            appData.videoObj = VideoReader(appData.videoFile);
            frames = read(appData.videoObj, [startFrame, endFrame]);
        catch
            frames = [];
        end
    end
    % After read([s e]) the reader is positioned at endFrame: the next
    % readFrame continues from endFrame+1. Record this so subsequent tail
    % extensions take the fast sequential path instead of re-seeking.
    appData.readerFramePos = endFrame;
end

function frame = getBufferedFrame(frameNum)
    %%GETBUFFEREDFRAME Return frame frameNum from the ring buffer, refilling on miss.
    frame = [];
    if frameNum < 1 || frameNum > totalFrames
        return;
    end

    fb = appData.frameBuffer;
    buffered = fb.len > 0 && frameNum >= fb.startIndex && ...
        frameNum < fb.startIndex + fb.len;

    if ~buffered
        % Refill centered on the miss so immediate neighbors are also ready.
        halfBack = max(1, floor(fb.capacity * 0.25));
        bufStart = max(1, frameNum - halfBack);
        bufEnd = bufStart + fb.capacity - 1;
        bufferEnsure(bufStart, bufEnd);
        fb = appData.frameBuffer;
        buffered = fb.len > 0 && frameNum >= fb.startIndex && ...
            frameNum < fb.startIndex + fb.len;
        if ~buffered
            return;
        end
    end

    slot = mod(frameNum - 1, fb.capacity) + 1;
    frame = fb.data(:, :, :, slot);
end

function startRefillTimer()
    %%STARTREFILLTIMER Background timer keeps a read-ahead window buffered.
    if ~isempty(appData.refillTimer) && isvalid(appData.refillTimer)
        return;
    end
    % 50 ms tick with chunked refill (see refillAheadWindow): each tick
    % decodes at most refillChunkFrames, so a refill never monopolizes the
    % main thread long enough to stall rendering.
    % 50 ms tick with chunked refill; BusyMode drop prevents queue buildup.
    appData.refillTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.05, ...
        'TimerFcn', @(~, ~) refillAheadWindow(), 'BusyMode', 'drop');
    start(appData.refillTimer);
end

function stopRefillTimer()
    if ~isempty(appData.refillTimer) && isvalid(appData.refillTimer)
        stop(appData.refillTimer);
        delete(appData.refillTimer);
    end
    appData.refillTimer = [];
end

function refillAheadWindow()
    % Keep a read-ahead margin decoded ahead of the playhead.
    %
    % PERFORMANCE: hysteresis-gated and append-only. The buffer only refills
    % when the ahead-margin drops below refillLowWater, and then only the
    % missing tail is decoded (see bufferEnsure case 1). Steady-state cost is
    % one decode of exactly the frames that were consumed -- not a full-window
    % re-decode per tick.
    if ~isvalid(fig) || isempty(appData.frameBuffer) || appData.frameBuffer.capacity <= 0
        return;
    end
    fb = appData.frameBuffer;

    if fb.len == 0
        % Cold start: decode the initial window.
        bufferEnsure(appData.currentFrame, appData.currentFrame + fb.capacity - 1);
        return;
    end

    bufEnd = fb.startIndex + fb.len - 1;
    aheadFrames = bufEnd - appData.currentFrame;

    % Refill early (high low-water) so each individual decode stays small;
    % and cap the per-tick decode to refillChunkFrames. Spreading the refill
    % across ticks is what eliminates the "play smooth, stall, play smooth"
    % pattern: previously one tick decoded the entire missing span at once,
    % blocking rendering (MATLAB timers run on the main thread).
    refillLowWater = max(4, round(fb.capacity * 0.7));
    refillChunkFrames = max(2, round(fb.capacity * 0.25));

    if aheadFrames < refillLowWater && appData.currentFrame >= fb.startIndex - max(1, round(fb.capacity * 0.25))
        % MATLAB min takes only two arrays (third arg is dim) - nest for
        % elementwise 3-way minimum.
        chunkEnd = min(min(bufEnd + refillChunkFrames, appData.currentFrame + fb.capacity - 1), totalFrames);
        if chunkEnd > bufEnd
            bufferEnsure(fb.startIndex, chunkEnd);
        end
    end
end

function renderFrameWithTrack(frame, frameNum)
    % Create a persistent image object that fills the axes and simply update
    % its CData each frame. This avoids imshow's axis resets and margins.
    if isempty(appData.imgHandle) || ~isvalid(appData.imgHandle)
        imgH = image(appData.videoAxes, frame);
        appData.imgHandle = imgH;

        vidH = size(frame, 1);
        vidW = size(frame, 2);
        
        axis(appData.videoAxes, 'off');
        set(appData.videoAxes, ...
            'XLim', [0.5, vidW + 0.5], ...
            'YLim', [0.5, vidH + 0.5], ...
            'YDir', 'reverse', ...
            'DataAspectRatio', [1 1 1], ...  % Equal aspect ratio - no distortion
            'PlotBoxAspectRatioMode', 'auto', ...
            'PositionConstraint', 'outerposition', ...  % Center within grid slot
            'XTick', [], 'YTick', [], ... 
            'XTickLabel', {}, 'YTickLabel', {}, ...
            'Box', 'off');
        
        axis(appData.videoAxes, 'tight');
        drawnow;
    else
        set(appData.imgHandle, 'CData', frame);
    end

    % Clear previous overlay graphics
    try
        if ~isempty(appData.overlayHandles)
            delete(appData.overlayHandles(isvalid(appData.overlayHandles)));
        end
    catch
    end
    appData.overlayHandles = gobjects(0);

    if ~isempty(appData.trackData) && appData.showTracking
        hold(appData.videoAxes, 'on');

        trackFrame = 1;
        nTrackRows = size(appData.trackData, 1);
        if nTrackRows == totalFrames
            % Tracking rows map 1:1 to decoded video frames (the SLEAP and
            % DLC providers enforce this). Use the frame index directly; the
            % timestamp match below drifts for VFR media because true PTS
            % times deviate from VideoReader's CFR frame grid.
            trackFrame = frameNum;
        elseif ~isempty(appData.trackDataTime)
            % Fallback for providers without a 1:1 row guarantee: match the
            % frame's PTS to the nearest tracking timestamp.
            framePTS = appData.frameTimestamps(min(frameNum, totalFrames));
            [~, trackFrame] = min(abs(double(appData.trackDataTime(:)) - double(framePTS)));
        end
        trackFrame = max(1, min(trackFrame, nTrackRows));

        % Draw the trail of the last N frames using the center bodypart (if present)
        trackHistoryLength = 125;
        if ~isempty(appData.centerPointBodyPartIndex) && ~isnan(appData.centerPointBodyPartIndex)
            centerIdx = appData.centerPointBodyPartIndex;
            startIdx = max(1, trackFrame - trackHistoryLength);
            endIdx = min(trackFrame, size(appData.trackData, 1));

            if endIdx > startIdx
                xTrack = appData.trackData(startIdx:endIdx, 1, centerIdx);
                yTrack = appData.trackData(startIdx:endIdx, 2, centerIdx);
                xTrack = xTrack(:);
                yTrack = yTrack(:);

                validIdx = ~isnan(xTrack) & ~isnan(yTrack);
                if any(validIdx)
                    xValid = xTrack(validIdx);
                    yValid = yTrack(validIdx);

                    numPoints = length(xValid);
                    if numPoints > 1
                        x_segments = [xValid(1:end-1), xValid(2:end)]';
                        y_segments = [yValid(1:end-1), yValid(2:end)]';

                        segmentIndices = (1:numPoints-1) / (numPoints-1);
                        segColors = [segmentIndices', zeros(numPoints-1, 1), 1-segmentIndices'];
                        alphas = 0.3 + 0.7 * segmentIndices';
                        lineWidths = 1 + 2 * segmentIndices';

                        x_plot = [x_segments; NaN(1, size(x_segments, 2))];
                        y_plot = [y_segments; NaN(1, size(y_segments, 2))];

                        if appData.fastMode
                            meanColor = mean(segColors, 1);
                            meanAlpha = mean(alphas);
                            meanWidth = mean(lineWidths);
                            h = line(appData.videoAxes, x_plot(:), y_plot(:), ...
                                'Color', [meanColor, meanAlpha], 'LineWidth', meanWidth);
                            appData.overlayHandles(end+1,1) = h;
                        else
                            uniqueWidths = unique(round(lineWidths * 2) / 2);
                            for w = uniqueWidths'
                                widthMask = abs(lineWidths - w) < 0.25;
                                if any(widthMask)
                                    batchX = x_plot(:, widthMask);
                                    batchY = y_plot(:, widthMask);
                                    batchColors = segColors(widthMask, :);
                                    batchAlphas = alphas(widthMask);
                                    meanColor = mean(batchColors, 1);
                                    meanAlpha = mean(batchAlphas);
                                    h = line(appData.videoAxes, batchX(:), batchY(:), ...
                                        'Color', [meanColor, meanAlpha], 'LineWidth', w);
                                    appData.overlayHandles(end+1,1) = h;
                                end
                            end
                        end
                    end
                end
            end
        end

        % Draw optional bodypart edges before the nodes so the node markers
        % remain visually prominent. Edge color follows its source node.
        if ~isempty(appData.trackingEdges) && trackFrame <= size(appData.trackData, 1)
            try
                xParts = squeeze(appData.trackData(trackFrame, 1, :));
                yParts = squeeze(appData.trackData(trackFrame, 2, :));
                xParts = xParts(:);
                yParts = yParts(:);
                nParts = numel(xParts);
                edgeColors = appData.colors;
                if isempty(edgeColors) || size(edgeColors, 1) ~= nParts
                    edgeColors = lines(nParts);
                end

                for renderEdgeIdx = 1:numel(appData.trackingEdges)
                    edge = appData.trackingEdges(renderEdgeIdx);
                    source = double(edge.source);
                    target = double(edge.target);
                    if ~isscalar(source) || ~isscalar(target) || ...
                            source < 1 || source > nParts || target < 1 || target > nParts || ...
                            source ~= fix(source) || target ~= fix(target)
                        continue;
                    end
                    if ~all(isfinite([xParts(source), yParts(source), xParts(target), yParts(target)]))
                        continue;
                    end
                    edgeHandle = line(appData.videoAxes, ...
                        [xParts(source), xParts(target)], ...
                        [yParts(source), yParts(target)], ...
                        'Color', edgeColors(source, :), ...
                        'LineWidth', 2, ...
                        'HitTest', 'off', ...
                        'PickableParts', 'none');
                    appData.overlayHandles(end+1, 1) = edgeHandle;
                end
            catch
                % Invalid optional edge metadata should not disable tracking
                % point rendering.
            end
        end

        % Plot current positions for ALL bodyparts using their colors
        if trackFrame <= size(appData.trackData, 1)
            try
                xParts = squeeze(appData.trackData(trackFrame, 1, :));
                yParts = squeeze(appData.trackData(trackFrame, 2, :));
            catch
                xParts = appData.trackData(trackFrame, 1, :);
                yParts = appData.trackData(trackFrame, 2, :);
            end
            xParts = xParts(:);
            yParts = yParts(:);

            inBounds = xParts > 0 & xParts <= size(frame, 2) & ...
                       yParts > 0 & yParts <= size(frame, 1);
            validMask = ~isnan(xParts) & ~isnan(yParts) & inBounds;

            if any(validMask)
                ptColors = appData.colors;
                if size(ptColors, 1) ~= numel(xParts)
                    try
                        ptColors = lines(numel(xParts));
                    catch
                        ptColors = hsv(numel(xParts));
                    end
                end
                markerSize = 50;
                if ~isempty(appData.trackingEdges)
                    markerSize = 35;
                end
                h = scatter(appData.videoAxes, xParts(validMask), yParts(validMask), markerSize, ptColors(validMask, :), 'filled', ...
                    'MarkerEdgeColor', 'w', 'LineWidth', 1);
                appData.overlayHandles(end+1,1) = h;
            end
        end

        hold(appData.videoAxes, 'off');
    end

    updateFpsDisplay();
end

function showFrameAtIndex(frameNum)
    frameNum = max(1, min(frameNum, totalFrames));
    actualFrameNum = displayFrameWithTrack(frameNum);
    % Always display the frame that was actually rendered so the label,
    % slider, and tracking overlay match the pixels on screen.
    if isempty(actualFrameNum) || ~isfinite(actualFrameNum)
        actualFrameNum = frameNum;
    end
    appData.currentFrame = actualFrameNum;
    appData.slider.Value = actualFrameNum;
    appData.frameLabel.Value = actualFrameNum;
end

function togglePlayback()
    if appData.isPlaying
        % Stop playback
        appData.isPlaying = false;
        if ~isempty(appData.timer) && isvalid(appData.timer)
            stop(appData.timer);
            delete(appData.timer);
        end
        appData.timer = [];
        playButton.Text = 'Play';
    else
        % Start playback from the currently displayed video frame. The
        % selected frame's PTS anchors the wall-clock playback schedule.
        if appData.currentFrame >= totalFrames
            return;
        end
        appData.isPlaying = true;
        playButton.Text = 'Pause';
        appData.frameCount = 0;
        appData.startTime = tic;
        appData.fpsHistory = [repmat(frameRate, 1, round(frameRate))];
        appData.playbackStartPTS = appData.frameTimestamps(appData.currentFrame);
        appData.playbackClock = tic;
        % Prime the buffer at the playhead so the first ticks render instantly.
        bufferEnsure(appData.currentFrame, appData.currentFrame + appData.frameBuffer.capacity - 1);
        % Tick at ~half the frame interval (rounded to the timer's 1 ms
        % precision to avoid sub-millisecond warnings). Half-interval ticks
        % give the pacing gate a second chance per frame, so jitter never
        % caps the display rate below the video's true frame rate.
        tickPeriod = max(0.001, round(500 / max(frameRate, 1)) / 1000);
        appData.timer = timer('ExecutionMode', 'fixedRate', 'Period', tickPeriod, ...
            'TimerFcn', @(obj, event) updateFrame, 'BusyMode', 'drop');
        start(appData.timer);
        startRefillTimer();
    end
end

function updateFrame()
    % Check if the figure is still open and video has more frames.
    if ~isvalid(fig)
        try
            togglePlayback();
        catch
        end
        return;
    end

    if appData.currentFrame >= totalFrames
        togglePlayback();
        return;
    end

    % Sequential playback pops frames from the buffer by index. PTS are used
    % only for the wall-clock pacing schedule, never frame addressing.
    nextFrameIndex = appData.currentFrame + 1;
    targetElapsed = appData.frameTimestamps(nextFrameIndex) - appData.playbackStartPTS;
    elapsed = toc(appData.playbackClock);
    if elapsed < targetElapsed
        return;
    end

    % If we fell behind (timer jitter, GC pause), skip ahead to the most
    % recent due frame so the display rate tracks real time instead of
    % accumulating lag.
    while nextFrameIndex < totalFrames
        nextDue = appData.frameTimestamps(nextFrameIndex + 1) - appData.playbackStartPTS;
        if elapsed < nextDue
            break;
        end
        nextFrameIndex = nextFrameIndex + 1;
    end

    frame = getBufferedFrame(nextFrameIndex);
    if isempty(frame)
        % Buffer miss (e.g. after a jump); synchronous refill once.
        halfBack = max(1, floor(appData.frameBuffer.capacity * 0.25));
        bufferEnsure(nextFrameIndex - halfBack, nextFrameIndex + appData.frameBuffer.capacity - 1);
        frame = getBufferedFrame(nextFrameIndex);
        if isempty(frame)
            togglePlayback();
            return;
        end
    end

    appData.videoFrameIndex = nextFrameIndex;
    renderFrameWithTrack(frame, nextFrameIndex);
    appData.currentFrame = nextFrameIndex;
    appData.slider.Value = nextFrameIndex;
    appData.frameLabel.Value = nextFrameIndex;
    % Limitrate caps redraw rate; callbacks are NOT suppressed so button and
    % keyboard events stay responsive during playback.
    drawnow limitrate;
end

function pauseAndJump(newValue)
    % This function is called when the user drags the slider
    appData.isPlaying = false;
    if ~isempty(appData.timer) && isvalid(appData.timer)
        stop(appData.timer);
        delete(appData.timer);
    end
    appData.timer = [];
    playButton.Text = 'Play';

    appData.currentFrame = max(1, min(round(newValue), totalFrames));
    showFrameAtIndex(appData.currentFrame);
end

function slider_valueChanging(newValue)
    if appData.isPlaying
        pauseAndJump(newValue);
    else
        slider_drag(newValue);
    end
end

function slider_drag(newValue)
    if appData.isPlaying
        return;
    end
    appData.currentFrame = max(1, min(round(newValue), totalFrames));
    appData.frameLabel.Value = appData.currentFrame;
end

function slider_callback(newValue)
    % Final callback after the user lets go of the slider
    if appData.isPlaying
        return;
    end
    appData.currentFrame = max(1, min(round(newValue), totalFrames));
    showFrameAtIndex(appData.currentFrame);
end

function jumpToFrame(frameNum)
    % Jump to a specific frame when the user enters a frame number
    frameNum = max(1, min(frameNum, totalFrames)); % Clamp to valid range
    
    % Pause playback if currently playing
    if appData.isPlaying
        appData.isPlaying = false;
        if ~isempty(appData.timer) && isvalid(appData.timer)
            stop(appData.timer);
            delete(appData.timer);
        end
        appData.timer = [];
        playButton.Text = 'Play';
    end
    
    showFrameAtIndex(frameNum);
end

function keyPressCallback(~, event)
    % Require consecutive m presses; any other key cancels a pending first m.
    if ~strcmp(event.Key, 'm')
        appData.lastMKeyPressTime = NaT;
    end

    switch event.Key
        case 'rightarrow'
            nextFrame();
        case 'leftarrow'
            prevFrame();
        case 'j'
            jumpToStartFrame();
        case 'm'
            currentKeyTime = datetime("now");
            if ~isnat(appData.lastMKeyPressTime) && ...
                    (seconds(currentKeyTime - appData.lastMKeyPressTime) <= appData.doubleMWindowSec)
                appData.lastMKeyPressTime = NaT;
                markStartFrame();
            else
                appData.lastMKeyPressTime = currentKeyTime;
            end
        case 't'
            % Toggle tracking display for performance
            if ~isempty(appData.trackData)
                appData.showTracking = ~appData.showTracking;
                showFrameAtIndex(appData.currentFrame);
                if appData.showTracking
                    fprintf('Tracking overlay: ON\n');
                else
                    fprintf('Tracking overlay: OFF (for better performance)\n');
                end
            end
        case 'f'
            % Toggle fast mode for tracking rendering
            if ~isempty(appData.trackData) && appData.showTracking
                appData.fastMode = ~appData.fastMode;
                showFrameAtIndex(appData.currentFrame);
                if appData.fastMode
                    fprintf('Fast mode: ON (simplified trail rendering)\n');
                else
                    fprintf('Fast mode: OFF (full quality trail rendering)\n');
                end
            end
        case 'r'
            % Toggle FPS display
            appData.showFps = ~appData.showFps;
            if appData.showFps
                fprintf('FPS display: ON\n');
                % Force update to show immediately
                updateFpsDisplay();
            else
                fprintf('FPS display: OFF\n');
                % Hide the FPS text if it exists
                if ~isempty(appData.fpsTextHandle) && isvalid(appData.fpsTextHandle)
                    set(appData.fpsTextHandle, 'Visible', 'off');
                end
            end
        case 'space'
            % Space bar to toggle play/pause
            togglePlayback();
    end
end
function nextFrame()
    % Advance by one frame
    if appData.currentFrame < totalFrames
        % Pause playback and then advance
        appData.isPlaying = false;
        if ~isempty(appData.timer) && isvalid(appData.timer)
            stop(appData.timer);
            delete(appData.timer);
        end
        appData.timer = [];
        playButton.Text = 'Play';
        appData.currentFrame = appData.currentFrame + 1;
        showFrameAtIndex(appData.currentFrame);
    end
end
function prevFrame()
    % Go back one frame
    if appData.currentFrame > 1
        % Pause playback and then go back
        appData.isPlaying = false;
        if ~isempty(appData.timer) && isvalid(appData.timer)
            stop(appData.timer);
            delete(appData.timer);
        end
        appData.timer = [];
        playButton.Text = 'Play';
        appData.currentFrame = appData.currentFrame - 1;
        showFrameAtIndex(appData.currentFrame);
    end
end
function jumpToStartFrame()
    if ~isempty(triggerStartFrame)
        % Ensure paused first!
        if appData.isPlaying
            % Stop playback
            appData.isPlaying = false;
            if ~isempty(appData.timer) && isvalid(appData.timer)
                stop(appData.timer);
                delete(appData.timer);
            end
            appData.timer = [];
            playButton.Text = 'Play';
        end

        jumpToFrame(triggerStartFrame);
    end
end

function markStartFrame()
    %%MARKSTARTFRAME Mark the current frame as the stimulus start frame and validate it
    % Updates/creates canonical ref.json trigger_events as [[start,end], ...]
    % and sets the first event's start frame to the current frame number
    % Sets trigger_events_start_validated to true
    % Copies the frame number to clipboard
    
    currentFrameNum = appData.currentFrame;
    
    % Read current ref.json
    try
        if isfile(refJsonPath)
            refData = jsondecode(fileread(refJsonPath));
        else
            refData = struct();
        end
    catch ME
        uialert(fig, sprintf('Error reading ref.json:\n%s', ME.message), 'Error');
        return;
    end

    % Canonicalize trigger events to a 1xN cell array of [start end] rows.
    try
        triggerEventsCanonical = cell(1, 0);
        if isfield(refData, 'trigger_events') && ~isempty(refData.trigger_events)
            triggerEventsLocal = refData.trigger_events;

            if isnumeric(triggerEventsLocal)
                vals = double(triggerEventsLocal);
                if isvector(vals) && numel(vals) == 2
                    triggerEventsCanonical = {reshape(vals, 1, 2)};
                elseif ismatrix(vals) && size(vals, 2) == 2
                    nEvents = size(vals, 1);
                    triggerEventsCanonical = cell(1, nEvents);
                    for ii = 1:nEvents
                        triggerEventsCanonical{ii} = vals(ii, :);
                    end
                else
                    error('Unexpected trigger_events format (numeric but not vector or Nx2 matrix)');
                end
            elseif iscell(triggerEventsLocal)
                nEvents = numel(triggerEventsLocal);
                triggerEventsCanonical = cell(1, nEvents);
                for ii = 1:nEvents
                    row = triggerEventsLocal{ii};
                    if isnumeric(row)
                        rowVals = double(row);
                    elseif iscell(row) && ~isempty(row) && isnumeric(row{1})
                        rowVals = double(row{1});
                    else
                        error('Unexpected event format at index %d (not numeric pair)', ii);
                    end

                    rowVals = rowVals(:)';
                    if numel(rowVals) ~= 2 || ~all(isfinite(rowVals))
                        error('Unexpected event format at index %d (must be finite [start end])', ii);
                    end
                    triggerEventsCanonical{ii} = rowVals;
                end
            else
                error('Unexpected trigger_events format (not numeric or cell)');
            end
        end

        % Create a default event if missing and always update first start frame.
        if isempty(triggerEventsCanonical)
            triggerEventsCanonical = {[currentFrameNum, currentFrameNum]};
        else
            firstEvent = double(triggerEventsCanonical{1});
            firstEvent = firstEvent(:)';
            if numel(firstEvent) < 2
                firstEvent = [currentFrameNum, currentFrameNum];
            else
                firstEvent(1) = currentFrameNum;
                if ~isfinite(firstEvent(2))
                    firstEvent(2) = currentFrameNum;
                end
                firstEvent = firstEvent(1:2);
            end
            triggerEventsCanonical{1} = firstEvent;
        end

        refData.trigger_events = triggerEventsCanonical;
    catch ME
        uialert(fig, sprintf('Error updating trigger_events:\n%s', ME.message), 'Error');
        return;
    end
    
    % Mark as validated
    refData.trigger_events_start_validated = true;
    
    % Write back to ref.json
    try
        jsonText = jsonencode(refData);
        fid = fopen(refJsonPath, 'w');
        if fid == -1
            error('Could not open file for writing');
        end
        fwrite(fid, jsonText, 'char');
        fclose(fid);
    catch ME
        uialert(fig, sprintf('Error writing ref.json:\n%s', ME.message), 'Error');
        return;
    end
    
    % Copy frame number to clipboard
    try
        clipboard('copy', sprintf('%d', currentFrameNum));
    catch
        % Silently fail if clipboard is not available
    end
    
    % Update triggerStartFrame and validation flag for future use
    triggerStartFrame = currentFrameNum;
    triggerStartFrameValidated = true;
    stimStartFrameButton.Enable = 'on';
    
    % Update button color to green to indicate manual validation
    markCheckedStartFrameButton.BackgroundColor = [240, 255, 242]/255; % Light green for validated
end

function closeFigure(src, ~)
    % Clean up timers if running
    if isfield(appData, 'timer') && ~isempty(appData.timer) && isvalid(appData.timer)
        stop(appData.timer);
        delete(appData.timer);
    end
    if isfield(appData, 'refillTimer') && ~isempty(appData.refillTimer) && isvalid(appData.refillTimer)
        stopRefillTimer();
    end
    delete(src);
end

end

%% Helper Functions for Metadata-based Trigger Synchronization

function stimStartFrame = extractMetadataStimStartFrame(trackingDataHeader, metadataTable)
    %%EXTRACTMETADATASTIMSTARTFRAME Extract STIM_START_FRAME from metadata for a given video with is tracking data file header info
    
    stimStartFrame = [];
    
    if isempty(metadataTable) || ~istable(metadataTable)
        return;
    end
    
    % Required columns for metadata matching
    requiredColumns = {'ETHOVISION_TRIAL', 'ETHOVISION_FILE', 'ETHOVISION_ARENA', 'STIM_START_FRAME'};
    if ~all(ismember(requiredColumns, metadataTable.Properties.VariableNames))
        return;
    end

    if isempty(trackingDataHeader)
        return;
    end
    
    try
        trialName = trackingDataHeader("Trial name");
        experimentName = trackingDataHeader("Experiment");
        arenaName = trackingDataHeader("Arena name");
        
        % Extract trial number
        trialParts = split(trialName, ' ');
        trialNumber = str2double(strtrim(trialParts{end}));
        
        % Find matching row in metadata using the same logic as alignEthovisionRawToStim
        trialMask = (metadataTable.ETHOVISION_TRIAL == trialNumber) & ...
                    (metadataTable.ETHOVISION_FILE == experimentName) & ...
                    (metadataTable.ETHOVISION_ARENA == arenaName);
        
        trialRowIdx = find(trialMask, 1);
        if ~isempty(trialRowIdx)
            stimStartVal = metadataTable.STIM_START_FRAME(trialRowIdx);
            if ~isnumeric(stimStartVal)
                stimStartVal = str2double(string(stimStartVal));
            end
            if ~isempty(stimStartVal) && ~isnan(stimStartVal)
                stimStartFrame = round(double(stimStartVal));
            end
        end
        
    catch
        % Silently fail if unable to extract metadata
    end
end

function synchronizeTriggerEventsWithMetadata(refJsonPath, stimStartFrame)
    %%SYNCHRONIZETRIGGEREVENTSSWITHMETADATA Update trigger_events in ref.json to match STIM_START_FRAME
    %   Sets the first trigger event's start frame to stimStartFrame,
    %   creates default trigger event if missing, and marks as validated
    
    if isempty(stimStartFrame) || isnan(stimStartFrame)
        return;
    end
    
    try
        % Load existing ref.json if it exists, otherwise create new structure
        if isfile(refJsonPath)
            refData = jsondecode(fileread(refJsonPath));
        else
            refData = struct();
        end
        
        stimStartFrame = round(double(stimStartFrame));
        
        % Canonicalize trigger_events to a 1xN cell array of [start end] rows.
        triggerEventsCanonical = cell(1, 0);
        if isfield(refData, 'trigger_events') && ~isempty(refData.trigger_events)
            triggerEventsLocal = refData.trigger_events;

            if isnumeric(triggerEventsLocal)
                vals = double(triggerEventsLocal);
                if isvector(vals) && numel(vals) == 2 && all(isfinite(vals))
                    triggerEventsCanonical = {reshape(vals, 1, 2)};
                elseif ismatrix(vals) && size(vals, 2) == 2 && all(isfinite(vals), 'all')
                    nEvents = size(vals, 1);
                    triggerEventsCanonical = cell(1, nEvents);
                    for ii = 1:nEvents
                        triggerEventsCanonical{ii} = vals(ii, :);
                    end
                end
            elseif iscell(triggerEventsLocal)
                nEvents = numel(triggerEventsLocal);
                triggerEventsCanonical = cell(1, nEvents);
                for ii = 1:nEvents
                    row = triggerEventsLocal{ii};
                    if isnumeric(row)
                        rowVals = double(row);
                    elseif iscell(row) && ~isempty(row) && isnumeric(row{1})
                        rowVals = double(row{1});
                    else
                        triggerEventsCanonical = cell(1, 0);
                        break;
                    end

                    rowVals = rowVals(:)';
                    if numel(rowVals) ~= 2 || ~all(isfinite(rowVals))
                        triggerEventsCanonical = cell(1, 0);
                        break;
                    end
                    triggerEventsCanonical{ii} = rowVals;
                end
            end
        end

        % Create default event if missing, then update first start frame.
        if isempty(triggerEventsCanonical)
            triggerEventsCanonical = {[stimStartFrame, stimStartFrame]};
        else
            firstEvent = double(triggerEventsCanonical{1});
            firstEvent = firstEvent(:)';
            if numel(firstEvent) < 2
                firstEvent = [stimStartFrame, stimStartFrame];
            else
                firstEvent(1) = stimStartFrame;
                if ~isfinite(firstEvent(2))
                    firstEvent(2) = stimStartFrame;
                end
                firstEvent = firstEvent(1:2);
            end
            triggerEventsCanonical{1} = firstEvent;
        end

        refData.trigger_events = triggerEventsCanonical;
        
        % Mark trigger_events_start_validated as true
        refData.trigger_events_start_validated = true;
        
        % Write back to ref.json
        jsonText = jsonencode(refData);
        fid = fopen(refJsonPath, 'w');
        if fid == -1
            return; % Silently fail if cannot write
        end
        fwrite(fid, jsonText, 'char');
        fclose(fid);
        
    catch
        % Silently fail if unable to read/write/process ref.json
    end
end