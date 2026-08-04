function [cacheData, loaded] = loadAlignedCache(cacheFile, variableNames)
    %LOADALIGNEDCACHE Load an aligned cache and remove corrupt artifacts.
    arguments
        cacheFile {mustBeFile}
        variableNames (1,:) string = strings(1, 0)
    end

    cacheData = struct();
    loaded = false;
    variableNames = cellstr(variableNames);
    extendedCacheFile = io.cache.windowsExtendedPath(cacheFile);

    try
        if isempty(variableNames)
            cacheData = load(extendedCacheFile);
        else
            cacheData = load(extendedCacheFile, variableNames{:});
        end
        loaded = true;
    catch ME
        warning('io:cache:loadAlignedCache:CorruptFile', ...
            'Aligned cache "%s" could not be loaded and will be removed. Original error: %s', ...
            cacheFile, ME.message);
        try
            delete(extendedCacheFile);
        catch cleanupError
            error('io:cache:loadAlignedCache:CleanupFailed', ...
                'Aligned cache "%s" could not be loaded or removed. Load error: %s Removal error: %s', ...
                cacheFile, ME.message, cleanupError.message);
        end
    end
end
