function [fig, referencePoint] = uiselectReferencePoint(kvargs)
%%UISELECTREFERENCEPOINT Open a video frame to select a reference point for place preference analysis
%   This function opens a video file and allows the user to select a point on the frame
%   that will be used as a reference point for calculating distances relative to in place preference analysis.
%
%   This returns the figure handle and the selected reference point coordinates.
%   The function also saves the reference point to a .midpoint.csv file next to the video file.
%   CSV format: "x,y\n<value_x>,<value_y>\n"
%
%   If MasterMetadataTable, TrackingDataFile, and TrackingProvider are provided, the function will use the first frame with stimulus onset as the default frame to display instead of the first frame in video.
%

arguments
    kvargs.VideoFile {mustBeFile}
    kvargs.TrackingDataFile {validator.mustBeFileOrEmpty} = []
    kvargs.TrackingProvider {validator.mustBeTrackingProviderOrEmpty} = []
    kvargs.MasterMetadataTable {validator.mustBeFileTableOrEmpty} = []
end

videoFrameNumber = 1; % Default to first frame unless Metadata exists, then select the first frame with stim
if ~isempty(kvargs.MasterMetadataTable) && ~isempty(kvargs.TrackingDataFile) && ~isempty(kvargs.TrackingProvider)
    masterMetadata = table();
    if istable(kvargs.MasterMetadataTable)
        [bool, missingHeaders] = io.metadata.isMasterMetadataTable(kvargs.MasterMetadataTable);
        if ~bool
            error('The provided MasterMetadataTable does not contain a valid master metadata table. Missing headers: {'' %s ''}', strjoin(missingHeaders, ''', '''));
        end
        masterMetadata = kvargs.MasterMetadataTable;
    elseif ~isempty(kvargs.MasterMetadataTable)
        masterMetadata = io.metadata.loadMasterMetadata(kvargs.MasterMetadataTable);
    end
    [header, ~, ~] = kvargs.TrackingProvider.loadTrackingData(kvargs.TrackingDataFile, Options=struct('HeaderOnly', true));
    trialName = header("Trial name");
    trialParts = split(trialName, ' ');
    trialNumber = str2double(strtrim(trialParts{end}));
    experimentName = header("Experiment");
    arenaName = header("Arena name"); % just to make sure the arena name is exactly as how it was exported
    if istable(masterMetadata) && ~isempty(masterMetadata)
        trialMask = (masterMetadata.ETHOVISION_TRIAL == trialNumber) & ...
            (masterMetadata.ETHOVISION_FILE == experimentName) & ...
            (masterMetadata.ETHOVISION_ARENA == arenaName);
        trialRowIdx = find(trialMask, 1);
        metadataRow = masterMetadata(trialRowIdx, :);
        if ismember('STIM_START_FRAME', masterMetadata.Properties.VariableNames)
            stimStartVal = metadataRow.('STIM_START_FRAME');
            if ~isnumeric(stimStartVal)
                stimStartVal = str2double(string(stimStartVal));
            end
            if isnumeric(stimStartVal) && ~isnan(stimStartVal) && stimStartVal > 0
                videoFrameNumber = stimStartVal;
            end
        end
    end
end


videoFilePath = kvargs.VideoFile;
[videoDir, videoBaseName, ~] = fileparts(videoFilePath);
midPointFilePath = fullfile(videoDir, strcat(videoBaseName, '.midpoint.csv'));

v = VideoReader(videoFilePath);
% Read the specified frame
v.CurrentTime = (videoFrameNumber - 1) / v.FrameRate;
vidWidth = v.Width;
vidHeight = v.Height;
frame = readFrame(v);

referencePoint = [vidWidth/2, vidHeight/2]; % Default to center point of frame
% If midpoint file exists, load that as default reference point
if ~isfile(midPointFilePath)
    % Find any existing midpoint files in the same directory and use that as default
    midPointFiles = dir(fullfile(videoDir, '*.midpoint.csv'));
    if ~isempty(midPointFiles)
        midPointFilePath = fullfile(videoDir, midPointFiles(end).name);
    end
