function t = rateofstay(standardizedTables, kvargs)
	%%RATEOFSTAY Cohort summary of percent time spent on the active stimulus side.
	% Reports the percent of active stimulus time spent on the side of
	% stimuliSorted(i) while that stimulus is active.

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
	stimStayCols = nan(nRowsEstimate, nOutputStims);
	stimStayFirstBoutCols = nan(nRowsEstimate, nOutputStims);
	stimStayLastBoutCols = nan(nRowsEstimate, nOutputStims);
	stimStayDeltaLastFirstCols = nan(nRowsEstimate, nOutputStims);

	rowIdx = 0;
	for i = 1:length(standardizedTables)
		stdTable = standardizedTables(i);
		midlineInfo = cohort.metrics.utils.getMidlineSideInfo(stdTable, StimulusIncludesTrailingISI=kvargs.StimulusIncludesTrailingISI);

		localStimNames = midlineInfo.localStimNames;
		stimBoutMasks = cell(numel(localStimNames), 1);
		for s = 1:numel(localStimNames)
			stimBoutMasks{s} = cohort.metrics.utils.stimBoutMasksForStim(midlineInfo.stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
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
		nAnimals = size(midlineInfo.distanceFromMidline, 2);

		for col = 1:nAnimals
			rowIdx = rowIdx + 1;

			md = struct();
			if col <= numel(animalKeys)
				md = stdTable.animalMetadata(animalKeys{col});
			end

			[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
				cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stdTable.stimfileName);

			distanceVec = midlineInfo.distanceFromMidline(:, col);
			localStayPct = nan(numel(localStimNames), 1);
			localStayPctFirst = nan(numel(localStimNames), 1);
			localStayPctLast = nan(numel(localStimNames), 1);
			for s = 1:numel(localStimNames)
				localStayPct(s) = percentTimeOnSide(distanceVec, midlineInfo.trialTime, midlineInfo.stimMasks{s}, sideSignForStimIndex(s));
				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					localStayPctFirst(s) = percentTimeOnSide(distanceVec, midlineInfo.trialTime, thisBoutMasks{1}, sideSignForStimIndex(s));
					localStayPctLast(s) = percentTimeOnSide(distanceVec, midlineInfo.trialTime, thisBoutMasks{end}, sideSignForStimIndex(s));
				end
			end

			for g = 1:nOutputStims
				stimStayCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStayPct, localIdxByOutputStim(g));
				stimStayFirstBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStayPctFirst, localIdxByOutputStim(g));
				stimStayLastBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStayPctLast, localIdxByOutputStim(g));
				stimStayDeltaLastFirstCols(rowIdx, g) = stimStayLastBoutCols(rowIdx, g) - stimStayFirstBoutCols(rowIdx, g);
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
		stimStayCols = stimStayCols(keep, :);
		stimStayFirstBoutCols = stimStayFirstBoutCols(keep, :);
		stimStayLastBoutCols = stimStayLastBoutCols(keep, :);
		stimStayDeltaLastFirstCols = stimStayDeltaLastFirstCols(keep, :);
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

	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		t.(sprintf('Percent Time on %s Side During Active Stimulus (%%)', stimLabel)) = stimStayCols(:, g);
		t.(sprintf('Percent Time on %s Side During First Bout (%%)', stimLabel)) = stimStayFirstBoutCols(:, g);
		t.(sprintf('Percent Time on %s Side During Last Bout (%%)', stimLabel)) = stimStayLastBoutCols(:, g);
		t.(sprintf('Percent Time on %s Side Last-First Across Bouts (%%)', stimLabel)) = stimStayDeltaLastFirstCols(:, g);
	end
end


function pct = percentTimeOnSide(distanceVec, trialTime, activeMask, targetSide)
	if isempty(distanceVec) || isempty(trialTime) || isempty(activeMask)
		pct = NaN;
		return;
	end

	distanceVec = distanceVec(:);
	trialTime = trialTime(:);
	activeMask = activeMask(:) & isfinite(distanceVec) & isfinite(trialTime);
	if numel(distanceVec) ~= numel(trialTime) || numel(activeMask) ~= numel(trialTime)
		pct = NaN;
		return;
	end

	intervalMask = activeMask(1:end-1) & activeMask(2:end);
	dt = diff(trialTime);
	validIntervals = intervalMask & isfinite(dt) & (dt > 0);
	activeTime = sum(dt(validIntervals), 'omitnan');
	if ~(isfinite(activeTime) && activeTime > 0)
		pct = NaN;
		return;
	end

	state = sign(distanceVec);
	targetIntervals = validIntervals & state(1:end-1) == targetSide & state(2:end) == targetSide;
	targetTime = sum(dt(targetIntervals), 'omitnan');
	pct = 100 * targetTime / activeTime;
end


function sideSign = sideSignForStimIndex(stimIdx)
	if stimIdx == 1
		sideSign = -1;
	else
		sideSign = 1;
	end
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
	if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
		labels = string(overrideSpec{tableIdx});
	else
		labels = string(overrideSpec);
	end
	labels = labels(:);
end
