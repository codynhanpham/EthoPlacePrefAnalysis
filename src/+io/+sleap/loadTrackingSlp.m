function [header, datatable, units] = loadTrackingSlp(filePath, kvargs)
    %%LOADTRACKINGSLP Load single-video, single-instance tracking from a SLEAP .slp file.
    %
    %   Inputs:
    %       filePath - Path to the SLEAP .slp file.
    %
    %   Name-Value Pair Arguments:
    %       MetadataTable - Reserved for compatibility with other tracking loaders.
    %       HeaderOnly - If true, skip loading the tracking datasets.
    %       Interpolation - Method used to fill missing X/Y predictions. Use
    %           'none' to preserve missing predictions as NaN. Interpolation
    %           is temporal and is applied independently to each node.
    %
    %   Outputs:
    %       header - String dictionary containing video and SLEAP metadata.
    %       datatable - Dense, video-length table of tracking data.
    %       units - String dictionary containing units for each table variable.

    arguments
        filePath {mustBeFile}
        kvargs.MetadataTable table = table() %#ok<INUSA>
        kvargs.Interpolation {mustBeMember(kvargs.Interpolation, ...
            {'none', 'linear', 'nearest', 'spline', 'makima', 'pchip', 'cubic'}), ...
            mustBeTextScalar} = 'none'
        kvargs.HeaderOnly (1,1) logical = false
    end

    if ~isscalar(cellstr(filePath))
        error('io:sleap:loadTrackingSlp:InvalidInput', ...
            'filePath must be a single string scalar or character vector.');
    end
    filePath = char(filePath);

    if ~endsWith(filePath, '.slp', 'IgnoreCase', true)
        error('io:sleap:loadTrackingSlp:InvalidFileExtension', ...
            'The specified file is not a valid SLEAP .slp file.');
    end

    % Confirm that this is HDF5 and that the required SLP objects exist.
    try
        h5info(filePath);
    catch ME
        error('io:sleap:loadTrackingSlp:InvalidHDF5File', ...
            'The specified file is not a valid HDF5 file. Error: %s', ME.message);
    end

    requiredPaths = {'/metadata', '/frames', '/instances', '/pred_points', '/videos_json'};
    for pathIdx = 1:numel(requiredPaths)
        try
            h5info(filePath, requiredPaths{pathIdx});
        catch ME
            error('io:sleap:loadTrackingSlp:MissingObject', ...
                'The SLEAP file is missing required HDF5 object "%s". Error: %s', ...
                requiredPaths{pathIdx}, ME.message);
        end
    end

    % /metadata is a group. Its JSON metadata and format identifier are
    % attributes on the group, not datasets.
    try
        metadataJson = localDecodeText(h5readatt(filePath, '/metadata', 'json'));
        formatId = h5readatt(filePath, '/metadata', 'format_id');
    catch ME
        error('io:sleap:loadTrackingSlp:MissingMetadata', ...
            'The SLEAP file is missing the required /metadata attributes (json and format_id). Error: %s', ...
            ME.message);
    end
    try
        slpMetadata = jsondecode(metadataJson);
    catch ME
        error('io:sleap:loadTrackingSlp:InvalidMetadata', ...
            'The /metadata/json attribute is not valid JSON. Error: %s', ME.message);
    end
    if ~isfield(slpMetadata, 'nodes') || isempty(slpMetadata.nodes) || ...
            ~isfield(slpMetadata.nodes, 'name')
        error('io:sleap:loadTrackingSlp:MissingNodes', ...
            'The SLEAP metadata does not contain node names.');
    end
    pointNodes = string({slpMetadata.nodes.name});
    if numel(unique(pointNodes)) ~= numel(pointNodes)
        error('io:sleap:loadTrackingSlp:DuplicateNodes', ...
            'The SLEAP metadata contains duplicate node names.');
    end
    nNodes = numel(pointNodes);

    % /videos_json contains one JSON object per video. This loader supports
    % exactly one source video.
    videoInfoSize = h5info(filePath, '/videos_json').Dataspace.Size;
    if prod(double(videoInfoSize)) ~= 1
        error('io:sleap:loadTrackingSlp:MultipleVideoSources', ...
            'The SLEAP .slp file contains %d video sources; exactly one is supported.', ...
            prod(double(videoInfoSize)));
    end
    try
        videoFileInfo = jsondecode(localDecodeText(h5read(filePath, '/videos_json')));
    catch ME
        error('io:sleap:loadTrackingSlp:InvalidVideoMetadata', ...
            'The /videos_json entry is not valid JSON. Error: %s', ME.message);
    end
    [videoFilePath, nVideoFrames] = localResolveVideo(filePath, videoFileInfo);
    [trialName, arenaName, experimentName] = localInferHeaders(videoFilePath, filePath);

    % Read the frame and instance indexes before constructing the header so
    % the number of frames represented by SLEAP is available even in
    % HeaderOnly mode. The point coordinates themselves are still skipped in
    % HeaderOnly mode.
    frames = localReadCompound(filePath, '/frames');
    instances = localReadCompound(filePath, '/instances');
    nFramesRows = localCompoundHeight(frames);
    nInstances = localCompoundHeight(instances);
    frameIds = localNumericColumn(frames, "frame_id");
    frameVideo = localNumericColumn(frames, "video");
    frameIdxSparse = localNumericColumn(frames, "frame_idx");
    instanceStart = localNumericColumn(frames, "instance_id_start");
    instanceEnd = localNumericColumn(frames, "instance_id_end");
    instanceType = localNumericColumn(instances, "instance_type");
    instanceFrameId = localNumericColumn(instances, "frame_id");

    if nFramesRows > 0 && any(frameVideo ~= frameVideo(1))
        error('io:sleap:loadTrackingSlp:MultipleVideoSources', ...
            'The SLEAP frame records reference multiple video sources.');
    end
    [frameRows, instanceRows] = localValidateFrameLinks(...
        frameIdxSparse, instanceStart, instanceEnd, instanceType, ...
        instanceFrameId, frameIds, nVideoFrames, nInstances);

    header = configureDictionary("string", "string");
    header("Video file") = string(videoFilePath);
    header("Trial name") = trialName;
    header("Arena name") = arenaName;
    header("Experiment") = experimentName;
    header("Video frames") = string(nVideoFrames);
    header("SLEAP predicted frames") = string(nnz(frameRows > 0));
    header("Interpolated frames") = "0";
    header("SLEAP format id") = string(formatId);
    header("SLEAP metadata jsonencode") = string(metadataJson);
    header("SLEAP interpolation") = string(kvargs.Interpolation);
    dataHeader = struct('bodyparts', {cellstr(pointNodes)}, ...
        'coords', {{'x', 'y', 'visible', 'score'}});
    header("SLEAP data header jsonencode") = string(jsonencode(dataHeader));

    datatable = table();
    units = configureDictionary("string", "string");
    if kvargs.HeaderOnly
        return;
    end

    % These datasets are linked by zero-based, half-open ranges:
    % frames -> instances -> pred_points.
    predPoints = localReadCompound(filePath, '/pred_points');
    nPredPoints = localCompoundHeight(predPoints);

    frameIdx = (0:nVideoFrames-1)';
    variableNames = strings(1, 1 + 4*nNodes);
    variableNames(1) = "Frame Idx";
    for nodeIdx = 1:nNodes
        columnOffset = 1 + 4*(nodeIdx - 1);
        variableNames(columnOffset + (1:4)) = [
            string(localVariableName(pointNodes(nodeIdx), 'x')), ...
            string(localVariableName(pointNodes(nodeIdx), 'y')), ...
            string(localVariableName(pointNodes(nodeIdx), 'visible')), ...
            string(localVariableName(pointNodes(nodeIdx), 'score'))];
    end
    tableData = cell(1, numel(variableNames));
    tableData{1} = frameIdx;
    for nodeIdx = 1:nNodes
        columnOffset = 1 + 4*(nodeIdx - 1);
        tableData{columnOffset + 1} = NaN(nVideoFrames, 1);
        tableData{columnOffset + 2} = NaN(nVideoFrames, 1);
        tableData{columnOffset + 3} = false(nVideoFrames, 1);
        tableData{columnOffset + 4} = NaN(nVideoFrames, 1);
    end
    datatable = table(tableData{:}, 'VariableNames', cellstr(variableNames));

    observedFrameMask = false(nVideoFrames, 1);

    pointStart = localNumericColumn(instances, "point_id_start");
    pointEnd = localNumericColumn(instances, "point_id_end");
    predX = localNumericColumn(predPoints, "x");
    predY = localNumericColumn(predPoints, "y");
    predVisible = logical(localNumericColumn(predPoints, "visible"));
    predScore = localNumericColumn(predPoints, "score");

    % Frame indices are zero-based in SLEAP and become MATLAB row indices by
    % adding one. Frames absent from /frames retain their initialized NaNs.
    validFrameMask = frameRows > 0;
    outputRows = frameRows(validFrameMask);
    selectedInstances = instanceRows(validFrameMask);
    observedFrameMask(outputRows) = true;

    pointStarts = pointStart(selectedInstances) + 1;
    pointEnds = pointEnd(selectedInstances);
    invalidPointRanges = ~isfinite(pointStarts) | ~isfinite(pointEnds) | ...
        pointStarts < 1 | pointEnds < pointStarts - 1 | pointEnds > nPredPoints;
    if any(invalidPointRanges)
        badFrame = find(invalidPointRanges, 1);
        error('io:sleap:loadTrackingSlp:InvalidPointRange', ...
            'Instance record %d contains an invalid predicted-point range [%g, %g).', ...
            selectedInstances(badFrame), pointStarts(badFrame) - 1, pointEnds(badFrame));
    end
    pointCounts = pointEnds - pointStarts + 1;
    if any(pointCounts ~= nNodes)
        badFrame = find(pointCounts ~= nNodes, 1);
        error('io:sleap:loadTrackingSlp:PointNodeCountMismatch', ...
            'Frame %d contains %d predicted points, but the metadata contains %d nodes.', ...
            frameIdxSparse(badFrame), pointCounts(badFrame), nNodes);
    end
    pointRows = pointStarts + (0:nNodes-1);
    xValues = predX(pointRows);
    yValues = predY(pointRows);
    visibleValues = predVisible(pointRows);
    scoreValues = predScore(pointRows);
    validPoints = visibleValues & isfinite(xValues) & isfinite(yValues);
    xValues(~validPoints) = NaN;
    yValues(~validPoints) = NaN;
    visibleValues(~validPoints) = false;
    scoreValues(~validPoints) = NaN;
    if isnumeric(formatId) && isscalar(formatId) && formatId < 1.1
        xValues(validPoints) = xValues(validPoints) - 0.5;
        yValues(validPoints) = yValues(validPoints) - 0.5;
    end
    for nodeIdx = 1:nNodes
        columnOffset = 1 + 4*(nodeIdx - 1);
        datatable{outputRows, columnOffset + 1} = xValues(:, nodeIdx);
        datatable{outputRows, columnOffset + 2} = yValues(:, nodeIdx);
        datatable{outputRows, columnOffset + 3} = visibleValues(:, nodeIdx);
        datatable{outputRows, columnOffset + 4} = scoreValues(:, nodeIdx);
    end

    % Interpolation is performed after sparse SLEAP records have been
    % expanded to the dense video timeline. This is a one-dimensional
    % temporal interpolation problem: each node coordinate is interpolated
    % independently across frame index. A 2-D interpolator is not needed
    % because X and Y are separate time series, and the number of nodes is
    % typically small compared with the number of video frames.
    interpolationMethod = char(string(kvargs.Interpolation));
    xVariableNames = strings(1, nNodes);
    yVariableNames = strings(1, nNodes);
    for nodeIdx = 1:nNodes
        xVariableNames(nodeIdx) = string(localVariableName(pointNodes(nodeIdx), 'x'));
        yVariableNames(nodeIdx) = string(localVariableName(pointNodes(nodeIdx), 'y'));
    end
    interpolatedFrameMask = false(nVideoFrames, 1);
    if ~strcmpi(interpolationMethod, 'none')
        xValues = datatable{:, xVariableNames};
        yValues = datatable{:, yVariableNames};
        xValues = localInterpolateColumns(xValues, frameIdx, interpolationMethod);
        yValues = localInterpolateColumns(yValues, frameIdx, interpolationMethod);
        datatable{:, xVariableNames} = xValues;
        datatable{:, yVariableNames} = yValues;
        interpolatedFrameMask = ~observedFrameMask & ...
            any(isfinite(xValues) | isfinite(yValues), 2);

        % Interpolated coordinates are estimates, not observed SLEAP points.
        % Keep Visible=false and Score=NaN for imputed rows so downstream code
        % can distinguish them from actual predictions.
    end

    header("SLEAP predicted frames") = string(nnz(observedFrameMask));
    header("Interpolated frames") = string(nnz(interpolatedFrameMask));

    for variableName = string(datatable.Properties.VariableNames)
        units(variableName) = "";
    end
    for nodeIdx = 1:nNodes
        units(localVariableName(pointNodes(nodeIdx), 'x')) = "px";
        units(localVariableName(pointNodes(nodeIdx), 'y')) = "px";
    end
