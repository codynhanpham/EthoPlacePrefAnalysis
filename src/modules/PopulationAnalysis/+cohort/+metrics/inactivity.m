function t = inactivity(standardizedTables, kvargs)
	%%INACTIVITY Cohort summary of inactivity/active duration statistics.
	% Detects inactivity with low-speed entry and high-speed exit hysteresis,
	% then reports four duration families (s):
	%   1) Inactive Total (per stimulus-active window total)
	%   2) Inactive Continuous (per inactivity bout duration)
	%   3) Active Total (per stimulus-active window total)
	%   4) Active Continuous (per active bout duration)
	% For each family, reports Min/Max/Mean/Std during all stimulus-active
	% windows and during each stimulus-specific active window.

	arguments
		standardizedTables struct {sdTable.mustBeStandardizedTable}
		kvargs.StimulusIncludesTrailingISI (1,1) logical = true
		kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
		kvargs.InactiveThresholds = []
		kvargs.ActiveThresholds = []
	end

	if isempty(standardizedTables)
		t = table();
		return;
	end

	hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
	overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
	outputStimNames = cohort.metrics.utils.getOutputStimNames(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
	nOutputStims = numel(outputStimNames);

	inactiveThresholds = resolveThresholdStruct(kvargs.InactiveThresholds, struct('speed', 3, 'duration', 5), 'InactiveThresholds');
	activeThresholds = resolveThresholdStruct(kvargs.ActiveThresholds, struct('speed', 8, 'duration', 1), 'ActiveThresholds');

	nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);
	[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);

	inactiveTotalAll = nan(nRowsEstimate, 4);
	inactiveContAll = nan(nRowsEstimate, 4);
	activeTotalAll = nan(nRowsEstimate, 4);
	activeContAll = nan(nRowsEstimate, 4);

	inactiveTotalByStim = nan(nRowsEstimate, nOutputStims, 4);
	inactiveContByStim = nan(nRowsEstimate, nOutputStims, 4);
	activeTotalByStim = nan(nRowsEstimate, nOutputStims, 4);
	activeContByStim = nan(nRowsEstimate, nOutputStims, 4);
	inactiveTotalByStimFirstBout = nan(nRowsEstimate, nOutputStims, 4);
	inactiveContByStimFirstBout = nan(nRowsEstimate, nOutputStims, 4);
	activeTotalByStimFirstBout = nan(nRowsEstimate, nOutputStims, 4);
	activeContByStimFirstBout = nan(nRowsEstimate, nOutputStims, 4);
	inactiveTotalByStimLastBout = nan(nRowsEstimate, nOutputStims, 4);
	inactiveContByStimLastBout = nan(nRowsEstimate, nOutputStims, 4);
	activeTotalByStimLastBout = nan(nRowsEstimate, nOutputStims, 4);
	activeContByStimLastBout = nan(nRowsEstimate, nOutputStims, 4);
	inactiveTotalByStimDeltaLastFirst = nan(nRowsEstimate, nOutputStims, 4);
	inactiveContByStimDeltaLastFirst = nan(nRowsEstimate, nOutputStims, 4);
	activeTotalByStimDeltaLastFirst = nan(nRowsEstimate, nOutputStims, 4);
	activeContByStimDeltaLastFirst = nan(nRowsEstimate, nOutputStims, 4);

	rowIdx = 0;
	for i = 1:length(standardizedTables)
		stdTable = standardizedTables(i);
		cp = stdTable.centerpointData;

		trialTime = cp{:, 'Trial time'};
		stimSequence = string(cp{:, 'Stimulus name'});
		xData = cp{:, 'X center'};
		yData = cp{:, 'Y center'};
		nAnimals = size(xData, 2);

		localStimNames = string(stdTable.stimuliSorted);
		localStimNames = localStimNames(:);

		allStimPointMask = cohort.metrics.utils.periodMaskAllStim(stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI);
		stimPointMasks = cell(numel(localStimNames), 1);
		for s = 1:numel(localStimNames)
			stimPointMasks{s} = cohort.metrics.utils.periodMaskForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
		end
		stimBoutMasks = cell(numel(localStimNames), 1);
		for s = 1:numel(localStimNames)
			stimBoutMasks{s} = cohort.metrics.utils.stimBoutMasksForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
		end

		localIdxByOutputStim = zeros(nOutputStims, 1);
		if hasOverride
			localDisplayNames = localOverrideLabels(overrideSpec, i);
			for g = 1:nOutputStims
				idx = find(strcmpi(localDisplayNames, outputStimNames(g)), 1, 'first');
				if isempty(idx)
					localIdxByOutputStim(g) = 0;
				else
					localIdxByOutputStim(g) = idx;
				end
			end
		else
			for g = 1:nOutputStims
				idx = cohort.metrics.utils.firstMatchingStimIndex(localStimNames, outputStimNames(g), hasOverride);
				if isempty(idx)
					localIdxByOutputStim(g) = 0;
				else
					localIdxByOutputStim(g) = idx;
				end
			end
		end

		animalKeys = keys(stdTable.animalMetadata);
		for col = 1:nAnimals
			rowIdx = rowIdx + 1;

			md = struct();
			if col <= numel(animalKeys)
				md = stdTable.animalMetadata(animalKeys{col});
			end
			[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
				cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stdTable.stimfileName);

			thisX = xData(:, col);
			thisY = yData(:, col);
			[speed, segStartTime, segEndTime, segValid] = segmentSpeed(thisX, thisY, trialTime);

			statsAll = evaluateMaskStats(speed, segStartTime, segEndTime, segValid, allStimPointMask, inactiveThresholds, activeThresholds);
			inactiveTotalAll(rowIdx, :) = statsAll.inactiveTotal;
			inactiveContAll(rowIdx, :) = statsAll.inactiveContinuous;
			activeTotalAll(rowIdx, :) = statsAll.activeTotal;
			activeContAll(rowIdx, :) = statsAll.activeContinuous;

			localStats = nan(numel(localStimNames), 16);
			localFirstBoutStats = nan(numel(localStimNames), 16);
			localLastBoutStats = nan(numel(localStimNames), 16);
			for s = 1:numel(localStimNames)
				statsS = evaluateMaskStats(speed, segStartTime, segEndTime, segValid, stimPointMasks{s}, inactiveThresholds, activeThresholds);
				localStats(s, :) = [statsS.inactiveTotal, statsS.inactiveContinuous, statsS.activeTotal, statsS.activeContinuous];

				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					statsFirst = evaluateMaskStats(speed, segStartTime, segEndTime, segValid, thisBoutMasks{1}, inactiveThresholds, activeThresholds);
					localFirstBoutStats(s, :) = [statsFirst.inactiveTotal, statsFirst.inactiveContinuous, statsFirst.activeTotal, statsFirst.activeContinuous];

					statsLast = evaluateMaskStats(speed, segStartTime, segEndTime, segValid, thisBoutMasks{end}, inactiveThresholds, activeThresholds);
					localLastBoutStats(s, :) = [statsLast.inactiveTotal, statsLast.inactiveContinuous, statsLast.activeTotal, statsLast.activeContinuous];
				end
			end

			for g = 1:nOutputStims
				vals = vectorByIndex(localStats, localIdxByOutputStim(g));
				inactiveTotalByStim(rowIdx, g, :) = vals(1:4);
				inactiveContByStim(rowIdx, g, :) = vals(5:8);
				activeTotalByStim(rowIdx, g, :) = vals(9:12);
				activeContByStim(rowIdx, g, :) = vals(13:16);

				valsFirst = vectorByIndex(localFirstBoutStats, localIdxByOutputStim(g));
				inactiveTotalByStimFirstBout(rowIdx, g, :) = valsFirst(1:4);
				inactiveContByStimFirstBout(rowIdx, g, :) = valsFirst(5:8);
				activeTotalByStimFirstBout(rowIdx, g, :) = valsFirst(9:12);
				activeContByStimFirstBout(rowIdx, g, :) = valsFirst(13:16);

				valsLast = vectorByIndex(localLastBoutStats, localIdxByOutputStim(g));
				inactiveTotalByStimLastBout(rowIdx, g, :) = valsLast(1:4);
				inactiveContByStimLastBout(rowIdx, g, :) = valsLast(5:8);
				activeTotalByStimLastBout(rowIdx, g, :) = valsLast(9:12);
				activeContByStimLastBout(rowIdx, g, :) = valsLast(13:16);

				inactiveTotalByStimDeltaLastFirst(rowIdx, g, :) = valsLast(1:4) - valsFirst(1:4);
				inactiveContByStimDeltaLastFirst(rowIdx, g, :) = valsLast(5:8) - valsFirst(5:8);
				activeTotalByStimDeltaLastFirst(rowIdx, g, :) = valsLast(9:12) - valsFirst(9:12);
				activeContByStimDeltaLastFirst(rowIdx, g, :) = valsLast(13:16) - valsFirst(13:16);
			end
		end
	end

	if rowIdx < nRowsEstimate
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
		inactiveTotalAll = inactiveTotalAll(keep, :);
		inactiveContAll = inactiveContAll(keep, :);
		activeTotalAll = activeTotalAll(keep, :);
		activeContAll = activeContAll(keep, :);
		inactiveTotalByStim = inactiveTotalByStim(keep, :, :);
		inactiveContByStim = inactiveContByStim(keep, :, :);
		activeTotalByStim = activeTotalByStim(keep, :, :);
		activeContByStim = activeContByStim(keep, :, :);
		inactiveTotalByStimFirstBout = inactiveTotalByStimFirstBout(keep, :, :);
		inactiveContByStimFirstBout = inactiveContByStimFirstBout(keep, :, :);
		activeTotalByStimFirstBout = activeTotalByStimFirstBout(keep, :, :);
		activeContByStimFirstBout = activeContByStimFirstBout(keep, :, :);
		inactiveTotalByStimLastBout = inactiveTotalByStimLastBout(keep, :, :);
		inactiveContByStimLastBout = inactiveContByStimLastBout(keep, :, :);
		activeTotalByStimLastBout = activeTotalByStimLastBout(keep, :, :);
		activeContByStimLastBout = activeContByStimLastBout(keep, :, :);
		inactiveTotalByStimDeltaLastFirst = inactiveTotalByStimDeltaLastFirst(keep, :, :);
		inactiveContByStimDeltaLastFirst = inactiveContByStimDeltaLastFirst(keep, :, :);
		activeTotalByStimDeltaLastFirst = activeTotalByStimDeltaLastFirst(keep, :, :);
		activeContByStimDeltaLastFirst = activeContByStimDeltaLastFirst(keep, :, :);
	end

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

	statNames = {'Min', 'Max', 'Mean', 'Std'};
	for s = 1:4
		t.(sprintf('Inactive Total %s During Stimulus (s)', statNames{s})) = inactiveTotalAll(:, s);
		t.(sprintf('Inactive Continuous %s During Stimulus (s)', statNames{s})) = inactiveContAll(:, s);
		t.(sprintf('Active Total %s During Stimulus (s)', statNames{s})) = activeTotalAll(:, s);
		t.(sprintf('Active Continuous %s During Stimulus (s)', statNames{s})) = activeContAll(:, s);
	end

	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		for s = 1:4
			t.(sprintf('Inactive Total %s During %s (s)', statNames{s}, stimLabel)) = inactiveTotalByStim(:, g, s);
			t.(sprintf('Inactive Continuous %s During %s (s)', statNames{s}, stimLabel)) = inactiveContByStim(:, g, s);
			t.(sprintf('Active Total %s During %s (s)', statNames{s}, stimLabel)) = activeTotalByStim(:, g, s);
			t.(sprintf('Active Continuous %s During %s (s)', statNames{s}, stimLabel)) = activeContByStim(:, g, s);
			t.(sprintf('Inactive Total %s During First %s Bout (s)', statNames{s}, stimLabel)) = inactiveTotalByStimFirstBout(:, g, s);
			t.(sprintf('Inactive Continuous %s During First %s Bout (s)', statNames{s}, stimLabel)) = inactiveContByStimFirstBout(:, g, s);
			t.(sprintf('Active Total %s During First %s Bout (s)', statNames{s}, stimLabel)) = activeTotalByStimFirstBout(:, g, s);
			t.(sprintf('Active Continuous %s During First %s Bout (s)', statNames{s}, stimLabel)) = activeContByStimFirstBout(:, g, s);
			t.(sprintf('Inactive Total %s During Last %s Bout (s)', statNames{s}, stimLabel)) = inactiveTotalByStimLastBout(:, g, s);
			t.(sprintf('Inactive Continuous %s During Last %s Bout (s)', statNames{s}, stimLabel)) = inactiveContByStimLastBout(:, g, s);
			t.(sprintf('Active Total %s During Last %s Bout (s)', statNames{s}, stimLabel)) = activeTotalByStimLastBout(:, g, s);
			t.(sprintf('Active Continuous %s During Last %s Bout (s)', statNames{s}, stimLabel)) = activeContByStimLastBout(:, g, s);
			t.(sprintf('Inactive Total %s Last-First During %s Bouts (s)', statNames{s}, stimLabel)) = inactiveTotalByStimDeltaLastFirst(:, g, s);
			t.(sprintf('Inactive Continuous %s Last-First During %s Bouts (s)', statNames{s}, stimLabel)) = inactiveContByStimDeltaLastFirst(:, g, s);
			t.(sprintf('Active Total %s Last-First During %s Bouts (s)', statNames{s}, stimLabel)) = activeTotalByStimDeltaLastFirst(:, g, s);
			t.(sprintf('Active Continuous %s Last-First During %s Bouts (s)', statNames{s}, stimLabel)) = activeContByStimDeltaLastFirst(:, g, s);
		end
	end
