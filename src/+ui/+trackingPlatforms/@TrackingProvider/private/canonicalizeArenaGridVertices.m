function [vertices, isUsable] = canonicalizeArenaGridVertices(verticesIn)
    [normalizedVertices, isUsable] = normalizeArenaGridVertices(verticesIn);
    vertices = zeros(0, 2);

    if ~isUsable || size(normalizedVertices, 1) ~= 4
        isUsable = false;
        return;
    end

    pointSums = sum(normalizedVertices, 2);
    pointDiffs = normalizedVertices(:, 1) - normalizedVertices(:, 2);

    [~, topLeftIdx] = min(pointSums);
    [~, bottomRightIdx] = max(pointSums);
    [~, topRightIdx] = max(pointDiffs);
    [~, bottomLeftIdx] = min(pointDiffs);

    orderedIdx = [topLeftIdx, topRightIdx, bottomRightIdx, bottomLeftIdx];
    if numel(unique(orderedIdx)) ~= 4
        sortedVertices = sortrows(normalizedVertices, [2, 1]);
        topVertices = sortedVertices(1:2, :);
        bottomVertices = sortedVertices(3:4, :);

        [~, topOrder] = sort(topVertices(:, 1), 'ascend');
        topVertices = topVertices(topOrder, :);

        [~, bottomOrder] = sort(bottomVertices(:, 1), 'ascend');
        bottomVertices = bottomVertices(bottomOrder, :);

        vertices = [topVertices(1, :); topVertices(2, :); bottomVertices(2, :); bottomVertices(1, :)];
        isUsable = true;
        return;
    end

    vertices = normalizedVertices(orderedIdx, :);
    isUsable = true;
end