end

function [frameRows, instanceRows] = localValidateFrameLinks(...
        frameIdx, instanceStart, instanceEnd, instanceType, ...
        instanceFrameId, frameIds, nVideoFrames, nInstances)
    nFramesRows = numel(frameIdx);
    frameRows = zeros(nFramesRows, 1);
    instanceRows = zeros(nFramesRows, 1);
    validFrameIndices = isfinite(frameIdx) & frameIdx >= 0 & ...
        frameIdx < nVideoFrames & frameIdx == fix(frameIdx);
    if any(~validFrameIndices)
        badRow = find(~validFrameIndices, 1);
        error('io:sleap:loadTrackingSlp:InvalidFrameIndex', ...
            'Frame record %d references invalid zero-based frame index %g.', ...
            badRow, frameIdx(badRow));
    end
    if numel(unique(frameIdx)) ~= nFramesRows
        error('io:sleap:loadTrackingSlp:DuplicateFrameIndex', ...
            'The SLEAP file contains more than one frame record for a video frame.');
    end

    for frameRow = 1:nFramesRows
        firstInstance = instanceStart(frameRow) + 1;
        lastInstance = instanceEnd(frameRow);
        if ~isfinite(firstInstance) || ~isfinite(lastInstance) || ...
                firstInstance < 1 || lastInstance < firstInstance - 1 || ...
                lastInstance > nInstances
            error('io:sleap:loadTrackingSlp:InvalidInstanceRange', ...
                'Frame record %d contains an invalid instance range [%g, %g).', ...
                frameRow, instanceStart(frameRow), instanceEnd(frameRow));
        end
        if lastInstance == firstInstance - 1
            continue;
        end
        if lastInstance - firstInstance + 1 ~= 1
            error('io:sleap:loadTrackingSlp:MultiInstanceDetected', ...
                'Frame %d contains %d instances; only single-instance SLEAP data is supported.', ...
                frameIdx(frameRow), lastInstance - firstInstance + 1);
        end

        instanceRow = firstInstance;
        if instanceType(instanceRow) ~= 1
            error('io:sleap:loadTrackingSlp:UnexpectedInstanceType', ...
                'Frame %d does not reference a predicted instance.', frameIdx(frameRow));
        end
        if instanceFrameId(instanceRow) ~= frameIds(frameRow)
            error('io:sleap:loadTrackingSlp:FrameReferenceMismatch', ...
                'Instance reference for frame %d does not match the containing frame.', ...
                frameIdx(frameRow));
        end
        frameRows(frameRow) = frameIdx(frameRow) + 1;
        instanceRows(frameRow) = instanceRow;
    end
