function [fig, pointA, pointB] = uiselectReferenceLine(kvargs)
%%UISELECTREFERENCELINE Open a video frame to select a reference line for place preference analysis
%   This function opens a video file and allows the user to select two points (A and B) on the frame
%   that will define a reference line for place preference analysis.
%
%   This returns the figure handle and the two selected point coordinates.
%   The function also saves the reference line points to a .ref.json file next to the video file.
%    JSON format: {"midline": {"x": [<value_x_A>, <value_x_B>], "y": [<value_y_A>, <value_y_B>]}}
%    CSV format (legacy): "x,y\n<value_x_A>,<value_y_A>\n<value_x_B>,<value_y_B>\n"
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

arenaGridMode = kvargs.TrackingProvider.userConfig.arena_grid_mode;
arenaGridConfig = kvargs.TrackingProvider.userConfig.arena_grid;
n_tiles = arenaGridConfig.n_tiles;
n_vertices = 4;
if isfield(arenaGridConfig, 'n_vertices')
    n_vertices = arenaGridConfig.n_vertices;
end
if iscell(n_vertices)
    n_vertices = cell2mat(n_vertices);
end
if isempty(n_vertices) || ~isnumeric(n_vertices)
    n_vertices = 4;
end
n_vertices = max(1, round(n_vertices(1)));

xGradientFn = "linear";
yGradientFn = "linear";
xGradientVals = [-1, 0, 1];
yGradientVals = [0.5, 1, 0.5];

if isfield(arenaGridConfig, 'score_x_gradient_function') && ~isempty(arenaGridConfig.score_x_gradient_function)
    xGradientFn = string(arenaGridConfig.score_x_gradient_function);
end
if isfield(arenaGridConfig, 'score_y_gradient_function') && ~isempty(arenaGridConfig.score_y_gradient_function)
    yGradientFn = string(arenaGridConfig.score_y_gradient_function);
end
if isfield(arenaGridConfig, 'score_x_gradient') && ~isempty(arenaGridConfig.score_x_gradient)
    xGradientVals = toNumericVector(arenaGridConfig.score_x_gradient, [-1, 0, 1]);
end
if isfield(arenaGridConfig, 'score_y_gradient') && ~isempty(arenaGridConfig.score_y_gradient)
    yGradientVals = toNumericVector(arenaGridConfig.score_y_gradient, [0.5, 1, 0.5]);
end

if numel(xGradientVals) < 2
    xGradientVals = [-1, 0, 1];
end
if numel(yGradientVals) < 2
    yGradientVals = [0.5, 1, 0.5];
end

gradientConfig = struct('xFunction', lower(string(xGradientFn)), 'yFunction', lower(string(yGradientFn)), ...
    'xValues', xGradientVals(:)', 'yValues', yGradientVals(:)');

includeDetailedArenaGridExport = false;
if isfield(arenaGridConfig, 'export_detailed') && ~isempty(arenaGridConfig.export_detailed)
    includeDetailedArenaGridExport = logical(arenaGridConfig.export_detailed);
end


videoFilePath = kvargs.VideoFile;
[videoDir, videoBaseName, ~] = fileparts(videoFilePath);
referenceLineFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

% Upgrade any legacy .midline.csv files in the folder to per-video .ref.json files.
graphics.migrateLegacyCSVRefs2JSON(videoDir);

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
meshVerticesSeed = zeros(0, 2);

% If current video's .ref.json does not exist, use any existing .ref.json as seed.
referenceLineSeedFilePath = referenceLineFilePath;
if ~isfile(referenceLineSeedFilePath)
    referenceLineFiles = dir(fullfile(videoDir, '*.ref.json'));
    if ~isempty(referenceLineFiles)
        referenceLineSeedFilePath = fullfile(videoDir, referenceLineFiles(end).name);
    end
end

