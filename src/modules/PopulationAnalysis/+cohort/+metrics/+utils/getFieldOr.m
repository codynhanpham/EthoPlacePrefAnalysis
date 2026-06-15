function out = getFieldOr(s, fieldName, defaultVal)
    if isstruct(s) && isfield(s, fieldName)
        out = s.(fieldName);
    else
        out = defaultVal;
    end
end
