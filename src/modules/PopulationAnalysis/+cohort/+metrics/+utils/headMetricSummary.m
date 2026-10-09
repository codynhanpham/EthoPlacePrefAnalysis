function [t, histogram] = headMetricSummary(standardizedTables, kvargs, metricKind)
%HEADMETRICSUMMARY Shared implementation for cohort head kinematic metrics.

if isempty(standardizedTables)
    t = table();
    return;
end

metricKind = char(metricKind);
switch metricKind
    case 'speed'
        componentNames = {'Head Speed'};
        units = {'cm/s'};
    case 'acceleration'
        componentNames = {'Head Acceleration', 'Head Deceleration'};
        units = {'cm/s^2', 'cm/s^2'};
    case 'angularVelocity'
        componentNames = {'Head Angular Velocity'};
        units = {'deg/s'};
    case 'bearingAngle'
        componentNames = {'Head Bearing Angle'};
        units = {'deg'};
    case 'noseHeadingAngularVelocity'
        componentNames = {'Head Angular Velocity'};
        units = {'deg/s'};
    otherwise
        error('cohort:metrics:headMetricSummary:InvalidMetricKind', ...
            'Unsupported head metric kind: %s.', metricKind);
end
isCircular = strcmp(metricKind, 'bearingAngle');

hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride( ...
    standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
outputStimNames = cohort.metrics.utils.getOutputStimNames( ...
    standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
nOutputStims = numel(outputStimNames);
nComponents = numel(componentNames);

nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);
[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
    cohort.metrics.utils.initCommonColumns(nRowsEstimate);

allStats = nan(nRowsEstimate, 4, nComponents);
stimStats = nan(nRowsEstimate, nOutputStims, 4, nComponents);
firstBoutStats = nan(nRowsEstimate, nOutputStims, 4, nComponents);
lastBoutStats = nan(nRowsEstimate, nOutputStims, 4, nComponents);
deltaStats = nan(nRowsEstimate, nOutputStims, 4, nComponents);

% Optional 72x5-degree histogram over [-180, 180), mirroring the Rust
% HeadAngleDistribution (bin i covers [-180+5i, -175+5i)). Accumulated only
% for circular (bearing) metrics; returned as the second output.
HEAD_ANGLE_BIN_COUNT = 72;
HEAD_ANGLE_BIN_WIDTH = 5;
histogramBins = zeros(HEAD_ANGLE_BIN_COUNT, 1);
histogramTotal = 0;

rowIdx = 0;
for tableIndex = 1:numel(standardizedTables)
    stdTable = standardizedTables(tableIndex);
    centerpointData = stdTable.centerpointData;
    trialTime = centerpointData{:, 'Trial time'};
    stimSequence = string(centerpointData{:, 'Stimulus name'});
    nAnimals = size(centerpointData{:, 'X center'}, 2);

    localStimNames = string(stdTable.stimuliSorted);
    localStimNames = localStimNames(:);
    allStimPointMask = cohort.metrics.utils.periodMaskAllStim( ...
        stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI);
    stimPointMasks = cell(numel(localStimNames), 1);
    stimBoutMasks = cell(numel(localStimNames), 1);
    for stimIndex = 1:numel(localStimNames)
        stimPointMasks{stimIndex} = cohort.metrics.utils.periodMaskForStim( ...
            stimSequence, localStimNames(stimIndex), localStimNames, ...
            kvargs.StimulusIncludesTrailingISI);
        stimBoutMasks{stimIndex} = cohort.metrics.utils.stimBoutMasksForStim( ...
            stimSequence, localStimNames(stimIndex), localStimNames, ...
            kvargs.StimulusIncludesTrailingISI);
    end

    localIdxByOutputStim = zeros(nOutputStims, 1);
    if hasOverride
        localDisplayNames = localOverrideLabels(overrideSpec, tableIndex);
        for outputIndex = 1:nOutputStims
            localIndex = find(strcmpi(localDisplayNames, outputStimNames(outputIndex)), 1, 'first');
            if ~isempty(localIndex)
                localIdxByOutputStim(outputIndex) = localIndex;
            end
        end
    else
        for outputIndex = 1:nOutputStims
            localIndex = cohort.metrics.utils.firstMatchingStimIndex( ...
                localStimNames, outputStimNames(outputIndex), hasOverride);
            if ~isempty(localIndex)
                localIdxByOutputStim(outputIndex) = localIndex;
            end
        end
    end

    [headX, headY, earLX, earLY, earRX, earRY, noseX, noseY, headAvailable] = ...
        cohort.metrics.utils.getHeadPositionMatrices( ...
        stdTable.bodyparts, numel(trialTime), nAnimals);
    animalKeys = keys(stdTable.animalMetadata);

    for animalIndex = 1:nAnimals
        rowIdx = rowIdx + 1;
        metadata = struct();
        if animalIndex <= numel(animalKeys)
            metadata = stdTable.animalMetadata(animalKeys{animalIndex});
        end
        [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
            cohort.metrics.utils.fillCommonColumns( ...
            mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, ...
            litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, ...
            metadata, stdTable.stimfileName);

        if headAvailable
            metricValues = computeMetricValues(metricKind, ...
                headX(:, animalIndex), headY(:, animalIndex), ...
                earLX(:, animalIndex), earLY(:, animalIndex), ...
                earRX(:, animalIndex), earRY(:, animalIndex), ...
                noseX(:, animalIndex), noseY(:, animalIndex), trialTime);
        else
            metricValues = struct('values', {cell(1, nComponents)}, ...
                'validMasks', {cell(1, nComponents)});
            for componentIndex = 1:nComponents
                metricValues.values{componentIndex} = nan(0, 1);
                metricValues.validMasks{componentIndex} = false(0, 1);
            end
        end

        for componentIndex = 1:nComponents
            [allStats(rowIdx, :, componentIndex)] = metricStats( ...
                metricValues.values{componentIndex}, ...
                segmentMask(metricValues.validMasks{componentIndex}, allStimPointMask, metricKind), ...
                metricKind, componentIndex);
        end

        if isCircular
            [histogramBins, histogramTotal] = accumulateHistogram( ...
                histogramBins, histogramTotal, metricValues.values{1}, ...
                metricValues.validMasks{1}, allStimPointMask, metricKind);
        end

        localStimStats = nan(numel(localStimNames), 4, nComponents);
        localFirstStats = nan(numel(localStimNames), 4, nComponents);
        localLastStats = nan(numel(localStimNames), 4, nComponents);
        for stimIndex = 1:numel(localStimNames)
            for componentIndex = 1:nComponents
                localStimStats(stimIndex, :, componentIndex) = metricStats( ...
                    metricValues.values{componentIndex}, ...
                    segmentMask(metricValues.validMasks{componentIndex}, stimPointMasks{stimIndex}, metricKind), ...
                    metricKind, componentIndex);
            end

            thisBoutMasks = stimBoutMasks{stimIndex};
            if isempty(thisBoutMasks)
                continue;
            end
            for componentIndex = 1:nComponents
                localFirstStats(stimIndex, :, componentIndex) = metricStats( ...
                    metricValues.values{componentIndex}, ...
                    segmentMask(metricValues.validMasks{componentIndex}, thisBoutMasks{1}, metricKind), ...
                    metricKind, componentIndex);
                localLastStats(stimIndex, :, componentIndex) = metricStats( ...
                    metricValues.values{componentIndex}, ...
                    segmentMask(metricValues.validMasks{componentIndex}, thisBoutMasks{end}, metricKind), ...
                    metricKind, componentIndex);
            end
        end

        for outputIndex = 1:nOutputStims
            localIndex = localIdxByOutputStim(outputIndex);
            for componentIndex = 1:nComponents
                stimStats(rowIdx, outputIndex, :, componentIndex) = ...
                    cohort.metrics.utils.statsByIndex(localStimStats(:, :, componentIndex), localIndex);
                firstBoutStats(rowIdx, outputIndex, :, componentIndex) = ...
                    cohort.metrics.utils.statsByIndex(localFirstStats(:, :, componentIndex), localIndex);
                lastBoutStats(rowIdx, outputIndex, :, componentIndex) = ...
                    cohort.metrics.utils.statsByIndex(localLastStats(:, :, componentIndex), localIndex);
                deltaStats(rowIdx, outputIndex, :, componentIndex) = ...
                    lastBoutStats(rowIdx, outputIndex, :, componentIndex) - ...
                    firstBoutStats(rowIdx, outputIndex, :, componentIndex);
            end
        end
    end
end

keep = 1:rowIdx;
mouseIdCol = mouseIdCol(keep);
geneCol = geneCol(keep);
cageCodeCol = cageCodeCol(keep);
geneIdCol = geneIdCol(keep);
sexCol = sexCol(keep);
genotypeCol = genotypeCol(keep);
litterCol = litterCol(keep);
toeIdCol = toeIdCol(keep);
dobCol = dobCol(keep);
ageCol = ageCol(keep);
stimProtocolCol = stimProtocolCol(keep);
allStats = allStats(keep, :, :);
stimStats = stimStats(keep, :, :, :);
firstBoutStats = firstBoutStats(keep, :, :, :);
lastBoutStats = lastBoutStats(keep, :, :, :);
deltaStats = deltaStats(keep, :, :, :);

t = table();
t.('Mouse_ID') = mouseIdCol;
t.('Gene') = geneCol;
t.('Cage #') = cageCodeCol;
t.('Gene_ID') = geneIdCol;
t.('Sex$') = sexCol;
t.('Genotype$') = genotypeCol;
t.('Litter') = litterCol;
t.('Toe_ID') = toeIdCol;
t.('DOB') = dobCol;
t.('Age') = ageCol;
t.('Stimulus Protocol') = stimProtocolCol;

for componentIndex = 1:nComponents
    componentName = componentNames{componentIndex};
    unit = units{componentIndex};
    t.(sprintf('%s Min During Stimulus (%s)', componentName, unit)) = allStats(:, 1, componentIndex);
    t.(sprintf('%s Max During Stimulus (%s)', componentName, unit)) = allStats(:, 2, componentIndex);
    t.(sprintf('%s Mean During Stimulus (%s)', componentName, unit)) = allStats(:, 3, componentIndex);
    t.(sprintf('%s Std During Stimulus (%s)', componentName, unit)) = allStats(:, 4, componentIndex);

    for outputIndex = 1:nOutputStims
        stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(outputIndex), outputIndex);
        t.(sprintf('%s Min During %s (%s)', componentName, stimLabel, unit)) = ...
            stimStats(:, outputIndex, 1, componentIndex);
        t.(sprintf('%s Max During %s (%s)', componentName, stimLabel, unit)) = ...
            stimStats(:, outputIndex, 2, componentIndex);
        t.(sprintf('%s Mean During %s (%s)', componentName, stimLabel, unit)) = ...
            stimStats(:, outputIndex, 3, componentIndex);
        t.(sprintf('%s Std During %s (%s)', componentName, stimLabel, unit)) = ...
            stimStats(:, outputIndex, 4, componentIndex);
        t.(sprintf('%s Min During First %s Bout (%s)', componentName, stimLabel, unit)) = ...
            firstBoutStats(:, outputIndex, 1, componentIndex);
        t.(sprintf('%s Max During First %s Bout (%s)', componentName, stimLabel, unit)) = ...
            firstBoutStats(:, outputIndex, 2, componentIndex);
        t.(sprintf('%s Mean During First %s Bout (%s)', componentName, stimLabel, unit)) = ...
            firstBoutStats(:, outputIndex, 3, componentIndex);
        t.(sprintf('%s Std During First %s Bout (%s)', componentName, stimLabel, unit)) = ...
            firstBoutStats(:, outputIndex, 4, componentIndex);
        t.(sprintf('%s Min During Last %s Bout (%s)', componentName, stimLabel, unit)) = ...
            lastBoutStats(:, outputIndex, 1, componentIndex);
        t.(sprintf('%s Max During Last %s Bout (%s)', componentName, stimLabel, unit)) = ...
            lastBoutStats(:, outputIndex, 2, componentIndex);
        t.(sprintf('%s Mean During Last %s Bout (%s)', componentName, stimLabel, unit)) = ...
            lastBoutStats(:, outputIndex, 3, componentIndex);
        t.(sprintf('%s Std During Last %s Bout (%s)', componentName, stimLabel, unit)) = ...
            lastBoutStats(:, outputIndex, 4, componentIndex);
        t.(sprintf('%s Min Last-First During %s Bouts (%s)', componentName, stimLabel, unit)) = ...
            deltaStats(:, outputIndex, 1, componentIndex);
        t.(sprintf('%s Max Last-First During %s Bouts (%s)', componentName, stimLabel, unit)) = ...
            deltaStats(:, outputIndex, 2, componentIndex);
        t.(sprintf('%s Mean Last-First During %s Bouts (%s)', componentName, stimLabel, unit)) = ...
            deltaStats(:, outputIndex, 3, componentIndex);
        t.(sprintf('%s Std Last-First During %s Bouts (%s)', componentName, stimLabel, unit)) = ...
            deltaStats(:, outputIndex, 4, componentIndex);
    end
end

if nargout > 1
    histogram = struct();
    histogram.bins = histogramBins;
    histogram.binEdges = (-180:HEAD_ANGLE_BIN_WIDTH:180)';
    histogram.total = histogramTotal;
else
    histogram = [];
end
end

function [histogramBins, histogramTotal] = accumulateHistogram(histogramBins, histogramTotal, values, validMask, pointMask, metricKind)
if isempty(values) || isempty(validMask) || numel(values) ~= numel(validMask)
    return;
end

mask = segmentMask(validMask, pointMask, metricKind) & isfinite(values);
if ~any(mask)
    return;
end

angles = values(mask);
binIndices = headAngleBinIndex(angles);
for binIndex = binIndices'
    histogramBins(binIndex) = histogramBins(binIndex) + 1;
end
histogramTotal = histogramTotal + numel(angles);
end

function binIndex = headAngleBinIndex(degrees)
% Map an angle in [-180, 180) to its 5-degree bin index (0 -> bin 36,
% +180 boundary -> bin 71), matching the Rust head_angle_bin_index.
shifted = (degrees + 180) / 5;
binIndex = min(max(floor(shifted), 0), 71) + 1;
end

function metricValues = computeMetricValues(metricKind, headX, headY, earLX, earLY, earRX, earRY, noseX, noseY, trialTime)
metricValues.values = cell(1, 2);
metricValues.validMasks = cell(1, 2);

switch metricKind
    case 'speed'
        dt = diff(trialTime);
        values = hypot(diff(headX), diff(headY)) ./ dt;
        valid = finiteAdjacent(headX, headY, dt);
        metricValues.values = {values};
        metricValues.validMasks = {valid};
    case 'acceleration'
        dt = diff(trialTime);
        speed = hypot(diff(headX), diff(headY)) ./ dt;
        speedValid = finiteAdjacent(headX, headY, dt) & isfinite(speed);
        segmentTime = (trialTime(1:end-1) + trialTime(2:end)) / 2;
        centerDt = diff(segmentTime);
        values = diff(speed) ./ centerDt;
        valid = speedValid(1:end-1) & speedValid(2:end) & ...
            isfinite(centerDt) & centerDt > 0;
        metricValues.values = {values, values};
        metricValues.validMasks = {valid, valid};
    case 'angularVelocity'
        axisX = earRX - earLX;
        axisY = earRY - earLY;
        axisLength = hypot(axisX, axisY);
        angle = atan2(axisY, axisX);
        dt = diff(trialTime);
        angleDelta = atan2(sin(diff(angle)), cos(diff(angle)));
        values = -rad2deg(angleDelta) ./ dt;
        valid = finiteAdjacent(earLX, earLY, earRX, earRY, dt) & ...
            axisLength(1:end-1) > 0 & axisLength(2:end) > 0 & isfinite(values);
        metricValues.values = {values};
        metricValues.validMasks = {valid};
    case {'bearingAngle', 'noseHeadingAngularVelocity'}
        % Rust-identical head bearing: direction = ear midpoint -> nose,
        % image convention (Y down). 0 deg = up, +90 = right, -90 = left,
        % range [-180, 180). Degenerate frames (non-finite coordinates or
        % nose coinciding with the ear midpoint) are excluded.
        midX = (earLX + earRX) / 2;
        midY = (earLY + earRY) / 2;
        dx = noseX - midX;
        dy = noseY - midY;
        frameValid = isfinite(dx) & isfinite(dy) & ~(dx == 0 & dy == 0);
        bearing = nan(size(dx));
        bearing(frameValid) = normalizeDegrees(atan2d(dx(frameValid), -dy(frameValid)));

        if strcmp(metricKind, 'bearingAngle')
            metricValues.values = {bearing};
            metricValues.validMasks = {frameValid};
        else
            % Angular velocity = wrapped time-derivative of the bearing
            % series (rotation root = ear midpoint). CW positive, CCW
            % negative, in deg/s.
            dt = diff(trialTime);
            bearingDelta = wrapTo180(diff(bearing));
            values = bearingDelta ./ dt;
            valid = frameValid(1:end-1) & frameValid(2:end) & ...
                isfinite(dt) & dt > 0 & isfinite(values);
            metricValues.values = {values};
            metricValues.validMasks = {valid};
        end
    end
end

function normalized = normalizeDegrees(degrees)
% Normalize an angle in degrees to the signed range [-180, 180), matching
% the Rust normalize_degrees helper.
normalized = mod(degrees, 360);
normalized(normalized >= 180) = normalized(normalized >= 180) - 360;
end

function valid = finiteAdjacent(varargin)
dt = varargin{end};
coordinates = varargin(1:end-1);
valid = isfinite(dt) & dt > 0;
for coordinateIndex = 1:numel(coordinates)
    coordinate = coordinates{coordinateIndex};
    valid = valid & isfinite(coordinate(1:end-1)) & isfinite(coordinate(2:end));
end
end

function mask = segmentMask(validMask, pointMask, metricKind)
if isempty(validMask) || isempty(pointMask)
    mask = false(size(validMask));
    return;
end

if strcmp(metricKind, 'acceleration')
    if numel(pointMask) < 3
        mask = false(size(validMask));
    else
        mask = pointMask(1:end-2) & pointMask(2:end-1) & pointMask(3:end);
    end
elseif strcmp(metricKind, 'bearingAngle')
    % Bearing is a per-frame quantity: the point mask applies directly.
    mask = pointMask;
else
    if numel(pointMask) < 2
        mask = false(size(validMask));
    else
        mask = pointMask(1:end-1) & pointMask(2:end);
    end
end
if numel(mask) ~= numel(validMask)
    mask = false(size(validMask));
else
    mask = mask & validMask;
end
end

function stats = metricStats(values, mask, metricKind, componentIndex)
stats = nan(1, 4);
if isempty(values) || isempty(mask) || numel(values) ~= numel(mask)
    return;
end

if strcmp(metricKind, 'acceleration')
    mask = mask & isfinite(values);
    if componentIndex == 1
        mask = mask & values > 0;
    else
        mask = mask & values < 0;
    end
    values = abs(values);
else
    mask = mask & isfinite(values);
end
if ~any(mask)
    return;
end

validValues = values(mask);

if strcmp(metricKind, 'bearingAngle')
    % Circular statistics: mean via atan2 of mean sin/cos, std via circular
    % dispersion sqrt(-2 ln R). Min/max are the raw linear extremes within
    % the mask (range endpoints, not circular quantities).
    radians = deg2rad(validValues);
    meanRadians = atan2(mean(sin(radians)), mean(cos(radians)));
    meanDegrees = normalizeDegrees(rad2deg(meanRadians));
    resultantLength = hypot(mean(cos(radians)), mean(sin(radians)));
    if resultantLength > 0
        circularStd = rad2deg(sqrt(-2 * log(resultantLength)));
    else
        circularStd = 180 / sqrt(3); % uniform-limit value when R = 0
    end
    stats = [min(validValues), max(validValues), meanDegrees, circularStd];
    return;
end

stats = [min(validValues), max(validValues), mean(validValues), std(validValues, 0)];
end

function labels = localOverrideLabels(overrideSpec, tableIndex)
if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
    labels = string(overrideSpec{tableIndex});
else
    labels = string(overrideSpec);
end
labels = labels(:);
end