end


function stats = evaluateMaskStats(speed, segStartTime, segEndTime, segValid, pointMask, inactiveThresholds, activeThresholds)
	stats = struct( ...
		'inactiveTotal', nan(1,4), ...
		'inactiveContinuous', nan(1,4), ...
		'activeTotal', nan(1,4), ...
		'activeContinuous', nan(1,4));

	if isempty(speed)
		return;
	end

	nPoints = numel(segStartTime) + 1;
	if numel(pointMask) ~= nPoints
		pointMask = false(nPoints, 1);
	end

	segMask = pointMask(1:end-1) & pointMask(2:end) & segValid;
	if ~any(segMask)
		return;
	end

	windows = segmentMaskWindows(segStartTime, segEndTime, segMask);
	inactiveBouts = detectInactivityBouts(speed, segStartTime, segEndTime, segMask, inactiveThresholds, activeThresholds);
	activeBouts = complementBouts(windows, inactiveBouts);

	inactiveTotals = totalsByWindows(inactiveBouts, windows);
	activeTotals = totalsByWindows(activeBouts, windows);
	inactiveCont = durationsFromBouts(inactiveBouts);
	activeCont = durationsFromBouts(activeBouts);

	stats.inactiveTotal = durationStats(inactiveTotals);
	stats.inactiveContinuous = durationStats(inactiveCont);
	stats.activeTotal = durationStats(activeTotals);
	stats.activeContinuous = durationStats(activeCont);
