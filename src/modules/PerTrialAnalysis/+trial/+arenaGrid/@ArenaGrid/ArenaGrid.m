classdef ArenaGrid
    %ARENAGRID Query tile and score for XY points using arena_grid export.
    % XY coordinates are expected in pixel units, with (0,0) at the top-left of the arena image (CRT coordinates).
    %
    % Supports initialization from:
    %   1) Path to *.arenagrid.mat
    %   2) A valid gradient export struct (arena_grid / gradientExport schema)
    %
    % Main methods are vectorized for Nx2 XY inputs:
    %   [tileRC, tileLinear, score] = query(xy)
    %   [tileRC, tileLinear, score] = query(xy, invertXGradient=true, invertYGradient=true)
    %   score = queryScore(xy)
    %   [tileRC, tileLinear] = queryTile(xy)
    %   tf = contains(xy) returns true for points inside the arena grid/mesh
    %   coords = crt2cartesian(xyCrt) converts from top-left-origin CRT to bottom-left-origin Cartesian coordinates
    %   coords = cartesian2crt(xyCartesian) converts from Cartesian to CRT coordinates


    properties (SetAccess = private)
        arena_grid struct
        triangulationObj
        scoreMatrix double
        nTilesXY (1,2) double
    end

    properties (Access = private)
        triangleToTileRC double
        triangleToTileLinear double
    end

    methods
        function obj = ArenaGrid(source)
            if nargin < 1
                error('trial:arenaGrid:ArenaGrid:MissingInput', ...
                    'Provide either a .arenagrid.mat path or a gradient export struct.');
            end

            arenaGrid = trial.arenaGrid.ArenaGrid.resolveSourceToStruct(source);
            trial.arenaGrid.ArenaGrid.validateGradientExportStruct(arenaGrid);

            vertices = double(arenaGrid.lookup.vertices_px);
            triangles = double(arenaGrid.lookup.triangles);
            triToTileRC = double(arenaGrid.lookup.triangle_to_tile_rc);
            nTilesXY = double(arenaGrid.grid.n_tiles_xy);

            % Always recompute score from stored nodes + midline + gradient config so the
            % score stays consistent with the actual midline position, regardless of what
            % value was frozen in the file.
            [pointA, pointB] = trial.arenaGrid.ArenaGrid.extractMidline(arenaGrid);
            if ~isempty(pointA) && ~isempty(pointB) && ...
                    isfield(arenaGrid.grid, 'nodes_x_px') && isfield(arenaGrid.grid, 'nodes_y_px')
                if ~isfield(arenaGrid, 'gradient')
                    warning('trial:arenaGrid:ArenaGrid:MissingGradientConfig', ...
                        ['Gradient config (function/values) not found in arena grid export. ' ...
                        'Falling back to default gradient values for score computation. ' ...
                        'Re-run the reference line UI to persist the correct gradient config.']);
                end
                [recomputedScore, ~] = trial.arenaGrid.ArenaGrid.regenerateScoreFromMidline(arenaGrid, pointA, pointB);
                arenaGrid.score = recomputedScore;
                arenaGrid.score_vector = recomputedScore(:);
            end

            obj.arena_grid = arenaGrid;
            obj.triangulationObj = triangulation(triangles, vertices);
            obj.scoreMatrix = double(arenaGrid.score);
            obj.nTilesXY = nTilesXY;
            obj.triangleToTileRC = triToTileRC;
            obj.triangleToTileLinear = sub2ind([nTilesXY(2), nTilesXY(1)], triToTileRC(:,1), triToTileRC(:,2));
        end

        function [tileRC, tileLinear, score] = query(obj, xy, args)
            %QUERY Return tile row/col, tile linear index, and score for each XY.
            arguments
                obj trial.arenaGrid.ArenaGrid
                xy (:,2) {mustBeNumeric}
                args.invertXGradient (1,1) logical = false
                args.invertYGradient (1,1) logical = false
            end
            xy = trial.arenaGrid.ArenaGrid.normalizeXY(xy);

            triId = pointLocation(obj.triangulationObj, xy(:,1), xy(:,2));
            n = size(xy, 1);

            tileRC = nan(n, 2);
            tileLinear = nan(n, 1);
            score = nan(n, 1);

            valid = ~isnan(triId);
            if any(valid)
                triIdx = triId(valid);
                tileRC(valid, :) = obj.triangleToTileRC(triIdx, :);
                tileLinear(valid) = obj.triangleToTileLinear(triIdx);
                queryScoreMatrix = obj.resolveQueryScoreMatrix(args.invertXGradient, args.invertYGradient);
                score(valid) = queryScoreMatrix(tileLinear(valid));
            end
        end

        function score = queryScore(obj, xy, args)
            %QUERYSCORE Return score only for each XY.
            % Optional args to invert the gradient direction along X and/or Y while still taking into account the mesh shape and reference line/point - these do not modify the underlying score matrix, just the returned score values.
            arguments
                obj trial.arenaGrid.ArenaGrid
                xy (:,2) {mustBeNumeric}
                args.invertXGradient (1,1) logical = false
                args.invertYGradient (1,1) logical = false
            end
            [~, ~, score] = obj.query(xy, ...
                invertXGradient=args.invertXGradient, ...
                invertYGradient=args.invertYGradient);
        end

        function [tileRC, tileLinear] = queryTile(obj, xy)
            %QUERYTILE Return tile row/col and tile linear index for each XY.
            [tileRC, tileLinear] = obj.query(xy);
        end

        function tf = contains(obj, xy)
            %CONTAINS True for XY points inside the triangulated arena grid.
            xy = trial.arenaGrid.ArenaGrid.normalizeXY(xy);
            triId = pointLocation(obj.triangulationObj, xy(:,1), xy(:,2));
            tf = ~isnan(triId);
        end

        function T = queryTable(obj, xy, args)
            %QUERYTABLE Convenience table output for batch queries.
            arguments
                obj trial.arenaGrid.ArenaGrid
                xy (:,2) {mustBeNumeric}
                args.invertXGradient (1,1) logical = false
                args.invertYGradient (1,1) logical = false
            end
            [tileRC, tileLinear, score] = obj.query(xy, ...
                invertXGradient=args.invertXGradient, ...
                invertYGradient=args.invertYGradient);
            T = table(xy(:,1), xy(:,2), tileRC(:,1), tileRC(:,2), tileLinear, score, ...
                'VariableNames', {'x', 'y', 'tile_row', 'tile_col', 'tile_linear', 'score'});
        end

        function arenaGrid = export(obj)
            %EXPORT Return the validated arena_grid struct held by this object.
            arenaGrid = obj.arena_grid;
        end

        function [pointA, pointB] = refMidline(obj)
            %REFMIDLINE Return midline points from ref.midline if available.
            [pointA, pointB] = trial.arenaGrid.ArenaGrid.extractMidline(obj.arena_grid);
        end

        function xyCartesian = crt2cartesian(obj, xyCrt)
            %CRT2CARTESIAN Convert top-left-origin XY to bottom-left-origin XY.
            videoHeight = trial.arenaGrid.ArenaGrid.getVideoHeightFromExport(obj.arena_grid);
            xyCartesian = trial.arenaGrid.ArenaGrid.convertCrtToCartesian(xyCrt, videoHeight);
        end

        function xyCrt = cartesian2crt(obj, xyCartesian)
            %CARTESIAN2CRT Convert bottom-left-origin XY to top-left-origin XY.
            videoHeight = trial.arenaGrid.ArenaGrid.getVideoHeightFromExport(obj.arena_grid);
            xyCrt = trial.arenaGrid.ArenaGrid.convertCartesianToCrt(xyCartesian, videoHeight);
        end
    end

    methods (Static)
        function obj = fromFile(matFilePath)
            obj = trial.arenaGrid.ArenaGrid(matFilePath);
        end

        function obj = fromStruct(gradientExport)
            obj = trial.arenaGrid.ArenaGrid(gradientExport);
        end

        function validateGradientExportStruct(gradientExport)
            if ~isstruct(gradientExport)
                error('trial:arenaGrid:ArenaGrid:InvalidType', ...
                    'Gradient export must be a struct.');
            end

            requiredTop = {'score', 'grid', 'lookup'};
            for i = 1:numel(requiredTop)
                if ~isfield(gradientExport, requiredTop{i})
                    error('trial:arenaGrid:ArenaGrid:MissingField', ...
                        'Missing required field: %s', requiredTop{i});
                end
            end

            requiredGrid = {'n_tiles_xy'};
            for i = 1:numel(requiredGrid)
                if ~isfield(gradientExport.grid, requiredGrid{i})
                    error('trial:arenaGrid:ArenaGrid:MissingField', ...
                        'Missing required field: grid.%s', requiredGrid{i});
                end
            end

            requiredLookup = {'vertices_px', 'triangles', 'triangle_to_tile_rc'};
            for i = 1:numel(requiredLookup)
                if ~isfield(gradientExport.lookup, requiredLookup{i})
                    error('trial:arenaGrid:ArenaGrid:MissingField', ...
                        'Missing required field: lookup.%s', requiredLookup{i});
                end
            end

            score = double(gradientExport.score);
            if ~ismatrix(score) || isempty(score)
                error('trial:arenaGrid:ArenaGrid:InvalidScore', ...
                    'score must be a non-empty 2D numeric matrix.');
            end

            nTilesXY = double(gradientExport.grid.n_tiles_xy);
            if numel(nTilesXY) ~= 2 || any(~isfinite(nTilesXY))
                error('trial:arenaGrid:ArenaGrid:InvalidTiles', ...
                    'grid.n_tiles_xy must be [nX, nY].');
            end
            nTilesXY = round(nTilesXY(:))';
            if any(nTilesXY < 1)
                error('trial:arenaGrid:ArenaGrid:InvalidTiles', ...
                    'grid.n_tiles_xy values must be >= 1.');
            end

            expectedScoreSize = [nTilesXY(2), nTilesXY(1)];
            if ~isequal(size(score), expectedScoreSize)
                error('trial:arenaGrid:ArenaGrid:ScoreSizeMismatch', ...
                    'score size must be [nY, nX] = [%d, %d].', expectedScoreSize(1), expectedScoreSize(2));
            end

            vertices = double(gradientExport.lookup.vertices_px);
            if size(vertices, 2) ~= 2 || isempty(vertices) || any(~isfinite(vertices), 'all')
                error('trial:arenaGrid:ArenaGrid:InvalidVertices', ...
                    'lookup.vertices_px must be a finite Nx2 matrix.');
            end

            triangles = double(gradientExport.lookup.triangles);
            if size(triangles, 2) ~= 3 || isempty(triangles)
                error('trial:arenaGrid:ArenaGrid:InvalidTriangles', ...
                    'lookup.triangles must be a non-empty Mx3 matrix.');
            end
            if any(triangles(:) < 1) || any(triangles(:) > size(vertices, 1)) || any(mod(triangles(:), 1) ~= 0)
                error('trial:arenaGrid:ArenaGrid:InvalidTriangles', ...
                    'lookup.triangles contain invalid vertex indices.');
            end

            triToTileRC = double(gradientExport.lookup.triangle_to_tile_rc);
            if size(triToTileRC, 2) ~= 2 || size(triToTileRC, 1) ~= size(triangles, 1)
                error('trial:arenaGrid:ArenaGrid:InvalidTriangleMap', ...
                    'lookup.triangle_to_tile_rc must be Mx2 and match number of triangles.');
            end
            if any(triToTileRC(:,1) < 1 | triToTileRC(:,1) > nTilesXY(2) | mod(triToTileRC(:,1), 1) ~= 0) || ...
                    any(triToTileRC(:,2) < 1 | triToTileRC(:,2) > nTilesXY(1) | mod(triToTileRC(:,2), 1) ~= 0)
                error('trial:arenaGrid:ArenaGrid:InvalidTriangleMap', ...
                    'lookup.triangle_to_tile_rc indices are out of range.');
            end

            if isfield(gradientExport, 'ref') && isstruct(gradientExport.ref) && ...
                    isfield(gradientExport.ref, 'video') && isstruct(gradientExport.ref.video)
                hasW = isfield(gradientExport.ref.video, 'width');
                hasH = isfield(gradientExport.ref.video, 'height');
                if hasW && hasH
                    w = double(gradientExport.ref.video.width);
                    h = double(gradientExport.ref.video.height);
                    if ~isscalar(w) || ~isscalar(h) || ~isfinite(w) || ~isfinite(h) || w <= 0 || h <= 0
                        error('trial:arenaGrid:ArenaGrid:InvalidVideoRef', ...
                            'ref.video.width and ref.video.height must be positive finite scalars.');
                    end
                end
            end

            if isfield(gradientExport, 'ref') && isstruct(gradientExport.ref) && ...
                    isfield(gradientExport.ref, 'midline')
                midline = gradientExport.ref.midline;
                if ~isstruct(midline) || ~isfield(midline, 'x') || ~isfield(midline, 'y')
                    error('trial:arenaGrid:ArenaGrid:InvalidMidlineRef', ...
                        'ref.midline must contain x and y fields.');
                end

                x = double(midline.x);
                y = double(midline.y);
                if numel(x) ~= 2 || numel(y) ~= 2 || any(~isfinite(x), 'all') || any(~isfinite(y), 'all')
                    error('trial:arenaGrid:ArenaGrid:InvalidMidlineRef', ...
                        'ref.midline.x and ref.midline.y must be finite 1x2 vectors.');
                end
            end
        end

        function xyCartesian = convertCrtToCartesian(xyCrt, videoHeight)
            %CONVERTCRTTOCARTESIAN Vectorized conversion from CRT to Cartesian.
            xyCrt = trial.arenaGrid.ArenaGrid.normalizeXY(xyCrt);
            videoHeight = trial.arenaGrid.ArenaGrid.normalizeVideoHeight(videoHeight);
            xyCartesian = [xyCrt(:,1), videoHeight - xyCrt(:,2)];
        end

        function xyCrt = convertCartesianToCrt(xyCartesian, videoHeight)
            %CONVERTCARTESIANTOCRT Vectorized conversion from Cartesian to CRT.
            xyCartesian = trial.arenaGrid.ArenaGrid.normalizeXY(xyCartesian);
            videoHeight = trial.arenaGrid.ArenaGrid.normalizeVideoHeight(videoHeight);
            xyCrt = [xyCartesian(:,1), videoHeight - xyCartesian(:,2)];
        end

        function [pointA, pointB] = extractMidline(gradientExport)
            %EXTRACTMIDLINE Return [x y] points from ref.midline when present.
            pointA = [];
            pointB = [];
            if ~isstruct(gradientExport) || ~isfield(gradientExport, 'ref') || ...
                    ~isstruct(gradientExport.ref) || ~isfield(gradientExport.ref, 'midline')
                return;
            end

            midline = gradientExport.ref.midline;
            if ~isstruct(midline) || ~isfield(midline, 'x') || ~isfield(midline, 'y')
                return;
            end

            x = double(midline.x);
            y = double(midline.y);
            if numel(x) < 2 || numel(y) < 2 || any(~isfinite(x(1:2)), 'all') || any(~isfinite(y(1:2)), 'all')
                return;
            end

            pointA = [x(1), y(1)];
            pointB = [x(2), y(2)];
        end
    end

    methods (Access = private)
        function scoreMatrix = resolveQueryScoreMatrix(obj, invertXGradient, invertYGradient)
            if ~invertXGradient && ~invertYGradient
                scoreMatrix = obj.scoreMatrix;
                return;
            end

            gradientExport = trial.arenaGrid.ArenaGrid.applyGradientInversionToExport(...
                obj.arena_grid, invertXGradient, invertYGradient);
            [pointA, pointB] = trial.arenaGrid.ArenaGrid.extractMidline(gradientExport);

            canRegenerate = ~isempty(pointA) && ~isempty(pointB) && ...
                isfield(gradientExport, 'grid') && isstruct(gradientExport.grid) && ...
                isfield(gradientExport.grid, 'nodes_x_px') && isfield(gradientExport.grid, 'nodes_y_px');
            if canRegenerate
                scoreMatrix = trial.arenaGrid.ArenaGrid.regenerateScoreFromMidline(gradientExport, pointA, pointB);
                return;
            end

            scoreMatrix = obj.scoreMatrix;
            if invertXGradient
                scoreMatrix = fliplr(scoreMatrix);
            end
            if invertYGradient
                scoreMatrix = flipud(scoreMatrix);
            end
        end
    end

    methods (Static, Access = private)
        function gradientExport = resolveSourceToStruct(source)
            if ischar(source) || (isstring(source) && isscalar(source))
                gradientExport = trial.arenaGrid.ArenaGrid.loadArenaGridStructFromMat(char(source));
                return;
            end

            if isstruct(source)
                gradientExport = source;
                return;
            end

            error('trial:arenaGrid:ArenaGrid:InvalidInput', ...
                'Input must be a .arenagrid.mat path or a gradient export struct.');
        end

        function gradientExport = loadArenaGridStructFromMat(matFilePath)
            if ~isfile(matFilePath)
                error('trial:arenaGrid:ArenaGrid:FileNotFound', ...
                    'File not found: %s', matFilePath);
            end

            S = load(matFilePath, '-mat');

            if isfield(S, 'arena_grid') && isstruct(S.arena_grid)
                gradientExport = S.arena_grid;
                matVarName = 'arena_grid';
            elseif isfield(S, 'gradientExport') && isstruct(S.gradientExport)
                gradientExport = S.gradientExport;
                matVarName = 'gradientExport';
            elseif isfield(S, 'uiselectReferenceLine_gradientExport') && isstruct(S.uiselectReferenceLine_gradientExport)
                gradientExport = S.uiselectReferenceLine_gradientExport;
                matVarName = 'uiselectReferenceLine_gradientExport';
            else
                error('trial:arenaGrid:ArenaGrid:MissingExport', ...
                    'Could not find a valid export struct in MAT file (expected arena_grid or gradientExport).');
            end

            % If ref.midline is already present, nothing to upgrade.
            [pointA, pointB] = trial.arenaGrid.ArenaGrid.extractMidline(gradientExport);
            if ~isempty(pointA) && ~isempty(pointB)
                return;
            end

            % Older files: backfill ref.midline from the sibling .ref.json.
            [pointA, pointB] = trial.arenaGrid.ArenaGrid.loadMidlineFromSiblingRefJson(matFilePath);
            if isempty(pointA) || isempty(pointB)
                warning('trial:arenaGrid:ArenaGrid:MidlineFallbackFailed', ...
                    ['No midline found in arena grid MAT or sibling .ref.json: %s\n' ...
                    'Score gradient may not reflect the correct midline position.'], matFilePath);
                return;
            end

            if ~isfield(gradientExport, 'ref') || ~isstruct(gradientExport.ref)
                gradientExport.ref = struct();
            end
            gradientExport.ref.midline = struct(...
                'x', [double(pointA(1)), double(pointB(1))], ...
                'y', [double(pointA(2)), double(pointB(2))]);

            % Persist the midline upgrade so future loads skip this fallback path.
            % Score recomputation is always done in the constructor, not here.
            try
                upgradedStruct = gradientExport;
                switch matVarName
                    case 'arena_grid'
                        arena_grid = upgradedStruct;
                        save(matFilePath, 'arena_grid', '-append');
                    case 'gradientExport'
                        gradientExport = upgradedStruct;
                        save(matFilePath, 'gradientExport', '-append');
                    case 'uiselectReferenceLine_gradientExport'
                        uiselectReferenceLine_gradientExport = upgradedStruct;
                        save(matFilePath, 'uiselectReferenceLine_gradientExport', '-append');
                end
            catch ME
                warning('trial:arenaGrid:ArenaGrid:MatUpgradeWriteFailed', ...
                    'Could not persist upgraded arena grid MAT file: %s\n%s', matFilePath, ME.message);
            end
        end

        function [pointA, pointB] = loadMidlineFromSiblingRefJson(matFilePath)
            pointA = [];
            pointB = [];

            [refDir, refBaseName, ~] = fileparts(matFilePath);
            jsonBaseName = regexprep(refBaseName, '(?i)\.arenagrid$', '');
            jsonPath = fullfile(refDir, strcat(jsonBaseName, '.json'));
            if ~isfile(jsonPath)
                return;
            end

            try
                jsonData = jsondecode(fileread(jsonPath));
            catch ME
                warning('trial:arenaGrid:ArenaGrid:RefJsonReadError', ...
                    'Could not read sibling ref JSON for midline fallback: %s\n%s', jsonPath, ME.message);
                return;
            end

            if ~isstruct(jsonData) || ~isfield(jsonData, 'midline') || ~isstruct(jsonData.midline) || ...
                    ~isfield(jsonData.midline, 'x') || ~isfield(jsonData.midline, 'y')
                return;
            end

            x = double(jsonData.midline.x);
            y = double(jsonData.midline.y);
            if numel(x) < 2 || numel(y) < 2 || any(~isfinite(x(1:2)), 'all') || any(~isfinite(y(1:2)), 'all')
                return;
            end

            pointA = [x(1), y(1)];
            pointB = [x(2), y(2)];
        end

        function [scoreMatrix, gradientMeta] = regenerateScoreFromMidline(gradientExport, pointA, pointB)
            nTilesXY = round(double(gradientExport.grid.n_tiles_xy(:)'));
            nX = max(1, nTilesXY(1));
            nY = max(1, nTilesXY(2));

            nodeX = [];
            nodeY = [];
            if isfield(gradientExport.grid, 'nodes_x_px') && isfield(gradientExport.grid, 'nodes_y_px')
                nodeX = double(gradientExport.grid.nodes_x_px);
                nodeY = double(gradientExport.grid.nodes_y_px);
            end

            validNodes = ~isempty(nodeX) && ~isempty(nodeY) && ...
                isequal(size(nodeX), [nY + 1, nX + 1]) && isequal(size(nodeY), [nY + 1, nX + 1]) && ...
                all(isfinite(nodeX), 'all') && all(isfinite(nodeY), 'all');
            if ~validNodes
                error('trial:arenaGrid:ArenaGrid:MissingGridNodes', ...
                    'Cannot regenerate score without valid grid.nodes_x_px and grid.nodes_y_px.');
            end

            centers = trial.arenaGrid.ArenaGrid.calculateCellCenters(nodeX, nodeY);
            allNodes = [nodeX(:), nodeY(:)];
            xNorm = trial.arenaGrid.ArenaGrid.normalizeXByMidline(centers, pointA, pointB, allNodes);

            [xFunction, yFunction, xValues, yValues] = trial.arenaGrid.ArenaGrid.resolveGradientConfig(gradientExport);
            xScores = trial.arenaGrid.ArenaGrid.evaluateGradientByFunction(xValues, xFunction, xNorm(:)');

            yNormGrid = repmat((1 - linspace(0, 1, nY + 1))', 1, nX + 1);
            yNormCenters = 0.25 * ( ...
                yNormGrid(1:end-1, 1:end-1) + ...
                yNormGrid(1:end-1, 2:end) + ...
                yNormGrid(2:end, 2:end) + ...
                yNormGrid(2:end, 1:end-1));
            yNormRowMajor = reshape(yNormCenters.', 1, []);
            yScores = trial.arenaGrid.ArenaGrid.evaluateGradientByFunction(yValues, yFunction, yNormRowMajor);

            scoreVector = xScores(:) .* yScores(:);
            scoreMatrix = reshape(scoreVector, [nX, nY])';
            gradientMeta = struct(...
                'x_function', xFunction, ...
                'y_function', yFunction, ...
                'x_values', xValues, ...
                'y_values', yValues);
        end

        function gradientExport = applyGradientInversionToExport(gradientExport, invertXGradient, invertYGradient)
            [xFunction, yFunction, xValues, yValues] = trial.arenaGrid.ArenaGrid.resolveGradientConfig(gradientExport);

            if invertXGradient
                xValues = fliplr(xValues);
            end
            if invertYGradient
                yValues = fliplr(yValues);
            end

            if ~isfield(gradientExport, 'gradient') || ~isstruct(gradientExport.gradient)
                gradientExport.gradient = struct();
            end
            gradientExport.gradient.x_function = char(string(xFunction));
            gradientExport.gradient.y_function = char(string(yFunction));
            gradientExport.gradient.x_values = xValues;
            gradientExport.gradient.y_values = yValues;
        end

        function centers = calculateCellCenters(nodeX, nodeY)
            nY = size(nodeX, 1) - 1;
            nX = size(nodeX, 2) - 1;
            centers = zeros(nX * nY, 2);
            idx = 1;
            for iy = 1:nY
                for ix = 1:nX
                    centers(idx, 1) = mean([nodeX(iy, ix), nodeX(iy, ix + 1), nodeX(iy + 1, ix + 1), nodeX(iy + 1, ix)]);
                    centers(idx, 2) = mean([nodeY(iy, ix), nodeY(iy, ix + 1), nodeY(iy + 1, ix + 1), nodeY(iy + 1, ix)]);
                    idx = idx + 1;
                end
            end
        end

        function xNorm = normalizeXByMidline(points, pointA, pointB, domainPts)
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
            values = double(values(:)');
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

        function [xFunction, yFunction, xValues, yValues] = resolveGradientConfig(gradientExport)
            xFunction = 'linear';
            yFunction = 'linear';
            xValues = [-1, 0, 1];
            yValues = [0.5, 1, 0.5];

            if isfield(gradientExport, 'gradient') && isstruct(gradientExport.gradient)
                g = gradientExport.gradient;
                if isfield(g, 'x_function') && ~isempty(g.x_function)
                    xFunction = char(string(g.x_function));
                end
                if isfield(g, 'y_function') && ~isempty(g.y_function)
                    yFunction = char(string(g.y_function));
                end
                if isfield(g, 'x_values') && isnumeric(g.x_values) && numel(g.x_values) >= 2
                    xValues = double(g.x_values(:)');
                end
                if isfield(g, 'y_values') && isnumeric(g.y_values) && numel(g.y_values) >= 2
                    yValues = double(g.y_values(:)');
                end
            end
        end

        function xy = normalizeXY(xy)
            if ~isnumeric(xy) || size(xy, 2) ~= 2
                error('trial:arenaGrid:ArenaGrid:InvalidXY', ...
                    'XY input must be an Nx2 numeric matrix in pixel coordinates.');
            end
            if isempty(xy)
                xy = zeros(0, 2);
                return;
            end
            xy = double(xy);
            if any(~isfinite(xy), 'all')
                error('trial:arenaGrid:ArenaGrid:InvalidXY', ...
                    'XY input contains NaN or Inf.');
            end
        end

        function videoHeight = normalizeVideoHeight(videoHeight)
            videoHeight = double(videoHeight);
            if ~isscalar(videoHeight) || ~isfinite(videoHeight) || videoHeight <= 0
                error('trial:arenaGrid:ArenaGrid:InvalidVideoHeight', ...
                    'videoHeight must be a positive finite scalar.');
            end
        end

        function videoHeight = getVideoHeightFromExport(gradientExport)
            if ~isfield(gradientExport, 'ref') || ~isstruct(gradientExport.ref) || ...
                    ~isfield(gradientExport.ref, 'video') || ~isstruct(gradientExport.ref.video) || ...
                    ~isfield(gradientExport.ref.video, 'height')
                error('trial:arenaGrid:ArenaGrid:MissingVideoRef', ...
                    'Missing ref.video.height in arena grid export.');
            end
            videoHeight = trial.arenaGrid.ArenaGrid.normalizeVideoHeight(gradientExport.ref.video.height);
        end
    end
end