end

function values = localInterpolateColumns(values, frameIdx, method)
    for columnIdx = 1:size(values, 2)
        missing = ~isfinite(values(:, columnIdx));
        valid = isfinite(values(:, columnIdx));
        if ~any(missing) || nnz(valid) < 2
            continue;
        end

        try
            interpolated = interp1(frameIdx(valid), values(valid, columnIdx), ...
                frameIdx(missing), method);
        catch ME
            error('io:sleap:loadTrackingSlp:InterpolationFailed', ...
                'Interpolation method "%s" failed for node column %d. Error: %s', ...
                method, columnIdx, ME.message);
        end
        values(missing, columnIdx) = interpolated;
    end
end

function variableName = localVariableName(nodeName, coordinateName)
    variableName = char(nodeName + " |> " + coordinateName);
end

function value = localNumericColumn(data, fieldName)
    fieldName = char(fieldName);
    if ~isfield(data, fieldName)
        error('io:sleap:loadTrackingSlp:MissingField', ...
            'The SLEAP dataset is missing required field "%s".', fieldName);
    end
    value = double(data.(fieldName));
    value = value(:);
end

function height = localCompoundHeight(data)
    fields = fieldnames(data);
    if isempty(fields)
        height = 0;
    else
        height = numel(data.(fields{1}));
    end
