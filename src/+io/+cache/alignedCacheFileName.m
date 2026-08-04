function cacheFileName = alignedCacheFileName(dataBaseName, trackingPlatform, compositeHash)
    %ALIGNEDCACHEFILENAME Build the provider-labeled aligned cache filename.
    arguments
        dataBaseName {mustBeTextScalar}
        trackingPlatform {mustBeTextScalar}
        compositeHash {mustBeTextScalar}
    end

    dataBaseName = string(dataBaseName);
    trackingPlatform = string(trackingPlatform);
    compositeHash = string(compositeHash);

    if strlength(dataBaseName) == 0 || strlength(trackingPlatform) == 0 || strlength(compositeHash) == 0
        error('io:cache:alignedCacheFileName:InvalidInput', ...
            'The data basename, tracking platform, and composite hash must be non-empty text scalars.');
    end
    cacheFileName = char(dataBaseName + " - " + trackingPlatform + " - " + compositeHash + ".mat");
end
