classdef testHeadMetrics < matlab.unittest.TestCase
    methods (Test)
        function computesHeadKinematicsInStandardizedUnits(testCase)
            standardizedTable = makeHeadStandardizedTable();

            speedTable = cohort.metrics.headSpeed(standardizedTable, ...
                'StimulusIncludesTrailingISI', false);
            accelerationTable = cohort.metrics.headAcceleration(standardizedTable, ...
                'StimulusIncludesTrailingISI', false);
            angularTable = cohort.metrics.headAngularVelocity(standardizedTable, ...
                'StimulusIncludesTrailingISI', false);

            testCase.verifyEqual(height(speedTable), 1);
            testCase.verifyEqual(speedTable.('Head Speed Mean During Stimulus (cm/s)'), 0.9, 'AbsTol', 1e-12);
            testCase.verifyEqual(speedTable.('Head Speed Mean During A (cm/s)'), 0.5, 'AbsTol', 1e-12);
            testCase.verifyEqual(speedTable.('Head Speed Mean During B (cm/s)'), 1.3, 'AbsTol', 1e-12);
            testCase.verifyEqual(speedTable.('Head Speed Mean During First A Bout (cm/s)'), 0.5, 'AbsTol', 1e-12);

            testCase.verifyEqual(accelerationTable.('Head Acceleration Mean During Stimulus (cm/s^2)'), 2, 'AbsTol', 1e-12);
            testCase.verifyTrue(isnan(accelerationTable.('Head Deceleration Mean During Stimulus (cm/s^2)')));

            testCase.verifyEqual(angularTable.('Head Angular Velocity Mean During B (deg/s)'), 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(angularTable.('Head Angular Velocity Mean During A (deg/s)'), 0, 'AbsTol', 1e-12);
        end

        function doesNotDoubleScaleBodypartCoordinates(testCase)
            standardizedTable = makeHeadStandardizedTable();
            standardizedTable.px2cm = 0.5;
            result = cohort.metrics.headSpeed(standardizedTable, ...
                'StimulusIncludesTrailingISI', false);

            testCase.verifyEqual(result.('Head Speed Mean During Stimulus (cm/s)'), 0.9, 'AbsTol', 1e-12);
        end

        function preservesRowsWhenEarsAreUnavailable(testCase)
            standardizedTable = makeHeadStandardizedTable();
            standardizedTable.bodyparts = standardizedTable.bodyparts(:, 1:2);

            result = cohort.metrics.headSpeed(standardizedTable);

            testCase.verifyEqual(height(result), 1);
            metricValues = result{:, 12:end};
            testCase.verifyTrue(all(isnan(metricValues), 'all'));
        end

        function defaultSummaryPreservesLegacyTablesWithoutEars(testCase)
            standardizedTable = makeHeadStandardizedTable();
            standardizedTable.bodyparts = standardizedTable.bodyparts(:, 1:2);

            result = cohort.summary(standardizedTable);

            testCase.verifyEqual(height(result), 1);
            testCase.verifyTrue(isnan(result.('Head Speed Mean During Stimulus (cm/s)')));
            testCase.verifyTrue(isnan(result.('Head Angular Velocity Mean During Stimulus (deg/s)')));
        end

        function summaryIncludesHeadMetrics(testCase)
            standardizedTable = makeHeadStandardizedTable();
            result = cohort.summary(standardizedTable, 'MetricsToInclude', ...
                {'headSpeed', 'headAcceleration', 'headAngularVelocity'});

            testCase.verifyEqual(height(result), 1);
            testCase.verifyTrue(ismember('Head Speed Mean During Stimulus (cm/s)', result.Properties.VariableNames));
            testCase.verifyTrue(ismember('Head Acceleration Mean During Stimulus (cm/s^2)', result.Properties.VariableNames));
            testCase.verifyTrue(ismember('Head Angular Velocity Mean During Stimulus (deg/s)', result.Properties.VariableNames));
        end

        function defaultSummaryIncludesHeadMetrics(testCase)
            standardizedTable = makeHeadStandardizedTable();
            result = cohort.summary(standardizedTable);

            testCase.verifyEqual(height(result), 1);
            testCase.verifyTrue(ismember('Head Speed Mean During Stimulus (cm/s)', result.Properties.VariableNames));
            testCase.verifyTrue(ismember('Head Acceleration Mean During Stimulus (cm/s^2)', result.Properties.VariableNames));
            testCase.verifyTrue(ismember('Head Angular Velocity Mean During Stimulus (deg/s)', result.Properties.VariableNames));
        end

        function appliesStimulusDisplayOverride(testCase)
            standardizedTable = makeHeadStandardizedTable();
            result = cohort.metrics.headSpeed(standardizedTable, ...
                'StimulusIncludesTrailingISI', false, ...
                'StimuliSortedColumnNameDisplayOverride', ["Reward", "Control"]);

            testCase.verifyTrue(ismember('Head Speed Mean During Reward (cm/s)', result.Properties.VariableNames));
            testCase.verifyTrue(ismember('Head Speed Mean During Control (cm/s)', result.Properties.VariableNames));
        end

        function computesBearingWithImageConvention(testCase)
            % Y-down image convention: nose above midpoint (smaller Y) = 0,
            % nose right = +90, nose left = -90.
            standardizedTable = makeBearingTable([0; 90; -90]);
            result = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(result.('Head Bearing Angle Mean During Stimulus (deg)'), 0, 'AbsTol', 1e-6);
            testCase.verifyEqual(result.('Head Bearing Angle Min During Stimulus (deg)'), -90, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.('Head Bearing Angle Max During Stimulus (deg)'), 90, 'AbsTol', 1e-9);

            % Nose below the midpoint (larger Y) faces down; in the reported
            % range [-180, 180) that value is represented as -180.
            downTable = makeBearingTable(180);
            downResult = cohort.metrics.headBearingAngle(downTable);
            testCase.verifyEqual(downResult.('Head Bearing Angle Mean During Stimulus (deg)'), -180, 'AbsTol', 1e-9);
        end

        function circularMeanHandlesWrapAround(testCase)
            % Frames at -179 and +179 must average near the +/-180 boundary
            % (reported as -180 in [-180, 180)), not near 0.
            standardizedTable = makeBearingTable([-179; 179]);
            result = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(result.('Head Bearing Angle Mean During Stimulus (deg)'), -180, 'AbsTol', 1e-6);
            testCase.verifyTrue(isfinite(result.('Head Bearing Angle Std During Stimulus (deg)')));
        end

        function angularVelocityMatchesBearingDerivative(testCase)
            % Constant clockwise rotation (bearing increasing) -> positive deg/s.
            % Bearing steps +90 deg per 0.1 s frame -> 900 deg/s.
            standardizedTable = makeBearingTable([0; 90; 180; -90; 0]);
            result = cohort.metrics.headAngularVelocity(standardizedTable);

            testCase.verifyEqual(result.('Head Angular Velocity Mean During Stimulus (deg/s)'), 900, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.('Head Angular Velocity Min During Stimulus (deg/s)'), 900, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.('Head Angular Velocity Max During Stimulus (deg/s)'), 900, 'AbsTol', 1e-9);
        end

        function bearingExcludesTrailingISIByDefault(testCase)
            % Fixture has an ISI row after stimulus A; with the default
            % (ISI excluded) the A-period mean must not include ISI frames.
            standardizedTable = makeBearingTableWithISI();
            result = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(result.('Head Bearing Angle Mean During A (deg)'), 0, 'AbsTol', 1e-9);
        end

        function histogramSecondOutputMatchesRustBins(testCase)
            % 0 deg -> bin 37; +90 -> bin 55; -90 -> bin 19; a down-facing
            % frame is represented as -180 and lands in bin 1 (the clamp to
            % bin 72 only applies to pre-normalization +180 inputs).
            standardizedTable = makeBearingTable([0; 90; -90]);
            [~, histogram] = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(numel(histogram.bins), 72);
            testCase.verifyEqual(numel(histogram.binEdges), 73);
            testCase.verifyEqual(histogram.binEdges(1), -180);
            testCase.verifyEqual(histogram.binEdges(end), 180);
            testCase.verifyEqual(histogram.bins(37), 1); % 0 deg
            testCase.verifyEqual(histogram.bins(55), 1); % +90 deg
            testCase.verifyEqual(histogram.bins(19), 1); % -90 deg
            testCase.verifyEqual(sum(histogram.bins), histogram.total);
            testCase.verifyEqual(histogram.total, 3);

            downTable = makeBearingTable(180);
            [~, downHistogram] = cohort.metrics.headBearingAngle(downTable);
            testCase.verifyEqual(downHistogram.bins(1), 1); % -180 representation
            testCase.verifyEqual(downHistogram.total, 1);
        end

        function bearingPreservesRowsWhenNoseIsMissing(testCase)
            standardizedTable = makeHeadStandardizedTable();
            standardizedTable.bodyparts = standardizedTable.bodyparts(:, 1:6); % ears only, no nose

            result = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(height(result), 1);
            metricValues = result{:, 12:end};
            testCase.verifyTrue(all(isnan(metricValues), 'all'));
        end

        function degenerateNoseAtMidpointYieldsNaN(testCase)
            % Frame 1 faces up (0 deg); frame 2 has the nose exactly at the
            % ear midpoint, which must be excluded as degenerate.
            standardizedTable = makeBearingTableWithDegenerateFrame();

            result = cohort.metrics.headBearingAngle(standardizedTable);

            testCase.verifyEqual(result.('Head Bearing Angle Mean During Stimulus (deg)'), 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.('Head Bearing Angle Min During Stimulus (deg)'), 0, 'AbsTol', 1e-9);
            testCase.verifyEqual(result.('Head Bearing Angle Max During Stimulus (deg)'), 0, 'AbsTol', 1e-9);
        end

        function summaryIncludesBearingColumns(testCase)
            standardizedTable = makeHeadStandardizedTable();
            result = cohort.summary(standardizedTable);

            testCase.verifyTrue(ismember('Head Bearing Angle Mean During Stimulus (deg)', result.Properties.VariableNames));
        end
    end
end

function standardizedTable = makeHeadStandardizedTable()
    nRows = 10;
    trialTime = (0:nRows-1)' / 10;
    stimulusName = ["NONE | Pre-Stimulus"; "A"; "A"; "A"; "A"; ...
        "B"; "B"; "B"; "B"; "NONE | Post-Stimulus"];
    headX = trialTime .^ 2;
    headY = zeros(nRows, 1);
    angle = [0; 0; 0; 0; 0; -pi/18; -2*pi/18; -3*pi/18; -4*pi/18; -4*pi/18];
    axisLength = 2;
    leftX = headX - axisLength / 2 * cos(angle);
    leftY = headY - axisLength / 2 * sin(angle);
    rightX = headX + axisLength / 2 * cos(angle);
    rightY = headY + axisLength / 2 * sin(angle);
    % Nose sits 1 cm above the ear midpoint in image coordinates (smaller Y),
    % so the bearing is 0 deg for every frame of the default fixture.
    noseX = headX;
    noseY = headY - 1;

    centerpointData = table(trialTime, stimulusName, ...
        headX, headY, zeros(nRows, 1), zeros(nRows, 1), ...
        'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
        'Y center', 'Distance from Midline', 'Arena Grid Score'});
    bodyparts = table(trialTime, stimulusName, leftX, leftY, rightX, rightY, ...
        noseX, noseY, ...
        'VariableNames', {'Trial time', 'Stimulus name', ...
        'X Ear_left', 'Y Ear_left', 'X Ear_right', 'Y Ear_right', ...
        'X nose', 'Y nose'});

    metadata = configureDictionary("string", "struct");
    metadata("animal1") = struct('sex', "F", 'strain', "strain", 'genotype', "genotype");

    standardizedTable = struct(...
        'stimfileName', "stimulus.flac", ...
        'stimuliSorted', ["A", "B"], ...
        'animalMetadata', metadata, ...
        'fps', 10, ...
        'px2cm', 0.5, ...
        'centerpointData', centerpointData, ...
        'bodyparts', bodyparts);
