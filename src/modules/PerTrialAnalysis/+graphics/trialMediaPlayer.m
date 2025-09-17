function fig = trialMediaPlayer(kvargs)
%%TRIALMEDIAPLAYER - Launch a simple video player with optional Ethovision tracking overlay
% It includes a progress slider, a play/pause toggle, and a frame number display,
% Keyboard controls: Arrow keys (frame navigation), Space (play/pause), T (toggle tracking), F (fast mode), R (toggle FPS).
%
% Optional tracking overlay:
%   When EthovisionXlsx is provided, the function will overlay animal tracking
%   data on the video frames. The coordinate conversion follows the same logic
%   as trialHeatmap.m, converting Ethovision coordinates to pixel coordinates
%   using ImgWidthFOV_cm and CenterOffset_cm parameters.

arguments
    kvargs.VideoFile {mustBeFile}
    kvargs.EthovisionXlsx {mustBeFile}
    kvargs.ImgWidthFOV_cm (1,1) double {mustBePositive} = 58.5
    kvargs.CenterOffset_cm (1,2) double = [0,0]
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

% Try to load tracking data if EthovisionXlsx is provided
trackData = [];
pixelSize = [];
if isfield(kvargs, 'EthovisionXlsx') && ~isempty(kvargs.EthovisionXlsx) && isfile(kvargs.EthovisionXlsx)
    try
        [~, datatable, ~] = io.ethovision.loadEthovisionXlsx(kvargs.EthovisionXlsx);

        % Calculate pixel size based on field of view
        vidObj_temp = VideoReader(fullPath);
        vidWidth = vidObj_temp.Width;
        vidHeight = vidObj_temp.Height;
        pixelSize = kvargs.ImgWidthFOV_cm / vidWidth; % cm/pixel

        xCenter = datatable{:, 'X center'};
        yCenter = datatable{:, 'Y center'};

        % Convert from Ethovision coordinates to pixel coordinates
        xPixel = xCenter + (vidWidth/2 * pixelSize) + kvargs.CenterOffset_cm(1);
        yPixel = yCenter + (vidHeight/2 * pixelSize) + kvargs.CenterOffset_cm(2);

        % Scale to pixel coordinates
        xPixel = xPixel / pixelSize;
        yPixel = yPixel / pixelSize;
        yPixel = vidHeight - yPixel; % Flip Y coordinates for image coordinate system

        % Store track data aligned with frame numbers
        trackData = [xPixel, yPixel];
    catch ME
        warning('EthoPlacePreference:LoadError', 'Failed to load Ethovision data: %s', ME.message);
        trackData = [];
    end
end


try
    videoObj = VideoReader(fullPath);
    frameRate = videoObj.FrameRate;
    totalFrames = videoObj.NumFrames;
catch
    uialert(uifigure, 'Error: Could not read the video file. Please check the file format and permissions.', 'Error');
    return;
end

screensize = get(0, 'ScreenSize');
figPos = [(screensize(3)-screensize(3)*0.6)/2, (screensize(4)-screensize(4)*0.7)/2, screensize(3)*0.6, screensize(4)*0.7];
[folder, name, ~] = fileparts(fullPath);
[~, folder] = fileparts(fileparts(folder));
fig = uifigure('Name', sprintf("%s - %s", folder, name), 'Position', figPos, ...
    'CloseRequestFcn', @(src, event) closeFigure(src, event));

mainGrid = uigridlayout(fig, [4 1]);
% Main video, frame label, play button, slider+nav buttons
mainGrid.RowHeight = {'1x', "fit", 32, 42};
mainGrid.ColumnWidth = {'1x'};
mainGrid.Padding = [10 10 10 10];

videoAxes = uiaxes(mainGrid);
videoAxes.Layout.Row = 1;
videoAxes.Layout.Column = 1;
videoAxes.Interactions = [];
videoAxes.Visible = 'off';
videoAxes.Toolbar.Visible = 'Off';
disableDefaultInteractivity(videoAxes);
videoAxes.DataAspectRatioMode = 'manual';
videoAxes.PlotBoxAspectRatioMode = 'manual';
videoAxes.BusyAction='cancel';
videoAxes.Interruptible='on';
videoAxes.HitTest='off';
videoAxes.PickableParts="none";

% Center the axes content and remove any default margins
videoAxes.Position = [0 0 1 1]; % Fill the entire grid cell
videoAxes.OuterPosition = [0 0 1 1]; % Remove outer margins

