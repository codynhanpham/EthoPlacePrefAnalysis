function cacheFilePath = alignedCacheFilePath(dataDirectory, dataBaseName, trackingPlatform, compositeHash)
    %ALIGNEDCACHEFILEPATH Build the full provider-labeled aligned cache path.
    arguments
        dataDirectory {mustBeFolder}
        dataBaseName {mustBeTextScalar}
        trackingPlatform {mustBeTextScalar}
        compositeHash {mustBeTextScalar}
    end

    cacheFilePath = fullfile(dataDirectory, ...
        io.cache.alignedCacheFileName(dataBaseName, trackingPlatform, compositeHash));
end
