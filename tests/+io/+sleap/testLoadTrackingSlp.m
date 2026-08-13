function tests = testLoadTrackingSlp
    tests = functiontests(localfunctions);
end

function testSelectsHighestScoringPredictedInstance(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.2, 0.9]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    [~, data] = io.sleap.loadTrackingSlp(slpFile);

    testCase.verifyEqual(data{1, 'nose |> x'}, 20);
    testCase.verifyEqual(data{1, 'nose |> y'}, 30);
    testCase.verifyEqual(data{1, 'nose |> score'}, 0.1);
end

function testUsesInstanceScoreInsteadOfPointScore(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.9, 0.1], ones(1, 2), ...
        [0.1, 0.1; 0.9, 0.9]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    [~, data] = io.sleap.loadTrackingSlp(slpFile);

    testCase.verifyEqual(data{1, 'nose |> x'}, 10);
    testCase.verifyEqual(data{1, 'nose |> score'}, 0.1);
end

function testEnforceSingleInstanceRejectsMultipleInstances(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.2, 0.9]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    testCase.verifyError(@() io.sleap.loadTrackingSlp(...
        slpFile, EnforceSingleInstance=true), ...
        'io:sleap:loadTrackingSlp:MultiInstanceDetected');
end

function testSingleInstanceSucceedsWithEnforcement(testCase)
    slpFile = createSyntheticSlp(1, 10, 0.9);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    [~, data] = io.sleap.loadTrackingSlp(...
        slpFile, EnforceSingleInstance=true);

    testCase.verifyEqual(data{1, 'nose |> x'}, 10);
end

function testEqualScoresSelectFirstInstance(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.5, 0.5]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    [~, data] = io.sleap.loadTrackingSlp(slpFile);

    testCase.verifyEqual(data{1, 'nose |> x'}, 10);
end

function testAllNonfiniteInstanceScoresFail(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [NaN, NaN]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    testCase.verifyError(@() io.sleap.loadTrackingSlp(slpFile), ...
        'io:sleap:loadTrackingSlp:InvalidInstanceScore');
end

function testMixedUserAndPredictedInstancesSelectsPredicted(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.99, 0.1], [0, 1]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    [~, data] = io.sleap.loadTrackingSlp(slpFile);

    testCase.verifyEqual(data{1, 'nose |> x'}, 20);
end

function testHeaderOnlyStillValidatesMultipleInstances(testCase)
    slpFile = createSyntheticSlp(1, [10, 20], [0.2, 0.9]);
    cleanupFile = onCleanup(@() delete(slpFile)); %#ok<NASGU>

    testCase.verifyError(@() io.sleap.loadTrackingSlp(...
        slpFile, HeaderOnly=true, EnforceSingleInstance=true), ...
        'io:sleap:loadTrackingSlp:MultiInstanceDetected');
end

function filePath = createSyntheticSlp(...
        nFrames, instanceCenters, instanceScores, instanceTypes, pointScores)
    if nargin < 4
        instanceTypes = ones(size(instanceScores));
    end
    instanceCenters = instanceCenters(:).';
    instanceScores = instanceScores(:).';
    instanceTypes = instanceTypes(:).';
    nInstances = numel(instanceCenters);
    if nargin < 5
        pointScores = repmat([0.1, 0.8], nInstances, 1);
    end
    nNodes = 2;
    filePath = [tempname, '.slp'];

    h5create(filePath, '/metadata/placeholder', [1 1], 'Datatype', 'uint8');
    h5write(filePath, '/metadata/placeholder', uint8(0));
    metadata = struct('nodes', struct('name', {'nose'; 'tail'}));
    h5writeatt(filePath, '/metadata', 'json', jsonencode(metadata));
    h5writeatt(filePath, '/metadata', 'format_id', 1.2);

    frameData = [
        1, 0, 0, 0, nInstances;
        ];
    writeMatrixDataset(filePath, '/frames', frameData, ...
        ["frame_id", "video", "frame_idx", "instance_id_start", "instance_id_end"]);

    instanceData = zeros(nInstances, 6);
    pointData = zeros(nInstances*nNodes, 4);
    for instanceIdx = 1:nInstances
        pointStart = (instanceIdx - 1)*nNodes;
        instanceData(instanceIdx, :) = [
            instanceIdx - 1, instanceTypes(instanceIdx), 1, instanceScores(instanceIdx), ...
            pointStart, pointStart + nNodes];
        pointRows = pointStart + (1:nNodes);
        pointData(pointRows, :) = [
            instanceCenters(instanceIdx), 30, 1, pointScores(instanceIdx, 1);
            instanceCenters(instanceIdx) + 1, 31, 1, pointScores(instanceIdx, 2)];
    end
    writeMatrixDataset(filePath, '/instances', instanceData, ...
        ["instance_id", "instance_type", "frame_id", "score", ...
        "point_id_start", "point_id_end"]);
    writeMatrixDataset(filePath, '/pred_points', pointData, ...
        ["x", "y", "visible", "score"]);

    videoJson = sprintf(['{"filename":"missing.mp4",', ...
        '"backend":{"shape":[%d,10,10,3]}}'], nFrames);
    h5create(filePath, '/videos_json', [1 1], 'Datatype', 'string');
    h5write(filePath, '/videos_json', string(videoJson));
end

function writeMatrixDataset(filePath, datasetPath, data, fieldNames)
    h5create(filePath, datasetPath, size(data));
    h5write(filePath, datasetPath, data);
    h5writeatt(filePath, datasetPath, 'field_names', jsonencode(fieldNames));
end