end

function standardizedTable = makeBearingTable(bearingDegrees)
% Build a one-animal fixture whose ear-midpoint-to-nose bearing equals the
% requested degrees on every frame, using image coordinates (Y down).
% bearingDegrees: n x 1 vector in [-180, 180).
nRows = numel(bearingDegrees);
trialTime = (0:nRows-1)' / 10;
stimulusName = repmat("A", nRows, 1);
midX = zeros(nRows, 1);
midY = zeros(nRows, 1);
noseDistance = 1;
directionX = sind(bearingDegrees);
directionY = -cosd(bearingDegrees); % image convention: up = -Y
noseX = midX + noseDistance * directionX;
noseY = midY + noseDistance * directionY;
axisLength = 2;
leftX = midX - axisLength / 2;
leftY = midY;
rightX = midX + axisLength / 2;
rightY = midY;

centerpointData = table(trialTime, stimulusName, ...
    midX, midY, zeros(nRows, 1), zeros(nRows, 1), ...
    'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
    'Y center', 'Distance from Midline', 'Arena Grid Score'});
bodyparts = table(trialTime, stimulusName, leftX, leftY, rightX, rightY, ...
    noseX, noseY, ...
    'VariableNames', {'Trial time', 'Stimulus name', ...
    'X Ear_left', 'Y Ear_left', 'X Ear_right', 'Y Ear_right', ...
    'X nose', 'Y nose'});

