function isValid = isValidFoldername(str)
    %%ISVALIDFOLDERNAME Check if a string could be used as a folder name
    %
    %   isValid = isValidFoldername(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   Outputs:
    %       isValid - true if the string could be used as a folder name
    
    % Check if input is empty or not a string/char
    if isempty(str) || (~isstring(str) && ~ischar(str))
        isValid = false;
        return;
    end
    
    str = char(str);
    
    if isempty(str) || all(isspace(str))
        isValid = false;
        return;
    end
    
    % Invalid characters for Windows (most restrictive)
    invalidChars = '<>:"|?*/\';
    for i = 1:length(invalidChars)
        if contains(str, invalidChars(i))
            isValid = false;
            return;
        end
    end
    
    % Check for control characters (ASCII 0-31)
    if any(str < 32)
        isValid = false;
        return;
    end
    
    % Check for trailing dots or spaces (invalid on Windows)
    if endsWith(str, '.') || endsWith(str, ' ')
        isValid = false;
        return;
    end
    
    % Check for reserved names on Windows (case-insensitive)
    reservedNames = {'CON', 'PRN', 'AUX', 'NUL', ...
                    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', ...
                    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'};
    baseName = str;
    dotIndex = find(str == '.', 1);
    if ~isempty(dotIndex)
        baseName = str(1:dotIndex-1);
    end
    
    if any(strcmpi(baseName, reservedNames))
        isValid = false;
        return;
    end
    
    % Check for relative path
    if strcmp(str, '.') || strcmp(str, '..')
        isValid = false;
        return;
    end
    
    % After all the checks, the string is probably a valid folder name
    isValid = true;
end