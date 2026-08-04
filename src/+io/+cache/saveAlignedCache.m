function saveAlignedCache(cacheFile, cacheData)
    %SAVEALIGNEDCACHE Atomically write an aligned cache MAT file.
    arguments
        cacheFile {mustBeTextScalar}
        cacheData (1,1) struct
    end

    cacheFile = char(cacheFile);
    cacheFolder = fileparts(cacheFile);
    if isempty(cacheFolder)
        cacheFolder = pwd;
    end
    if ~isfolder(cacheFolder)
        error('io:cache:saveAlignedCache:MissingFolder', ...
            'The aligned cache folder does not exist: %s', cacheFolder);
    end

    temporaryFile = [tempname(cacheFolder), '.mat'];
    cleanupTemporaryFile = onCleanup(@() localDeleteIfPresent(temporaryFile));
    extendedTemporaryFile = io.cache.windowsExtendedPath(temporaryFile);
    extendedCacheFile = io.cache.windowsExtendedPath(cacheFile);

    try
        save(extendedTemporaryFile, '-struct', 'cacheData', '-v7.3');
        localValidateCache(extendedTemporaryFile, fieldnames(cacheData));
        [moved, moveMessage] = movefile(extendedTemporaryFile, extendedCacheFile, 'f');
        if ~moved
            error('io:cache:saveAlignedCache:MoveFailed', ...
                'Could not move the temporary aligned cache into place: %s', moveMessage);
        end
        localValidateCache(extendedCacheFile, fieldnames(cacheData));
    catch ME
        if isfile(extendedCacheFile)
            try
                localValidateCache(extendedCacheFile, fieldnames(cacheData));
            catch
                delete(extendedCacheFile);
            end
        end
        error('io:cache:saveAlignedCache:WriteFailed', ...
            'Could not write aligned cache "%s": %s', cacheFile, ME.message);
    end
end

function localValidateCache(cacheFile, requiredNames)
    loadedData = load(cacheFile, requiredNames{:});
    availableNames = string(fieldnames(loadedData));
    missingNames = setdiff(string(requiredNames), availableNames);
    if ~isempty(missingNames)
        error('io:cache:saveAlignedCache:InvalidFile', ...
            'Aligned cache is missing variables after save: %s.', strjoin(missingNames, ', '));
    end
end

function localDeleteIfPresent(filePath)
    if isfile(filePath)
        delete(filePath);
    end
end
