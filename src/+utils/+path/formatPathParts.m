function str = formatPathParts(path, nparts, sep)
    %%FORMATPATHPARTS Format the last N parts of a file path into a single string
    %   This function takes a path and returns a string consisting of the last N parts of the path,
    %   joined by the file separator. This is useful for displaying short/relative paths in titles or labels.

    arguments
        path (1,1) string
        nparts (1,1) {mustBePositive, mustBeInteger} = 2
        sep {mustBeTextScalar} = filesep
    end

    pathParts = fullfile(path); % Normalize the path
    pathParts = char(pathParts); % Convert to char array for strsplit
    pathParts = strsplit(pathParts, sep);
    
    if length(pathParts) <= nparts
        str = path; % Return the full path if it has fewer parts than nparts
    else
        str = strjoin(pathParts(end-nparts+1:end), "/");
    end
end