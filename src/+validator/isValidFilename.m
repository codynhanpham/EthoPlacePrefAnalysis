function isValid = isValidFilename(str)
    %ISVALIDFILENAME Check if a string could be used as a filename
    %
    %   isValid = isValidFilename(filename)
    %
    %   Inputs:
    %       str - string to check
    %
    %   Outputs:
    %       isValid - true if the string could be used as a filename
    
    str = char(str);
    
    badCharacters = ismember(str, ['/' '\' '*' ':' '?' '<' '>' '|' '"']);
    isValid = ~isempty(str) && ~any(badCharacters) && ~isfolder(str);
    if ~isValid, return; end

    % If the string is of length 1, must also not contains a dot or a space
    if isValid && isscalar(str)
        if class(str) == "string", str = char(str); end
        isValid = ~any(str == '.');
        isValid = isValid & ~any(str == ' ');
    end
end