function t = midlineCrossingFreq(standardizedTables, kvargs)
	%%MIDLINECROSSINGFREQ Cohort summary of midline crossing counts.
	% Reports the number of midline crossings during any active stimulus period,
	% plus the number of crossings into the side of stimuliSorted(i) while that
	% stimulus is active.

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
	stimAllCrossCol = nan(nRowsEstimate, 1);
	stimCrossCols = nan(nRowsEstimate, nOutputStims);
	stimCrossFirstBoutCols = nan(nRowsEstimate, nOutputStims);
	stimCrossLastBoutCols = nan(nRowsEstimate, nOutputStims);
	stimCrossDeltaLastFirstCols = nan(nRowsEstimate, nOutputStims);

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
			stimAllCrossCol(rowIdx) = countMidlineCrossings(distanceVec, midlineInfo.allStimMask);

			localCrossings = nan(numel(localStimNames), 1);
			localCrossingsFirstBout = nan(numel(localStimNames), 1);
			localCrossingsLastBout = nan(numel(localStimNames), 1);
			for s = 1:numel(localStimNames)
				localCrossings(s) = countCrossingsIntoSide(distanceVec, midlineInfo.stimMasks{s}, sideSignForStimIndex(s));
				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					localCrossingsFirstBout(s) = countCrossingsIntoSide(distanceVec, thisBoutMasks{1}, sideSignForStimIndex(s));
					localCrossingsLastBout(s) = countCrossingsIntoSide(distanceVec, thisBoutMasks{end}, sideSignForStimIndex(s));
				end
			end
			for g = 1:nOutputStims
				stimCrossCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localCrossings, localIdxByOutputStim(g));
				stimCrossFirstBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localCrossingsFirstBout, localIdxByOutputStim(g));
				stimCrossLastBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localCrossingsLastBout, localIdxByOutputStim(g));
				stimCrossDeltaLastFirstCols(rowIdx, g) = stimCrossLastBoutCols(rowIdx, g) - stimCrossFirstBoutCols(rowIdx, g);
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
		stimAllCrossCol = stimAllCrossCol(keep);
		stimCrossCols = stimCrossCols(keep, :);
		stimCrossFirstBoutCols = stimCrossFirstBoutCols(keep, :);
		stimCrossLastBoutCols = stimCrossLastBoutCols(keep, :);
		stimCrossDeltaLastFirstCols = stimCrossDeltaLastFirstCols(keep, :);
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

	t.('Midline Crossings During Active Stimulus (count)') = stimAllCrossCol;
	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		t.(sprintf('Midline Crossings Into %s During Active Stimulus (count)', stimLabel)) = stimCrossCols(:, g);
		t.(sprintf('Midline Crossings Into %s During First Bout (count)', stimLabel)) = stimCrossFirstBoutCols(:, g);
		t.(sprintf('Midline Crossings Into %s During Last Bout (count)', stimLabel)) = stimCrossLastBoutCols(:, g);
		t.(sprintf('Midline Crossings Into %s Last-First Across Bouts (count)', stimLabel)) = stimCrossDeltaLastFirstCols(:, g);
	end
end


function nCrossings = countMidlineCrossings(distanceVec, activeMask)
	if isempty(distanceVec) || isempty(activeMask)
		nCrossings = NaN;
		return;
	end

	distanceVec = distanceVec(:);
	activeMask = activeMask(:) & isfinite(distanceVec);
	if ~any(activeMask)
		nCrossings = NaN;
		return;
	end

	runStarts = find(diff([false; activeMask; false]) == 1);
	runEnds = find(diff([false; activeMask; false]) == -1) - 1;
	nCrossings = 0;

	for r = 1:numel(runStarts)
		segState = sign(distanceVec(runStarts(r):runEnds(r)));
		segState = segState(segState ~= 0);
		if numel(segState) < 2
			continue;
		end
		nCrossings = nCrossings + sum(segState(1:end-1) ~= segState(2:end));
	end
end


function nCrossings = countCrossingsIntoSide(distanceVec, activeMask, targetSide)
	if isempty(distanceVec) || isempty(activeMask)
		nCrossings = NaN;
		return;
	end

	distanceVec = distanceVec(:);
	activeMask = activeMask(:) & isfinite(distanceVec);
	if ~any(activeMask)
		nCrossings = NaN;
		return;
	end

	runStarts = find(diff([false; activeMask; false]) == 1);
	runEnds = find(diff([false; activeMask; false]) == -1) - 1;
	nCrossings = 0;

	for r = 1:numel(runStarts)
		segState = sign(distanceVec(runStarts(r):runEnds(r)));
		segState = segState(segState ~= 0);
		if numel(segState) < 2
			continue;
		end
		nCrossings = nCrossings + sum(segState(1:end-1) ~= targetSide & segState(2:end) == targetSide);
	end
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
