function values = normalizeTextList(value, argumentName)
    if isstring(value) || ischar(value)
        values = string(value);
    elseif iscell(value)
        values = string(value);
    else
        error('Invalid %s value. Provide a string, char vector, string array, or cell array of text queries.', argumentName);
    end

    values = values(:).';
    if any(values == "")
        error('Invalid %s value. Empty entries are not allowed.', argumentName);
    end

    values = arrayfun(@quoteCliValue, values, 'UniformOutput', true);
end