function parts = appendCrop(value)
    if isempty(value)
        parts = string.empty(1, 0);
        return;
    end

    if ~isnumeric(value) || numel(value) ~= 4
        error('Invalid Crop value. Provide a numeric vector with 4 elements or empty.');
    end

    parts = ["-c", string(strjoin(string(value(:).'), " "))];
end