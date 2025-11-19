function mustBeValidFilepath(str)
    %%MUSTBEVALIDFILEPAT Assert a string is a valid file path, regardless of whether the file currently exist or not
    %
    %   mustBeValidFilepathOrEmpty(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: mustBeValidFilename, mustBeValidFilenameOrEmpty, mustBeValidFolderPath, mustBeValidFolderPathOrEmpty
    
    if ~ffmpeg.validator.isValidFilepath(str)
        error('Input must be a valid file path (can be created, or currently exist) for the system or an empty string.')
    end
end