end

function data = localReadCompound(filePath, datasetPath)
    raw = h5read(filePath, datasetPath);
    if isstruct(raw)
        names = fieldnames(raw);
        data = struct();
        for i = 1:numel(names)
            data.(names{i}) = reshape([raw.(names{i})], [], 1);
        end
        return;
    end

    try
        fieldNames = jsondecode(localDecodeText(h5readatt(filePath, datasetPath, 'field_names')));
        fieldNames = string(fieldNames(:));
    catch ME
        error('io:sleap:loadTrackingSlp:UnsupportedDatasetLayout', ...
            'Dataset "%s" is not a native compound dataset and has no readable field_names attribute. Error: %s', ...
            datasetPath, ME.message);
    end
    matrix = raw;
    if isvector(matrix) && numel(fieldNames) == numel(matrix)
        matrix = reshape(matrix, 1, []);
    elseif size(matrix, 2) ~= numel(fieldNames) && size(matrix, 1) == numel(fieldNames)
        matrix = matrix.';
    end
    if size(matrix, 2) ~= numel(fieldNames)
        error('io:sleap:loadTrackingSlp:UnsupportedDatasetLayout', ...
            'Dataset "%s" has dimensions incompatible with its field_names attribute.', datasetPath);
    end
    data = struct();
    for i = 1:numel(fieldNames)
        data.(char(fieldNames(i))) = matrix(:, i);
    end
