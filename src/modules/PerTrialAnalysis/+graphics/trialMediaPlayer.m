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
markCheckedStartFrameButton.Enable = ~isempty(triggerStartFrame);
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
    'frameTimestamps', frameTimestamps, 'frameTimestampEdges', [], 'overlayHandles', gobjects(0), ...
    'lastSeekTime', NaN, 'videoFile', fullPath, 'lastMKeyPressTime', NaT, 'doubleMWindowSec', 0.3);

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
    % Updates ref.json trigger_events first element to the current frame number
    % Sets trigger_events_start_validated to true
    % Copies the frame number to clipboard
    
    if isempty(triggerStartFrame)
        uialert(fig, 'No trigger event to mark. Please ensure a trigger event was detected first.', 'No Trigger Event');
        return;
    end
    
    currentFrameNum = appData.currentFrame;
    
    % Read current ref.json
    try
        if isfile(refJsonPath)
            refData = jsondecode(fileread(refJsonPath));
        else
            uialert(fig, 'Reference JSON file does not exist.', 'Error');
            return;
        end
    catch ME
        uialert(fig, sprintf('Error reading ref.json:\n%s', ME.message), 'Error');
        return;
    end
    
    % Ensure trigger_events exists and is not empty
    if ~isfield(refData, 'trigger_events') || isempty(refData.trigger_events)
        uialert(fig, 'No trigger events in ref.json.', 'Error');
        return;
    end
    
    triggerEventsLocal = refData.trigger_events;
    
    % Update the first event's start frame in the appropriate format
    try
        if isnumeric(triggerEventsLocal)
            vals = double(triggerEventsLocal);
            if isvector(vals) && numel(vals) == 2
                % Legacy format: [on off]
                vals(1) = currentFrameNum;
                refData.trigger_events = vals;
            elseif ismatrix(vals) && size(vals, 2) == 2
                % Matrix format: Nx2
                vals(1, 1) = currentFrameNum;
                refData.trigger_events = vals;
            else
                error('Unexpected trigger_events format (numeric but not vector or Nx2 matrix)');
            end
        elseif iscell(triggerEventsLocal) && ~isempty(triggerEventsLocal)
            % Cell array format
            firstEvent = triggerEventsLocal{1};
            if isnumeric(firstEvent)
                firstEvent = double(firstEvent);
                if numel(firstEvent) >= 1
                    firstEvent(1) = currentFrameNum;
                    triggerEventsLocal{1} = firstEvent;
                    refData.trigger_events = triggerEventsLocal;
                else
                    error('First event has invalid format (empty numeric array)');
                end
            else
                error('Unexpected first event format (not numeric)');
            end
        else
            error('Unexpected trigger_events format (not numeric or cell)');
        end
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
    
    % Update button color to green to indicate manual validation
    markCheckedStartFrameButton.BackgroundColor = [240, 255, 242]/255; % Light green for validated
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
        
        % Ensure trigger_events exists and update first event's start frame
        if ~isfield(refData, 'trigger_events') || isempty(refData.trigger_events)
            % Create default trigger event with just the start frame
            % Using the format [start, start] as a simple default
            refData.trigger_events = [stimStartFrame, stimStartFrame];
        else
            triggerEventsLocal = refData.trigger_events;
            
            % Update based on the format
            if isnumeric(triggerEventsLocal)
                vals = double(triggerEventsLocal);
                if isvector(vals)
                    % Vector format: update first element
                    vals(1) = stimStartFrame;
                    refData.trigger_events = vals;
                elseif ismatrix(vals)
                    % Matrix format: update first row, first column
                    vals(1, 1) = stimStartFrame;
                    refData.trigger_events = vals;
                end
            elseif iscell(triggerEventsLocal) && ~isempty(triggerEventsLocal)
                % Cell array format: update first event
                firstEvent = triggerEventsLocal{1};
                if isnumeric(firstEvent)
                    firstEvent = double(firstEvent);
                    if isempty(firstEvent)
                        firstEvent = [stimStartFrame, stimStartFrame];
                    else
                        firstEvent(1) = stimStartFrame;
                    end
                    triggerEventsLocal{1} = firstEvent;
                    refData.trigger_events = triggerEventsLocal;
                end
            end
        end
        
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