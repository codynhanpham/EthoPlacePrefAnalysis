function value = metricByIndex(metrics, idx)
    value = NaN;
    if ~isempty(idx) && idx >= 1 && idx <= numel(metrics)
        value = metrics(idx);
    end
end