end

function text = localDecodeText(value)
    if iscell(value)
        if numel(value) ~= 1
            error('io:sleap:loadTrackingSlp:InvalidText', ...
                'Expected one HDF5 text value.');
        end
        value = value{1};
    end
    if isstring(value)
        text = char(value);
    elseif ischar(value)
        text = value;
    elseif isnumeric(value) || islogical(value)
        text = native2unicode(uint8(value(:).'), 'UTF-8');
    else
        error('io:sleap:loadTrackingSlp:InvalidText', ...
            'Unsupported HDF5 text representation of class %s.', class(value));
    end
end

function [videoPath, nVideoFrames] = localResolveVideo(slpPath, videoInfo)
    slpFolder = fileparts(slpPath);
    candidateNames = strings(0, 1);
    if isfield(videoInfo, 'filename') && ~isempty(videoInfo.filename)
        candidateNames(end+1) = string(videoInfo.filename);
    end
    if isfield(videoInfo, 'source_video') && isstruct(videoInfo.source_video) && ...
            isfield(videoInfo.source_video, 'filename') && ~isempty(videoInfo.source_video.filename)
        candidateNames(end+1) = string(videoInfo.source_video.filename);
    end

    videoPath = "";
    for i = 1:numel(candidateNames)
        candidate = char(candidateNames(i));
        if isfile(candidate)
            videoPath = string(candidate);
            break;
        end
        candidate = fullfile(slpFolder, candidate);
        if isfile(candidate)
            videoPath = string(candidate);
            break;
        end
    end
    if strlength(videoPath) == 0
        [~, slpName] = fileparts(slpPath);
        videoName = regexprep(slpName, '\.predictions$', '');
        extensions = {'.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.3gp'};
        for extension = extensions
            candidate = fullfile(fileparts(slpFolder), [videoName extension{1}]);
            if isfile(candidate)
                videoPath = string(candidate);
                break
            end
        end
    end

    nVideoFrames = NaN;
    if isfield(videoInfo, 'backend') && isstruct(videoInfo.backend) && ...
            isfield(videoInfo.backend, 'shape') && ~isempty(videoInfo.backend.shape)
        shape = double(videoInfo.backend.shape);
        if ~isempty(shape) && isfinite(shape(1)) && shape(1) >= 1 && shape(1) == fix(shape(1))
            nVideoFrames = shape(1);
        end
    end
    if isnan(nVideoFrames) && strlength(videoPath) > 0
        try
            reader = VideoReader(char(videoPath));
            nVideoFrames = reader.NumFrames;
        catch
            nVideoFrames = NaN;
        end
    end
    if isnan(nVideoFrames)
        error('io:sleap:loadTrackingSlp:MissingVideoFrameCount', ...
            'Unable to determine the video frame count from SLEAP metadata or the source video.');
    end
end

function [trialName, arenaName, experimentName] = localInferHeaders(videoPath, slpPath)
    if strlength(videoPath) > 0
        [videoFolder, videoName] = fileparts(char(videoPath));
    else
        [videoFolder, videoName] = fileparts(slpPath);
        videoName = regexprep(videoName, '\.predictions$', '');
    end
    videoName = string(videoName);
    trialName = videoName;
    arenaName = "Arena 1";
    if contains(videoName, " @ ")
        nameParts = split(videoName, " @ ");
        trialName = nameParts(1);
        arenaName = strjoin(nameParts(2:end), " @ ");
    end

    pathParts = split(string(videoFolder), filesep);
    mediaIdx = find(strcmpi(pathParts, "Media Files"), 1, 'last');
    if ~isempty(mediaIdx) && mediaIdx > 1
        experimentName = pathParts(mediaIdx - 1);
    else
        [~, experimentName] = fileparts(fileparts(videoFolder));
        if isempty(experimentName)
            [~, experimentName] = fileparts(fileparts(slpPath));
        end
        experimentName = string(experimentName);
    end
end