if isfile(referenceLineSeedFilePath)
    try
        jsonData = jsondecode(fileread(referenceLineSeedFilePath));
        % midline points should be in struct data.midline.x and data.midline.y as 2-element vectors
        if isfield(jsonData, 'midline') && isfield(jsonData.midline, 'x') && isfield(jsonData.midline, 'y')
            if numel(jsonData.midline.x) >= 2 && numel(jsonData.midline.y) >= 2
                pointA = [jsonData.midline.x(1), jsonData.midline.y(1)];
                pointB = [jsonData.midline.x(2), jsonData.midline.y(2)];
            end
        end
        if isfield(jsonData, 'arena_grid') && isstruct(jsonData.arena_grid) && isfield(jsonData.arena_grid, 'vertices')
            meshVerticesSeed = validateMeshVertices(jsonData.arena_grid.vertices);
        end
    catch ME
        warning('UISELECTREFERENCELINE:LoadError', 'Error loading existing referenceline file: %s\nUsing default vertical line.\n%s', referenceLineSeedFilePath, ME.message);
    end
end

% Mesh seed chain (same folder):
% 1) current video's .ref.json if present and valid
% 2) any other .ref.json with valid arena_grid.vertices
% 3) default mesh (handled later)
if isempty(meshVerticesSeed)
    meshSeedFilePath = referenceLineFilePath;
    if isfile(meshSeedFilePath)
        try
            meshJsonData = jsondecode(fileread(meshSeedFilePath));
            if isfield(meshJsonData, 'arena_grid') && isstruct(meshJsonData.arena_grid) && isfield(meshJsonData.arena_grid, 'vertices')
                meshVerticesSeed = validateMeshVertices(meshJsonData.arena_grid.vertices);
            end
        catch
            % Ignore malformed mesh seed files and continue fallback.
        end
    end

    if isempty(meshVerticesSeed)
        referenceLineFiles = dir(fullfile(videoDir, '*.ref.json'));
        for i = numel(referenceLineFiles):-1:1
            candidatePath = fullfile(videoDir, referenceLineFiles(i).name);
            if strcmp(candidatePath, referenceLineFilePath)
                continue;
            end
            try
                meshJsonData = jsondecode(fileread(candidatePath));
                if isfield(meshJsonData, 'arena_grid') && isstruct(meshJsonData.arena_grid) && isfield(meshJsonData.arena_grid, 'vertices')
                    candidateVertices = validateMeshVertices(meshJsonData.arena_grid.vertices);
                    if ~isempty(candidateVertices)
                        meshVerticesSeed = candidateVertices;
                        break;
                    end
                end
            catch
                % Ignore malformed candidate files and continue fallback.
            end
        end
    end
end
% Reset the referenceLineFilePath to the current video file's referenceline file (to be saved later)
referenceLineFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

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

isManualArenaGrid = strcmpi(string(arenaGridMode), "manual");
meshLineHandles = gobjects(0);
meshMarkerHandles = gobjects(0);
meshGradientHandle = gobjects(0);

% Draw a draggable manual mesh first so the midline stays visually on top.
if isManualArenaGrid
    [meshVertices, nTilesValidated] = createDefaultManualMesh(vidWidth, vidHeight, n_vertices, n_tiles);
    if ~isempty(meshVerticesSeed)
        meshVertices = meshVerticesSeed;
    end
    meshGradientHandle = drawManualMeshGradient(ax, meshVertices, nTilesValidated, gradientConfig, pointA, pointB);
    meshLineHandles = gobjects(0); % Use interpolated patch edges instead of separate line overlays.
    meshMarkerHandles = gobjects(size(meshVertices, 1), 1);
    for k = 1:size(meshVertices, 1)
        meshMarkerHandles(k) = plot(ax, meshVertices(k,1), meshVertices(k,2), 'o', ...
            'Color', [1.0, 0.84, 0.0], 'MarkerSize', 12, 'LineWidth', 2, ...
            'MarkerFaceColor', [1.0, 0.84, 0.0], 'HitTest', 'on');
    end
