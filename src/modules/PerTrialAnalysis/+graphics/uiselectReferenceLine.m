function [fig, pointA, pointB] = uiselectReferenceLine(kvargs)
%%UISELECTREFERENCELINE Open a video frame to select a reference line for place preference analysis
%   This function opens a video file and allows the user to select two points (A and B) on the frame
%   that will define a reference line for place preference analysis.
%
%   This returns the figure handle and the two selected point coordinates.
%   The function also saves the reference line points to a .midline.csv file next to the video file.
%   CSV format: "x,y\n<value_x_A>,<value_y_A>\n<value_x_B>,<value_y_B>\n"
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
referenceLineFilePath = fullfile(videoDir, strcat(videoBaseName, '.midline.csv'));

v = VideoReader(videoFilePath);
% Read the specified frame
v.CurrentTime = (videoFrameNumber - 1) / v.FrameRate;
vidWidth = v.Width;
vidHeight = v.Height;
frame = readFrame(v);

% Default: vertical line at center X, point A at 15% Y, point B at 85% Y
centerX = vidWidth / 2;
pointA = [centerX, vidHeight * 0.15];
pointB = [centerX, vidHeight * 0.85];

% If referenceline file exists, load that as default
if ~isfile(referenceLineFilePath)
    % Find any existing referenceline files in the same directory and use that as default
    referenceLineFiles = dir(fullfile(videoDir, '*.midline.csv'));
    if ~isempty(referenceLineFiles)
        referenceLineFilePath = fullfile(videoDir, referenceLineFiles(end).name);
    end
end
if isfile(referenceLineFilePath)
    try
        lineData = readtable(referenceLineFilePath);
        if all(ismember({'x', 'y'}, lineData.Properties.VariableNames)) && height(lineData) >= 2
            pointA = [lineData.x(1), lineData.y(1)];
            pointB = [lineData.x(2), lineData.y(2)];
        end
    catch ME
        warning('UISELECTREFERENCELINE:LoadError', 'Error loading existing referenceline file: %s\nUsing default vertical line.\n%s', referenceLineFilePath, ME.message);
    end
end
% Reset the referenceLineFilePath to the current video file's referenceline file (to be saved later)
referenceLineFilePath = fullfile(videoDir, strcat(videoBaseName, '.midline.csv'));

name = strcat(header("Experiment"), " - ", header("Trial name"));
name = strcat(name, " @ ", string(arenaName));

[screensize, videoaspect] = deal(get(0, 'ScreenSize'), vidWidth / vidHeight);
extendHeight = 90; % title offset
[figW, figH] = ui.dynamicFigureSize(videoaspect, extendHeight);
figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

fig = figure('Name', sprintf('Select Reference Line - %s', name), 'NumberTitle', 'off', 'Position', figPos, 'Units', 'pixels');
t = tiledlayout(1,1, 'TileSpacing', 'none', 'Padding', 'none');
t.Position = [0 0 1 1]; % Ensure tiledlayout fills entire figure
ax = nexttile(t);
i = imshow(frame, 'Parent', ax);
set(i, 'HitTest', 'off'); % Disable image hit test to allow axes click detection
set(ax, 'PickableParts', 'all'); % Ensure axes can receive clicks
axis(ax, 'image'); % Maintain aspect ratio
title(ax, sprintf('Select Reference Line for %s\n(Drag points A and B, close window when done)', name), 'Interpreter', 'none');
hold(ax, 'on');

% Calculate and draw the extended line
[lineX, lineY] = calculateExtendedLine(pointA, pointB, vidWidth, vidHeight);
lineHandle = plot(ax, lineX, lineY, 'g-', 'LineWidth', 2, 'HitTest', 'on');

% Create markers at points A and B (larger size for better hitbox)
markerA = plot(ax, pointA(1), pointA(2), 'ro', 'MarkerSize', 14, 'LineWidth', 2, 'MarkerFaceColor', 'r');
markerB = plot(ax, pointB(1), pointB(2), 'bs', 'MarkerSize', 14, 'LineWidth', 2, 'MarkerFaceColor', 'b');

