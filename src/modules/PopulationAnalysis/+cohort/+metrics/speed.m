function t = speed(standardizedTables, kvargs)
	%%SPEED Cohort summary of instantaneous speed statistics
	% Reports min/max/mean/std of point-to-point instantaneous speed (cm/s)
	% during all stimulus periods and during each stimuliSorted(i) period.

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

	speedAllMin = nan(nRowsEstimate, 1);
	speedAllMax = nan(nRowsEstimate, 1);
	speedAllMean = nan(nRowsEstimate, 1);
	speedAllStd = nan(nRowsEstimate, 1);

	speedByStimMin = nan(nRowsEstimate, nOutputStims);
	speedByStimMax = nan(nRowsEstimate, nOutputStims);
	speedByStimMean = nan(nRowsEstimate, nOutputStims);
	speedByStimStd = nan(nRowsEstimate, nOutputStims);

	speedByStimFirstBoutMin = nan(nRowsEstimate, nOutputStims);
	speedByStimFirstBoutMax = nan(nRowsEstimate, nOutputStims);
	speedByStimFirstBoutMean = nan(nRowsEstimate, nOutputStims);
	speedByStimFirstBoutStd = nan(nRowsEstimate, nOutputStims);

	speedByStimLastBoutMin = nan(nRowsEstimate, nOutputStims);
	speedByStimLastBoutMax = nan(nRowsEstimate, nOutputStims);
	speedByStimLastBoutMean = nan(nRowsEstimate, nOutputStims);
	speedByStimLastBoutStd = nan(nRowsEstimate, nOutputStims);

	speedByStimDeltaLastFirstMin = nan(nRowsEstimate, nOutputStims);
	speedByStimDeltaLastFirstMax = nan(nRowsEstimate, nOutputStims);
	speedByStimDeltaLastFirstMean = nan(nRowsEstimate, nOutputStims);
	speedByStimDeltaLastFirstStd = nan(nRowsEstimate, nOutputStims);

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

			[instSpeed, segMaskAll] = instantaneousSpeed(thisX, thisY, trialTime, allStimPointMask);
			[speedAllMin(rowIdx), speedAllMax(rowIdx), speedAllMean(rowIdx), speedAllStd(rowIdx)] = maskedStats(instSpeed, segMaskAll);

			localStimStats = nan(numel(localStimNames), 4);
			localStimFirstBoutStats = nan(numel(localStimNames), 4);
			localStimLastBoutStats = nan(numel(localStimNames), 4);
			for s = 1:numel(localStimNames)
				[instSpeedStim, segMaskStim] = instantaneousSpeed(thisX, thisY, trialTime, stimPointMasks{s});
				[localStimStats(s,1), localStimStats(s,2), localStimStats(s,3), localStimStats(s,4)] = maskedStats(instSpeedStim, segMaskStim);

				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					[instSpeedFirst, segMaskFirst] = instantaneousSpeed(thisX, thisY, trialTime, thisBoutMasks{1});
					[localStimFirstBoutStats(s,1), localStimFirstBoutStats(s,2), localStimFirstBoutStats(s,3), localStimFirstBoutStats(s,4)] = maskedStats(instSpeedFirst, segMaskFirst);

					[instSpeedLast, segMaskLast] = instantaneousSpeed(thisX, thisY, trialTime, thisBoutMasks{end});
					[localStimLastBoutStats(s,1), localStimLastBoutStats(s,2), localStimLastBoutStats(s,3), localStimLastBoutStats(s,4)] = maskedStats(instSpeedLast, segMaskLast);
				end
			end

			for g = 1:nOutputStims
				stats = cohort.metrics.utils.statsByIndex(localStimStats, localIdxByOutputStim(g));
				speedByStimMin(rowIdx, g) = stats(1);
				speedByStimMax(rowIdx, g) = stats(2);
				speedByStimMean(rowIdx, g) = stats(3);
				speedByStimStd(rowIdx, g) = stats(4);

				firstStats = cohort.metrics.utils.statsByIndex(localStimFirstBoutStats, localIdxByOutputStim(g));
				speedByStimFirstBoutMin(rowIdx, g) = firstStats(1);
				speedByStimFirstBoutMax(rowIdx, g) = firstStats(2);
				speedByStimFirstBoutMean(rowIdx, g) = firstStats(3);
				speedByStimFirstBoutStd(rowIdx, g) = firstStats(4);

				lastStats = cohort.metrics.utils.statsByIndex(localStimLastBoutStats, localIdxByOutputStim(g));
				speedByStimLastBoutMin(rowIdx, g) = lastStats(1);
				speedByStimLastBoutMax(rowIdx, g) = lastStats(2);
				speedByStimLastBoutMean(rowIdx, g) = lastStats(3);
				speedByStimLastBoutStd(rowIdx, g) = lastStats(4);

				speedByStimDeltaLastFirstMin(rowIdx, g) = speedByStimLastBoutMin(rowIdx, g) - speedByStimFirstBoutMin(rowIdx, g);
				speedByStimDeltaLastFirstMax(rowIdx, g) = speedByStimLastBoutMax(rowIdx, g) - speedByStimFirstBoutMax(rowIdx, g);
				speedByStimDeltaLastFirstMean(rowIdx, g) = speedByStimLastBoutMean(rowIdx, g) - speedByStimFirstBoutMean(rowIdx, g);
				speedByStimDeltaLastFirstStd(rowIdx, g) = speedByStimLastBoutStd(rowIdx, g) - speedByStimFirstBoutStd(rowIdx, g);
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

		speedAllMin = speedAllMin(keep);
		speedAllMax = speedAllMax(keep);
		speedAllMean = speedAllMean(keep);
		speedAllStd = speedAllStd(keep);
		speedByStimMin = speedByStimMin(keep, :);
		speedByStimMax = speedByStimMax(keep, :);
		speedByStimMean = speedByStimMean(keep, :);
		speedByStimStd = speedByStimStd(keep, :);
		speedByStimFirstBoutMin = speedByStimFirstBoutMin(keep, :);
		speedByStimFirstBoutMax = speedByStimFirstBoutMax(keep, :);
		speedByStimFirstBoutMean = speedByStimFirstBoutMean(keep, :);
		speedByStimFirstBoutStd = speedByStimFirstBoutStd(keep, :);
		speedByStimLastBoutMin = speedByStimLastBoutMin(keep, :);
		speedByStimLastBoutMax = speedByStimLastBoutMax(keep, :);
		speedByStimLastBoutMean = speedByStimLastBoutMean(keep, :);
		speedByStimLastBoutStd = speedByStimLastBoutStd(keep, :);
		speedByStimDeltaLastFirstMin = speedByStimDeltaLastFirstMin(keep, :);
		speedByStimDeltaLastFirstMax = speedByStimDeltaLastFirstMax(keep, :);
		speedByStimDeltaLastFirstMean = speedByStimDeltaLastFirstMean(keep, :);
		speedByStimDeltaLastFirstStd = speedByStimDeltaLastFirstStd(keep, :);
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

	t.('Speed Min During Stimulus (cm/s)') = speedAllMin;
	t.('Speed Max During Stimulus (cm/s)') = speedAllMax;
	t.('Speed Mean During Stimulus (cm/s)') = speedAllMean;
	t.('Speed Std During Stimulus (cm/s)') = speedAllStd;

	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		t.(sprintf('Speed Min During %s (cm/s)', stimLabel)) = speedByStimMin(:, g);
		t.(sprintf('Speed Max During %s (cm/s)', stimLabel)) = speedByStimMax(:, g);
		t.(sprintf('Speed Mean During %s (cm/s)', stimLabel)) = speedByStimMean(:, g);
		t.(sprintf('Speed Std During %s (cm/s)', stimLabel)) = speedByStimStd(:, g);
		t.(sprintf('Speed Min During First %s Bout (cm/s)', stimLabel)) = speedByStimFirstBoutMin(:, g);
		t.(sprintf('Speed Max During First %s Bout (cm/s)', stimLabel)) = speedByStimFirstBoutMax(:, g);
		t.(sprintf('Speed Mean During First %s Bout (cm/s)', stimLabel)) = speedByStimFirstBoutMean(:, g);
		t.(sprintf('Speed Std During First %s Bout (cm/s)', stimLabel)) = speedByStimFirstBoutStd(:, g);
		t.(sprintf('Speed Min During Last %s Bout (cm/s)', stimLabel)) = speedByStimLastBoutMin(:, g);
		t.(sprintf('Speed Max During Last %s Bout (cm/s)', stimLabel)) = speedByStimLastBoutMax(:, g);
		t.(sprintf('Speed Mean During Last %s Bout (cm/s)', stimLabel)) = speedByStimLastBoutMean(:, g);
		t.(sprintf('Speed Std During Last %s Bout (cm/s)', stimLabel)) = speedByStimLastBoutStd(:, g);
		t.(sprintf('Speed Min Last-First During %s Bouts (cm/s)', stimLabel)) = speedByStimDeltaLastFirstMin(:, g);
		t.(sprintf('Speed Max Last-First During %s Bouts (cm/s)', stimLabel)) = speedByStimDeltaLastFirstMax(:, g);
		t.(sprintf('Speed Mean Last-First During %s Bouts (cm/s)', stimLabel)) = speedByStimDeltaLastFirstMean(:, g);
		t.(sprintf('Speed Std Last-First During %s Bouts (cm/s)', stimLabel)) = speedByStimDeltaLastFirstStd(:, g);
	end
end


function [instSpeed, segMask] = instantaneousSpeed(x, y, t, pointMask)
	if isempty(x) || isempty(y) || isempty(t)
		instSpeed = nan(0, 1);
		segMask = false(0, 1);
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
	segMask = pointMask(1:end-1) & pointMask(2:end) & isfinite(dt) & (dt > 0);
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
