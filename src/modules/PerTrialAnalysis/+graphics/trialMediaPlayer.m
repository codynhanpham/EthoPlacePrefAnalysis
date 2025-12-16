function fig = trialMediaPlayer(kvargs)
%%TRIALMEDIAPLAYER - Launch a simple video player with optional Ethovision tracking overlay
% It includes a progress slider, a play/pause toggle, and a frame number display,
% Keyboard controls: Arrow keys (frame navigation), Space (play/pause), T (toggle tracking), F (fast mode), R (toggle FPS).
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

% Try to load tracking data if TrackingDataFile is provided
trackData = [];
trackDataTime = [];
pixelSize = [];
bpColors = [];
bodypartNames = strings(0);
centerPointBodyPartIndex = [];
frameTimestamps = [];

if isfield(kvargs, 'TrackingDataFile') && ~isempty(kvargs.TrackingDataFile) && isfile(kvargs.TrackingDataFile) && ~isempty(kvargs.TrackingProvider)
    try
        [timestampSec, coords, metadata] = kvargs.TrackingProvider.loadTrackingCoordsPixels(kvargs.TrackingDataFile);
        % Assign outputs
        trackData = coords; % Nx2xM
        trackDataTime = timestampSec;
        
        % Use tracking timestamps for video navigation
        frameTimestamps = timestampSec;

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

% Determine frame timestamps if not already set by tracking
if isempty(frameTimestamps)
    try
        % Try to use ffprobe to get PTS
        [pts, timebase] = ffprobe.pts(fullPath);
        frameTimestamps = pts * timebase;
    catch
        % Fallback to constant frame rate if ffprobe fails or not available
        warning('graphics:trialMediaPlayer:FFprobeFailed', 'Could not get PTS from ffprobe. Falling back to constant frame rate.');
        frameTimestamps = (0:videoObj.NumFrames-1)' / frameRate;
    end
end

totalFrames = length(frameTimestamps);

[screensize, videoaspect] = deal(get(0, 'ScreenSize'), vidWidth / vidHeight);
extendHeight = 118; % controller offset
[figW, figH] = ui.dynamicFigureSize(videoaspect, extendHeight);

% Center the figure on the primary screen
figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];
[folder, name, ~] = fileparts(fullPath);
[~, folder] = fileparts(fileparts(folder));
fig = uifigure('Name', sprintf("%s - %s", folder, name), 'Position', figPos, ...
    'CloseRequestFcn', @(src, event) closeFigure(src, event));

mainGrid = uigridlayout(fig, [4 1]);
% Main video, frame label, play button, slider+nav buttons
mainGrid.RowHeight = {'1x', "fit", 32, 42};
mainGrid.ColumnWidth = {'1x'};
mainGrid.Padding = [5 5 5 5];
mainGrid.RowSpacing = 5;
mainGrid.ColumnSpacing = 5;

videoAxes = uiaxes(mainGrid);
videoAxes.Layout.Row = 1;
videoAxes.Layout.Column = 1;
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

playButton = uibutton(mainGrid, 'Text', 'Play', 'ButtonPushedFcn', @(btn, event) togglePlayback);
playButton.Layout.Row = 3;
playButton.Layout.Column = 1;
controlsGrid = uigridlayout(mainGrid, [1 3]);
controlsGrid.Layout.Row = 4;
controlsGrid.Layout.Column = 1;
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
slider.MajorTicksMode = 'auto';
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
    'frameTimestamps', frameTimestamps, 'frameTimestampEdges', [], 'overlayHandles', gobjects(0), ...
    'lastSeekTime', NaN, 'videoFile', fullPath);

% Precompute timestamp bin edges for fast time->index mapping
try
    ts = appData.frameTimestamps(:);
    if numel(ts) >= 2
        mids = (ts(1:end-1) + ts(2:end)) / 2;
        appData.frameTimestampEdges = [-Inf; mids; Inf];
    elseif isscalar(ts)
        appData.frameTimestampEdges = [-Inf; Inf];
    else
        appData.frameTimestampEdges = [];
    end
catch
    appData.frameTimestampEdges = [];
end


% Set up a keyboard listener on the figure
set(fig, 'WindowKeyPressFcn', @keyPressCallback);

% Slider behavior:
% - While stopped: drag updates label only; release seeks once.
% - While playing: first drag pauses; release seeks.
slider.ValueChangingFcn = @(source, event) slider_valueChanging(event.Value);
slider.ValueChangedFcn = @(source, event) slider_callback(source.Value);

showFrameAtIndex(1); % Show first frame with tracking overlay
togglePlayback();


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

function displayFrameWithTrack(frameNum, ~)
    %%DISPLAYFRAMEWITHTRACK - Display a video frame with optional tracking overlay
    % Inputs:
    %   frameNum - Video frame number to display (index in frameTimestamps)
    %   realFrameTime - Real time of the frame in seconds
    
    if frameNum < 1 || frameNum > length(appData.frameTimestamps)
        return;
    end

    % Get timestamp for the requested frame
    t = appData.frameTimestamps(frameNum);
    
    ensureVideoObjAtTime(t);
    try
        if ~hasFrame(appData.videoObj)
            return;
        end
        % VideoReader.CurrentTime typically advances *after* readFrame().
        % Capture it before reading so tracking aligns with the displayed frame.
        realFrameTime = appData.videoObj.CurrentTime;
        frame = readFrame(appData.videoObj);
    catch
        return;
    end

    renderFrameWithTrack(frame, realFrameTime);