else
    meshVertices = zeros(0, 2);
    nTilesValidated = [10, 10];
end

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
    'dragStartPos', [], 'isManualArenaGrid', isManualArenaGrid, ...
    'meshVertices', meshVertices, 'nTiles', nTilesValidated, 'gradientConfig', gradientConfig, ...
    'includeDetailedArenaGridExport', includeDetailedArenaGridExport);
set(fig, 'UserData', figData);

% Set up mouse callbacks for dragging
set(markerA, 'ButtonDownFcn', @(src, event) startDrag(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath, 'A'));
set(markerB, 'ButtonDownFcn', @(src, event) startDrag(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath, 'B'));
set(lineHandle, 'ButtonDownFcn', @(src, event) startDragLine(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath));
for k = 1:numel(meshMarkerHandles)
    tag = sprintf('MESH_%d', k);
    set(meshMarkerHandles(k), 'ButtonDownFcn', @(src, event) startDrag(src, event, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath, tag));
end
set(fig, 'WindowButtonMotionFcn', @(src, event) dragPoint(src, event, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath));
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


function startDrag(~, ~, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath, pointName)
    % Start dragging a point
    figData = get(fig, 'UserData');
    figData.dragging = true;
    figData.draggedPoint = pointName;
    figData.dragStartPos = [];
    set(fig, 'UserData', figData);
    
    % Immediately trigger dragPoint to start dragging without requiring mouse movement
    dragPoint([], [], ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath);
end


function startDragLine(~, ~, fig, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath)
    % Start dragging the entire line
    figData = get(fig, 'UserData');
    currentPoint = get(ax, 'CurrentPoint');
    figData.dragging = true;
    figData.draggedPoint = 'LINE';
    figData.dragStartPos = [currentPoint(1,1), currentPoint(1,2)];
    set(fig, 'UserData', figData);
    
    % Immediately trigger dragPoint to start dragging without requiring mouse movement
    dragPoint([], [], ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath);
end


function dragPoint(~, ~, ax, markerA, markerB, lineHandle, textA, textB, meshMarkerHandles, meshLineHandles, meshGradientHandle, referenceLineFilePath) %#ok<INUSD>
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
        elseif startsWith(figData.draggedPoint, 'MESH_') && figData.isManualArenaGrid
            idx = str2double(erase(figData.draggedPoint, 'MESH_'));
            if ~isnan(idx) && idx >= 1 && idx <= size(figData.meshVertices, 1)
                % Keep default stacked-vertex behavior: all vertices mapped to the same corner move together.
                cornerIdx = mod(idx - 1, 4) + 1;
                allIdx = 1:size(figData.meshVertices, 1);
                mappedCorners = mod(allIdx - 1, 4) + 1;
                groupIdx = allIdx(mappedCorners == cornerIdx);
                figData.meshVertices(groupIdx, :) = repmat(newPos, numel(groupIdx), 1);
                for k = groupIdx
                    set(meshMarkerHandles(k), 'XData', figData.meshVertices(k,1), 'YData', figData.meshVertices(k,2));
                end
            end
        end
        
        % Recalculate and update the line
        [lineX, lineY] = calculateExtendedLine(figData.pointA, figData.pointB, figData.vidWidth, figData.vidHeight);
        set(lineHandle, 'XData', lineX, 'YData', lineY);

        if figData.isManualArenaGrid && ~isempty(meshGradientHandle) && all(isgraphics(meshGradientHandle))
            updateManualMeshGradient(meshGradientHandle, figData.meshVertices, figData.nTiles, figData.gradientConfig, figData.pointA, figData.pointB);
        end
        
        % Update title with current coordinates
        if figData.isManualArenaGrid
            title(ax, sprintf(['Point A: (%.1f, %.1f) px, Point B: (%.1f, %.1f) px\n' ...
                'Drag A/B, line, or mesh vertices to adjust, close window when done'], ...
                figData.pointA(1), figData.pointA(2), figData.pointB(1), figData.pointB(2)), 'Interpreter', 'none');
        else
            title(ax, sprintf('Point A: (%.1f, %.1f) px, Point B: (%.1f, %.1f) px\nDrag points to adjust, close window when done', ...
                figData.pointA(1), figData.pointA(2), figData.pointB(1), figData.pointB(2)), 'Interpreter', 'none');
        end
        
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

        % Check if mouse is near any mesh marker
        isNearMeshMarker = false;
        if figData.isManualArenaGrid && ~isempty(meshMarkerHandles)
            for k = 1:numel(meshMarkerHandles)
                meshPos = [get(meshMarkerHandles(k), 'XData'), get(meshMarkerHandles(k), 'YData')];
                distMesh = sqrt((mousePos(1) - meshPos(1))^2 + (mousePos(2) - meshPos(2))^2);
                if distMesh < threshold
                    isNearMeshMarker = true;
                    break;
                end
            end
        end
        
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
        
        if distA < threshold || distB < threshold || isNearLine || isNearMeshMarker
            set(fig, 'Pointer', 'fleur');
        else
            set(fig, 'Pointer', 'arrow');
        end
    end
