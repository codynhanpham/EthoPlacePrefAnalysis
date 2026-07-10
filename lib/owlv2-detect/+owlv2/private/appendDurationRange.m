function parts = appendDurationRange(value)
    if isempty(value)
        parts = string.empty(1, 0);
        return;
    end

    if ~isnumeric(value) || numel(value) ~= 2
        error('Invalid DurationRange value. Provide a numeric vector with 2 elements or empty.');
    end

    parts = ["-r", string(strjoin(string(value(:).'), " "))];
end