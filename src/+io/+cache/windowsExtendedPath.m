function extendedPath = windowsExtendedPath(filePath)
    %WINDOWSEXTENDEDPATH Return a Windows extended-length path when applicable.
    arguments
        filePath {mustBeTextScalar}
    end

    extendedPath = char(filePath);
    if ~ispc || startsWith(extendedPath, [char(92), char(92), char(63), char(92)])
        return;
    end

    if startsWith(extendedPath, [char(92), char(92)])
        extendedPath = [char(92), char(92), char(63), char(92), ...
            'UNC', extendedPath(3:end)];
    elseif ~isempty(regexp(extendedPath, '^[A-Za-z]:[\\/]', 'once'))
        extendedPath = [char(92), char(92), char(63), char(92), extendedPath];
    end
end
