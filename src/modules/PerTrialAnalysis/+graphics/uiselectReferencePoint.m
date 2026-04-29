function [fig, referencePoint] = uiselectReferencePoint(kvargs)
%%UISELECTREFERENCEPOINT Open a video frame to select a reference point for place preference analysis
%   This function opens a video file and allows the user to select a point on the frame
%   that will be used as a reference point for calculating distances relative to in place preference analysis.
%
%   This returns the figure handle and the selected reference point coordinates.
%   The function also saves the reference point to a .ref.json file next to the video file.
%    JSON format: {"midpoint": {"x": <value_x>, "y": <value_y>}}
%    CSV format (legacy): "x,y\n<value_x>,<value_y>\n"
%
%   If MasterMetadataTable, TrackingDataFile, and TrackingProvider are provided, the function will use the first frame with stimulus onset as the default frame to display instead of the first frame in video.
%

arguments
    kvargs.VideoFile {mustBeFile}
    kvargs.TrackingDataFile {validator.mustBeFileOrEmpty} = []
    kvargs.TrackingProvider {validator.mustBeTrackingProviderOrEmpty} = []
    kvargs.MasterMetadataTable {validator.mustBeFileTableOrEmpty} = []
end

arenaGridMode = "FOV";
n_tiles = [50, 50];
xGradientFn = "linear";
yGradientFn = "linear";
xGradientVals = [-1, 0, 1];
yGradientVals = [0.5, 1, 0.5];
includeDetailedArenaGridExport = false;

if ~isempty(kvargs.TrackingProvider) && isprop(kvargs.TrackingProvider, 'userConfig') && isstruct(kvargs.TrackingProvider.userConfig)
    userConfig = kvargs.TrackingProvider.userConfig;
    if isfield(userConfig, 'arena_grid_mode') && ~isempty(userConfig.arena_grid_mode)
        arenaGridMode = string(userConfig.arena_grid_mode);
    end

    if isfield(userConfig, 'arena_grid') && isstruct(userConfig.arena_grid)
        arenaGridConfig = userConfig.arena_grid;
        if isfield(arenaGridConfig, 'n_tiles') && ~isempty(arenaGridConfig.n_tiles)
            n_tiles = toNumericVector(arenaGridConfig.n_tiles, [50, 50]);
        end
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
        if isfield(arenaGridConfig, 'export_detailed') && ~isempty(arenaGridConfig.export_detailed)
            includeDetailedArenaGridExport = logical(arenaGridConfig.export_detailed);
        end
    end
end

if numel(n_tiles) < 2
    n_tiles = [50, 50];
end
n_tiles = [max(1, round(n_tiles(1))), max(1, round(n_tiles(2)))];

if numel(xGradientVals) < 2
    xGradientVals = [-1, 0, 1];
end
if numel(yGradientVals) < 2
    yGradientVals = [0.5, 1, 0.5];
end

gradientConfig = struct('xFunction', lower(string(xGradientFn)), 'yFunction', lower(string(yGradientFn)), ...
    'xValues', xGradientVals(:)', 'yValues', yGradientVals(:)');

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
referencePointFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

% Upgrade any legacy .midpoint.csv files in the folder to per-video .ref.json files.
graphics.migrateLegacyCSVRefs2JSON(videoDir);

v = VideoReader(videoFilePath);
% Read the specified frame
v.CurrentTime = (videoFrameNumber - 1) / v.FrameRate;
vidWidth = v.Width;
vidHeight = v.Height;
frame = readFrame(v);

referencePoint = [vidWidth/2, vidHeight/2]; % Default to center point of frame
meshVerticesSeed = zeros(0, 2);
% If current video's .ref.json does not exist, use any existing .ref.json as seed.
referencePointSeedFilePath = referencePointFilePath;
if ~isfile(referencePointSeedFilePath)
    referencePointFiles = dir(fullfile(videoDir, '*.ref.json'));
    if ~isempty(referencePointFiles)
        referencePointSeedFilePath = fullfile(videoDir, referencePointFiles(end).name);
    end
end

