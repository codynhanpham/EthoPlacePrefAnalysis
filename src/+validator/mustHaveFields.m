function mustHaveFields(value, requiredFields)
    %MUSTHAVEFIELDS Assert that a struct has all the required fields
    %
    %   mustHaveFields(value, requiredFields)
    %
    %   Inputs:
    %       value - struct to check
    %       requiredFields - cell array of strings, each string is the name of a required field

    if ~isstruct(value)
        error('Validator:InvalidStruct', 'Input must be a struct.');
    end

    requiredFields = cellstr(requiredFields);

    if ~all(isfield(value, requiredFields))
        missing = requiredFields(~isfield(value, requiredFields));
        error('Validator:MissingFields', 'Missing required fields: {''%s''}', strjoin(missing, ''', '''));
    end
end