% Add text labels for points
textA = text(ax, pointA(1), pointA(2), ' A', 'Color', 'red', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom', 'HitTest', 'off');
textB = text(ax, pointB(1), pointB(2), ' B', 'Color', 'blue', 'FontSize', 14, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom', 'HitTest', 'off');

% Store state in figure UserData
figData = struct('pointA', pointA, 'pointB', pointB, 'userInteracted', false, ...
    'dragging', false, 'draggedPoint', '', 'vidWidth', vidWidth, 'vidHeight', vidHeight, ...
    'dragStartPos', []);
set(fig, 'UserData', figData);

% Set up mouse callbacks for dragging
set(markerA, 'ButtonDownFcn', @(src, event) startDrag(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath, 'A'));
set(markerB, 'ButtonDownFcn', @(src, event) startDrag(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath, 'B'));
set(lineHandle, 'ButtonDownFcn', @(src, event) startDragLine(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath));
set(fig, 'WindowButtonMotionFcn', @(src, event) dragPoint(src, event, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath));
set(fig, 'WindowButtonUpFcn', @(src, event) stopDrag(src, event, referenceLineFilePath));

% Set up scroll wheel zoom callback
set(fig, 'WindowScrollWheelFcn', @(src, event) scrollWheelCallback(src, event, ax));

% Set up figure close callback to save the final reference line
set(fig, 'CloseRequestFcn', @(src, event) figureCloseCallback(src, event, referenceLineFilePath));

% Wait for figure to close and get the final points
waitfor(fig);

% Retrieve the final points from base workspace
if evalin('base', 'exist(''uiselectReferenceLine_resultA'', ''var'')')
    pointA = evalin('base', 'uiselectReferenceLine_resultA');
    evalin('base', 'clear uiselectReferenceLine_resultA');
end
if evalin('base', 'exist(''uiselectReferenceLine_resultB'', ''var'')')
    pointB = evalin('base', 'uiselectReferenceLine_resultB');
    evalin('base', 'clear uiselectReferenceLine_resultB');
end

end


function [lineX, lineY] = calculateExtendedLine(pointA, pointB, vidWidth, vidHeight)
    % Calculate a line that goes through points A and B and extends to the edge of the frame
    
    % Handle vertical line case
    if abs(pointB(1) - pointA(1)) < 1e-6
        lineX = [pointA(1), pointA(1)];
        lineY = [0.5, vidHeight + 0.5];
        return;
    end
    
    % Calculate line equation: y = mx + c
    m = (pointB(2) - pointA(2)) / (pointB(1) - pointA(1));
    c = pointA(2) - m * pointA(1);
    
    % Find intersections with frame boundaries
    intersections = [];
    
    % Left edge (x = 0.5)
    y_left = m * 0.5 + c;
    if y_left >= 0.5 && y_left <= vidHeight + 0.5
        intersections(end+1, :) = [0.5, y_left];
    end
    
    % Right edge (x = vidWidth + 0.5)
    y_right = m * (vidWidth + 0.5) + c;
    if y_right >= 0.5 && y_right <= vidHeight + 0.5
        intersections(end+1, :) = [vidWidth + 0.5, y_right];
    end
    
    % Top edge (y = 0.5)
    x_top = (0.5 - c) / m;
    if x_top >= 0.5 && x_top <= vidWidth + 0.5
        intersections(end+1, :) = [x_top, 0.5];
    end
    
    % Bottom edge (y = vidHeight + 0.5)
    x_bottom = (vidHeight + 0.5 - c) / m;
    if x_bottom >= 0.5 && x_bottom <= vidWidth + 0.5
        intersections(end+1, :) = [x_bottom, vidHeight + 0.5];
    end
    
    % Use the two intersection points (should be exactly 2)
    if size(intersections, 1) >= 2
        lineX = [intersections(1, 1), intersections(2, 1)];
        lineY = [intersections(1, 2), intersections(2, 2)];
    else
        % Fallback: just draw line between A and B
        lineX = [pointA(1), pointB(1)];
        lineY = [pointA(2), pointB(2)];
    end
end


function startDrag(~, ~, fig, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath, pointName)
    % Start dragging a point
    figData = get(fig, 'UserData');
    figData.dragging = true;
    figData.draggedPoint = pointName;
    figData.dragStartPos = [];
    set(fig, 'UserData', figData);
    
    % Immediately trigger dragPoint to start dragging without requiring mouse movement
    dragPoint([], [], ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath);
end


function startDragLine(~, ~, fig, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath)
    % Start dragging the entire line
    figData = get(fig, 'UserData');
    currentPoint = get(ax, 'CurrentPoint');
    figData.dragging = true;
    figData.draggedPoint = 'LINE';
    figData.dragStartPos = [currentPoint(1,1), currentPoint(1,2)];
    set(fig, 'UserData', figData);
    
    % Immediately trigger dragPoint to start dragging without requiring mouse movement
    dragPoint([], [], ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath);
end


function dragPoint(~, ~, ax, markerA, markerB, lineHandle, textA, textB, referenceLineFilePath) %#ok<INUSD>
    % Update point position while dragging
    fig = ancestor(ax, 'figure');
    figData = get(fig, 'UserData');
    
    if figData.dragging
        % Set cursor to dragging state
        set(fig, 'Pointer', 'fleur');
        
        % Get current mouse position in axes coordinates
        currentPoint = get(ax, 'CurrentPoint');
        newPos = [currentPoint(1,1), currentPoint(1,2)];
        
        % Update the appropriate point or translate the line
        if strcmp(figData.draggedPoint, 'A')
            figData.pointA = newPos;
            set(markerA, 'XData', newPos(1), 'YData', newPos(2));
            set(textA, 'Position', [newPos(1), newPos(2), 0]);
        elseif strcmp(figData.draggedPoint, 'B')
            figData.pointB = newPos;
            set(markerB, 'XData', newPos(1), 'YData', newPos(2));
            set(textB, 'Position', [newPos(1), newPos(2), 0]);
        elseif strcmp(figData.draggedPoint, 'LINE')
            % Calculate offset from drag start position
            offset = newPos - figData.dragStartPos;
            
            % Translate both points
            figData.pointA = figData.pointA + offset;
            figData.pointB = figData.pointB + offset;
            figData.dragStartPos = newPos; % Update start position for next frame
            
            % Update markers
            set(markerA, 'XData', figData.pointA(1), 'YData', figData.pointA(2));
            set(markerB, 'XData', figData.pointB(1), 'YData', figData.pointB(2));
            set(textA, 'Position', [figData.pointA(1), figData.pointA(2), 0]);
            set(textB, 'Position', [figData.pointB(1), figData.pointB(2), 0]);
        end
        
        % Recalculate and update the line
        [lineX, lineY] = calculateExtendedLine(figData.pointA, figData.pointB, figData.vidWidth, figData.vidHeight);
        set(lineHandle, 'XData', lineX, 'YData', lineY);
        
        % Update title with current coordinates
        title(ax, sprintf('Point A: (%.1f, %.1f) px, Point B: (%.1f, %.1f) px\nDrag points to adjust, close window when done', ...
            figData.pointA(1), figData.pointA(2), figData.pointB(1), figData.pointB(2)), 'Interpreter', 'none');
        
        % Mark as user interacted
        figData.userInteracted = true;
        set(fig, 'UserData', figData);
    else
        % Check if mouse is over a marker or line and update cursor accordingly
        currentPoint = get(ax, 'CurrentPoint');
        mousePos = [currentPoint(1,1), currentPoint(1,2)];
        
        % Get current marker positions
        pointA = [get(markerA, 'XData'), get(markerA, 'YData')];
        pointB = [get(markerB, 'XData'), get(markerB, 'YData')];
        
        % Calculate distance threshold based on marker size (in data units)
        % Estimate: MarkerSize 14 is roughly 10-15 pixels, adjust based on zoom
        xlims = xlim(ax);
        ylims = ylim(ax);
        xRange = xlims(2) - xlims(1);
        yRange = ylims(2) - ylims(1);
        figPos = get(fig, 'Position');
        pixelToDataX = xRange / figPos(3);
        pixelToDataY = yRange / figPos(4);
        threshold = 15 * max(pixelToDataX, pixelToDataY); % 15 pixels in data units
        
        % Check if mouse is near either marker
        distA = sqrt((mousePos(1) - pointA(1))^2 + (mousePos(2) - pointA(2))^2);
        distB = sqrt((mousePos(1) - pointB(1))^2 + (mousePos(2) - pointB(2))^2);
        
        % Check if mouse is near the line (perpendicular distance)
        isNearLine = false; %#ok<NASGU>
        if abs(pointB(1) - pointA(1)) < 1e-6
            % Vertical line
            distToLine = abs(mousePos(1) - pointA(1));
            onSegment = mousePos(2) >= min(pointA(2), pointB(2)) && mousePos(2) <= max(pointA(2), pointB(2));
            isNearLine = distToLine < threshold && onSegment;
        else
            % Calculate perpendicular distance to line
            dx = pointB(1) - pointA(1);
            dy = pointB(2) - pointA(2);
            distToLine = abs(dy * mousePos(1) - dx * mousePos(2) + pointB(1) * pointA(2) - pointB(2) * pointA(1)) / sqrt(dx^2 + dy^2);
            
            % Check if projection is within the extended line bounds (within frame)
            lineX = get(lineHandle, 'XData');
            lineY = get(lineHandle, 'YData');
            minX = min(lineX);
            maxX = max(lineX);
            minY = min(lineY);
            maxY = max(lineY);
            onSegment = mousePos(1) >= minX && mousePos(1) <= maxX && mousePos(2) >= minY && mousePos(2) <= maxY;
            
            isNearLine = distToLine < threshold && onSegment;
        end
        
        if distA < threshold || distB < threshold || isNearLine
            set(fig, 'Pointer', 'fleur');
        else
            set(fig, 'Pointer', 'arrow');
        end
    end
end


function stopDrag(src, ~, referenceLineFilePath)
    % Stop dragging and save the new positions
    figData = get(src, 'UserData');
    
    if figData.dragging
        figData.dragging = false;
        figData.draggedPoint = '';
        set(src, 'UserData', figData);
        
        % Reset cursor to arrow
        set(src, 'Pointer', 'arrow');
        
        % Save to file after drag is complete
        saveReferenceLineToFile(figData.pointA, figData.pointB, referenceLineFilePath);
    end
end


function figureCloseCallback(src, ~, referenceLineFilePath)
    % Get the final points from figure data
    figData = get(src, 'UserData');
    
    if ~isempty(figData) && isfield(figData, 'pointA') && isfield(figData, 'pointB')
        finalPointA = figData.pointA;
        finalPointB = figData.pointB;
        
        % Always save to file on close
        saveReferenceLineToFile(finalPointA, finalPointB, referenceLineFilePath);
        
        % Store in base workspace for return, these will be cleared after retrieval
        assignin('base', 'uiselectReferenceLine_resultA', finalPointA);
        assignin('base', 'uiselectReferenceLine_resultB', finalPointB);
    end
    
    % Close the figure
    delete(src);
end


function saveReferenceLineToFile(pointA, pointB, referenceLineFilePath)
    % Save the reference line points to CSV file
    % CSV format: "x,y\n<value_x_A>,<value_y_A>\n<value_x_B>,<value_y_B>\n"
    try
        fileID = fopen(referenceLineFilePath, 'w');
        if fileID == -1
            warning('Could not open file for writing: %s', referenceLineFilePath);
            return;
        end
        fprintf(fileID, 'x,y\n%.6f,%.6f\n%.6f,%.6f\n', pointA(1), pointA(2), pointB(1), pointB(2));
        fclose(fileID);
    catch ME
        warning('UISELECTREFERENCELINE:SaveError', 'Error saving reference line to file: %s', ME.message);
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