frameLabel = uilabel(mainGrid, 'Text', 'Frame: 1');
frameLabel.Layout.Row = 2;
frameLabel.Layout.Column = 1;
frameLabel.FontWeight = 'bold';
frameLabel.HorizontalAlignment = 'center';

playButton = uibutton(mainGrid, 'Text', 'Play', 'ButtonPushedFcn', @(btn, event) togglePlayback);
playButton.Layout.Row = 3;
playButton.Layout.Column = 1;
controlsGrid = uigridlayout(mainGrid, [1 3]);
controlsGrid.Layout.Row = 4;
controlsGrid.Layout.Column = 1;
controlsGrid.ColumnWidth = {'fit', '1x', 'fit'};
controlsGrid.ColumnSpacing = 4;
controlsGrid.Padding = [0 0 0 0];
prevButton = uibutton(controlsGrid, 'Text', '<', 'ButtonPushedFcn', @(btn, event) prevFrame);
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

nextButton = uibutton(controlsGrid, 'Text', '>', 'ButtonPushedFcn', @(btn, event) nextFrame);
nextButton.Layout.Row = 1;
nextButton.Layout.Column = 3;


appData = struct('videoObj', videoObj, 'slider', slider, 'frameLabel', frameLabel, ...
    'videoAxes', videoAxes, 'isPlaying', false, 'currentFrame', 1, 'timer', [], ...
    'trackData', trackData, 'pixelSize', pixelSize, 'lastFrameTime', tic, ...
    'showTracking', true, 'fastMode', false, 'showFps', false, ...
    'fpsHistory', [repmat(frameRate, 1, round(frameRate))], 'fpsTextHandle', [], 'frameCount', 0, 'startTime', tic);


% Set up a keyboard listener on the figure
set(fig, 'WindowKeyPressFcn', @keyPressCallback);
displayFrameWithTrack(1); % Show first frame with tracking overlay
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

function displayFrameWithTrack(frameNum)
    frame = read(appData.videoObj, frameNum);
    imshow(frame, 'Parent', appData.videoAxes);

    % Draw tracking data if available and enabled
    if ~isempty(appData.trackData) && frameNum <= size(appData.trackData, 1) && appData.showTracking
        hold(appData.videoAxes, 'on');

        % Draw the trail of the last N frames
        trackHistoryLength = 125;
        startIdx = max(1, frameNum - trackHistoryLength);
        endIdx = min(frameNum, size(appData.trackData, 1));

        if endIdx > startIdx
            xTrack = appData.trackData(startIdx:endIdx, 1);
            yTrack = appData.trackData(startIdx:endIdx, 2);

            % Remove NaN values but keep track of original indices for color mapping
            validIdx = ~isnan(xTrack) & ~isnan(yTrack);

            if any(validIdx)
                xValid = xTrack(validIdx);
                yValid = yTrack(validIdx);

                numPoints = length(xValid);
                if numPoints > 1
                    % Create matrices for all line segments
                    x_segments = [xValid(1:end-1), xValid(2:end)]';
                    y_segments = [yValid(1:end-1), yValid(2:end)]';

                    % Pre-compute all colors and properties
                    segmentIndices = (1:numPoints-1) / (numPoints-1); % Normalize to [0,1]
                    colors = [segmentIndices', zeros(numPoints-1, 1), 1-segmentIndices']; % Blue to red
                    alphas = 0.3 + 0.7 * segmentIndices'; % Progressive alpha
                    lineWidths = 1 + 2 * segmentIndices'; % Progressive width

                    x_plot = [x_segments; NaN(1, size(x_segments, 2))];
                    y_plot = [y_segments; NaN(1, size(y_segments, 2))];

                    % Plot segments in batches by line width to reduce plot calls
                    if appData.fastMode
                        meanColor = mean(colors, 1);
                        meanAlpha = mean(alphas);
                        meanWidth = mean(lineWidths);
                        line(appData.videoAxes, x_plot(:), y_plot(:), ...
                            'Color', [meanColor, meanAlpha], 'LineWidth', meanWidth);
                    else
                        uniqueWidths = unique(round(lineWidths * 2) / 2);

                        for w = uniqueWidths'
                            widthMask = abs(lineWidths - w) < 0.25;
                            if any(widthMask)
                                % Get segments for this width
                                batchX = x_plot(:, widthMask);
                                batchY = y_plot(:, widthMask);
                                batchColors = colors(widthMask, :);
                                batchAlphas = alphas(widthMask);

                                % Use mean color and alpha for this batch
                                meanColor = mean(batchColors, 1);
                                meanAlpha = mean(batchAlphas);

                                line(appData.videoAxes, batchX(:), batchY(:), ...
                                    'Color', [meanColor, meanAlpha], 'LineWidth', w);
                            end
                        end
                    end
                end

                % Plot current position as a circle if within bounds
                if frameNum <= size(appData.trackData, 1) && ...
                        ~isnan(appData.trackData(frameNum, 1)) && ~isnan(appData.trackData(frameNum, 2))
                    currentX = appData.trackData(frameNum, 1);
                    currentY = appData.trackData(frameNum, 2);

                    % Check if position is within video bounds
                    if currentX > 0 && currentX <= size(frame, 2) && ...
                            currentY > 0 && currentY <= size(frame, 1)
                        plot(appData.videoAxes, currentX, currentY, ...
                            'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'red', ...
                            'MarkerEdgeColor', 'white', 'LineWidth', 2);
                    end
                end
            end
        end

        hold(appData.videoAxes, 'off');
    end

    % Update FPS display overlay
    updateFpsDisplay();
