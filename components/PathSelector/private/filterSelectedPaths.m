%% filterSelectedPaths - Function
%
% function filteredPaths = filterSelectedPaths(paths, Name, Value)
%
% This function filters the paths based on the options provided.
%
% Parameters:
%   paths: The paths to be filtered. As 1d string array or cell array of char vectors.
%   Name-Value: The options for filtering the paths.
%       Type: (Required) The type of paths to be filtered. Either 'folder' or 'file'.
%       AllowMultiple: (Optional) A boolean value indicating whether multiple paths can be selected. Default is false.


function filteredPaths = filterSelectedPaths(paths, options)
    arguments
        paths {mustBeNonempty, mustBeCellOrString(paths)}
        
        options.Type (1,1) string {mustBeMember(options.Type, ["folder", "file"])} = "folder"
        options.AllowMultiple logical = false
    end

    % Validate the options
    if ~isfield(options, "Type")
        error("The 'Type' option is required. Specify either 'folder' or 'file'.");
    end
    if ~isfield(options, "AllowMultiple")
        options.AllowMultiple = false;
    end

    paths = cellstr(paths);

    % Filter the paths based on the options
    switch options.Type
        case "folder"
            filteredPaths = paths(cellfun(@isfolder, paths));
        case "file"
            filteredPaths = paths(~cellfun(@isfolder, paths));
        otherwise
            error("Invalid 'Type' value. Specify either 'folder' or 'file'.");
    end

    cellstr(filteredPaths);

    if isempty(filteredPaths)
        filteredPaths = cell(0);
        return;
    end


    % Check if multiple paths are allowed, if not, return the first path
    if ~options.AllowMultiple
        filteredPaths = cellstr(filteredPaths{1});
    end
end