if isfile(referencePointSeedFilePath)
    try
        jsonData = jsondecode(fileread(referencePointSeedFilePath));
        if isfield(jsonData, 'midpoint')
            if isstruct(jsonData.midpoint) && isfield(jsonData.midpoint, 'x') && isfield(jsonData.midpoint, 'y')
                referencePoint = [jsonData.midpoint.x, jsonData.midpoint.y];
            elseif isnumeric(jsonData.midpoint) && numel(jsonData.midpoint) >= 2
                referencePoint = [jsonData.midpoint(1), jsonData.midpoint(2)];
            end
        end
        if isfield(jsonData, 'arena_grid') && isstruct(jsonData.arena_grid) && isfield(jsonData.arena_grid, 'vertices')
            meshVerticesSeed = validateMeshVertices(jsonData.arena_grid.vertices);
        end
    catch ME
        warning('UISELECTREFERENCEPOINT:LoadError', 'Error loading existing reference point file: %s\nUsing the center of the frame as default.\n%s', referencePointSeedFilePath, ME.message);
    end
end

if isempty(meshVerticesSeed)
    referencePointFiles = dir(fullfile(videoDir, '*.ref.json'));
    for i = numel(referencePointFiles):-1:1
        candidatePath = fullfile(videoDir, referencePointFiles(i).name);
        if strcmp(candidatePath, referencePointFilePath)
            continue;
        end
        try
            candidateData = jsondecode(fileread(candidatePath));
            if isfield(candidateData, 'arena_grid') && isstruct(candidateData.arena_grid) && isfield(candidateData.arena_grid, 'vertices')
                candidateVertices = validateMeshVertices(candidateData.arena_grid.vertices);
                if ~isempty(candidateVertices)
                    meshVerticesSeed = candidateVertices;
                    break;
                end
            end
        catch
            % Ignore malformed candidate JSON and continue fallback.
        end
    end
end

if isempty(meshVerticesSeed)
    meshVertices = createDefaultMeshForMode(vidWidth, vidHeight, arenaGridMode);
else
    meshVertices = meshVerticesSeed;
end

% Reset the path to the current video's .ref.json file (to be saved later)
referencePointFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));

name = string(videoBaseName);
if exist('header', 'var')
    name = strcat(header("Experiment"), " - ", header("Trial name"));
    if exist('arenaName', 'var')
        name = strcat(name, " @ ", string(arenaName));
    end
end

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
title(ax, buildPointSelectionTitle(name, strcmpi(string(arenaGridMode), "manual")), 'Interpreter', 'none');
hold(ax, 'on');

isManualArenaGrid = strcmpi(string(arenaGridMode), "manual");
meshGradientHandle = drawPointMeshGradient(ax, meshVertices, n_tiles, gradientConfig, referencePoint);
meshMarkerHandles = gobjects(0);
if isManualArenaGrid
    meshMarkerHandles = gobjects(size(meshVertices, 1), 1);
    for k = 1:size(meshVertices, 1)
        meshMarkerHandles(k) = plot(ax, meshVertices(k,1), meshVertices(k,2), 'o', ...
            'Color', [0.98, 0.87, 0.22], 'MarkerFaceColor', [0.98, 0.87, 0.22], ...
            'MarkerSize', 8, 'LineWidth', 1.2);
    end
end

% Create initial marker at default position (center)
markerHandle = plot(ax, referencePoint(1), referencePoint(2), 'r+', 'MarkerSize', 18, 'LineWidth', 2, 'HitTest', 'off');

% Store initial state in figure UserData
figData = struct('referencePoint', referencePoint, 'userInteracted', false, ...
    'meshVertices', meshVertices, 'nTiles', n_tiles, 'gradientConfig', gradientConfig, ...
    'vidWidth', vidWidth, 'vidHeight', vidHeight, ...
    'includeDetailedArenaGridExport', includeDetailedArenaGridExport, ...
    'dragging', false, 'draggedPoint', '');
set(fig, 'UserData', figData);

% Set up click callback for the axes
set(ax, 'ButtonDownFcn', @(src, event) axesClickCallback(src, event, ax, markerHandle, meshGradientHandle, referencePointFilePath, fig, name, isManualArenaGrid));

for k = 1:numel(meshMarkerHandles)
    tag = sprintf('MESH_%d', k);
    set(meshMarkerHandles(k), 'ButtonDownFcn', @(src, event) startDragMeshVertex(src, event, fig, tag));