end


function [meshVertices, nTilesValidated] = createDefaultManualMesh(vidWidth, vidHeight, nVertices, nTiles)
    xLeft = 0.10 * vidWidth;
    xRight = 0.90 * vidWidth;
    yTop = 0.10 * vidHeight;
    yBottom = 0.90 * vidHeight;

    baseCorners = [
        xLeft, yTop;    % top-left
        xRight, yTop;   % top-right
        xRight, yBottom;% bottom-right
        xLeft, yBottom  % bottom-left
    ];

    if nargin < 3 || isempty(nVertices) || ~isnumeric(nVertices)
        nVertices = 4;
    end
    nVertices = max(1, round(nVertices(1)));

    meshVertices = zeros(nVertices, 2);
    for i = 1:nVertices
        cornerIdx = mod(i - 1, 4) + 1;
        meshVertices(i, :) = baseCorners(cornerIdx, :);
    end

    nTilesValidated = [10, 10];
    if nargin >= 4 && isnumeric(nTiles) && numel(nTiles) >= 2
        nTilesValidated = [max(1, round(nTiles(1))), max(1, round(nTiles(2)))];
    end
end


function meshGradientHandle = drawManualMeshGradient(ax, meshVertices, nTiles, gradientConfig, pointA, pointB)
    [V, F, C] = calculateMeshGradientFaces(meshVertices, nTiles, gradientConfig, pointA, pointB);
    meshGradientHandle = patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceVertexCData', C, 'FaceColor', 'interp', 'EdgeColor', 'interp', ...
        'LineWidth', 0.8, 'FaceAlpha', 0.38, 'HitTest', 'off', 'PickableParts', 'none');
    colormap(ax, turbo(256));
    if ~isempty(C)
        clim(ax, [min(C), max(C)]);
    end
end


function updateManualMeshGradient(meshGradientHandle, meshVertices, nTiles, gradientConfig, pointA, pointB)
    [V, F, C] = calculateMeshGradientFaces(meshVertices, nTiles, gradientConfig, pointA, pointB);
    set(meshGradientHandle, 'Faces', F, 'Vertices', V, 'FaceVertexCData', C);
    ax = ancestor(meshGradientHandle, 'axes');
    colormap(ax, turbo(256));
    if ~isempty(C)
        clim(ax, [min(C), max(C)]);
    end
end


