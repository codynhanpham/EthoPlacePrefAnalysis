function tests = testAlignedCacheIO
    tests = functiontests(localfunctions);
end

function testAtomicRoundTrip(testCase)
    cacheFolder = tempname;
    mkdir(cacheFolder);
    cleanupFolder = onCleanup(@() rmdir(cacheFolder, 's'));
    cacheFile = fullfile(cacheFolder, 'trial - EthoVision - hash.mat');
    cacheData = struct('value', 42, 'text', "aligned");
    fileId = fopen(cacheFile, 'w');
    fwrite(fileId, 'partial corrupt cache', 'char');
    fclose(fileId);

    io.cache.saveAlignedCache(cacheFile, cacheData);
    [loadedData, loaded] = io.cache.loadAlignedCache(cacheFile, ["value", "text"]);

    testCase.verifyTrue(loaded);
    testCase.verifyEqual(loadedData.value, 42);
    testCase.verifyEqual(loadedData.text, "aligned");
    testCase.verifyFalse(isfile(cacheFile + ".tmp"));
end

function testCorruptCacheIsRemoved(testCase)
    cacheFolder = tempname;
    mkdir(cacheFolder);
    cleanupFolder = onCleanup(@() rmdir(cacheFolder, 's')); %#ok<NASGU>
    cacheFile = fullfile(cacheFolder, 'trial - EthoVision - corrupt.mat');
    fileId = fopen(cacheFile, 'w');
    fwrite(fileId, 'not a MAT file', 'char');
    fclose(fileId);

    warningState = warning('off', 'io:cache:loadAlignedCache:CorruptFile');
    cleanupWarning = onCleanup(@() warning(warningState)); %#ok<NASGU>
    [loadedData, loaded] = io.cache.loadAlignedCache(cacheFile, "value");

    testCase.verifyFalse(loaded);
    testCase.verifyEmpty(fieldnames(loadedData));
    testCase.verifyFalse(isfile(cacheFile));
end

function testMalformedHdf5CacheIsRemoved(testCase)
    cacheFolder = tempname;
    mkdir(cacheFolder);
    cleanupFolder = onCleanup(@() rmdir(cacheFolder, 's')); %#ok<NASGU>
    cacheFile = fullfile(cacheFolder, 'trial - EthoVision - malformed.mat');
    h5create(cacheFile, '/partial', [1 1]);
    h5write(cacheFile, '/partial', 1);

    warningState = warning('off', 'io:cache:loadAlignedCache:CorruptFile');
    cleanupWarning = onCleanup(@() warning(warningState)); %#ok<NASGU>
    [loadedData, loaded] = io.cache.loadAlignedCache(cacheFile, "header");

    testCase.verifyFalse(loaded);
    testCase.verifyEmpty(fieldnames(loadedData));
    testCase.verifyFalse(isfile(cacheFile));
end