end
set(fig, 'WindowButtonMotionFcn', @(src, event) dragMeshVertex(src, event, ax, meshMarkerHandles, meshGradientHandle));
set(fig, 'WindowButtonUpFcn', @(src, event) stopDragMeshVertex(src, event, referencePointFilePath));

% Set up scroll wheel zoom callback
set(fig, 'WindowScrollWheelFcn', @(src, event) scrollWheelCallback(src, event, ax));

% Set up figure close callback to save the final reference point
set(fig, 'CloseRequestFcn', @(src, event) figureCloseCallback(src, event, referencePointFilePath));

% Wait for figure to close and get the final reference point
waitfor(fig);

% Retrieve the final reference point from base workspace
if evalin('base', 'exist(''uiselectReferencePoint_result'', ''var'')')
    referencePoint = evalin('base', 'uiselectReferencePoint_result');
    evalin('base', 'clear uiselectReferencePoint_result');
end

end



function axesClickCallback(~, ~, ax, markerHandle, meshGradientHandle, referencePointFilePath, fig, name, isManualArenaGrid)
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

    updatePointMeshGradient(meshGradientHandle, figData.meshVertices, figData.nTiles, figData.gradientConfig, newReferencePoint);
    
    % Immediately save to file
    saveReferencePointToFile(newReferencePoint, referencePointFilePath, figData);
    
    % Update title to show coordinates
    title(ax, sprintf('%s\nReference Point: (%.1f, %.1f) px', buildPointSelectionTitle(name, isManualArenaGrid), newReferencePoint(1), newReferencePoint(2)), 'Interpreter', 'none');
end


function startDragMeshVertex(~, ~, fig, pointName)
    figData = get(fig, 'UserData');
    figData.dragging = true;
    figData.draggedPoint = pointName;
    set(fig, 'UserData', figData);
end


function dragMeshVertex(fig, ~, ax, meshMarkerHandles, meshGradientHandle)
    figData = get(fig, 'UserData');
    if ~figData.dragging
        return;
    end

    draggedName = string(figData.draggedPoint);
    if ~startsWith(draggedName, "MESH_")
        return;
    end

    meshIdx = str2double(extractAfter(draggedName, "MESH_"));
    if isnan(meshIdx) || meshIdx < 1 || meshIdx > size(figData.meshVertices, 1)
        return;
    end

    currentPoint = get(ax, 'CurrentPoint');
    newX = currentPoint(1,1);
    newY = currentPoint(1,2);
    newX = min(max(newX, 0.5), figData.vidWidth + 0.5);
    newY = min(max(newY, 0.5), figData.vidHeight + 0.5);

    figData.meshVertices(meshIdx, :) = [newX, newY];
    set(fig, 'UserData', figData);

    set(meshMarkerHandles(meshIdx), 'XData', newX, 'YData', newY);
    updatePointMeshGradient(meshGradientHandle, figData.meshVertices, figData.nTiles, figData.gradientConfig, figData.referencePoint);
end


function stopDragMeshVertex(src, ~, referencePointFilePath)
    figData = get(src, 'UserData');
    if ~figData.dragging
        return;
    end

    figData.dragging = false;
    figData.draggedPoint = '';
    set(src, 'UserData', figData);

    saveReferencePointToFile(figData.referencePoint, referencePointFilePath, figData);
end

function figureCloseCallback(src, ~, referencePointFilePath)
    % Get the final reference point from figure data
    figData = get(src, 'UserData');
    
    if ~isempty(figData) && isfield(figData, 'referencePoint')
        finalReferencePoint = figData.referencePoint;
        
        % Always save to file on close
        saveReferencePointToFile(finalReferencePoint, referencePointFilePath, figData);

        % Store in base workspace for return, this will be cleared after retrieval
        assignin('base', 'uiselectReferencePoint_result', finalReferencePoint);
    end
    
    % Close the figure
    delete(src);
end

