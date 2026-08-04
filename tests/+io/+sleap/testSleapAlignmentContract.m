function tests = testSleapAlignmentContract
    tests = functiontests(localfunctions);
end

function testSleapAdvertisesAlignment(testCase)
    provider = ui.trackingPlatforms.platforms.SLEAP();
    testCase.verifyTrue(provider.supportsCapability("alignTrackingToStim"));
    testCase.verifyFalse(provider.supportsCapability("L1export"));
end

function testSleapCacheNameUsesProviderLabel(testCase)
    compositeHash = string(repmat('a', 1, 64));
    cacheName = io.cache.alignedCacheFileName("Trial 01.predictions", "SLEAP", compositeHash);
    info = io.cache.parseAlignedCacheFileName(cacheName, ...
        ExpectedDataBaseName="Trial 01.predictions", ...
        ExpectedTrackingPlatform="SLEAP");

    testCase.verifyEqual(string(cacheName), ...
        "Trial 01.predictions - SLEAP - " + compositeHash + ".mat");
    testCase.verifyTrue(info.isProviderLabeled);
    testCase.verifyEqual(info.dataBaseName, "Trial 01.predictions");
    testCase.verifyEqual(info.trackingPlatform, "SLEAP");
end

function testTrialSummaryExposesBodypartsOutput(testCase)
    testCase.verifyEqual(nargout('trial.stats.trialSummary'), 3);
end
