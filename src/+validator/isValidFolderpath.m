function isValid = isValidFolderpath(str)
    %%ISVALIDFOLDERPATH Check if a string is a valid folder path, regardless of whether the folder currently exist or not
    %
    %   isValid = isValidFolderpath(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   Outputs:
    %       isValid - true if the string is a valid folder path, regardless of whether the folder currently exist or not
    %
    %   See also: validator.isValidFoldername, validator.isValidFilename, validator.isValidFilepath
    
    % Check if input is empty or not a string/char
    if isempty(str) || (~isstring(str) && ~ischar(str))
        isValid = false;
        return;
    end
    
    str = char(str);
    
    % Check if string is empty or all whitespace
    if isempty(str) || all(isspace(str))
        isValid = false;
        return;
    end
    
    % Normalize path separators to use filesep for consistency
    normalizedPath = strrep(str, '/', filesep);
    normalizedPath = strrep(normalizedPath, '\', filesep);
    
    % Handle special cases first
    
    % 1. Check for UNC paths on Windows (\\server\share)
    if ispc && length(normalizedPath) >= 2 && strcmp(normalizedPath(1:2), [filesep filesep])
        % UNC path: \\server\share\...
        if length(normalizedPath) == 2
            % Just "\\" is not valid
            isValid = false;
            return;
        end
        % Remove the leading "\\" and validate the rest
        pathParts = strsplit(normalizedPath(3:end), filesep);
        if length(pathParts) < 2 || isempty(pathParts{1}) || isempty(pathParts{2})
            % UNC path must have at least server and share
            isValid = false;
            return;
        end
        % Validate each part (server, share, and any subdirectories)
        for i = 1:length(pathParts)
            if ~isempty(pathParts{i}) && ~validator.isValidFoldername(pathParts{i})
                isValid = false;
                return;
            end
        end
        isValid = true;
        return;
    end
    
    % 2. Check for Windows drive letters (C:, C:\, C:\folder)
    if ispc && length(normalizedPath) >= 2 && normalizedPath(2) == ':'
        driveLetter = normalizedPath(1);
        % Check if it's a valid drive letter
        if ~isstrprop(driveLetter, 'alpha')
            isValid = false;
            return;
        end
        
        % Handle different drive path formats
        if length(normalizedPath) == 2
            % Just "C:" - valid
            isValid = true;
            return;
        elseif length(normalizedPath) == 3 && normalizedPath(3) == filesep
            % "C:\" - valid
            isValid = true;
            return;
        elseif normalizedPath(3) == filesep
            % "C:\folder\..." - validate the rest
            pathParts = strsplit(normalizedPath(4:end), filesep);
        else
            % "C:folder" - relative to current directory on drive C
            pathParts = strsplit(normalizedPath(3:end), filesep);
        end
        
        % Validate each path component
        for i = 1:length(pathParts)
            if ~isempty(pathParts{i})
                % Allow relative path components like "." and ".."
                if ~(strcmp(pathParts{i}, '.') || strcmp(pathParts{i}, '..') || validator.isValidFoldername(pathParts{i}))
                    isValid = false;
                    return;
                end
            end
        end
        isValid = true;
        return;
    end
    
    % 3. Handle relative and absolute paths without drive letters
    
    % Check if it starts with a separator (absolute path on Unix/Linux)
    if normalizedPath(1) == filesep
        % Absolute path: /folder/subfolder
        if isscalar(normalizedPath)
            % Just "/" - valid root
            isValid = true;
            return;
        end
        pathParts = strsplit(normalizedPath(2:end), filesep);
    else
        % Relative path: folder/subfolder, ./folder, ../folder
        pathParts = strsplit(normalizedPath, filesep);
    end
    
    % Validate each path component
    for i = 1:length(pathParts)
        if ~isempty(pathParts{i})
            % Allow relative path components like "." and ".."
            if ~(strcmp(pathParts{i}, '.') || strcmp(pathParts{i}, '..') || validator.isValidFoldername(pathParts{i}))
                isValid = false;
                return;
            end
        end
    end
    
    % Check for consecutive separators (which would create empty parts)
    if contains(normalizedPath, [filesep filesep])
        % Multiple consecutive separators are generally not valid
        % Exception: UNC paths already handled above
        isValid = false;
        return;
    end
    
    % Check for trailing separator
    if length(normalizedPath) > 1 && normalizedPath(end) == filesep
        % Trailing separator is generally acceptable for directories
        % No additional validation needed
    end
    
    % If we've made it this far, the path is valid
    isValid = true;
end