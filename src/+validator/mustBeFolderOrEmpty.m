function mustBeFolderOrEmpty(input)
    %%MUSTBEFOLDEROREMPTY Assert that the input is either an empty string or a valid folder path
    %   This function, if input is NOT empty, also make sure the folder exists. To only require a valid folder path (even if it does not currently exist), use mustBeValidFolderPath() or mustBeValidFolderPathOrEmpty()
    %
    %   mustBeFolderOrEmpty(input)
    %
    %   Inputs:
    %       input - input to check. Valid inputs are:
    %           - empty string
    %           - folder path that exists
    %
    %   See also: mustBeValidFolderpath, mustBeValidFolderpathOrEmpty, mustBeValidFilenameOrEmpty
    
    if isempty(input)
        return
    end
    if ~isfolder(fullfile(input))
        error('The string must be a valid folder path or an empty string')
    end
end