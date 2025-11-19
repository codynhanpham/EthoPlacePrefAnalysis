function isValid = isValidFilepath(str)
    %ISVALIDFILEPATH Check if a string is a valid file path, regardless of whether the file currently exist or not
    %
    %   isValid = isValidFilename(filename)
    %
    %   Inputs:
    %       str - string to check
    %
    %   Outputs:
    %       isValid - true if the string is a valid file path, regardless of whether the file currently exist or not
    
    str = char(str);
    
    isValid = ~isempty(str) && ~isfolder(str);
    if ~isValid, return; end
    [~, name, ~] = fileparts(str);
    if ~ffmpeg.validator.isValidFilename(name), isValid = false; return; end

    % If the string is of length 1, must also not contains a dot or a space
    if class(str) == "string", str = char(str); end
    if isValid && isscalar(str)
        isValid = ~any(str == '.');
        isValid = isValid & ~any(str == ' ');
    end
end