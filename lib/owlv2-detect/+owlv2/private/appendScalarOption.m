function parts = appendScalarOption(flag, value, argumentName)
    if isempty(value)
        parts = string.empty(1, 0);
        return;
    end

    if isstring(value) || ischar(value)
        scalar = string(value);
        if scalar == ""
            parts = string.empty(1, 0);
            return;
        end
        parts = [string(flag), quoteCliValue(scalar)];
        return;
    end

    if ~(isscalar(value) || islogical(value))
        error('Invalid %s value. Provide a scalar or empty to use the CLI default.', argumentName);
    end

    parts = [string(flag), string(num2str(value))];
end