end
if isfile(midPointFilePath)
    try
        midpointData = readtable(midPointFilePath);
        if all(ismember({'x', 'y'}, midpointData.Properties.VariableNames))
            referencePoint = [midpointData.x(1), midpointData.y(1)];
        end
    catch ME
        warning('UISELECTREFERENCEPOINT:LoadError', 'Error loading existing midpoint file: %s\nUsing the center of the frame as default.\n%s', midPointFilePath, ME.message);
    end
end
% Reset the midPointFilePath to the current video file's midpoint file (to be saved later)
midPointFilePath = fullfile(videoDir, strcat(videoBaseName, '.midpoint.csv'));

name = strcat(header("Experiment"), " - ", header("Trial name"));
name = strcat(name, " @ ", string(arenaName));

[screensize, videoaspect] = deal(get(0, 'ScreenSize'), vidWidth / vidHeight);
extendHeight = 90; % title offset
[figW, figH] = ui.dynamicFigureSize(videoaspect, extendHeight);
figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

fig = figure('Name', sprintf('Select Reference Point - %s', name), 'NumberTitle', 'off', 'Position', figPos, 'Units', 'pixels');
t = tiledlayout(1,1, 'TileSpacing', 'none', 'Padding', 'none');
t.Position = [0 0 1 1]; % Ensure tiledlayout fills entire figure
ax = nexttile(t);
i = imshow(frame, 'Parent', ax);
set(i, 'HitTest', 'off'); % Disable image hit test to allow axes click detection
set(ax, 'PickableParts', 'all'); % Ensure axes can receive clicks
axis(ax, 'image'); % Maintain aspect ratio
title(ax, sprintf('Select Reference Point for %s\n(Click to select, close window when done)', name), 'Interpreter', 'none');
hold(ax, 'on');

% Create initial marker at default position (center)
markerHandle = plot(ax, referencePoint(1), referencePoint(2), 'r+', 'MarkerSize', 18, 'LineWidth', 2, 'HitTest', 'off');

% Store initial state in figure UserData
figData = struct('referencePoint', referencePoint, 'userInteracted', false);
set(fig, 'UserData', figData);

% Set up click callback for the axes
set(ax, 'ButtonDownFcn', @(src, event) axesClickCallback(src, event, ax, markerHandle, midPointFilePath, fig));

% Set up scroll wheel zoom callback
set(fig, 'WindowScrollWheelFcn', @(src, event) scrollWheelCallback(src, event, ax));

% Set up figure close callback to save the final reference point
set(fig, 'CloseRequestFcn', @(src, event) figureCloseCallback(src, event, midPointFilePath));

% Wait for figure to close and get the final reference point
waitfor(fig);

% Retrieve the final reference point from base workspace
if evalin('base', 'exist(''uiselectReferencePoint_result'', ''var'')')
    referencePoint = evalin('base', 'uiselectReferencePoint_result');
    evalin('base', 'clear uiselectReferencePoint_result');
end

end



function axesClickCallback(~, ~, ax, markerHandle, midPointFilePath, fig)
    % Get the current point where the user clicked
    currentPoint = get(ax, 'CurrentPoint');
    newReferencePoint = [currentPoint(1,1), currentPoint(1,2)];
    
    % Update the marker position
    set(markerHandle, 'XData', newReferencePoint(1), 'YData', newReferencePoint(2));
    
    % Store the new reference point in figure's UserData
    figData = get(fig, 'UserData');
    figData.referencePoint = newReferencePoint;
    figData.userInteracted = true;
    set(fig, 'UserData', figData);
    
    % Immediately save to file
    saveReferencePointToFile(newReferencePoint, midPointFilePath);
    
    % Update title to show coordinates
    title(ax, sprintf('Reference Point: (%.1f, %.1f) px\nClick to update, close window when done', newReferencePoint(1), newReferencePoint(2)), 'Interpreter', 'none');
end

