function f = distFromMidlineProgressionByBoutBinned(standardizedTable, kvargs)
	%%DISTFROMMIDLINEPROGRESSIONBYBOUTBINNED Plot distance-from-midline progression by bout bin as mean +/- SEM lines
	%
	%   For each bout and each animal, computes progression as:
	%       progression = signedDistance(boutEnd) - signedDistance(boutStart)
	%
	%   signedDistance is oriented so positive means toward currently active stimulus.
	%   Therefore:
	%       Positive progression = net movement toward active stimulus over bout.
	%       Negative progression = net movement away from active stimulus over bout.
	%
	%   Bouts are grouped into bins of BinWidth stimulus bouts and displayed as stacked lines
	%   (stimulus by line style, sex by color) with SEM shading.
	%
	%   f = graphics.distFromMidlineProgressionByBoutBinned(standardizedTable, kvargs)
	%
	%   Inputs:
	%       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
	%
	%   Name-Value Pair Arguments:
	%       'BinWidth' : Positive integer specifying number of stimulus bouts per bin. Default is 1.
	%		'MeanWindowFrames' : Positive integer number of frames to average at the start and end of each bout for progression calculation. Default is 15 frames (0.5s at 30fps). For onset, this is frames right after stimulus start; for offset, this is frames right before stimulus end. If this is < 1, non-finite, or empty, no averaging is done and single frames at start and end are used.
	%       'Title' : Text scalar for overall figure title. Default is ''.
	%       'SameYLim' : Logical scalar for harmonized y-limits across subplots. Default is true.
	%       'YLim' : 1x2 double array [min, max]. Default is [] (auto). Overrides SameYLim.
	%       'ShowDataPoints' : Logical scalar to overlay jittered per-animal bin means. Default is true.
	%
	%   Outputs:
	%       f : Figure handle of generated plot
	%
	%   See also: graphics.distFromMidlineByBoutBinned, graphics.stateProgressionMetricsByBoutBinned

	arguments
		standardizedTable struct {mustBeNonempty}

		kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
		kvargs.MeanWindowFrames {validateMeanWindowFrames(kvargs.MeanWindowFrames, 15)} = 15
		kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
		kvargs.SameYLim (1,1) logical = true
		kvargs.YLim double {validateYLim} = []
		kvargs.ShowDataPoints (1,1) logical = true
	end

	kvargs.MeanWindowFrames = validateMeanWindowFrames(kvargs.MeanWindowFrames, 15);
	kvargs.YLim = validateYLim(kvargs.YLim);

	requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', ...
        'fps', 'px2cm', 'centerpointData', 'bodyparts'};
	missing = setdiff(requiredFields, fieldnames(standardizedTable), 'stable');
	if ~isempty(missing)
		error('The provided standardizedTable is missing required fields: { ''%s'' }', strjoin(missing, ''', '''));
	end

	stimSets = {standardizedTable.stimuliSorted};
	nstimsets = length(stimSets);

	animalSexes = cellfun(@(x) {x.values().sex}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
	animalSexes = unique([animalSexes{:}]);
	nsexes = length(animalSexes);

	% Each plot grouped by StimSet x Strain x Genotype.
	existingCombos = {};
	for si = 1:nstimsets
		thisMeta = standardizedTable(si).animalMetadata;
		theseStrains = {thisMeta.values().strain};
		theseGenotypes = {thisMeta.values().genotype};
		for ai = 1:length(theseStrains)
			existingCombos{end+1} = {si, theseStrains{ai}, theseGenotypes{ai}}; %#ok<AGROW>
		end
	end
	[~, uniqueIdx] = unique(cellfun(@(c) sprintf('%d|%s|%s', c{1}, c{2}, c{3}), existingCombos, 'UniformOutput', false), 'stable');
	existingCombos = existingCombos(uniqueIdx);

	nplots = length(existingCombos);

	NORMAL_LINE_STYLE = {'-'}; % stimuliSorted should place 'normal' stimulus first
	OTHER_LINE_STYLE = {'-.', '--', ':'}; % for additional stimuli, each gets a different non-solid line style
	knownOtherStimLineStyles = configureDictionary('char', 'char'); % Map known non-normal stimulus keywords to specific line styles (e.g., 'inverted' -> '-.', 'white noise' -> '--', etc.)

	ncols = ceil(sqrt(nplots));
	nrows = ceil(nplots / ncols);

	[screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols / nrows);
	[figW, figH] = ui.dynamicFigureSize(videoaspect, 0);
	figPos = [(screensize(3) - figW) / 2, (screensize(4) - figH) / 2, figW, figH];

	f = figure('Name', sprintf("Distance From Midline Progression By Bout (Bin Width: %d bouts)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
	t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
	t.Title.String = kvargs.Title;
	t.Title.FontWeight = 'bold';

	for stimsetIdx = 1:nstimsets
		thisStimSet = stimSets{stimsetIdx};
		thisStdTable = standardizedTable(stimsetIdx);
		stimPeriodTable = thisStdTable.centerpointData;
		stimPeriodTable = graphics.filterStimulusPeriodRows(stimPeriodTable);

		if ~ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
			error('distFromMidlineProgressionByBoutBinned:missingDistanceFromMidline', ...
				'centerpointData for stimset [%s] does not contain ''Distance from Midline''.', ...
				strjoin(thisStimSet, '/'));
		end

		stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Stimulus name', 'Distance from Midline'}));
		stimSequence = stimPeriodTable{:, 'Stimulus name'};
		distanceFromMidlineMatrix = stimPeriodTable{:, 'Distance from Midline'}; % time x nAnimals
		if isempty(distanceFromMidlineMatrix) || all(isnan(distanceFromMidlineMatrix), 'all')
			error('distFromMidlineProgressionByBoutBinned:allDistanceFromMidlineNaN', ...
				'Distance from Midline for stimset [%s] is empty or entirely NaN.', ...
				strjoin(thisStimSet, '/'));
		end

		columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
		columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
		columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

		% Normalize each replicate to (-1,1) — same convention as distFromMidlineByBoutBinned.
		for replicateIdx = 1:size(distanceFromMidlineMatrix, 2)
			colData = distanceFromMidlineMatrix(:, replicateIdx);
			maxVal = max(colData, [], 'omitnan');
			minVal = min(colData, [], 'omitnan');

			if maxVal > 0 && ~isnan(maxVal)
				posMask = colData > 0;
				colData(posMask) = colData(posMask) / maxVal;
			end

			if minVal < 0 && ~isnan(minVal)
				negMask = colData < 0;
				colData(negMask) = colData(negMask) / abs(minVal);
			end

			distanceFromMidlineMatrix(:, replicateIdx) = colData;
		end

		% Collect all stimulus starts in stimset to define bout boundaries.
		allStimStartsInSet = [];
		for stimIdx = 1:length(thisStimSet)
			isStim = endsWith(stimSequence, thisStimSet{stimIdx});
			allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
		end
		allStimStartsInSet = sort(allStimStartsInSet);

		% Build bout metadata per stimulus.
		stimsBouts = configureDictionary("char", "struct");
		for stimIdx = 1:length(thisStimSet)
			stimName = thisStimSet{stimIdx};
			isStim = endsWith(stimSequence, stimName);
			boutStartIdx = find(diff([0; isStim]) == 1);
			nBouts = length(boutStartIdx);

			boutEndIdx = zeros(nBouts, 1);
			for boutIdx = 1:nBouts
				nextStarts = allStimStartsInSet(allStimStartsInSet > boutStartIdx(boutIdx));
				if isempty(nextStarts)
					boutEndIdx(boutIdx) = size(stimSequence, 1);
				else
					boutEndIdx(boutIdx) = nextStarts(1) - 1;
				end
			end

			nBins = ceil(nBouts / kvargs.BinWidth);
			binLabels = cell(nBins, 1);
			for binIdx = 1:nBins
				bStart = (binIdx - 1) * kvargs.BinWidth + 1;
				bEnd = min(binIdx * kvargs.BinWidth, nBouts);
				binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bStart - 1) / nBouts * 100, bEnd / nBouts * 100);
			end

			% Sign so positive always means toward active stimulus.
			% stim{1} active on negative side => flip sign.
			% stim{2} active on positive side => keep sign.
			if stimIdx == 1
				progressionSign = -1;
			else
				progressionSign = +1;
			end

			stimsBouts(stimName) = struct( ...
				'nBouts', nBouts, ...
				'boutStartIdx', boutStartIdx, ...
				'boutEndIdx', boutEndIdx, ...
				'nBins', nBins, ...
				'binLabels', {binLabels}, ...
				'progressionSign', progressionSign ...
			);
		end

		for comboIdx = 1:length(existingCombos)
			combo = existingCombos{comboIdx};
			if combo{1} ~= stimsetIdx
				continue;
			end
			strain = combo{2};
			genotype = combo{3};

			strainMask = strcmp(columnByStrainOrder, strain);
			genotypeMask = strcmp(columnByGenotypeOrder, genotype);

			a = nexttile(t);
			hold(a, 'on');

			orderedXLabels = {};
			for stimIdx = 1:length(thisStimSet)
				stimName = thisStimSet{stimIdx};
				boutInfo = stimsBouts(stimName);
				for binIdx = 1:boutInfo.nBins
					if ~ismember(boutInfo.binLabels{binIdx}, orderedXLabels)
						orderedXLabels{end+1} = boutInfo.binLabels{binIdx}; %#ok<AGROW>
					end
				end
			end

			lineHandles = [];
			lineLabels = {};
			scatterData = struct();
			scatterKeys = {};

			for sexIdx = 1:nsexes
				sex = animalSexes{sexIdx};
				sexMask = strcmp(columnBySexOrder, sex);
				combinedMask = strainMask & genotypeMask & sexMask;
				if ~any(combinedMask)
					continue;
				end

				animalDistances = distanceFromMidlineMatrix(:, combinedMask); % time x nAnimals
				lineColor = resolveSexColor(sex);

				for stimIdx = 1:length(thisStimSet)
					stimName = thisStimSet{stimIdx};
					boutInfo = stimsBouts(stimName);
					nBouts = boutInfo.nBouts;
					boutStartIdx = boutInfo.boutStartIdx;
					boutEndIdx = boutInfo.boutEndIdx;
					nBins = boutInfo.nBins;
					binLabels = boutInfo.binLabels;
					progressionSign = boutInfo.progressionSign;

					if nBouts == 0
						continue;
					end

					% Per-bout progression: signed(end - start), positive = toward active stimulus.
					% Uses MeanWindowFrames to average frames at start and end of each bout.
					perBoutProgress = NaN(nBouts, sum(combinedMask));
					for boutIdx = 1:nBouts
						startIdx = boutStartIdx(boutIdx);
						endIdx = boutEndIdx(boutIdx);

						% Start window: frames right after stimulus onset
						startWindowEnd = min(startIdx + kvargs.MeanWindowFrames - 1, size(animalDistances, 1));
						startVals = mean(animalDistances(startIdx:startWindowEnd, :), 1, 'omitnan');

						% End window: frames right before stimulus offset
						endWindowStart = max(endIdx - kvargs.MeanWindowFrames + 1, 1);
						endVals = mean(animalDistances(endWindowStart:endIdx, :), 1, 'omitnan');

						perBoutProgress(boutIdx, :) = progressionSign * (endVals - startVals);
					end

					meanByBin = NaN(nBins, 1);
					semByBin = NaN(nBins, 1);
					nByBin = zeros(nBins, 1);
					xNumeric = NaN(nBins, 1);
					animalMeansByBin = cell(nBins, 1);

					for binIdx = 1:nBins
						bStart = (binIdx - 1) * kvargs.BinWidth + 1;
						bEnd = min(binIdx * kvargs.BinWidth, nBouts);
						binMeans = mean(perBoutProgress(bStart:bEnd, :), 1, 'omitnan');
						validVals = binMeans(~isnan(binMeans));

						animalMeansByBin{binIdx} = validVals;

						nByBin(binIdx) = numel(validVals);
						if ~isempty(validVals)
							meanByBin(binIdx) = mean(validVals, 'omitnan');
							semByBin(binIdx) = std(validVals, 0, 'omitnan') / sqrt(numel(validVals));
						end

						xNumeric(binIdx) = find(strcmp(orderedXLabels, binLabels{binIdx}), 1);
					end

					compositeKey = sprintf('%s:%s', stimName, sex);
					scatterKeys{end+1} = compositeKey; %#ok<AGROW>
					scatterData.(matlab.lang.makeValidName(compositeKey)) = struct( ...
						'xNumeric', xNumeric, ...
						'animalMeansByBin', {animalMeansByBin} ...
					);

					validPlotMask = ~isnan(xNumeric) & ~isnan(meanByBin);
					if ~any(validPlotMask)
						continue;
					end

					xVals = xNumeric(validPlotMask);
					yVals = meanByBin(validPlotMask);
					semVals = semByBin(validPlotMask);
					semVals(isnan(semVals)) = 0;

					fill(a, [xVals; flipud(xVals)], ...
						[yVals + semVals; flipud(yVals - semVals)], ...
						lineColor, ...
						'FaceAlpha', 0.10, ...
						'EdgeColor', 'none', ...
						'HandleVisibility', 'off');

					% Determine line style for this stimulus
					if stimIdx == 1
						lineStyle = NORMAL_LINE_STYLE{1};
					else
						assignedStyle = false;
						if isKey(knownOtherStimLineStyles, stimName)
							lineStyle = knownOtherStimLineStyles(stimName);
							assignedStyle = true;
						end
						if ~assignedStyle
							currentKnownOtherStimIndex = length(knownOtherStimLineStyles.keys()) + 1;
							lineStyle = OTHER_LINE_STYLE{mod(currentKnownOtherStimIndex-1, length(OTHER_LINE_STYLE)) + 1};
							knownOtherStimLineStyles(stimName) = lineStyle;
						end
					end
					lineHandle = plot(a, xVals, yVals, ...
						'Color', lineColor, ...
						'LineStyle', lineStyle, ...
						'LineWidth', 2, ...
						'Marker', 'o', ...
						'MarkerFaceColor', lineColor, ...
						'DisplayName', sprintf('%s - %s', stimName, sex));

					lineHandles = [lineHandles; lineHandle]; %#ok<AGROW>
					lineLabels{end+1} = sprintf('%s - %s (n=%d)', stimName, sex, max(nByBin)); %#ok<AGROW>
				end
			end

			if kvargs.ShowDataPoints && ~isempty(scatterKeys)
				nScatterGroups = length(scatterKeys);
				jitterWidth = 0.15;
				totalSpan = jitterWidth * 2;
				groupOffsets = linspace(-totalSpan / 2, totalSpan / 2, max(nScatterGroups, 1));

				for scIdx = 1:nScatterGroups
					cKey = scatterKeys{scIdx};
					sd = scatterData.(matlab.lang.makeValidName(cKey));
					parts = strsplit(cKey, ':');
					scStimName = parts{1};
					scSex = parts{2};
					scColor = resolveSexColor(scSex);
					stimIdxForScatter = find(strcmp(thisStimSet, scStimName), 1);
					scMarker = resolveStimulusMarker(stimIdxForScatter);

					for binIdx = 1:length(sd.xNumeric)
						xc = sd.xNumeric(binIdx);
						vals = sd.animalMeansByBin{binIdx};
						if isnan(xc) || isempty(vals)
							continue;
						end

						jitter = groupOffsets(scIdx) + jitterWidth * (2 * rand(numel(vals), 1) - 1);
						scatter(a, xc + jitter, vals(:), 18, ...
							'Marker', scMarker, ...
							'MarkerFaceColor', scColor, ...
							'MarkerEdgeColor', 'none', ...
							'MarkerFaceAlpha', 0.35, ...
							'HandleVisibility', 'off');
					end
				end
			end

			if ~isempty(orderedXLabels)
				xticks(a, 1:numel(orderedXLabels));
				xticklabels(a, orderedXLabels);
				xtickangle(a, 35);
				xlim(a, [0.5, numel(orderedXLabels) + 0.5]);
			end

			if ~isempty(lineHandles)
				lgd = legend(a, lineHandles, lineLabels, 'Location', 'best', 'Interpreter', 'none');
				lgd.AutoUpdate = 'off';
			end

			yline(a, 0, ':k', 'LineWidth', 0.5, 'HandleVisibility', 'off');
			hold(a, 'off');
			title(a, sprintf('[%s]\n%s  %s\n(Bin = %d bouts, MeanWindowFrames = %d)', strjoin(thisStimSet, ' / '), strain, genotype, kvargs.BinWidth, kvargs.MeanWindowFrames), 'Interpreter', 'none');
			xlabel(a, 'Bouts (% of session)');
			ylabel(a, sprintf('Distance-from-Midline Progression\n(Positive = net moved toward active stimulus;\n\tNegative = net moved away from active stimulus)'));
			grid(a, 'on');
		end
	end

	if ~isempty(kvargs.YLim)
		allAxes = findall(t, 'Type', 'Axes');
		if ~isempty(allAxes)
			ylim(allAxes, kvargs.YLim);
		end
	elseif kvargs.SameYLim
		allAxes = findall(t, 'Type', 'Axes');
		if ~isempty(allAxes)
			yLimMatrix = NaN(numel(allAxes), 2);
			for axIdx = 1:numel(allAxes)
				thisYLim = ylim(allAxes(axIdx));
				if all(isfinite(thisYLim))
					yLimMatrix(axIdx, :) = thisYLim;
				end
			end

			globalYMin = min(yLimMatrix(:, 1), [], 'omitnan');
			globalYMax = max(yLimMatrix(:, 2), [], 'omitnan');
			if isfinite(globalYMin) && isfinite(globalYMax) && globalYMax > globalYMin
				ylim(allAxes, [globalYMin, globalYMax]);
			end
		end
	end
end


function w = validateMeanWindowFrames(x, default)
	if ~isscalar(default)
		error('Default value for MeanWindowFrames must be a scalar.');
	end
	if ~isnumeric(default) || ~isfinite(default) || default < 1 || floor(default) ~= default
		error('Default value for MeanWindowFrames must be a positive integer.');
	end

	if isempty(x)
		w = default;
		return;
	end
	if ~isscalar(x)
		error('MeanWindowFrames must be a scalar.');
	end
	% If x is not finite positive integer, use default and issue warning.
	if ~isnumeric(x) || ~isfinite(x) || x < 1 || floor(x) ~= x
		warning('MeanWindowFrames must be a positive integer. Using default value of %d.', default);
		w = default;
		return;
	end
	w = x;
end


function yLim = validateYLim(yLim)
	if isempty(yLim)
		return;
	end

	if ~(isnumeric(yLim) && isreal(yLim) && numel(yLim) == 2)
		error('YLim must be empty or a numeric 2-element vector [min, max].');
	end

	if ~(isequal(size(yLim), [1, 2]) || isequal(size(yLim), [2, 1]))
		error('YLim must be shape (1,2) or (2,1).');
	end

	yLim = reshape(yLim, 1, 2);
	if ~all(isfinite(yLim))
		error('YLim values must be finite.');
	end
	if yLim(2) <= yLim(1)
		error('YLim upper bound must be greater than lower bound.');
	end
end

function color = resolveSexColor(sexLabel)
	if strcmpi(sexLabel, 'M') || strcmpi(sexLabel, 'Male')
		color = [0 0.447 0.741];
	elseif strcmpi(sexLabel, 'F') || strcmpi(sexLabel, 'Female')
		color = [0.850 0.325 0.098];
	else
		color = [0.5 0.5 0.5];
	end
end

function marker = resolveStimulusMarker(stimIdx)
	if isempty(stimIdx)
		marker = 'o';
		return;
	end

	markerOptions = {'o', '^', 's', 'd'};
	marker = markerOptions{mod(stimIdx - 1, numel(markerOptions)) + 1};
end