end


function windows = segmentMaskWindows(segStartTime, segEndTime, segMask)
	windows = nan(0, 2);
	if isempty(segMask)
		return;
	end

	runStarts = find(diff([false; segMask(:); false]) == 1);
	runEnds = find(diff([false; segMask(:); false]) == -1) - 1;
	for i = 1:numel(runStarts)
		windows(end+1, :) = [segStartTime(runStarts(i)), segEndTime(runEnds(i))]; %#ok<AGROW>
	end
end


function bouts = detectInactivityBouts(speed, segStartTime, segEndTime, segMask, inactiveThresholds, activeThresholds)
	bouts = nan(0, 2);
	if isempty(speed)
		return;
	end

	isInactive = false;
	belowRunStart = NaN;
	aboveRunStart = NaN;
	belowRunDuration = 0;
	aboveRunDuration = 0;
	currentBoutStart = NaN;

	for k = 1:numel(speed)
		if ~segMask(k) || ~isfinite(speed(k))
			belowRunStart = NaN;
			aboveRunStart = NaN;
			belowRunDuration = 0;
			aboveRunDuration = 0;
			continue;
		end

		segDuration = segEndTime(k) - segStartTime(k);
		if ~(isfinite(segDuration) && segDuration > 0)
			continue;
		end

		if ~isInactive
			if speed(k) < inactiveThresholds.speed
				if isnan(belowRunStart)
					belowRunStart = segStartTime(k);
					belowRunDuration = 0;
				end
				belowRunDuration = belowRunDuration + segDuration;
				if belowRunDuration >= inactiveThresholds.duration
					currentBoutStart = belowRunStart;
					isInactive = true;
					aboveRunStart = NaN;
					aboveRunDuration = 0;
				end
			else
				belowRunStart = NaN;
				belowRunDuration = 0;
			end
		else
			if speed(k) > activeThresholds.speed
				if isnan(aboveRunStart)
					aboveRunStart = segStartTime(k);
					aboveRunDuration = 0;
				end
				aboveRunDuration = aboveRunDuration + segDuration;
				if aboveRunDuration >= activeThresholds.duration
					bouts(end+1, :) = [currentBoutStart, aboveRunStart]; %#ok<AGROW>
					isInactive = false;
					currentBoutStart = NaN;
					belowRunStart = NaN;
					belowRunDuration = 0;
					aboveRunStart = NaN;
					aboveRunDuration = 0;
				end
			else
				aboveRunStart = NaN;
				aboveRunDuration = 0;
			end
		end
	end

	if isInactive && ~isnan(currentBoutStart)
		lastValidSeg = find(segMask, 1, 'last');
		if isempty(lastValidSeg)
			lastEnd = segEndTime(end);
		else
			lastEnd = segEndTime(lastValidSeg);
		end
		bouts(end+1, :) = [currentBoutStart, lastEnd]; %#ok<AGROW>
	end
