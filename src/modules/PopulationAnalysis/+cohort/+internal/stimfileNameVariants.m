function variants = stimfileNameVariants(x, name)
    %STIMFILENAMEVARIANTS All stimulus file names stored in a stimfileName field.
    %
    %   variants = cohort.internal.stimfileNameVariants(x)
    %
    %   A standardizedTables entry produced by
    %   population.temp.joinStdTableByStim stores the ORIGINAL protocol file
    %   names of the joined variations in stimfileName (a cell array), while
    %   single-protocol tables store a plain char/string. This helper returns
    %   every name as a string column vector: char/string scalars yield one
    %   entry, cell arrays yield one entry per element (1x1 nested cells are
    %   unwrapped recursively).

    arguments
        x
        name {mustBeTextScalar} = 'stimfileName'
    end

    if ischar(x)
        variants = string(x);
    elseif isstring(x)
        variants = x(:);
    elseif iscell(x)
        parts = strings(0, 1);
        for i = 1:numel(x)
            parts = [parts; cohort.internal.stimfileNameVariants(x{i}, name)]; %#ok<AGROW>
        end
        variants = parts;
    else
        error('cohort:internal:stimfileNameVariants:NotText', ...
            '%s must hold text (char, string, or a cell of text), got %s.', ...
            name, class(x));
    end

    variants = variants(:);
    variants = variants(strlength(strtrim(variants)) > 0);
end
