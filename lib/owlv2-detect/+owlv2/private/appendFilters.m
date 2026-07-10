function parts = appendFilters(value)
    if isempty(value)
        parts = string.empty(1, 0);
        return;
    end

    filters = normalizeFilterPairs(value);
    parts = string.empty(1, 0);
    for i = 1:size(filters, 1)
        parts = [parts, "-f", quoteCliValue(filters{i, 1}), string(num2str(filters{i, 2}))]; %#ok<AGROW>
    end
end