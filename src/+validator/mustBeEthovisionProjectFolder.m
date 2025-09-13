function mustBeEthovisionProjectFolder(folderPath)
    %%MUSTBEETHOVISIONPROJECTFOLDER Validate if a folder is an EthoVision project folder
    %
    % See also: isEthovisionProjectFolder

    if ~isEthovisionProjectFolder(folderPath)
        error("Invalid EthoVision project folder. A valid EthoVision project folder must contains at least:" + newline + ...
            "   - A project file with extension `.evxt`" + newline + ...
            "   - A `Export Files` subfolder" + newline + ...
            "   - A `Media Files` subfolder" + newline);
    end
end