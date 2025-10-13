function mustBeValidFoldernameOrEmpty(str)
    %%MUSTBEVALIDFOLDERNAMEOREMPTY Assert a string is a valid folder name, regardless of whether the folder currently exist or not
    %
    %   mustBeValidFoldernameOrEmpty(str)
    %
    %   Inputs:
    %       str - string to check
    %
    %   See also: mustBeValidFoldername, mustBeValidFilename, mustBeValidFilepath
    
    if isempty(str)
        return
    end
    
    if ~validator.isValidFoldername(str)
        error('Input must be a valid folder name (can be created, or currently exist) for the system or an empty string.')
    end
end