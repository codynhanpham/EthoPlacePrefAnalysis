function [vertices, isUsable] = normalizeArenaGridVertices(verticesIn)
    vertices = zeros(0, 2);
    isUsable = false;

    if isempty(verticesIn)
        return;
    end

    if iscell(verticesIn)
        try
            verticesIn = cell2mat(verticesIn);
        catch
            return;
        end
    end

    if ~isnumeric(verticesIn)
        return;
    end

    verticesIn = double(verticesIn);
    if isvector(verticesIn) && numel(verticesIn) == 2
        verticesIn = reshape(verticesIn, 1, 2);
    end

    if ndims(verticesIn) ~= 2 || size(verticesIn, 2) ~= 2 || ~all(isfinite(verticesIn), 'all')
        return;
    end

    vertices = verticesIn;
    isUsable = true;
end