function saveReferencePointToFile(referencePoint, referencePointFilePath, figData)
    % Save the reference point to .ref.json in midpoint field while preserving other JSON fields.
    jsonData = struct();
    if isfile(referencePointFilePath)
        try
            jsonData = jsondecode(fileread(referencePointFilePath));
        catch ME
            warning('UISELECTREFERENCEPOINT:SaveLoadError', 'Error loading existing reference point file for saving: %s\nOverwriting midpoint field with new data.\n%s', referencePointFilePath, ME.message);
        end
    end
    jsonData.midpoint.x = referencePoint(1);
    jsonData.midpoint.y = referencePoint(2);
    if nargin >= 3 && isstruct(figData) && isfield(figData, 'meshVertices') && isnumeric(figData.meshVertices) && size(figData.meshVertices, 2) == 2 && ~isempty(figData.meshVertices)
        jsonData.arena_grid.vertices = figData.meshVertices;
    end

    try
        jsonText = jsonencode(jsonData);
        fileID = fopen(referencePointFilePath, 'w');
        if fileID == -1
            warning('Could not open file for writing: %s', referencePointFilePath);
            return;
        end
        fwrite(fileID, jsonText, 'char');
        fclose(fileID);
    catch ME
        warning('UISELECTREFERENCEPOINT:SaveError', 'Error saving reference point to file: %s', ME.message);
    end

    try
        if nargin >= 3 && isstruct(figData) && isfield(figData, 'meshVertices') && isfield(figData, 'nTiles') && ...
                isfield(figData, 'gradientConfig') && isfield(figData, 'vidWidth') && isfield(figData, 'vidHeight')
            gradientExport = buildPointGradientExport(figData.meshVertices, figData.nTiles, figData.gradientConfig, ...
                referencePoint, figData.vidWidth, figData.vidHeight, figData.includeDetailedArenaGridExport);
            saveArenaGridExportToMat(gradientExport, referencePointFilePath);
        end
    catch ME
        warning('UISELECTREFERENCEPOINT:SaveArenaGridError', 'Error saving arena grid export for reference point: %s\n%s', referencePointFilePath, ME.message);
    end
end


function meshVertices = createDefaultMeshForMode(vidWidth, vidHeight, arenaGridMode)
    modeName = lower(string(arenaGridMode));
    switch modeName
        case "manual"
            meshVertices = [
                0.10 * vidWidth, 0.10 * vidHeight;
                0.90 * vidWidth, 0.10 * vidHeight;
                0.90 * vidWidth, 0.90 * vidHeight;
                0.10 * vidWidth, 0.90 * vidHeight
            ];
        otherwise
            meshVertices = [
                0.5, 0.5;
                vidWidth + 0.5, 0.5;
                vidWidth + 0.5, vidHeight + 0.5;
                0.5, vidHeight + 0.5
            ];
    end
end


