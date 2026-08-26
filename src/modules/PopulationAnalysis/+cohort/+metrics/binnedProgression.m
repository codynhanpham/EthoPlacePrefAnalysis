function t = binnedProgression(standardizedTables, kvargs)
	%%BINNEDPROGRESSION Cohort summary of bout-binned stimulus progression.
	% Reports, for each animal and each stimulus within each stimset, the mean
	% progression score within each time bin (bins group consecutive stimulus
	% bouts). This is the table-export logic of population.temp.plotProgressionInTab
	% extracted into a standalone cohort metric (no plotting).
	%
	%   t = binnedProgression(standardizedTables)
	%   t = binnedProgression(standardizedTables, 'MetricType', 'state', ...)
	%
	%   Inputs:
	%       standardizedTables - A struct array of standardized tables (see
	%           population.stats.populationPositionOverTime). Each table's
	%           centerpointData must contain 'Trial time', 'Stimulus name', and
	%           the metric column. Data columns are per-animal (N x K), NOT the
	%           widened (N x (Ka+Kb)) form produced by joinStdTableByStim.
	%
	%   Name-Value Pair Arguments:
	%       'MetricType'  - 'distance' (default) or 'state'. Selects the metric
	%                       column: 'Distance from Midline' or 'Arena Grid Score'.
	%       'BinWidth'    - Number of consecutive bouts grouped into one time bin
	%                       (default 1).
	%       'MeanWindowFrames' - Number of frames averaged at the start and end of
	%                       each bout to compute per-bout progression (default 15).
	%       'StimuliSortedColumnNameDisplayOverride' - Optional display-name
	%                       override for stimuli (see sdTable.mustBeStimuliSortedDisplayOverride).
	%
	%   Outputs:
	%       t - A table with one row per (animal, stimset, stimulus):
	%           + Common columns: Mouse_ID, Gene, Cage #, Gene_ID, Sex$, Genotype$,
	%             Litter, Toe_ID, DOB, Age, Stimulus Protocol
	%           + Stimulus Name, StimsetIdx, Group (animal strain from metadata)
	%           + Progression: TimeBin_1__{perc_range%}, TimeBin_2__{perc_range%}, ...,
	%             TimeBin_N__{perc_range%} (mean progression within each bin).
	%
	%   See also: population.temp.plotProgressionInTab, cohort.metrics.midlineCrossingFreq

	arguments
		standardizedTables struct {sdTable.mustBeStandardizedTable}
		kvargs.MetricType (1,1) string {mustBeMember(kvargs.MetricType, ["distance", "state"])} = "distance"
		kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 6
		kvargs.MeanWindowFrames (1,1) {mustBePositive, mustBeInteger} = 15
		kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
	end

	if isempty(standardizedTables)
		t = table();
		return;
	end

	switch kvargs.MetricType
		case 'state'
			metricCol = 'Arena Grid Score';
		case 'distance'
			metricCol = 'Distance from Midline';
	end

	hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
	overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);

	% Estimate total rows: sum over tables of (nStims * nAnimals).
	nRowsEstimate = 0;
	for i = 1:numel(standardizedTables)
		nAnimals = size(standardizedTables(i).centerpointData{:, 'X center'}, 2);
		nRowsEstimate = nRowsEstimate + numel(standardizedTables(i).stimuliSorted) * nAnimals;
	end

	[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);
	expStimulusName = strings(nRowsEstimate, 1);
	expStimsetIdx = zeros(nRowsEstimate, 1);
	expGroup = strings(nRowsEstimate, 1);
	expBinValues = cell(nRowsEstimate, 1);
	expBinLabels = cell(nRowsEstimate, 1);
	expRowIdx = 0;

	for stimsetIdx = 1:numel(standardizedTables)
		thisStdTable = standardizedTables(stimsetIdx);
		thisStimSet = string(thisStdTable.stimuliSorted);
		thisStimSet = thisStimSet(:);

		% Prepare centerpointData (drop pre/post-stimulus rows).
		stimPeriodTable = thisStdTable.centerpointData;
		stimPeriodTable = graphics.filterStimulusPeriodRows(stimPeriodTable);

		if ~ismember(metricCol, stimPeriodTable.Properties.VariableNames)
			error('Missing ''%s'' in centerpointData.', metricCol);
		end

		keepVars = {'Trial time', 'Stimulus name', metricCol};
		if strcmp(kvargs.MetricType, 'state') && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
			keepVars = [keepVars, {'Distance from Midline'}];
		end
		stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, keepVars));

		trialTime = stimPeriodTable{:, 'Trial time'};
		stimSequence = stimPeriodTable{:, 'Stimulus name'};
		allMetric = stimPeriodTable{:, metricCol};
		nAnimals = size(allMetric, 2);

		if isempty(allMetric) || all(isnan(allMetric), 'all')
			error('''%s'' for stimset %d is empty or all NaN.', metricCol, stimsetIdx);
		end

		% Normalize distance columns to (-1, 1).
		if strcmp(kvargs.MetricType, 'distance')
			for colIdx = 1:nAnimals
				c = allMetric(:, colIdx);
				mx = max(c, [], 'omitnan'); mn = min(c, [], 'omitnan');
				if mx > 0 && ~isnan(mx); c(c>0) = c(c>0) / mx; end
				if mn < 0 && ~isnan(mn); c(c<0) = c(c<0) / abs(mn); end
				allMetric(:, colIdx) = c;
			end
		end

		% For state: compute Arena Grid Score orientation using Distance from Midline.
		arenaTowardStim1Sign = ones(1, nAnimals);
		if strcmp(kvargs.MetricType, 'state') && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
			allDfm = stimPeriodTable{:, 'Distance from Midline'};
			if size(allDfm, 2) == nAnimals
				for ai = 1:nAnimals
					ags = allMetric(:, ai); dfm = allDfm(:, ai);
					v = isfinite(ags) & isfinite(dfm);
					if nnz(v) >= 3
						c = corr(ags(v), dfm(v));
						if isfinite(c) && c ~= 0
							arenaTowardStim1Sign(ai) = sign(-c);
						end
					end
				end
			end
		end

		% Collect all stimulus starts in this stimset.
		allStimStartsInSet = [];
		for stimIdx = 1:numel(thisStimSet)
			isStim = endsWith(stimSequence, thisStimSet(stimIdx));
			allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
		end
		allStimStartsInSet = sort(allStimStartsInSet);

		% Build bout metadata per stimulus.
		stimsBouts = configureDictionary("char", "struct");
		for stimIdx = 1:numel(thisStimSet)
			stimName = char(thisStimSet(stimIdx));
			isStim = endsWith(stimSequence, stimName);
			boutStartIdx = find(diff([0; isStim]) == 1);
			nBouts = length(boutStartIdx);
			boutEndIdx = zeros(nBouts, 1);
			for boutIdx = 1:nBouts
				nxt = allStimStartsInSet(allStimStartsInSet > boutStartIdx(boutIdx));
				if isempty(nxt)
					boutEndIdx(boutIdx) = size(stimSequence, 1);
				else
					boutEndIdx(boutIdx) = nxt(1) - 1;
				end
			end
			nBins = ceil(nBouts / kvargs.BinWidth);
			binLabels = cell(nBins, 1);
			binMeanTrialTime = NaN(nBins, 1);
			for binIdx = 1:nBins
				bs = (binIdx-1)*kvargs.BinWidth + 1;
				be = min(binIdx*kvargs.BinWidth, nBouts);
				binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bs-1)/nBouts*100, be/nBouts*100);

				thisBoutMeanTimes = NaN(be - bs + 1, 1);
				for localBoutIdx = bs:be
					localIdx = localBoutIdx - bs + 1;
					localStart = boutStartIdx(localBoutIdx);
					localEnd = boutEndIdx(localBoutIdx);
					thisBoutMeanTimes(localIdx) = mean(trialTime(localStart:localEnd), 'omitnan');
				end
				binMeanTrialTime(binIdx) = mean(thisBoutMeanTimes, 'omitnan');
			end
			if strcmp(kvargs.MetricType, 'distance')
				progSign = -1 + 2*(stimIdx > 1); % -1 for stim1, +1 for stim2
			else
				progSign = 1 - 2*(stimIdx > 1);  % +1 for stim1, -1 for stim2
			end
			stimsBouts(stimName) = struct(...
				'nBouts', nBouts, 'boutStartIdx', boutStartIdx, ...
				'boutEndIdx', boutEndIdx, 'nBins', nBins, ...
				'binLabels', {binLabels}, 'binMeanTrialTime', binMeanTrialTime, ...
				'progressionSign', progSign);
		end

		% Local display names for this table (override-aware).
		if hasOverride
			localDisplayNames = localOverrideLabels(overrideSpec, stimsetIdx);
		else
			localDisplayNames = thisStimSet;
		end

		animalKeys = keys(thisStdTable.animalMetadata);

		for stimIdx = 1:numel(thisStimSet)
			stimName = char(thisStimSet(stimIdx));
			bi = stimsBouts(stimName);
			if bi.nBouts == 0; continue; end

			perBoutProgress = NaN(bi.nBouts, nAnimals);
			for boutIdx = 1:bi.nBouts
				sIdx = bi.boutStartIdx(boutIdx);
				eIdx = bi.boutEndIdx(boutIdx);
				swEnd = min(sIdx + kvargs.MeanWindowFrames - 1, size(allMetric, 1));
				sVals = mean(allMetric(sIdx:swEnd, :), 1, 'omitnan');
				ewStart = max(eIdx - kvargs.MeanWindowFrames + 1, 1);
				eVals = mean(allMetric(ewStart:eIdx, :), 1, 'omitnan');
				if strcmp(kvargs.MetricType, 'distance')
					perBoutProgress(boutIdx, :) = bi.progressionSign * (eVals - sVals);
				else
					perBoutProgress(boutIdx, :) = bi.progressionSign .* arenaTowardStim1Sign .* (eVals - sVals);
				end
			end

			animalMeansByBin = cell(bi.nBins, 1);
			for binIdx = 1:bi.nBins
				bs = (binIdx-1)*kvargs.BinWidth + 1;
				be = min(binIdx*kvargs.BinWidth, bi.nBouts);
				bm = mean(perBoutProgress(bs:be, :), 1, 'omitnan');
				vv = bm(~isnan(bm));
				animalMeansByBin{binIdx} = vv;
			end

			for animalIdx = 1:nAnimals
				if animalIdx > numel(animalKeys)
					continue;
				end
				md = thisStdTable.animalMetadata(animalKeys{animalIdx});

				expRowIdx = expRowIdx + 1;
				[mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
					cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, expRowIdx, md, thisStdTable.stimfileName);
				expStimulusName(expRowIdx) = localDisplayNames(stimIdx);
				expStimsetIdx(expRowIdx) = stimsetIdx;
				expGroup(expRowIdx) = string(cohort.metrics.utils.getFieldOr(md, 'strain', ''));
				expBinLabels{expRowIdx} = bi.binLabels;
				animalVals = NaN(bi.nBins, 1);
				for binIdx = 1:bi.nBins
					vv = animalMeansByBin{binIdx};
					if animalIdx <= numel(vv)
						animalVals(binIdx) = vv(animalIdx);
					end
				end
				expBinValues{expRowIdx} = animalVals;
			end
		end
	end

	if expRowIdx < nRowsEstimate
		keep = 1:expRowIdx;
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
		expStimulusName = expStimulusName(keep);
		expStimsetIdx = expStimsetIdx(keep);
		expGroup = expGroup(keep);
		expBinLabels = expBinLabels(keep);
		expBinValues = expBinValues(keep);
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
	t.('Stimulus Name') = expStimulusName;
	t.('StimsetIdx') = expStimsetIdx;
	t.('Group') = expGroup;

	% Determine the maximum number of bins across all rows for column naming.
	maxBins = 0;
	for ri = 1:numel(expBinValues)
		if ~isempty(expBinValues{ri})
			maxBins = max(maxBins, numel(expBinValues{ri}));
		end
	end

	for bi = 1:maxBins
		colVals = NaN(expRowIdx, 1);
		for ri = 1:expRowIdx
			v = expBinValues{ri};
			if ~isempty(v) && bi <= numel(v)
				colVals(ri) = v(bi);
			end
		end
		label = '';
		for ri = 1:expRowIdx
			lbls = expBinLabels{ri};
			if ~isempty(lbls) && bi <= numel(lbls)
				label = lbls{bi};
				break;
			end
		end
		t.(sprintf('TimeBin_%d__%s', bi, label)) = colVals;
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