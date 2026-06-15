function stats = statsByIndex(localStats, idx)
    stats = [NaN, NaN, NaN, NaN];
    if ~isempty(idx) && idx >= 1 && idx <= size(localStats, 1)
        stats = localStats(idx, :);
    end
end
