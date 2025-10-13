function mustBeValidFilename(str)
    %%MUSTBEVALIDFILENAME Assert a string is a valid filename, regardless of whether the file currently exist or not
    %
    %   mustBeValidFilename(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: mustBeValidFilename, mustBeValidFilenameOrEmpty, mustBeValidFolderPath, mustBeValidFolderPathOrEmpty
    
    if ~validator.isValidFilename(str)
        error('Input must be a valid filename (can be created, or currently exist) for the system')
    end
end