function [V, F, C] = calculateMeshGradientFaces(meshVertices, nTiles, gradientConfig, pointA, pointB)
    [gridNodes, ~, ~] = calculateMeshNodeGrid(meshVertices, nTiles);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    V = reshape(gridNodes, [], 2);
    F = zeros(nX * nY, 4);

    % Vertex-wise composition so both faces and edges can be interpolated.
    xNormVertex = normalizeXByMidlineAB(V, pointA, pointB, gridNodes);
    xScores = evaluateGradientByFunction(gradientConfig.xValues, gradientConfig.xFunction, xNormVertex(:)');

    yNormVertexGrid = repmat((1 - linspace(0, 1, nY + 1))', 1, nX + 1);
    yNormVertex = yNormVertexGrid(:);
    yScores = evaluateGradientByFunction(gradientConfig.yValues, gradientConfig.yFunction, yNormVertex(:)');

    C = xScores(:) .* yScores(:);

    faceIdx = 1;
    for iy = 1:nY
        for ix = 1:nX
            tl = sub2ind([nY+1, nX+1], iy, ix);
            tr = sub2ind([nY+1, nX+1], iy, ix + 1);
            br = sub2ind([nY+1, nX+1], iy + 1, ix + 1);
            bl = sub2ind([nY+1, nX+1], iy + 1, ix);
            F(faceIdx, :) = [tl, tr, br, bl];
            faceIdx = faceIdx + 1;
        end
    end
end


function [gridNodes, xNormCentersRaw, yNormCenters] = calculateMeshNodeGrid(meshVertices, nTiles)
    corners = meshVertices;
    if size(corners, 1) < 4
        corners = [corners; repmat(corners(end, :), 4 - size(corners, 1), 1)];
    end
    corners = corners(1:4, :);

    tl = corners(1, :);
    tr = corners(2, :);
    br = corners(3, :);
    bl = corners(4, :);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    sVals = linspace(0, 1, nX + 1);
    tVals = linspace(0, 1, nY + 1);
    gridNodes = zeros(nY + 1, nX + 1, 2);
    for iy = 1:(nY + 1)
        t = tVals(iy);
        for ix = 1:(nX + 1)
            s = sVals(ix);
            pTop = (1 - s) * tl + s * tr;
            pBottom = (1 - s) * bl + s * br;
            p = (1 - t) * pTop + t * pBottom;
            gridNodes(iy, ix, :) = p;
        end
    end

    [xGrid, yGrid] = meshgrid((0.5:1:nX-0.5) / nX, (0.5:1:nY-0.5) / nY);
    xNormCentersRaw = xGrid;
    % y in image coordinates grows downward, so invert to make top=max and bottom=min behavior.
    yNormCenters = 1 - yGrid;
end


function centers = calculateCellCenters(gridNodes)
    nY = size(gridNodes, 1) - 1;
    nX = size(gridNodes, 2) - 1;
    centers = zeros(nX * nY, 2);
    idx = 1;
    for iy = 1:nY
        for ix = 1:nX
            p1 = squeeze(gridNodes(iy, ix, :))';
            p2 = squeeze(gridNodes(iy, ix + 1, :))';
            p3 = squeeze(gridNodes(iy + 1, ix + 1, :))';
            p4 = squeeze(gridNodes(iy + 1, ix, :))';
            centers(idx, :) = (p1 + p2 + p3 + p4) / 4;
            idx = idx + 1;
        end
    end
end


function xNorm = normalizeXByMidlineAB(points, pointA, pointB, gridNodes)
    xNorm = 0.5 * ones(size(points, 1), 1);

    direction = pointB - pointA;
    normDir = norm(direction);
    if normDir < 1e-9
        return;
    end

    normal = [-direction(2), direction(1)] / normDir;
    % Keep X orientation consistent: right side of image should map to higher X values.
    if normal(1) < 0
        normal = -normal;
    end
    signedD = (points - pointA) * normal';

    domainPts = reshape(gridNodes, [], 2);
    domainD = (domainPts - pointA) * normal';
    maxPos = max(domainD);
    maxNeg = min(domainD);

    posDen = max(maxPos, eps);
    negDen = max(abs(maxNeg), eps);

    posMask = signedD >= 0;
    xNorm(posMask) = 0.5 + 0.5 * (signedD(posMask) / posDen);
    xNorm(~posMask) = 0.5 + 0.5 * (signedD(~posMask) / negDen);
    xNorm = min(max(xNorm, 0), 1);
end


function y = evaluateGradientByFunction(values, methodName, x)
    values = values(:)';
    if numel(values) < 2
        values = [values, values];
    end

    method = lower(string(methodName));
    xi = linspace(0, 1, numel(values));
    x = min(max(x, 0), 1);

    switch method
        case "linear"
            interpMethod = 'linear';
            y = interp1(xi, values, x, interpMethod, 'extrap');
        case "quadratic"
            if numel(values) >= 3
                p = polyfit(xi, values, 2);
                y = polyval(p, x);
            else
                y = interp1(xi, values, x, 'linear', 'extrap');
            end
        case "cubic"
            y = interp1(xi, values, x, 'pchip', 'extrap');
        case "spline"
            y = interp1(xi, values, x, 'spline', 'extrap');
        case "makima"
            y = interp1(xi, values, x, 'makima', 'extrap');
        otherwise
            y = interp1(xi, values, x, 'linear', 'extrap');
    end
end


function v = toNumericVector(inValue, fallback)
    v = fallback;
    try
        if isnumeric(inValue)
            v = double(inValue(:)');
        elseif iscell(inValue)
            v = cell2mat(inValue(:)');
            v = double(v(:)');
        else
            parsed = str2num(char(string(inValue))); %#ok<ST2NM>
            if ~isempty(parsed)
                v = double(parsed(:)');
            end
        end
    catch
        v = fallback;
    end
end


function meshVertices = validateMeshVertices(verticesIn)
    meshVertices = zeros(0, 2);
    try
        if iscell(verticesIn)
            verticesIn = cell2mat(verticesIn);
        end
        if isnumeric(verticesIn) && ~isempty(verticesIn)
            verticesIn = double(verticesIn);
            if isvector(verticesIn) && numel(verticesIn) == 2
                verticesIn = reshape(verticesIn, 1, 2);
            end
            if size(verticesIn, 2) == 2 && all(isfinite(verticesIn), 'all')
                meshVertices = verticesIn;
            end
        end
    catch
        meshVertices = zeros(0, 2);
    end
end


function meshLineHandles = drawManualMesh(ax, meshVertices, nTiles)
    [verticalLines, horizontalLines] = calculateMeshLines(meshVertices, nTiles);
    meshLineHandles = gobjects(size(verticalLines, 1) + size(horizontalLines, 1), 1);
    hIdx = 1;
    for i = 1:size(verticalLines, 1)
        meshLineHandles(hIdx) = plot(ax, verticalLines(i,:,1), verticalLines(i,:,2), '-', ...
            'Color', [0.90, 0.75, 0.15], 'LineWidth', 1.0, 'HitTest', 'off');
        hIdx = hIdx + 1;
    end
    for i = 1:size(horizontalLines, 1)
        meshLineHandles(hIdx) = plot(ax, horizontalLines(i,:,1), horizontalLines(i,:,2), '-', ...
            'Color', [0.90, 0.75, 0.15], 'LineWidth', 1.0, 'HitTest', 'off');
        hIdx = hIdx + 1;
    end
end


function updateManualMesh(meshLineHandles, meshVertices, nTiles)
    [verticalLines, horizontalLines] = calculateMeshLines(meshVertices, nTiles);
    nVert = size(verticalLines, 1);
    for i = 1:nVert
        set(meshLineHandles(i), 'XData', verticalLines(i,:,1), 'YData', verticalLines(i,:,2));
    end
    for i = 1:size(horizontalLines, 1)
        handleIdx = nVert + i;
        set(meshLineHandles(handleIdx), 'XData', horizontalLines(i,:,1), 'YData', horizontalLines(i,:,2));
    end
end


function [verticalLines, horizontalLines] = calculateMeshLines(meshVertices, nTiles)
    corners = meshVertices;
    if size(corners, 1) < 4
        corners = [corners; repmat(corners(end, :), 4 - size(corners, 1), 1)];
    end
    corners = corners(1:4, :);

    tl = corners(1, :);
    tr = corners(2, :);
    br = corners(3, :);
    bl = corners(4, :);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    verticalLines = zeros(nX + 1, 2, 2);
    sVals = linspace(0, 1, nX + 1);
    for i = 1:numel(sVals)
        s = sVals(i);
        topPoint = (1 - s) * tl + s * tr;
        bottomPoint = (1 - s) * bl + s * br;
        verticalLines(i, :, 1) = [topPoint(1), bottomPoint(1)];
        verticalLines(i, :, 2) = [topPoint(2), bottomPoint(2)];
    end

    horizontalLines = zeros(nY + 1, 2, 2);
    tVals = linspace(0, 1, nY + 1);
    for i = 1:numel(tVals)
        t = tVals(i);
        leftPoint = (1 - t) * tl + t * bl;
        rightPoint = (1 - t) * tr + t * br;
        horizontalLines(i, :, 1) = [leftPoint(1), rightPoint(1)];
        horizontalLines(i, :, 2) = [leftPoint(2), rightPoint(2)];
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
        saveReferenceLineToFile(figData.pointA, figData.pointB, figData.meshVertices, referenceLineFilePath);
    end
end


function figureCloseCallback(src, ~, referenceLineFilePath)
    % Get the final points from figure data
    figData = get(src, 'UserData');
    
    if ~isempty(figData) && isfield(figData, 'pointA') && isfield(figData, 'pointB')
        finalPointA = figData.pointA;
        finalPointB = figData.pointB;
        
        % Always save to file on close
        saveReferenceLineToFile(finalPointA, finalPointB, figData.meshVertices, referenceLineFilePath);
        
        % Store in base workspace for return, these will be cleared after retrieval
        assignin('base', 'uiselectReferenceLine_resultA', finalPointA);
        assignin('base', 'uiselectReferenceLine_resultB', finalPointB);

        if isfield(figData, 'isManualArenaGrid') && figData.isManualArenaGrid && ...
                isfield(figData, 'meshVertices') && ~isempty(figData.meshVertices)
            gradientExport = buildMeshGradientExport(figData.meshVertices, figData.nTiles, figData.gradientConfig, finalPointA, finalPointB, ...
                figData.vidWidth, figData.vidHeight);
            saveArenaGridExportToMat(gradientExport, referenceLineFilePath);
        end
    end
    
    % Close the figure
    delete(src);
end


function scoreMatrix = calculateMeshGradientScoreMatrix(meshVertices, nTiles, gradientConfig, pointA, pointB)
    [gridNodes, ~, yNormCenters] = calculateMeshNodeGrid(meshVertices, nTiles);
    centers = calculateCellCenters(gridNodes);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    xNormCenters = normalizeXByMidlineAB(centers, pointA, pointB, gridNodes);
    xScores = evaluateGradientByFunction(gradientConfig.xValues, gradientConfig.xFunction, xNormCenters(:)');
    yNormCentersRowMajor = reshape(yNormCenters.', 1, []);
    yScores = evaluateGradientByFunction(gradientConfig.yValues, gradientConfig.yFunction, yNormCentersRowMajor);

    scoreVector = xScores(:) .* yScores(:);
    scoreMatrix = reshape(scoreVector, [nX, nY])';
end


function gradientExport = buildMeshGradientExport(meshVertices, nTiles, gradientConfig, pointA, pointB, vidWidth, vidHeight)
    [gridNodes, ~, ~] = calculateMeshNodeGrid(meshVertices, nTiles);
    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    scoreMatrix = calculateMeshGradientScoreMatrix(meshVertices, nTiles, gradientConfig, pointA, pointB);
    centersList = calculateCellCenters(gridNodes);
    centers = zeros(nY, nX, 2);
    idx = 1;
    for iy = 1:nY
        for ix = 1:nX
            centers(iy, ix, :) = centersList(idx, :);
            idx = idx + 1;
        end
    end

    nodeX = gridNodes(:,:,1);
    nodeY = gridNodes(:,:,2);
    verticesPx = reshape(gridNodes, [], 2);

    triangles = zeros(nX * nY * 2, 3);
    triToTileRC = zeros(nX * nY * 2, 2);
    triIdx = 1;

    for iy = 1:nY
        for ix = 1:nX
            tl = sub2ind([nY+1, nX+1], iy, ix);
            tr = sub2ind([nY+1, nX+1], iy, ix + 1);
            br = sub2ind([nY+1, nX+1], iy + 1, ix + 1);
            bl = sub2ind([nY+1, nX+1], iy + 1, ix);

            triangles(triIdx, :) = [tl, tr, br];
            triToTileRC(triIdx, :) = [iy, ix];
            triIdx = triIdx + 1;

            triangles(triIdx, :) = [tl, br, bl];
            triToTileRC(triIdx, :) = [iy, ix];
            triIdx = triIdx + 1;
        end
    end

    gradientExport = struct();
    gradientExport.score = scoreMatrix;
    gradientExport.score_vector = scoreMatrix(:);
    gradientExport.grid = struct(...
        'nodes_x_px', nodeX, ...
        'nodes_y_px', nodeY, ...
        'centers_px', centers, ...
        'n_tiles_xy', [nX, nY]);
    gradientExport.lookup = struct(...
        'vertices_px', verticesPx, ...
        'triangles', triangles, ...
        'triangle_to_tile_rc', triToTileRC, ...
        'triangle_to_tile_linear', sub2ind([nY, nX], triToTileRC(:,1), triToTileRC(:,2)));
    gradientExport.ref = struct('video', struct('width', double(vidWidth), 'height', double(vidHeight)));
end


function saveReferenceLineToFile(pointA, pointB, meshVertices, referenceLineFilePath)
    %%Save the reference line points to a .ref.json file in the .midline field
    % Preserve existing data structure if file already exists, otherwise create new structure
    jsonData = struct();
    if isfile(referenceLineFilePath)
        try
            jsonData = jsondecode(fileread(referenceLineFilePath));
        catch ME
            warning('UISELECTREFERENCELINE:SaveLoadError', 'Error loading existing referenceline file for saving: %s\nOverwriting with new reference line data.\n%s', referenceLineFilePath, ME.message);
        end
    end
    jsonData.midline.x = [pointA(1), pointB(1)];
    jsonData.midline.y = [pointA(2), pointB(2)];
    if nargin >= 3 && isnumeric(meshVertices) && size(meshVertices, 2) == 2 && ~isempty(meshVertices)
        jsonData.arena_grid.vertices = meshVertices;
    end

    try
        jsonText = jsonencode(jsonData);
        fid = fopen(referenceLineFilePath, 'w');
        if fid == -1
            warning('UISELECTREFERENCELINE:SaveError', 'Could not open file for writing: %s', referenceLineFilePath);
            return;
        end
        fwrite(fid, jsonText, 'char');
        fclose(fid);
    catch ME
        warning('UISELECTREFERENCELINE:SaveError', 'Error saving reference line to file: %s', ME.message);
    end
end


function saveArenaGridExportToMat(gradientExport, referenceLineFilePath)
    [refDir, refBaseName, ~] = fileparts(referenceLineFilePath);
    arenaGridMatPath = fullfile(refDir, strcat(refBaseName, '.arenagrid.mat'));
    arena_grid = gradientExport;
    try
        % v6 is typically much faster to write for large numeric structs.
        save(arenaGridMatPath, 'arena_grid', '-v6');
    catch ME
        warning('UISELECTREFERENCELINE:SaveArenaGridError', 'Error saving arena grid export to file: %s\n%s', arenaGridMatPath, ME.message);
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