metadata = configureDictionary("string", "struct");
metadata("animal1") = struct('sex', "F", 'strain', "strain", 'genotype', "genotype");

standardizedTable = struct(...
    'stimfileName', "stimulus.flac", ...
    'stimuliSorted', ["A"], ...
    'animalMetadata', metadata, ...
    'fps', 10, ...
    'px2cm', 0.5, ...
    'centerpointData', centerpointData, ...
    'bodyparts', bodyparts);
end

function standardizedTable = makeBearingTableWithDegenerateFrame()
% Frame 1: nose 1 cm above the ear midpoint (bearing 0 deg).
% Frame 2: nose exactly at the ear midpoint (degenerate, excluded).
nRows = 2;
trialTime = (0:nRows-1)' / 10;
stimulusName = repmat("A", nRows, 1);
midX = zeros(nRows, 1);
midY = zeros(nRows, 1);
leftX = midX - 1;
leftY = midY;
rightX = midX + 1;
rightY = midY;
noseX = [0; 0];
noseY = [-1; 0];

centerpointData = table(trialTime, stimulusName, ...
    midX, midY, zeros(nRows, 1), zeros(nRows, 1), ...
    'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
    'Y center', 'Distance from Midline', 'Arena Grid Score'});
bodyparts = table(trialTime, stimulusName, leftX, leftY, rightX, rightY, ...
    noseX, noseY, ...
    'VariableNames', {'Trial time', 'Stimulus name', ...
    'X Ear_left', 'Y Ear_left', 'X Ear_right', 'Y Ear_right', ...
    'X nose', 'Y nose'});

