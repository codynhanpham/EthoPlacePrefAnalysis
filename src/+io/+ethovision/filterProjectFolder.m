function filterProjectFolder(comp)
    %FILTERPROJECTFOLDER To be used with FolderSelectorWithDropdown component
    %   Provide this function handle and its {2:end} arguments to FolderSelectorWithDropdown.DropdownItemsFilterFcn
    %   {@filterProjectFolder}

    if nargin < 1
        return
    end
    
    comp.DropdownItems = cell(0,2);

    % Filter for subfolders that are EthoVision project folders
    subfolders = dir(string(comp.SelectedParent));
    subfolders = subfolders([subfolders.isdir]);
    subfolders = subfolders(~ismember({subfolders.name}, {'.', '..'}));
    evProjectFolders = subfolders(arrayfun(@(x) validator.isEthovisionProjectFolder(fullfile(comp.SelectedParent, x.name)), subfolders));
    [~, sortIdx] = sort(string({evProjectFolders.name}), 'descend');
    evProjectFolders = evProjectFolders(sortIdx);
    evProjectFoldersPath = fullfile(comp.SelectedParent, {evProjectFolders.name});

    if isempty(evProjectFoldersPath)
        if ~isempty(comp.AppFigure)
            uialert(comp.AppFigure, ...
            sprintf("The metadata file does not list any imaging output, or the imaging output directory does not exist."), ...
            "Missing Imaging Output", ...
            "Icon",'warning');
        end
        comp.DropdownItems = cell(0,1);
        return
    end

    % For project folders, create a struct with fields: dir = value of dir(), type = 'single'
    for i = 1:length(evProjectFoldersPath)
        dirname = evProjectFoldersPath{i};
        [~, dirname] = fileparts(dirname);
        comp.DropdownItems{i,1} = char(dirname);
        comp.DropdownItems{i,2} = struct('dir', evProjectFolders(i), 'type', 'single');
    end

    % Add a (Population) option with dir = evProjectFolders, type = 'population' and place it at the top
    comp.DropdownItems = [ {'(Population)', struct('dir', evProjectFolders, 'type', 'population')}; comp.DropdownItems ];

    if isempty(comp.SelectedContent)
        comp.setSelection(2); % Select the first EthoVision project folder by default
    end
end