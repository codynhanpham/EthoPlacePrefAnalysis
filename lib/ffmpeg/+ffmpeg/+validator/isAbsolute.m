function bool = isAbsolute(pathStr)
    %%ISABSOLUTE Check if a given path string is absolute using Java's File object.
    %   This function does NOT check if the path exists

    arguments
        pathStr {mustBeTextScalar}
    end

    pathStr = char(pathStr);

    fileObj = java.io.File(pathStr);
    bool = fileObj.isAbsolute();
end