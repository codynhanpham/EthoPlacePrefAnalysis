function x = numericOrNaN(value)
    if isnumeric(value) && isscalar(value)
        x = double(value);
        return;
    end

    x = str2double(string(value));
    if isnan(x)
        x = NaN;
    end
end
