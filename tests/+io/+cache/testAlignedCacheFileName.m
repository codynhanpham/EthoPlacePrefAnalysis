function tests = testAlignedCacheFileName
    tests = functiontests(localfunctions);
end

function testCanonicalNamePreservesBaseName(testCase)
    dataBaseName = "Trial 01 - chamber A";
    trackingPlatform = "EthoVision";
    compositeHash = string(repmat('a', 1, 64));

    cacheName = io.cache.alignedCacheFileName(dataBaseName, trackingPlatform, compositeHash);
    info = io.cache.parseAlignedCacheFileName(cacheName);

    testCase.verifyEqual(string(cacheName), ...
        "Trial 01 - chamber A - EthoVision - " + compositeHash + ".mat");
    testCase.verifyTrue(info.isAlignedCache);
    testCase.verifyTrue(info.isProviderLabeled);
    testCase.verifyFalse(info.isLegacy);
    testCase.verifyEqual(info.dataBaseName, dataBaseName);
    testCase.verifyEqual(info.trackingPlatform, trackingPlatform);
    testCase.verifyEqual(info.compositeHash, compositeHash);
end

function testLegacyNameIsRecognizedWithExpectedBaseName(testCase)
    dataBaseName = "Trial 01 - chamber A";
    compositeHash = string(repmat('b', 1, 64));
    legacyName = dataBaseName + " - " + compositeHash + ".mat";

    info = io.cache.parseAlignedCacheFileName(legacyName, ...
        ExpectedDataBaseName=dataBaseName, ...
        ExpectedTrackingPlatform="EthoVision");

    testCase.verifyTrue(info.isAlignedCache);
    testCase.verifyTrue(info.isLegacy);
    testCase.verifyFalse(info.isProviderLabeled);
    testCase.verifyEqual(info.dataBaseName, dataBaseName);
    testCase.verifyEqual(info.compositeHash, compositeHash);
end

function testExpectedBaseNamePreventsPrefixCollision(testCase)
    dataBaseName = "Trial 01";
    otherDataBaseName = "Trial 01 - chamber A";
    compositeHash = string(repmat('c', 1, 64));
    otherCacheName = io.cache.alignedCacheFileName(otherDataBaseName, "EthoVision", compositeHash);

    info = io.cache.parseAlignedCacheFileName(otherCacheName, ...
        ExpectedDataBaseName=dataBaseName, ...
        ExpectedTrackingPlatform="EthoVision");

    testCase.verifyFalse(info.isAlignedCache);
end

function testProviderFilterRejectsOtherProvider(testCase)
    dataBaseName = "Trial 02";
    compositeHash = string(repmat('d', 1, 64));
    cacheName = io.cache.alignedCacheFileName(dataBaseName, "DeepLabCut", compositeHash);

    info = io.cache.parseAlignedCacheFileName(cacheName, ...
        ExpectedDataBaseName=dataBaseName, ...
        ExpectedTrackingPlatform="EthoVision");

    testCase.verifyFalse(info.isAlignedCache);
end

function testMalformedHashIsIgnored(testCase)
    info = io.cache.parseAlignedCacheFileName( ...
        "Trial 03 - EthoVision - not-a-sha256-hash.mat", ...
        ExpectedDataBaseName="Trial 03", ...
        ExpectedTrackingPlatform="EthoVision");

    testCase.verifyFalse(info.isAlignedCache);
end

function testEthoVisionRejectsL1Export(testCase)
    provider = ui.trackingPlatforms.platforms.EthoVision();
    testCase.verifyFalse(provider.supportsCapability("L1export"));
    testCase.verifyError(@() provider.requireCapability("L1export"), ...
        'ui:trackingPlatforms:TrackingProvider:UnsupportedCapability');
end

function testUnsupportedProviderRejectsL1Export(testCase)
    provider = ui.trackingPlatforms.platforms.DeepLabCut();
    testCase.verifyFalse(provider.supportsCapability("L1export"));
    testCase.verifyError(@() provider.requireCapability("L1export"), ...
        'ui:trackingPlatforms:TrackingProvider:UnsupportedCapability');
end
