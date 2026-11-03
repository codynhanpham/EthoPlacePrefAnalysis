function tests = testSleapWorkers
    tests = functiontests(localfunctions);
end

function testNamedArgWinsWhenGreaterThanOne(testCase)
    testCase.verifyEqual(io.sleap.resolveWorkers(3, struct(), 10), 3);
end

function testConfigUsedWhenNamedArgIsOne(testCase)
    cfg = struct('workers', 4);
    testCase.verifyEqual(io.sleap.resolveWorkers(1, cfg, 10), 4);
end

function testNamedArgOverridesConfig(testCase)
    cfg = struct('workers', 4);
    testCase.verifyEqual(io.sleap.resolveWorkers(2, cfg, 10), 2);
end

function testMissingFieldDefaultsToOne(testCase)
    testCase.verifyEqual(io.sleap.resolveWorkers(1, struct(), 10), 1);
end

function testEmptyConfigValueDefaultsToOne(testCase)
    cfg = struct('workers', []);
    testCase.verifyEqual(io.sleap.resolveWorkers(1, cfg, 10), 1);
end

function testClampToVideoCountFromConfig(testCase)
    cfg = struct('workers', 4);
    testCase.verifyEqual(io.sleap.resolveWorkers(1, cfg, 2), 2);
end

function testClampToVideoCountFromNamedArg(testCase)
    testCase.verifyEqual(io.sleap.resolveWorkers(5, struct(), 3), 3);
end

function testConfigWorkersOneStaysSequential(testCase)
    cfg = struct('workers', 1);
    testCase.verifyEqual(io.sleap.resolveWorkers(1, cfg, 5), 1);
end

function testSingleVideoClampsEverything(testCase)
    cfg = struct('workers', 8);
    testCase.verifyEqual(io.sleap.resolveWorkers(1, cfg, 1), 1);
    testCase.verifyEqual(io.sleap.resolveWorkers(4, struct(), 1), 1);
end

function testInvalidConfigWorkersError(testCase)
    import matlab.unittest.constraints.Throws
    badValues = {0, -2, 1.5, NaN, Inf, 'x', [1 2]};
    for i = 1:numel(badValues)
        cfg = struct('workers', badValues{i});
        testCase.verifyThat(@() io.sleap.resolveWorkers(1, cfg, 5), ...
            Throws('io:sleap:runSLEAP:InvalidWorkers'), ...
            sprintf('Expected InvalidWorkers error for value: %s', evalc('disp(badValues{i})')));
    end
end

function testInvalidNamedArgError(testCase)
    import matlab.unittest.constraints.Throws
    testCase.verifyThat(@() io.sleap.resolveWorkers(1.5, struct(), 5), ...
        Throws('io:sleap:runSLEAP:InvalidWorkers'));
    testCase.verifyThat(@() io.sleap.resolveWorkers(0, struct(), 5), ...
        Throws('io:sleap:runSLEAP:InvalidWorkers'));
end