end


function activeBouts = complementBouts(windows, inactiveBouts)
	activeBouts = nan(0, 2);
	if isempty(windows)
		return;
	end

	for i = 1:size(windows, 1)
		ws = windows(i, 1);
		we = windows(i, 2);
		if ~(isfinite(ws) && isfinite(we) && we > ws)
			continue;
		end

		overlaps = intervalIntersections(inactiveBouts, [ws, we]);
		cursor = ws;
		for j = 1:size(overlaps, 1)
			os = overlaps(j, 1);
			oe = overlaps(j, 2);
			if os > cursor
				activeBouts(end+1, :) = [cursor, os]; %#ok<AGROW>
			end
			cursor = max(cursor, oe);
		end
		if cursor < we
			activeBouts(end+1, :) = [cursor, we]; %#ok<AGROW>
		end
	end
end


function totals = totalsByWindows(bouts, windows)
	totals = nan(size(windows, 1), 1);
	for i = 1:size(windows, 1)
		overlaps = intervalIntersections(bouts, windows(i, :));
		if isempty(overlaps)
			totals(i) = 0;
		else
			totals(i) = sum(overlaps(:, 2) - overlaps(:, 1), 'omitnan');
		end
	end
end


function overlaps = intervalIntersections(intervals, window)
	overlaps = nan(0, 2);
	if isempty(intervals)
		return;
	end

	ws = window(1);
	we = window(2);
	for i = 1:size(intervals, 1)
		s = max(intervals(i, 1), ws);
		e = min(intervals(i, 2), we);
		if isfinite(s) && isfinite(e) && e > s
			overlaps(end+1, :) = [s, e]; %#ok<AGROW>
		end
	end
