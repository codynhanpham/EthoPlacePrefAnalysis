function [dirparts, name, ext] = canonicalPathParts(path, root)
    % canonicalPathParts - Get the directory parts, name, and extension of a path in a consistent way.
    %
    % This function uses filesep to split the path into parts, ensuring it works across different operating systems.
    % It also handles edge cases such as paths with trailing file separators or no extension, following the behavior of fileparts().
    %
    % Usage:
    %   [dirparts, name, ext] = canonicalPathParts(path, root)
    %
    % Inputs:
    %   path - The input path string (can be relative or absolute)
    %   root - (optional) The root directory to resolve relative paths against. Defaults to pwd.
    %
    % Outputs:
    %   dirparts - A cell array of directory parts leading to the file. Reconstruct the directory path with fullfile(dirparts{:}).
    %   name - The base name of the file without extension.
    %   ext - The file extension (including the dot), or an empty string if there is no extension.

    arguments
        path {mustBeTextScalar}
        root {mustBeTextScalar} = pwd
    end

    canonicalPath = utils.path.canonicalize(path, root);

    % Get the name + extension, this will be the last part of the path
    [dirpath, name, ext] = fileparts(canonicalPath);

    % Canonicalized path should follow the OS-specific file separator, so we can split on that
    dirparts = strsplit(dirpath, filesep);
end