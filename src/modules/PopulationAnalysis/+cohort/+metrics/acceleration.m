function t = acceleration(standardizedTables, kvargs)
	%%ACCELERATION Cohort summary of instantaneous acceleration statistics
	% Reports signed accel/decel summaries during all stimulus periods and
	% during each output stimulus period. Min/max/mean/std are computed on
	% the absolute acceleration magnitude within each signed subset.

	arguments
		standardizedTables struct {sdTable.mustBeStandardizedTable}
		kvargs.StimulusIncludesTrailingISI (1,1) logical = true
		kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
	end

	if isempty(standardizedTables)
		t = table();
		return;
	end

	hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
	overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
	outputStimNames = cohort.metrics.utils.getOutputStimNames(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
	nOutputStims = numel(outputStimNames);

	nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);

	[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);

	accAllMin = nan(nRowsEstimate, 1);
	accAllMax = nan(nRowsEstimate, 1);
	accAllMean = nan(nRowsEstimate, 1);
	accAllStd = nan(nRowsEstimate, 1);
	decelAllMin = nan(nRowsEstimate, 1);
	decelAllMax = nan(nRowsEstimate, 1);
	decelAllMean = nan(nRowsEstimate, 1);
	decelAllStd = nan(nRowsEstimate, 1);

	accByStimMin = nan(nRowsEstimate, nOutputStims);
	accByStimMax = nan(nRowsEstimate, nOutputStims);
	accByStimMean = nan(nRowsEstimate, nOutputStims);
	accByStimStd = nan(nRowsEstimate, nOutputStims);
	decelByStimMin = nan(nRowsEstimate, nOutputStims);
	decelByStimMax = nan(nRowsEstimate, nOutputStims);
	decelByStimMean = nan(nRowsEstimate, nOutputStims);
	decelByStimStd = nan(nRowsEstimate, nOutputStims);

	accByStimFirstBoutMin = nan(nRowsEstimate, nOutputStims);
	accByStimFirstBoutMax = nan(nRowsEstimate, nOutputStims);
	accByStimFirstBoutMean = nan(nRowsEstimate, nOutputStims);
	accByStimFirstBoutStd = nan(nRowsEstimate, nOutputStims);
	decelByStimFirstBoutMin = nan(nRowsEstimate, nOutputStims);
	decelByStimFirstBoutMax = nan(nRowsEstimate, nOutputStims);
	decelByStimFirstBoutMean = nan(nRowsEstimate, nOutputStims);
	decelByStimFirstBoutStd = nan(nRowsEstimate, nOutputStims);

	accByStimLastBoutMin = nan(nRowsEstimate, nOutputStims);
	accByStimLastBoutMax = nan(nRowsEstimate, nOutputStims);
	accByStimLastBoutMean = nan(nRowsEstimate, nOutputStims);
	accByStimLastBoutStd = nan(nRowsEstimate, nOutputStims);
	decelByStimLastBoutMin = nan(nRowsEstimate, nOutputStims);
	decelByStimLastBoutMax = nan(nRowsEstimate, nOutputStims);
	decelByStimLastBoutMean = nan(nRowsEstimate, nOutputStims);
	decelByStimLastBoutStd = nan(nRowsEstimate, nOutputStims);

	accByStimDeltaLastFirstMin = nan(nRowsEstimate, nOutputStims);
	accByStimDeltaLastFirstMax = nan(nRowsEstimate, nOutputStims);
	accByStimDeltaLastFirstMean = nan(nRowsEstimate, nOutputStims);
	accByStimDeltaLastFirstStd = nan(nRowsEstimate, nOutputStims);
	decelByStimDeltaLastFirstMin = nan(nRowsEstimate, nOutputStims);
	decelByStimDeltaLastFirstMax = nan(nRowsEstimate, nOutputStims);
	decelByStimDeltaLastFirstMean = nan(nRowsEstimate, nOutputStims);
	decelByStimDeltaLastFirstStd = nan(nRowsEstimate, nOutputStims);

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

			[instAcc, accMaskAll] = instantaneousAcceleration(thisX, thisY, trialTime, allStimPointMask);
			[accAllMin(rowIdx), accAllMax(rowIdx), accAllMean(rowIdx), accAllStd(rowIdx)] = maskedStats(abs(instAcc), accMaskAll & instAcc > 0);
			[decelAllMin(rowIdx), decelAllMax(rowIdx), decelAllMean(rowIdx), decelAllStd(rowIdx)] = maskedStats(abs(instAcc), accMaskAll & instAcc < 0);

			localStimStats = nan(numel(localStimNames), 4);
			localDecelStats = nan(numel(localStimNames), 4);
			localStimFirstBoutStats = nan(numel(localStimNames), 4);
			localDecelFirstBoutStats = nan(numel(localStimNames), 4);
			localStimLastBoutStats = nan(numel(localStimNames), 4);
			localDecelLastBoutStats = nan(numel(localStimNames), 4);
			for s = 1:numel(localStimNames)
				[instAccStim, accMaskStim] = instantaneousAcceleration(thisX, thisY, trialTime, stimPointMasks{s});
				[localStimStats(s,1), localStimStats(s,2), localStimStats(s,3), localStimStats(s,4)] = maskedStats(abs(instAccStim), accMaskStim & instAccStim > 0);
				[localDecelStats(s,1), localDecelStats(s,2), localDecelStats(s,3), localDecelStats(s,4)] = maskedStats(abs(instAccStim), accMaskStim & instAccStim < 0);

				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					[instAccFirst, accMaskFirst] = instantaneousAcceleration(thisX, thisY, trialTime, thisBoutMasks{1});
					[localStimFirstBoutStats(s,1), localStimFirstBoutStats(s,2), localStimFirstBoutStats(s,3), localStimFirstBoutStats(s,4)] = maskedStats(abs(instAccFirst), accMaskFirst & instAccFirst > 0);
					[localDecelFirstBoutStats(s,1), localDecelFirstBoutStats(s,2), localDecelFirstBoutStats(s,3), localDecelFirstBoutStats(s,4)] = maskedStats(abs(instAccFirst), accMaskFirst & instAccFirst < 0);

					[instAccLast, accMaskLast] = instantaneousAcceleration(thisX, thisY, trialTime, thisBoutMasks{end});
					[localStimLastBoutStats(s,1), localStimLastBoutStats(s,2), localStimLastBoutStats(s,3), localStimLastBoutStats(s,4)] = maskedStats(abs(instAccLast), accMaskLast & instAccLast > 0);
					[localDecelLastBoutStats(s,1), localDecelLastBoutStats(s,2), localDecelLastBoutStats(s,3), localDecelLastBoutStats(s,4)] = maskedStats(abs(instAccLast), accMaskLast & instAccLast < 0);
				end
			end

			for g = 1:nOutputStims
				stats = cohort.metrics.utils.statsByIndex(localStimStats, localIdxByOutputStim(g));
				accByStimMin(rowIdx, g) = stats(1);
				accByStimMax(rowIdx, g) = stats(2);
				accByStimMean(rowIdx, g) = stats(3);
				accByStimStd(rowIdx, g) = stats(4);

				decelStats = cohort.metrics.utils.statsByIndex(localDecelStats, localIdxByOutputStim(g));
				decelByStimMin(rowIdx, g) = decelStats(1);
				decelByStimMax(rowIdx, g) = decelStats(2);
				decelByStimMean(rowIdx, g) = decelStats(3);
				decelByStimStd(rowIdx, g) = decelStats(4);

				firstStats = cohort.metrics.utils.statsByIndex(localStimFirstBoutStats, localIdxByOutputStim(g));
				accByStimFirstBoutMin(rowIdx, g) = firstStats(1);
				accByStimFirstBoutMax(rowIdx, g) = firstStats(2);
				accByStimFirstBoutMean(rowIdx, g) = firstStats(3);
				accByStimFirstBoutStd(rowIdx, g) = firstStats(4);

				decelFirstStats = cohort.metrics.utils.statsByIndex(localDecelFirstBoutStats, localIdxByOutputStim(g));
				decelByStimFirstBoutMin(rowIdx, g) = decelFirstStats(1);
				decelByStimFirstBoutMax(rowIdx, g) = decelFirstStats(2);
				decelByStimFirstBoutMean(rowIdx, g) = decelFirstStats(3);
				decelByStimFirstBoutStd(rowIdx, g) = decelFirstStats(4);

				lastStats = cohort.metrics.utils.statsByIndex(localStimLastBoutStats, localIdxByOutputStim(g));
				accByStimLastBoutMin(rowIdx, g) = lastStats(1);
				accByStimLastBoutMax(rowIdx, g) = lastStats(2);
				accByStimLastBoutMean(rowIdx, g) = lastStats(3);
				accByStimLastBoutStd(rowIdx, g) = lastStats(4);

				decelLastStats = cohort.metrics.utils.statsByIndex(localDecelLastBoutStats, localIdxByOutputStim(g));
				decelByStimLastBoutMin(rowIdx, g) = decelLastStats(1);
				decelByStimLastBoutMax(rowIdx, g) = decelLastStats(2);
				decelByStimLastBoutMean(rowIdx, g) = decelLastStats(3);
				decelByStimLastBoutStd(rowIdx, g) = decelLastStats(4);

				accByStimDeltaLastFirstMin(rowIdx, g) = accByStimLastBoutMin(rowIdx, g) - accByStimFirstBoutMin(rowIdx, g);
				accByStimDeltaLastFirstMax(rowIdx, g) = accByStimLastBoutMax(rowIdx, g) - accByStimFirstBoutMax(rowIdx, g);
				accByStimDeltaLastFirstMean(rowIdx, g) = accByStimLastBoutMean(rowIdx, g) - accByStimFirstBoutMean(rowIdx, g);
				accByStimDeltaLastFirstStd(rowIdx, g) = accByStimLastBoutStd(rowIdx, g) - accByStimFirstBoutStd(rowIdx, g);
				decelByStimDeltaLastFirstMin(rowIdx, g) = decelByStimLastBoutMin(rowIdx, g) - decelByStimFirstBoutMin(rowIdx, g);
				decelByStimDeltaLastFirstMax(rowIdx, g) = decelByStimLastBoutMax(rowIdx, g) - decelByStimFirstBoutMax(rowIdx, g);
				decelByStimDeltaLastFirstMean(rowIdx, g) = decelByStimLastBoutMean(rowIdx, g) - decelByStimFirstBoutMean(rowIdx, g);
				decelByStimDeltaLastFirstStd(rowIdx, g) = decelByStimLastBoutStd(rowIdx, g) - decelByStimFirstBoutStd(rowIdx, g);
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

		accAllMin = accAllMin(keep);
		accAllMax = accAllMax(keep);
		accAllMean = accAllMean(keep);
		accAllStd = accAllStd(keep);
		decelAllMin = decelAllMin(keep);
		decelAllMax = decelAllMax(keep);
		decelAllMean = decelAllMean(keep);
		decelAllStd = decelAllStd(keep);
		accByStimMin = accByStimMin(keep, :);
		accByStimMax = accByStimMax(keep, :);
		accByStimMean = accByStimMean(keep, :);
		accByStimStd = accByStimStd(keep, :);
		decelByStimMin = decelByStimMin(keep, :);
		decelByStimMax = decelByStimMax(keep, :);
		decelByStimMean = decelByStimMean(keep, :);
		decelByStimStd = decelByStimStd(keep, :);
		accByStimFirstBoutMin = accByStimFirstBoutMin(keep, :);
		accByStimFirstBoutMax = accByStimFirstBoutMax(keep, :);
		accByStimFirstBoutMean = accByStimFirstBoutMean(keep, :);
		accByStimFirstBoutStd = accByStimFirstBoutStd(keep, :);
		decelByStimFirstBoutMin = decelByStimFirstBoutMin(keep, :);
		decelByStimFirstBoutMax = decelByStimFirstBoutMax(keep, :);
		decelByStimFirstBoutMean = decelByStimFirstBoutMean(keep, :);
		decelByStimFirstBoutStd = decelByStimFirstBoutStd(keep, :);
		accByStimLastBoutMin = accByStimLastBoutMin(keep, :);
		accByStimLastBoutMax = accByStimLastBoutMax(keep, :);
		accByStimLastBoutMean = accByStimLastBoutMean(keep, :);
		accByStimLastBoutStd = accByStimLastBoutStd(keep, :);
		decelByStimLastBoutMin = decelByStimLastBoutMin(keep, :);
		decelByStimLastBoutMax = decelByStimLastBoutMax(keep, :);
		decelByStimLastBoutMean = decelByStimLastBoutMean(keep, :);
		decelByStimLastBoutStd = decelByStimLastBoutStd(keep, :);
		accByStimDeltaLastFirstMin = accByStimDeltaLastFirstMin(keep, :);
		accByStimDeltaLastFirstMax = accByStimDeltaLastFirstMax(keep, :);
		accByStimDeltaLastFirstMean = accByStimDeltaLastFirstMean(keep, :);
		accByStimDeltaLastFirstStd = accByStimDeltaLastFirstStd(keep, :);
		decelByStimDeltaLastFirstMin = decelByStimDeltaLastFirstMin(keep, :);
		decelByStimDeltaLastFirstMax = decelByStimDeltaLastFirstMax(keep, :);
		decelByStimDeltaLastFirstMean = decelByStimDeltaLastFirstMean(keep, :);
		decelByStimDeltaLastFirstStd = decelByStimDeltaLastFirstStd(keep, :);
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

	t.('Acceleration Min During Stimulus (cm/s^2)') = accAllMin;
	t.('Acceleration Max During Stimulus (cm/s^2)') = accAllMax;
	t.('Acceleration Mean During Stimulus (cm/s^2)') = accAllMean;
	t.('Acceleration Std During Stimulus (cm/s^2)') = accAllStd;
	t.('Deceleration Min During Stimulus (cm/s^2)') = decelAllMin;
	t.('Deceleration Max During Stimulus (cm/s^2)') = decelAllMax;
	t.('Deceleration Mean During Stimulus (cm/s^2)') = decelAllMean;
	t.('Deceleration Std During Stimulus (cm/s^2)') = decelAllStd;

	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		t.(sprintf('Acceleration Min During %s (cm/s^2)', stimLabel)) = accByStimMin(:, g);
		t.(sprintf('Acceleration Max During %s (cm/s^2)', stimLabel)) = accByStimMax(:, g);
		t.(sprintf('Acceleration Mean During %s (cm/s^2)', stimLabel)) = accByStimMean(:, g);
		t.(sprintf('Acceleration Std During %s (cm/s^2)', stimLabel)) = accByStimStd(:, g);
		t.(sprintf('Deceleration Min During %s (cm/s^2)', stimLabel)) = decelByStimMin(:, g);
		t.(sprintf('Deceleration Max During %s (cm/s^2)', stimLabel)) = decelByStimMax(:, g);
		t.(sprintf('Deceleration Mean During %s (cm/s^2)', stimLabel)) = decelByStimMean(:, g);
		t.(sprintf('Deceleration Std During %s (cm/s^2)', stimLabel)) = decelByStimStd(:, g);
		t.(sprintf('Acceleration Min During First %s Bout (cm/s^2)', stimLabel)) = accByStimFirstBoutMin(:, g);
		t.(sprintf('Acceleration Max During First %s Bout (cm/s^2)', stimLabel)) = accByStimFirstBoutMax(:, g);
		t.(sprintf('Acceleration Mean During First %s Bout (cm/s^2)', stimLabel)) = accByStimFirstBoutMean(:, g);
		t.(sprintf('Acceleration Std During First %s Bout (cm/s^2)', stimLabel)) = accByStimFirstBoutStd(:, g);
		t.(sprintf('Deceleration Min During First %s Bout (cm/s^2)', stimLabel)) = decelByStimFirstBoutMin(:, g);
		t.(sprintf('Deceleration Max During First %s Bout (cm/s^2)', stimLabel)) = decelByStimFirstBoutMax(:, g);
		t.(sprintf('Deceleration Mean During First %s Bout (cm/s^2)', stimLabel)) = decelByStimFirstBoutMean(:, g);
		t.(sprintf('Deceleration Std During First %s Bout (cm/s^2)', stimLabel)) = decelByStimFirstBoutStd(:, g);
		t.(sprintf('Acceleration Min During Last %s Bout (cm/s^2)', stimLabel)) = accByStimLastBoutMin(:, g);
		t.(sprintf('Acceleration Max During Last %s Bout (cm/s^2)', stimLabel)) = accByStimLastBoutMax(:, g);
		t.(sprintf('Acceleration Mean During Last %s Bout (cm/s^2)', stimLabel)) = accByStimLastBoutMean(:, g);
		t.(sprintf('Acceleration Std During Last %s Bout (cm/s^2)', stimLabel)) = accByStimLastBoutStd(:, g);
		t.(sprintf('Deceleration Min During Last %s Bout (cm/s^2)', stimLabel)) = decelByStimLastBoutMin(:, g);
		t.(sprintf('Deceleration Max During Last %s Bout (cm/s^2)', stimLabel)) = decelByStimLastBoutMax(:, g);
		t.(sprintf('Deceleration Mean During Last %s Bout (cm/s^2)', stimLabel)) = decelByStimLastBoutMean(:, g);
		t.(sprintf('Deceleration Std During Last %s Bout (cm/s^2)', stimLabel)) = decelByStimLastBoutStd(:, g);
		t.(sprintf('Acceleration Min Last-First During %s Bouts (cm/s^2)', stimLabel)) = accByStimDeltaLastFirstMin(:, g);
		t.(sprintf('Acceleration Max Last-First During %s Bouts (cm/s^2)', stimLabel)) = accByStimDeltaLastFirstMax(:, g);
		t.(sprintf('Acceleration Mean Last-First During %s Bouts (cm/s^2)', stimLabel)) = accByStimDeltaLastFirstMean(:, g);
		t.(sprintf('Acceleration Std Last-First During %s Bouts (cm/s^2)', stimLabel)) = accByStimDeltaLastFirstStd(:, g);
		t.(sprintf('Deceleration Min Last-First During %s Bouts (cm/s^2)', stimLabel)) = decelByStimDeltaLastFirstMin(:, g);
		t.(sprintf('Deceleration Max Last-First During %s Bouts (cm/s^2)', stimLabel)) = decelByStimDeltaLastFirstMax(:, g);
		t.(sprintf('Deceleration Mean Last-First During %s Bouts (cm/s^2)', stimLabel)) = decelByStimDeltaLastFirstMean(:, g);
		t.(sprintf('Deceleration Std Last-First During %s Bouts (cm/s^2)', stimLabel)) = decelByStimDeltaLastFirstStd(:, g);
	end
