function mustBeYmlOrStruct(x)
    %%MUSTBEYMLORSTRUCT Validate that input is either a YAML file path or a struct

    if ~(ischar(x) || isstring(x) || iscellstr(x) || isstruct(x))
        error('Input must be either a YAML file path (string/char) or a struct.');
    end
    if (ischar(x) || isstring(x) || iscellstr(x))
        if ~isfile(x)
            error('Input string/char must be a valid file path to a YAML file.');
        end
        [~, ~, ext] = fileparts(x);
        if ~ismember(lower(ext), {'.yml', '.yaml'})
            error('Input file must have a .yml or .yaml extension.');
        end
    end
end