function tests = testAlignedCacheFilePath
    tests = functiontests(localfunctions);
end

function testLongBasenameKeepsFullHash(testCase)
    cacheFolder = tempname;
    mkdir(cacheFolder);
    cleanupFolder = onCleanup(@() rmdir(cacheFolder, 's')); %#ok<NASGU>
    dataBaseName = string(repmat('x', 1, 80));
    compositeHash = string(repmat('a', 1, 64));

    cachePath = io.cache.alignedCacheFilePath(cacheFolder, dataBaseName, ...
        "EthoVision", compositeHash);
    [~, cacheName, extension] = fileparts(cachePath);
    info = io.cache.parseAlignedCacheFileName([cacheName, extension], ...
        ExpectedDataBaseName=dataBaseName, ExpectedTrackingPlatform="EthoVision");

    testCase.verifyTrue(startsWith(string(cacheName), dataBaseName + " - EthoVision - "));
    testCase.verifyTrue(info.isAlignedCache);
    testCase.verifyTrue(info.isProviderLabeled);
    testCase.verifyEqual(info.dataBaseName, dataBaseName);
    testCase.verifyEqual(info.trackingPlatform, "EthoVision");
    testCase.verifyEqual(info.compositeHash, compositeHash);
    testCase.verifyEqual(strlength(string(cachePath)), ...
        strlength(string(fullfile(cacheFolder, [char(dataBaseName), ' - EthoVision - ', char(compositeHash), '.mat']))));
end

function testLongBasenameCanBeSavedAndLoaded(testCase)
    cacheFolder = tempname;
    mkdir(cacheFolder);
    cleanupFolder = onCleanup(@() rmdir(cacheFolder, 's')); %#ok<NASGU>
    dataBaseName = string(repmat('y', 1, 80));
    compositeHash = string(repmat('b', 1, 64));
    cachePath = io.cache.alignedCacheFilePath(cacheFolder, dataBaseName, ...
        "EthoVision", compositeHash);

    io.cache.saveAlignedCache(cachePath, struct('value', 7));
    [cacheData, loaded] = io.cache.loadAlignedCache(cachePath, "value");

    testCase.verifyTrue(loaded);
    testCase.verifyEqual(cacheData.value, 7);
end