metadata = configureDictionary("string", "struct");
metadata("animal1") = struct('sex', "F", 'strain', "strain", 'genotype', "genotype");

standardizedTable = struct(...
    'stimfileName', "stimulus.flac", ...
    'stimuliSorted', ["A"], ...
    'animalMetadata', metadata, ...
    'fps', 10, ...
    'px2cm', 0.5, ...
    'centerpointData', centerpointData, ...
    'bodyparts', bodyparts);
end

function standardizedTable = makeBearingTableWithISI()
% Two A frames at 0 deg, one ISI frame at 180 deg, one B frame at 0 deg.
% With ISI excluded (default), the A-period mean is 0 deg; with ISI included
% it would be contaminated by the 180 deg ISI frame.
bearingDegrees = [0; 0; 180; 0];
nRows = numel(bearingDegrees);
trialTime = (0:nRows-1)' / 10;
stimulusName = ["A"; "A"; "ISI"; "B"];
midX = zeros(nRows, 1);
midY = zeros(nRows, 1);
directionX = sind(bearingDegrees);
directionY = -cosd(bearingDegrees);
noseX = midX + directionX;
noseY = midY + directionY;
leftX = midX - 1;
leftY = midY;
rightX = midX + 1;
rightY = midY;

centerpointData = table(trialTime, stimulusName, ...
    midX, midY, zeros(nRows, 1), zeros(nRows, 1), ...
    'VariableNames', {'Trial time', 'Stimulus name', 'X center', ...
    'Y center', 'Distance from Midline', 'Arena Grid Score'});
bodyparts = table(trialTime, stimulusName, leftX, leftY, rightX, rightY, ...
    noseX, noseY, ...
    'VariableNames', {'Trial time', 'Stimulus name', ...
    'X Ear_left', 'Y Ear_left', 'X Ear_right', 'Y Ear_right', ...
    'X nose', 'Y nose'});

metadata = configureDictionary("string", "struct");
metadata("animal1") = struct('sex', "F", 'strain', "strain", 'genotype', "genotype");

standardizedTable = struct(...
    'stimfileName', "stimulus.flac", ...
    'stimuliSorted', ["A", "B"], ...
    'animalMetadata', metadata, ...
    'fps', 10, ...
    'px2cm', 0.5, ...
    'centerpointData', centerpointData, ...
    'bodyparts', bodyparts);
end