end

function renderFrameWithTrack(frame, realFrameTime)
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
        if ~isempty(realFrameTime) && ~isempty(appData.trackDataTime)
            [~, trackFrame] = min(abs(appData.trackDataTime - realFrameTime));
        end
        trackFrame = max(1, min(trackFrame, size(appData.trackData, 1)));

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
                h = scatter(appData.videoAxes, xParts(validMask), yParts(validMask), 70, ptColors(validMask, :), 'filled', ...
                    'MarkerEdgeColor', 'w', 'LineWidth', 1.2);
                appData.overlayHandles(end+1,1) = h;
            end
        end

        hold(appData.videoAxes, 'off');
    end

    updateFpsDisplay();
end

function idx = timeToFrameIndex(t)
    try
        if isempty(appData.frameTimestampEdges) || isempty(appData.frameTimestamps)
            idx = max(1, min(appData.currentFrame, totalFrames));
            return;
        end
        idx = discretize(t, appData.frameTimestampEdges);
        if isempty(idx) || isnan(idx)
            idx = 1;
        end
        idx = max(1, min(idx, totalFrames));
    catch
        idx = max(1, min(appData.currentFrame, totalFrames));
    end
end

function ensureVideoObjAtTime(t)
    try
        if ~isfinite(t) || t < 0
            t = 0;
        end
        if isfinite(appData.lastSeekTime) && t < appData.lastSeekTime
            appData.videoObj = VideoReader(appData.videoFile);
        end
        appData.videoObj.CurrentTime = t;
        appData.lastSeekTime = t;
    catch
        try
            appData.videoObj = VideoReader(appData.videoFile);
            appData.videoObj.CurrentTime = t;
            appData.lastSeekTime = t;
        catch
        end
    end
end

function showFrameAtIndex(frameNum)
    frameNum = max(1, min(frameNum, totalFrames));
    appData.currentFrame = frameNum;
    displayFrameWithTrack(frameNum);
    appData.slider.Value = frameNum;
    appData.frameLabel.Value = frameNum;
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
        % Start playback
        appData.isPlaying = true;
        playButton.Text = 'Pause';

        % Reset FPS counter for accurate measurement
        appData.frameCount = 0;
        appData.startTime = tic;
        appData.fpsHistory = [repmat(frameRate, 1, round(frameRate))]; % Reset history

        % Set up a timer to read frames with more aggressive timing
        targetPeriod = 1/frameRate;
        % Use a faster period to compensate for rendering overhead
        actualPeriod = max(0.001, round(targetPeriod * 0.8, 3)); % 20% faster to account for overhead
        appData.timer = timer('ExecutionMode', 'fixedRate', 'Period', actualPeriod, ...
            'TimerFcn', @(obj, event) updateFrame);
        appData.lastFrameTime = tic;
        start(appData.timer);
    end
end

function updateFrame()
    % Check if the figure is still open and video has more frames
    % Stream decode: do NOT seek per frame; only readFrame sequentially.
    if ~isvalid(fig)
        try
            togglePlayback();
        catch
        end
        return;
    end

    if isempty(appData.videoObj)
        try
            appData.videoObj = VideoReader(appData.videoFile);
        catch
            togglePlayback();
            return;
        end
    end

    if ~hasFrame(appData.videoObj)
        togglePlayback();
        return;
    end

    targetPeriod = 1/frameRate;
    elapsedTime = toc(appData.lastFrameTime);
    skipCount = max(1, min(5, floor(elapsedTime / targetPeriod)));

    try
        for k = 1:(skipCount-1)
            if hasFrame(appData.videoObj)
                readFrame(appData.videoObj);
            else
                togglePlayback();
                return;
            end
        end

        if hasFrame(appData.videoObj)
            % Capture time before reading; CurrentTime advances after readFrame().
            realFrameTime = appData.videoObj.CurrentTime;
            frame = readFrame(appData.videoObj);
        else
            togglePlayback();
            return;
        end
    catch
        togglePlayback();
        return;
    end

    renderFrameWithTrack(frame, realFrameTime);

    idx = timeToFrameIndex(realFrameTime);
    appData.currentFrame = idx;
    appData.slider.Value = idx;
    appData.frameLabel.Value = idx;

    appData.lastFrameTime = tic;
    drawnow limitrate nocallbacks;
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
    switch event.Key
        case 'rightarrow'
            nextFrame();
        case 'leftarrow'
            prevFrame();
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

function closeFigure(src, ~)
    % Clean up timer if running
    if isfield(appData, 'timer') && ~isempty(appData.timer) && isvalid(appData.timer)
        stop(appData.timer);
        delete(appData.timer);
    end
    delete(src);
end

end