function figureCloseCallback(src, ~, midPointFilePath)
    % Get the final reference point from figure data
    figData = get(src, 'UserData');
    
    if ~isempty(figData) && isfield(figData, 'referencePoint')
        finalReferencePoint = figData.referencePoint;
        
        % Only save to file if user has interacted
        % if figData.userInteracted
        %     saveReferencePointToFile(finalReferencePoint, midPointFilePath);
        % end

        % Always save to file on close
        saveReferencePointToFile(finalReferencePoint, midPointFilePath);

        % Store in base workspace for return, this will be cleared after retrieval
        assignin('base', 'uiselectReferencePoint_result', finalReferencePoint);
    end
    
    % Close the figure
    delete(src);
end

function saveReferencePointToFile(referencePoint, midPointFilePath)
    % Save the reference point to CSV file
    % CSV format: "x,y\n<value_x>,<value_y>\n"
    try
        fileID = fopen(midPointFilePath, 'w');
        if fileID == -1
            warning('Could not open file for writing: %s', midPointFilePath);
            return;
        end
        fprintf(fileID, 'x,y\n%.6f,%.6f\n', referencePoint(1), referencePoint(2));
        fclose(fileID);
    catch ME
        warning('UISELECTREFERENCEPOINT:SaveError', 'Error saving reference point to file: %s', ME.message);
    end
end

function scrollWheelCallback(~, event, ax)
    % Implement scroll wheel zoom functionality
    % event.VerticalScrollCount: positive = scroll down (zoom out), negative = scroll up (zoom in)
    
    zoomFactor = 1.1; % Zoom factor per scroll step
    scrollSteps = event.VerticalScrollCount;
    
    % Get original image size from the image object
    imageHandle = findobj(ax, 'Type', 'image');
    if ~isempty(imageHandle)
        imageData = get(imageHandle, 'CData');
        [originalHeight, originalWidth, ~] = size(imageData);
        originalXLims = [0.5, originalWidth + 0.5];
        originalYLims = [0.5, originalHeight + 0.5];
    else
        % Fallback if image handle not found
        originalXLims = [0.5, 640.5];
        originalYLims = [0.5, 480.5];
    end
    
    % Get current axes limits
    xlims = xlim(ax);
    ylims = ylim(ax);
    
    % Calculate current zoom level relative to original image size
    originalWidth = originalXLims(2) - originalXLims(1);
    originalHeight = originalYLims(2) - originalYLims(1);
    currentWidth = xlims(2) - xlims(1);
    currentHeight = ylims(2) - ylims(1);
    currentZoomX = originalWidth / currentWidth;
    currentZoomY = originalHeight / currentHeight;
    currentZoom = min(currentZoomX, currentZoomY); % Use the limiting dimension
    
    % Calculate zoom factor (negative scroll = zoom in, positive = zoom out)
    if scrollSteps < 0
        % Zoom in
        zoom = zoomFactor^(-scrollSteps);
    else
        % Zoom out
        zoom = 1 / (zoomFactor^scrollSteps);
    end
    
    % Calculate new zoom level
    newZoom = currentZoom * zoom;
    
    % If new zoom is <= 1 (at or beyond original size), center the image
    if newZoom <= 1
        xlim(ax, originalXLims);
        ylim(ax, originalYLims);
        return;
    end
    
    % Get current pointer position in axes coordinates
    currentPoint = get(ax, 'CurrentPoint');
    mouseX = currentPoint(1,1);
    mouseY = currentPoint(1,2);
    
    % Check if mouse is within the axes bounds
    if mouseX < xlims(1) || mouseX > xlims(2) || mouseY < ylims(1) || mouseY > ylims(2)
        % If mouse is outside axes, zoom around center
        mouseX = mean(xlims);
        mouseY = mean(ylims);
    end
    
    % Calculate new width and height
    newWidth = currentWidth / zoom;
    newHeight = currentHeight / zoom;
    
    % Calculate relative position of mouse in current view
    relX = (mouseX - xlims(1)) / currentWidth;
    relY = (mouseY - ylims(1)) / currentHeight;

    % Calculate new limits maintaining the relative mouse position
    newXLims = [mouseX - relX * newWidth, mouseX + (1 - relX) * newWidth];
    newYLims = [mouseY - relY * newHeight, mouseY + (1 - relY) * newHeight];
    
    % Set new limits
    xlim(ax, newXLims);
    ylim(ax, newYLims);
end