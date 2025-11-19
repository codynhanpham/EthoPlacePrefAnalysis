function mustBeValidFilenameOrEmpty(str)
    %MUSTBEVALIDFILENAMEOREMPTY Check a given string that could be either a valid filename or an empty string
    %
    %   mustBeValidFilenameOrEmpty(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: isValidFilename, mustBeEmpty
    
    str = char(str);
    
    if isempty(str)
        return
    end

    if ~ffmpeg.validator.isValidFilename(str)
        error('The string must be a valid filename or an empty string')
    end
end