end


function [instAcc, accMask] = instantaneousAcceleration(x, y, t, pointMask)
	if isempty(x) || isempty(y) || isempty(t)
		instAcc = nan(0, 1);
		accMask = false(0, 1);
		return;
	end

	if numel(pointMask) ~= numel(t)
		pointMask = false(size(t));
	end

	dx = diff(x);
	dy = diff(y);
	dt = diff(t);
	stepDist = sqrt(dx.^2 + dy.^2);
	instSpeed = stepDist ./ dt;

	if numel(instSpeed) < 2
		instAcc = nan(0, 1);
		accMask = false(0, 1);
		return;
	end

	segCenterTime = (t(1:end-1) + t(2:end)) / 2;
	dCenter = diff(segCenterTime);
	instAcc = diff(instSpeed) ./ dCenter;

	accMask = pointMask(1:end-2) & pointMask(2:end-1) & pointMask(3:end) & ...
		isfinite(dCenter) & (dCenter > 0) & isfinite(instSpeed(1:end-1)) & isfinite(instSpeed(2:end));
end


function [vmin, vmax, vmean, vstd] = maskedStats(values, mask)
	vmin = NaN;
	vmax = NaN;
	vmean = NaN;
	vstd = NaN;

	if isempty(values) || isempty(mask) || numel(values) ~= numel(mask)
		return;
	end

	valid = mask & isfinite(values);
	if ~any(valid)
		return;
	end

	vals = values(valid);
	vmin = min(vals, [], 'omitnan');
	vmax = max(vals, [], 'omitnan');
	vmean = mean(vals, 'omitnan');
	vstd = std(vals, 0, 'omitnan');
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
	if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
		labels = string(overrideSpec{tableIdx});
	else
		labels = string(overrideSpec);
	end
	labels = labels(:);
end