function gradientExport = buildPointGradientExport(meshVertices, nTiles, gradientConfig, referencePoint, vidWidth, vidHeight, includeDetailed)
    [gridNodes, ~, ~] = calculateMeshNodeGrid(meshVertices, nTiles);
    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    virtualPointA = [referencePoint(1), 0.5];
    virtualPointB = [referencePoint(1), vidHeight + 0.5];

    scoreMatrix = calculatePointGradientScoreMatrix(meshVertices, nTiles, gradientConfig, referencePoint);
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
        'n_tiles_xy', [nX, nY]);
    if includeDetailed
        gradientExport.grid.centers_px = centers;
    end

    gradientExport.lookup = struct(...
        'vertices_px', verticesPx, ...
        'triangles', triangles, ...
        'triangle_to_tile_rc', triToTileRC, ...
        'triangle_to_tile_linear', sub2ind([nY, nX], triToTileRC(:,1), triToTileRC(:,2)));
    gradientExport.gradient = struct(...
        'x_function', char(gradientConfig.xFunction), ...
        'y_function', char(gradientConfig.yFunction), ...
        'x_values', double(gradientConfig.xValues(:)'), ...
        'y_values', double(gradientConfig.yValues(:)'));
    gradientExport.ref = struct(...
        'mode', 'point', ...
        'video', struct('width', double(vidWidth), 'height', double(vidHeight)), ...
        'midpoint', struct('x', double(referencePoint(1)), 'y', double(referencePoint(2))), ...
        'midline', struct('x', [double(virtualPointA(1)), double(virtualPointB(1))], ...
            'y', [double(virtualPointA(2)), double(virtualPointB(2))]));
end


function scoreMatrix = calculatePointGradientScoreMatrix(meshVertices, nTiles, gradientConfig, referencePoint)
    [gridNodes, ~, ~] = calculateMeshNodeGrid(meshVertices, nTiles);
    centers = calculateCellCenters(gridNodes);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    domainPts = reshape(gridNodes, [], 2);
    xNormCenters = normalizeByMidpointAxis(centers(:,1), referencePoint(1), domainPts(:,1));
    yNormCenters = normalizeByMidpointAxis(centers(:,2), referencePoint(2), domainPts(:,2));
    xScores = evaluateGradientByFunction(gradientConfig.xValues, gradientConfig.xFunction, xNormCenters(:)');
    yScores = evaluateGradientByFunction(gradientConfig.yValues, gradientConfig.yFunction, yNormCenters(:)');

    scoreVector = xScores(:) .* yScores(:);
    scoreMatrix = reshape(scoreVector, [nX, nY])';
end


function meshGradientHandle = drawPointMeshGradient(ax, meshVertices, nTiles, gradientConfig, referencePoint)
    [V, F, C] = calculatePointMeshGradientFaces(meshVertices, nTiles, gradientConfig, referencePoint);
    meshGradientHandle = patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceVertexCData', C, 'FaceColor', 'interp', 'EdgeColor', 'interp', ...
        'LineWidth', 0.8, 'FaceAlpha', 0.38, 'HitTest', 'off', 'PickableParts', 'none');
    colormap(ax, turbo(256));
    if ~isempty(C)
        clim(ax, [min(C), max(C)]);
    end
end


function updatePointMeshGradient(meshGradientHandle, meshVertices, nTiles, gradientConfig, referencePoint)
    [V, F, C] = calculatePointMeshGradientFaces(meshVertices, nTiles, gradientConfig, referencePoint);
    set(meshGradientHandle, 'Faces', F, 'Vertices', V, 'FaceVertexCData', C);
    ax = ancestor(meshGradientHandle, 'axes');
    colormap(ax, turbo(256));
    if ~isempty(C)
        clim(ax, [min(C), max(C)]);
    end
end


function [V, F, C] = calculatePointMeshGradientFaces(meshVertices, nTiles, gradientConfig, referencePoint)
    [gridNodes, ~, ~] = calculateMeshNodeGrid(meshVertices, nTiles);

    nX = max(1, round(nTiles(1)));
    nY = max(1, round(nTiles(2)));

    V = reshape(gridNodes, [], 2);
    F = zeros(nX * nY, 4);

    domainPts = reshape(gridNodes, [], 2);
    xNormVertex = normalizeByMidpointAxis(V(:,1), referencePoint(1), domainPts(:,1));
    yNormVertex = normalizeByMidpointAxis(V(:,2), referencePoint(2), domainPts(:,2));

    xScores = evaluateGradientByFunction(gradientConfig.xValues, gradientConfig.xFunction, xNormVertex(:)');
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


function axisNorm = normalizeByMidpointAxis(values, midpointValue, domainValues)
    axisNorm = 0.5 * ones(size(values));

    signedD = values - midpointValue;
    domainD = domainValues - midpointValue;
    maxPos = max(domainD);
    maxNeg = min(domainD);

    posDen = max(maxPos, eps);
    negDen = max(abs(maxNeg), eps);

    posMask = signedD >= 0;
    axisNorm(posMask) = 0.5 + 0.5 * (signedD(posMask) / posDen);
    axisNorm(~posMask) = 0.5 + 0.5 * (signedD(~posMask) / negDen);
    axisNorm = min(max(axisNorm, 0), 1);
end


function txt = buildPointSelectionTitle(name, isManualArenaGrid)
    if isManualArenaGrid
        txt = sprintf('Select Reference Point for %s\n(Click to set midpoint, drag yellow vertices for arena mesh, close window when done)', name);
    else
        txt = sprintf('Select Reference Point for %s\n(Click to set midpoint, close window when done)', name);
    end
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
            y = interp1(xi, values, x, 'linear', 'extrap');
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


function saveArenaGridExportToMat(gradientExport, referencePointFilePath)
    [refDir, refBaseName, ~] = fileparts(referencePointFilePath);
    arenaGridMatPath = fullfile(refDir, strcat(refBaseName, '.arenagrid.mat'));
    arena_grid = gradientExport;
    try
        save(arenaGridMatPath, 'arena_grid', '-v6');
    catch ME
        warning('UISELECTREFERENCEPOINT:SaveArenaGridError', 'Error saving arena grid export to file: %s\n%s', arenaGridMatPath, ME.message);
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