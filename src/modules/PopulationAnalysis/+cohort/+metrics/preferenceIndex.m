function t = preferenceIndex(standardizedTables, kvargs)
	%%PREFERENCEINDEX Cohort summary of stimuliSorted(1)-signed preference index.
	% Uses 'Arena Grid Score', which is signed positive toward stimuliSorted(1)
	% and negative toward stimuliSorted(2). Reports mean score during all
	% active stimulus periods and during each stimulus-specific active period.

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
	prefAllCol = nan(nRowsEstimate, 1);
	prefByStimCols = nan(nRowsEstimate, nOutputStims);
	prefByStimFirstBoutCols = nan(nRowsEstimate, nOutputStims);
	prefByStimLastBoutCols = nan(nRowsEstimate, nOutputStims);
	prefByStimDeltaLastFirstCols = nan(nRowsEstimate, nOutputStims);

	rowIdx = 0;
	for i = 1:length(standardizedTables)
		stdTable = standardizedTables(i);
		cp = stdTable.centerpointData;

		stimSequence = string(cp{:, 'Stimulus name'});
		arenaGridData = cp{:, 'Arena Grid Score'};
		nAnimals = size(arenaGridData, 2);

		localStimNames = string(stdTable.stimuliSorted);
		localStimNames = localStimNames(:);

		allStimMask = cohort.metrics.utils.periodMaskAllStim(stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI);
		stimMasks = cell(numel(localStimNames), 1);
		for s = 1:numel(localStimNames)
			stimMasks{s} = cohort.metrics.utils.periodMaskForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
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

			thisPref = arenaGridData(:, col);
			prefAllCol(rowIdx) = meanWithinMask(thisPref, allStimMask);

			localStimMeans = nan(numel(localStimNames), 1);
			localStimFirstBoutMeans = nan(numel(localStimNames), 1);
			localStimLastBoutMeans = nan(numel(localStimNames), 1);
			for s = 1:numel(localStimNames)
				localStimMeans(s) = meanWithinMask(thisPref, stimMasks{s});
				thisBoutMasks = stimBoutMasks{s};
				if ~isempty(thisBoutMasks)
					localStimFirstBoutMeans(s) = meanWithinMask(thisPref, thisBoutMasks{1});
					localStimLastBoutMeans(s) = meanWithinMask(thisPref, thisBoutMasks{end});
				end
			end

			for g = 1:nOutputStims
				prefByStimCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimMeans, localIdxByOutputStim(g));
				prefByStimFirstBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimFirstBoutMeans, localIdxByOutputStim(g));
				prefByStimLastBoutCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimLastBoutMeans, localIdxByOutputStim(g));
				prefByStimDeltaLastFirstCols(rowIdx, g) = prefByStimLastBoutCols(rowIdx, g) - prefByStimFirstBoutCols(rowIdx, g);
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
		prefAllCol = prefAllCol(keep);
		prefByStimCols = prefByStimCols(keep, :);
		prefByStimFirstBoutCols = prefByStimFirstBoutCols(keep, :);
		prefByStimLastBoutCols = prefByStimLastBoutCols(keep, :);
		prefByStimDeltaLastFirstCols = prefByStimDeltaLastFirstCols(keep, :);
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

	if nOutputStims >= 1
		stim1DisplayLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(1), 1);
	else
		stim1DisplayLabel = 'StimuliSorted(1)';
	end

	t.(sprintf('%s Preference Index During Active Stimulus', stim1DisplayLabel)) = prefAllCol;
	for g = 1:nOutputStims
		stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
		t.(sprintf('%s Preference Index During %s', stim1DisplayLabel, stimLabel)) = prefByStimCols(:, g);
		t.(sprintf('%s Preference Index During First %s Bout', stim1DisplayLabel, stimLabel)) = prefByStimFirstBoutCols(:, g);
		t.(sprintf('%s Preference Index During Last %s Bout', stim1DisplayLabel, stimLabel)) = prefByStimLastBoutCols(:, g);
		t.(sprintf('%s Preference Index Last-First During %s Bouts', stim1DisplayLabel, stimLabel)) = prefByStimDeltaLastFirstCols(:, g);
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


function vmean = meanWithinMask(values, pointMask)
	vmean = NaN;
	if isempty(values) || isempty(pointMask)
		return;
	end

	values = values(:);
	pointMask = pointMask(:);
	if numel(values) ~= numel(pointMask)
		return;
	end

	valid = pointMask & isfinite(values);
	if ~any(valid)
		return;
	end

	vmean = mean(values(valid), 'omitnan');
end
