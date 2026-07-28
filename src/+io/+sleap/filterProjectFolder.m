function filterProjectFolder(comp, kvargs)
    %FILTERPROJECTFOLDER To be used with FolderSelectorWithDropdown component
    %   Provide this function handle and its {2:end} arguments to FolderSelectorWithDropdown.DropdownItemsFilterFcn
    %   {@filterProjectFolder}

    arguments
        comp (1,1) FolderSelectorWithDropdown
        kvargs.SearchDepth (1,1) double {mustBePositive, mustBeInteger} = 2
        kvargs.VideoExtensions (1,:) {mustBeText} = {'mp4', 'avi', 'mov'}
    end

    if isempty(comp.SelectedParent) || ~isfolder(comp.SelectedParent)
        comp.DropdownItems = cell(0,2);
        return
    end
    
    comp.DropdownItems = cell(0,2);


    % Any direct subfolders, whose 'SearchDepth' level subfolders contains any 'VideoExtensions' files are valid
    subfolders = dir(string(comp.SelectedParent));
    subfolders = subfolders([subfolders.isdir]);
    subfolders = subfolders(~ismember({subfolders.name}, {'.', '..'}));
    projectFolders = struct.empty();
    projectFoldersPath = cell(0,1);
    
    % Search each subfolder for video files within SearchDepth levels
    for subIdx = 1:length(subfolders)
        subfolderPath = fullfile(comp.SelectedParent, subfolders(subIdx).name);
        
        % Check if this subfolder or its subdirectories contain video files
        hasVideoFiles = false;
        
        for depth = 0:kvargs.SearchDepth-1
            for extIdx = 1:length(kvargs.VideoExtensions)
                ext = kvargs.VideoExtensions{extIdx};
                
                % Build the search pattern with depth wildcards
                depthPattern = join(repmat(strcat("*", filesep), [1, depth]), '');
                if depth == 0
                    depthPattern = "";
                end
                
                filterMatchPattern = sprintf('*.%s', ext);
                fullFileMatch = fullfile(subfolderPath, depthPattern, filterMatchPattern);
                
                foundFiles = dir(fullFileMatch);
                if ~isempty(foundFiles)
                    hasVideoFiles = true;
                    break;
                end
            end
            
            if hasVideoFiles
                break;
            end
        end
        
        % If video files were found, add this folder to the project folders
        if hasVideoFiles
            if isempty(projectFolders)
                projectFolders = subfolders(subIdx);
            else
                projectFolders(end+1) = subfolders(subIdx); %#ok<AGROW>
            end
            projectFoldersPath{end+1} = subfolderPath; %#ok<AGROW>
        end
    end


    if isempty(projectFoldersPath)
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
    for i = 1:length(projectFoldersPath)
        dirname = projectFoldersPath{i};
        [~, dirname] = fileparts(dirname);
        comp.DropdownItems{i,1} = char(dirname);
        comp.DropdownItems{i,2} = struct('dir', projectFolders(i), 'type', 'single');
    end

    % Add a (Population) option with dir = projectFolders, type = 'population' and place it at the top
    comp.DropdownItems = [ {'(Population)', struct('dir', projectFolders, 'type', 'population')}; comp.DropdownItems ];

    if isempty(comp.SelectedContent)
        comp.setSelection(2); % Select the first project folder by default
    end
end