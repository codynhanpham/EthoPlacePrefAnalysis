function bool = isEthovisionProjectFolder(folderPath)
    %%ISETHOVISIONPROJECTFOLDER Check if a folder is an EthoVision project folder
    %   A valid EthoVision project folder must contains at least:
    %       - A project file with extension `.evxt`
    %       - A `Export Files` subfolder
    %       - A `Media Files` subfolder

    arguments
        folderPath {mustBeFolder}
    end

    projectFile = fullfile(folderPath, '*.evxt');
    if isempty(dir(string(projectFile)))
        bool = false;
        return;
    end

    exportFolder = fullfile(folderPath, 'Export Files');
    if ~isfolder(exportFolder)
        bool = false;
        return;
    end

    mediaFolder = fullfile(folderPath, 'Media Files');
    if ~isfolder(mediaFolder)
        bool = false;
        return;
    end

    bool = true;
end