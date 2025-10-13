function mustBeTextScalarOrEmpty(x)
    if isempty(x)
        return
    else
        mustBeTextScalar(x);
    end
end