end


function d = durationsFromBouts(bouts)
	if isempty(bouts)
		d = nan(0, 1);
		return;
	end

	d = bouts(:, 2) - bouts(:, 1);
	d = d(isfinite(d) & d > 0);
end


function [speed, segStartTime, segEndTime, valid] = segmentSpeed(x, y, t)
	if isempty(x) || isempty(y) || isempty(t) || numel(t) < 2
		speed = nan(0, 1);
		segStartTime = nan(0, 1);
		segEndTime = nan(0, 1);
		valid = false(0, 1);
		return;
	end

	dx = diff(x);
	dy = diff(y);
	dt = diff(t);
	segStartTime = t(1:end-1);
	segEndTime = t(2:end);
	stepDist = sqrt(dx.^2 + dy.^2);
	speed = stepDist ./ dt;
	valid = isfinite(speed) & isfinite(dt) & (dt > 0);
end


function mmmsStats = durationStats(values)
	mmmsStats = [NaN, NaN, NaN, NaN];
	if isempty(values)
		return;
	end

	values = values(:);
	valid = isfinite(values);
	if ~any(valid)
		return;
	end

	vals = values(valid);
	mmmsStats(1) = min(vals, [], 'omitnan');
	mmmsStats(2) = max(vals, [], 'omitnan');
	mmmsStats(3) = mean(vals, 'omitnan');
	mmmsStats(4) = std(vals, 0, 'omitnan');
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
	if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
		labels = string(overrideSpec{tableIdx});
	else
		labels = string(overrideSpec);
	end
	labels = labels(:);
end


function out = vectorByIndex(matrix, idx)
	out = nan(1, size(matrix, 2));
	if ~isempty(idx) && idx >= 1 && idx <= size(matrix, 1)
		out = matrix(idx, :);
	end
end


function mustBeThresholdStruct(s, name)
	if ~isstruct(s) || ~isscalar(s)
		error('%s must be a scalar struct with fields speed and duration.', name);
	end
	if ~isfield(s, 'speed') || ~isfield(s, 'duration')
		error('%s must contain fields speed and duration.', name);
	end
	if ~isnumeric(s.speed) || ~isscalar(s.speed) || ~isfinite(s.speed) || s.speed < 0
		error('%s.speed must be a finite nonnegative numeric scalar.', name);
	end
	if ~isnumeric(s.duration) || ~isscalar(s.duration) || ~isfinite(s.duration) || s.duration < 0
		error('%s.duration must be a finite nonnegative numeric scalar.', name);
	end
end


function s = resolveThresholdStruct(inputValue, defaultValue, name)
	if isempty(inputValue)
		s = defaultValue;
		return;
	end

	if isstruct(inputValue) && isscalar(inputValue) && isempty(fieldnames(inputValue))
		s = defaultValue;
		return;
	end

	mustBeThresholdStruct(inputValue, name);
	s = inputValue;
end
