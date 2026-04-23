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

            obj.arena_grid = arenaGrid;
            obj.triangulationObj = triangulation(triangles, vertices);
            obj.scoreMatrix = double(arenaGrid.score);
            obj.nTilesXY = nTilesXY;
            obj.triangleToTileRC = triToTileRC;
            obj.triangleToTileLinear = sub2ind([nTilesXY(2), nTilesXY(1)], triToTileRC(:,1), triToTileRC(:,2));
        end

        function [tileRC, tileLinear, score] = query(obj, xy)
            %QUERY Return tile row/col, tile linear index, and score for each XY.
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
                score(valid) = obj.scoreMatrix(tileLinear(valid));
            end
        end

        function score = queryScore(obj, xy)
            %QUERYSCORE Return score only for each XY.
            [~, ~, score] = obj.query(xy);
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

        function T = queryTable(obj, xy)
            %QUERYTABLE Convenience table output for batch queries.
            [tileRC, tileLinear, score] = obj.query(xy);
            T = table(xy(:,1), xy(:,2), tileRC(:,1), tileRC(:,2), tileLinear, score, ...
                'VariableNames', {'x', 'y', 'tile_row', 'tile_col', 'tile_linear', 'score'});
        end

        function arenaGrid = export(obj)
            %EXPORT Return the validated arena_grid struct held by this object.
            arenaGrid = obj.arena_grid;
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
                return;
            end
            if isfield(S, 'gradientExport') && isstruct(S.gradientExport)
                gradientExport = S.gradientExport;
                return;
            end
            if isfield(S, 'uiselectReferenceLine_gradientExport') && isstruct(S.uiselectReferenceLine_gradientExport)
                gradientExport = S.uiselectReferenceLine_gradientExport;
                return;
            end

            error('trial:arenaGrid:ArenaGrid:MissingExport', ...
                'Could not find a valid export struct in MAT file (expected arena_grid or gradientExport).');
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
