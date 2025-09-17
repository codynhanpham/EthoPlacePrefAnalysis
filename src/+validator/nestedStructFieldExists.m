function bool = nestedStructFieldExists(s, fieldPath)
    %%NESTEDSTRUCTFIELDEXISTS Checks if a nested field exists in a structure.
    %   
    %   bool = nestedStructFieldExists(s, fieldPath) checks if the nested field exists
    %
    %   Inputs:
    %       s - The structure to check
    %       fieldPath - A cell array of strings representing the path to the nested field
    %
    %   Outputs:
    %       bool - true if the nested field exists, false otherwise
    %
    %   Example:
    %       s.a.b.c = 1;
    %       exists = nestedStructFieldExists(s, {'a', 'b', 'c'}); % returns true
    %       exists = nestedStructFieldExists(s, {'a', 'b', 'd'}); % returns false

    arguments
        s struct
        fieldPath cell
    end

    bool = true; % Assume it exists initially

    currentStruct = s;
    for i = 1:length(fieldPath)
        fieldName = fieldPath{i};
        if isstruct(currentStruct) && isfield(currentStruct, fieldName)
            currentStruct = currentStruct.(fieldName);
        else
            bool = false;
            return;
        end
    end

end