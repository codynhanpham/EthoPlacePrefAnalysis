function mustBeValidFolderpath(str)
    %%MUSTBEVALIDFOLDERPATH Assert a string is a valid folder path, regardless of whether the folder currently exist or not
    %
    %   mustBeValidFolderpath(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: mustBeValidFoldername, mustBeValidFilename, mustBeValidFilepath
    
    if ~validator.isValidFolderpath(str)
        error('Input must be a valid folder path (can be created, or currently exist) for the system')
    end

end