end

function togglePlayback()
    if appData.isPlaying
        % Stop playback
        appData.isPlaying = false;
        stop(appData.timer);
        playButton.Text = 'Play';

        slider.ValueChangingFcn = @(source, event) slider_callback(event.Value);
    else
        % Start playback
        appData.isPlaying = true;
        playButton.Text = 'Pause';

        % Reset FPS counter for accurate measurement
        appData.frameCount = 0;
        appData.startTime = tic;
        appData.fpsHistory = [repmat(frameRate, 1, round(frameRate))]; % Reset history

        % Slider value-changing callback will pause playback and jump
        slider.ValueChangingFcn = @(source, event) pauseAndJump(event.Value);
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
    if ~isvalid(fig) || appData.currentFrame > totalFrames
        togglePlayback();
        return;
    end

    targetFrameTime = 1/frameRate;
    elapsedTime = toc(appData.lastFrameTime);

    % Only render every few frames if we're behind
    shouldRender = (elapsedTime >= targetFrameTime * 0.8) || ...
        (mod(appData.currentFrame, max(1, floor(elapsedTime / targetFrameTime))) == 0);

    if shouldRender
        % Display the frame with tracking overlay
        displayFrameWithTrack(appData.currentFrame);

        % Update the UI elements
        appData.slider.Value = appData.currentFrame;
        appData.frameLabel.Text = ['Frame: ' num2str(appData.currentFrame)];

        appData.lastFrameTime = tic;
        drawnow;
    end

    frameSkip = max(1, min(5, floor(elapsedTime / targetFrameTime))); % Skip up to 5 frames
    appData.currentFrame = appData.currentFrame + frameSkip;
end

function pauseAndJump(newValue)
    % This function is called when the user drags the slider
    appData.isPlaying = false;
    stop(appData.timer);
    playButton.Text = 'Play';

    appData.currentFrame = round(newValue);
    displayFrameWithTrack(appData.currentFrame);

    appData.frameLabel.Text = ['Frame: ' num2str(appData.currentFrame)];
end

function slider_callback(newValue)
    % Final callback after the user lets go of the slider
    appData.currentFrame = round(newValue);
    displayFrameWithTrack(appData.currentFrame);

    appData.frameLabel.Text = ['Frame: ' num2str(appData.currentFrame)];
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
                displayFrameWithTrack(appData.currentFrame);
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
                displayFrameWithTrack(appData.currentFrame);
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
        stop(appData.timer);
        playButton.Text = 'Play';
        appData.currentFrame = appData.currentFrame + 1;
        displayFrameWithTrack(appData.currentFrame);
        appData.slider.Value = appData.currentFrame;
        appData.frameLabel.Text = ['Frame: ' num2str(appData.currentFrame)];
    end
end
function prevFrame()
    % Go back one frame
    if appData.currentFrame > 1
        % Pause playback and then go back
        appData.isPlaying = false;
        stop(appData.timer);
        playButton.Text = 'Play';
        appData.currentFrame = appData.currentFrame - 1;
        displayFrameWithTrack(appData.currentFrame);
        appData.slider.Value = appData.currentFrame;
        appData.frameLabel.Text = ['Frame: ' num2str(appData.currentFrame)];
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
