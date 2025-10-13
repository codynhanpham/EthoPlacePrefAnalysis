function mustBeValidFoldername(str)
    %%MUSTBEVALIDFOLDERNAME Assert a string is a valid folder name, regardless of whether the folder currently exist or not
    %
    %   mustBeValidFoldername(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: mustBeValidFoldername, mustBeValidFilename, mustBeValidFilepath
    
    if ~validator.isValidFoldername(str)
        error('Input must be a valid folder name (can be created, or currently exist) for the system')
    end

end