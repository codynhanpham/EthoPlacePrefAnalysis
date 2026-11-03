function s = textScalar(x, name)
    %TEXTSCALAR Coerce a value to a string scalar.
    %
    %   s = cohort.internal.textScalar(x)
    %   s = cohort.internal.textScalar(x, 'stimfileName')
    %
    %   Accepts char row vectors, string scalars, 1x1 cells (unwrapped
    %   recursively), and scalar numerics. Anything else raises a clear error
    %   naming the offending field. Used to normalize metadata- and
    %   table-derived labels (stimfileName, strain, genotype, ...) whose
    %   storage type can vary across standardizedTables producers.

    arguments
        x
        name {mustBeTextScalar} = 'value'
    end

    if ischar(x)
        s = string(x);
    elseif isstring(x) && isscalar(x)
        s = x;
    elseif iscell(x) && numel(x) == 1
        s = cohort.internal.textScalar(x{1}, name);
    elseif isnumeric(x) && isscalar(x)
        s = string(x);
    else
        error('cohort:internal:textScalar:NotTextScalar', ...
            '%s must hold a single text value (got %s with %d element(s)).', ...
            name, class(x), numel(x));
    end
end
