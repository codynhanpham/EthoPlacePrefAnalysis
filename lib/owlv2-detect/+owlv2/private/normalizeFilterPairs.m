function filters = normalizeFilterPairs(value)
    if ~iscell(value)
        error('Invalid Filter value. Provide a nested cell array like {{type, value}, {type, value}} or empty.');
    end

    if isempty(value)
        filters = cell(0, 2);
        return;
    end

    if size(value, 2) ~= 2
        error('Invalid Filter value. Each filter entry must contain exactly {type, value}.');
    end

    allowedTypes = ["brightness", "contrast", "highlight", "shadow"];
    filters = value;

    for i = 1:size(filters, 1)
        typeValue = string(filters{i, 1});
        numericValue = filters{i, 2};

        if typeValue == ""
            error('Invalid Filter entry at row %d. Filter type cannot be empty.', i);
        end
        if ~any(typeValue == allowedTypes)
            error('Invalid Filter entry at row %d. Supported filter types are brightness, contrast, highlight, and shadow.', i);
        end
        if isempty(numericValue) || ~isscalar(numericValue) || ~isnumeric(numericValue)
            error('Invalid Filter entry at row %d. Filter value must be a numeric scalar between -1 and 1.', i);
        end
        if numericValue < -1 || numericValue > 1
            error('Invalid Filter entry at row %d. Filter value must be between -1 and 1.', i);
        end

        filters{i, 1} = char(typeValue);
        filters{i, 2} = numericValue;
    end
end