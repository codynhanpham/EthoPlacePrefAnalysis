function mustBeValidFilenameOrEmpty(str)
    %MUSTBEVALIDFILENAMEOREMPTY Check a given string that could be either a valid filename or an empty string
    %
    %   mustBeValidFilenameOrEmpty(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: isValidFilename, mustBeEmpty
    
    if isempty(str)
        return
    end

    if ~validator.isValidFilename(str)
        error('The string must be a valid filename or an empty string')
    end
end