function plotActivityDurationRelStimInTab(parent, mergedTable, kvargs)
	%%PLOTACTIVITYDURATIONRELSTIMINTAB Plot active-duration in relative-to-onset window across bout bins
	%
	%   plotActivityDurationRelStimInTab(parent, mergedTable)
	%
	%   Renders one tile per stimset. Within each tile, each strain (from the merged
	%   animalMetadata groups) is plotted as a separate set of lines using strainColorMap.
	%
	%   For each stimulus bout, this computes duration spent in active state (seconds)
	%   within window relative to stimulus onset (t=0).
	%
	%   Active/inactive hysteresis thresholds:
	%       Enter active  : speed > ActiveSpeedThreshold for >= ActiveDurationThresholdSeconds
	%       Exit active   : speed < InactiveSpeedThreshold for >= InactiveDurationThresholdSeconds
	%
	%   Name-Value Pair Arguments:
	%       'BinWidth', 'RelativeStimOnsetWindowSeconds',
	%       'ActiveSpeedThreshold', 'ActiveDurationThresholdSeconds',
	%       'InactiveSpeedThreshold', 'InactiveDurationThresholdSeconds',
	%       'SameYLim', 'YLim', 'ShowDataPoints'
	%       RelativeStimOnsetWindowSeconds supports NaN for window end to use
	%       dynamic bout end (next stimulus start - 1), e.g., [0, NaN].

	arguments
		parent (1,1)
		mergedTable struct {mustBeNonempty}

		kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
		kvargs.RelativeStimOnsetWindowSeconds (1,2) double {mustBeWindowSpec} = [-4, 0]
		kvargs.ActiveSpeedThreshold (1,1) double {mustBeNonnegative, mustBeFinite} = 5
		kvargs.ActiveDurationThresholdSeconds (1,1) double {mustBePositive, mustBeFinite} = 1.5
		kvargs.InactiveSpeedThreshold (1,1) double {mustBeNonnegative, mustBeFinite} = 2.5
		kvargs.InactiveDurationThresholdSeconds (1,1) double {mustBePositive, mustBeFinite} = 4
		kvargs.SameYLim (1,1) logical = true
		kvargs.YLim double = []
		kvargs.ShowDataPoints (1,1) logical = true
	end

	stimSets = {mergedTable.stimuliSorted};
	nstimsets = length(stimSets);

	if ~isfield(mergedTable, 'nAnimalsA')
		error('Missing field ''nAnimalsA'' in mergedTable. Ensure mergedTable is from joinStdTableByStim.');
	end

	% Determine group colors from animalMetadata across stimsets.
	metaDict = mergedTable(1).animalMetadata;
	metaVals = metaDict.values();
	nmeta = length(metaVals);
	ncolsA = mergedTable(1).nAnimalsA;
	ncolsB = nmeta - ncolsA;

	if ncolsA < 1
		error('Group A has no animals (nAnimalsA=%d).', ncolsA);
	end

	groupAStrain = string(metaVals(1).strain);
	colorA = graphics.strainColorMap(char(groupAStrain));

	hasGroupBGlobal = ncolsB > 0;
	groupBStrain = "";
	colorB = [0.2 0.2 0.2];
	if hasGroupBGlobal
		groupBStrain = string(metaVals(ncolsA+1).strain);
		colorB = graphics.strainColorMap(char(groupBStrain));
	end

	ncols = min(nstimsets, 2);
	nrows = ceil(nstimsets / ncols);
	t = tiledlayout(parent, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');

	allAxes = gobjects(0);

	NORMAL_LINE_STYLE = {'-'};
	OTHER_LINE_STYLE = {'-.', '--', ':'};
	knownOtherStimLineStyles = configureDictionary('char', 'char');

	for stimsetIdx = 1:nstimsets
		thisStimSet = stimSets{stimsetIdx};
		thisStdTable = mergedTable(stimsetIdx);

		stimPeriodTable = thisStdTable.centerpointData;
		stimPeriodTable = graphics.filterStimulusPeriodRows(stimPeriodTable);

		requiredVars = {'Trial time', 'Stimulus name', 'X center', 'Y center'};
		if ~all(ismember(requiredVars, stimPeriodTable.Properties.VariableNames))
			missing = requiredVars(~ismember(requiredVars, stimPeriodTable.Properties.VariableNames));
			error('Missing required variables in centerpointData: %s', strjoin(missing, ', '));
		end

		trialTime = stimPeriodTable{:, 'Trial time'};
		stimSequence = stimPeriodTable{:, 'Stimulus name'};

		allX = stimPeriodTable{:, 'X center'};
		allY = stimPeriodTable{:, 'Y center'};

		xA = allX(:, 1:ncolsA);
		yA = allY(:, 1:ncolsA);
		xB = allX(:, ncolsA+1:end);
		yB = allY(:, ncolsA+1:end);

		hasGroupB = hasGroupBGlobal && ~isempty(xB) && ~all(isnan(xB), 'all') && ~all(isnan(yB), 'all');

		if isempty(xA) || isempty(yA) || all(isnan(xA), 'all') || all(isnan(yA), 'all')
			error('''X center''/''Y center'' for group A in stimset %d is empty or all NaN.', stimsetIdx);
		end

		dt = median(diff(trialTime), 'omitnan');
		if ~isfinite(dt) || dt <= 0
			error('Could not infer a valid frame interval from ''Trial time'' for stimset %d.', stimsetIdx);
		end
		windowSec = kvargs.RelativeStimOnsetWindowSeconds;
		offsetStart = round(windowSec(1) / dt);
		useDynamicEnd = isnan(windowSec(2));
		if ~useDynamicEnd
			offsetEnd = round(windowSec(2) / dt);
		end

		if useDynamicEnd
			windowLabel = sprintf('[%0.2f, bout-end]', windowSec(1));
		else
			windowLabel = sprintf('[%0.2f, %0.2f]', windowSec(1), windowSec(2));
		end

		% Collect all stimulus starts in this stimset to infer dynamic bout ends
		allStimStartsInSet = [];
		for stimIdx = 1:length(thisStimSet)
			isStim = endsWith(stimSequence, thisStimSet{stimIdx});
			allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
		end
		allStimStartsInSet = sort(allStimStartsInSet);

		% Build bout metadata per stimulus
		stimsBouts = configureDictionary("char", "struct");
		for stimIdx = 1:length(thisStimSet)
			stimName = thisStimSet{stimIdx};
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
			for binIdx = 1:nBins
				bs = (binIdx-1)*kvargs.BinWidth + 1;
				be = min(binIdx*kvargs.BinWidth, nBouts);
				binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bs-1)/nBouts*100, be/nBouts*100);
			end

			stimsBouts(stimName) = struct(...
				'nBouts', nBouts, ...
				'boutStartIdx', boutStartIdx, ...
				'boutEndIdx', boutEndIdx, ...
				'nBins', nBins, ...
				'binLabels', {binLabels});
		end

		a = nexttile(t, stimsetIdx);
		hold(a, 'on');
		allAxes(end+1) = a; %#ok<AGROW>

		orderedXLabels = {};
		for stimIdx = 1:length(thisStimSet)
			bi = stimsBouts(thisStimSet{stimIdx});
			for binIdx = 1:bi.nBins
				if ~ismember(bi.binLabels{binIdx}, orderedXLabels)
					orderedXLabels{end+1} = bi.binLabels{binIdx}; %#ok<AGROW>
				end
			end
		end

		lineHandles = [];
		lineLabels = {};

		scatterData = struct();
		scatterKeys = {};

		groupADisp = char(groupAStrain);
		groups = {{xA, yA, colorA, groupADisp}};
		if hasGroupB
			groupBDisp = char(groupBStrain);
			groups{end+1} = {xB, yB, colorB, groupBDisp};
		end

		for g = 1:length(groups)
			grp = groups{g};
			xMat = grp{1};
			yMat = grp{2};
			grpColor = grp{3};
			grpName = grp{4};

			for stimIdx = 1:length(thisStimSet)
				stimName = thisStimSet{stimIdx};
				bi = stimsBouts(stimName);
				if bi.nBouts == 0
					continue;
				end

				% Per-bout active duration (s) in relative-to-onset window.
				perBoutActiveDuration = NaN(bi.nBouts, size(xMat, 2));
				for boutIdx = 1:bi.nBouts
					sIdx = bi.boutStartIdx(boutIdx);
					winStartIdx = sIdx + offsetStart;
					if useDynamicEnd
						winEndIdx = bi.boutEndIdx(boutIdx);
					else
						winEndIdx = sIdx + offsetEnd;
					end

					if winStartIdx < 1 || winEndIdx > size(xMat, 1) || winEndIdx <= winStartIdx
						continue;
					end

					thisT = trialTime(winStartIdx:winEndIdx);
					for ai = 1:size(xMat, 2)
						segX = xMat(winStartIdx:winEndIdx, ai);
						segY = yMat(winStartIdx:winEndIdx, ai);
						activeDur = computeActiveDurationHysteresis(segX, segY, thisT, ...
							kvargs.ActiveSpeedThreshold, kvargs.ActiveDurationThresholdSeconds, ...
							kvargs.InactiveSpeedThreshold, kvargs.InactiveDurationThresholdSeconds);
						perBoutActiveDuration(boutIdx, ai) = activeDur;
					end
				end

				meanByBin = NaN(bi.nBins, 1);
				semByBin = NaN(bi.nBins, 1);
				nByBin = zeros(bi.nBins, 1);
				xNumeric = NaN(bi.nBins, 1);
				animalMeansByBin = cell(bi.nBins, 1);

				for binIdx = 1:bi.nBins
					bs = (binIdx-1)*kvargs.BinWidth + 1;
					be = min(binIdx*kvargs.BinWidth, bi.nBouts);

					bm = mean(perBoutActiveDuration(bs:be, :), 1, 'omitnan');
					vv = bm(~isnan(bm));
					animalMeansByBin{binIdx} = vv;
					nByBin(binIdx) = numel(vv);

					if ~isempty(vv)
						meanByBin(binIdx) = mean(vv, 'omitnan');
						semByBin(binIdx) = std(vv, 0, 'omitnan') / sqrt(numel(vv));
					end

					xNumeric(binIdx) = find(strcmp(orderedXLabels, bi.binLabels{binIdx}), 1);
				end

				ck = sprintf('%s:%s', stimName, grpName);
				scatterKeys{end+1} = ck; %#ok<AGROW>
				scatterData.(matlab.lang.makeValidName(ck)) = struct(...
					'xNumeric', xNumeric, 'animalMeansByBin', {animalMeansByBin});

				validPlotMask = ~isnan(xNumeric) & ~isnan(meanByBin);
				if ~any(validPlotMask)
					continue;
				end

				xV = xNumeric(validPlotMask);
				yV = meanByBin(validPlotMask);
				sV = semByBin(validPlotMask);
				sV(isnan(sV)) = 0;

				fill(a, [xV; flipud(xV)], [yV+sV; flipud(yV-sV)], ...
					grpColor, 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');

				if stimIdx == 1
					ls = NORMAL_LINE_STYLE{1};
				else
					if isKey(knownOtherStimLineStyles, stimName)
						ls = knownOtherStimLineStyles(stimName);
					else
						idx = length(knownOtherStimLineStyles.keys()) + 1;
						ls = OTHER_LINE_STYLE{mod(idx-1, length(OTHER_LINE_STYLE))+1};
						knownOtherStimLineStyles(stimName) = ls;
					end
				end

				lh = plot(a, xV, yV, 'Color', grpColor, 'LineStyle', ls, ...
					'LineWidth', 2, 'Marker', 'o', 'MarkerFaceColor', grpColor, ...
					'DisplayName', sprintf('%s - %s', stimName, grpName));
				lineHandles = [lineHandles; lh]; %#ok<AGROW>
				lineLabels{end+1} = sprintf('%s - %s (n=%d)', stimName, grpName, max(nByBin)); %#ok<AGROW>
			end
		end

		if kvargs.ShowDataPoints && ~isempty(scatterKeys)
			nSG = length(scatterKeys);
			jw = 0.15;
			off = linspace(-jw, jw, max(nSG, 1));

			for si = 1:nSG
				sd = scatterData.(matlab.lang.makeValidName(scatterKeys{si}));
				pts = strsplit(scatterKeys{si}, ':');
				sStim = pts{1};
				sGrp = pts{2};

				sIdx = find(strcmp(thisStimSet, sStim), 1);
				sMrk = 'o';
				mOpts = {'o', '^', 's', 'd'};
				if ~isempty(sIdx)
					sMrk = mOpts{mod(sIdx-1, numel(mOpts))+1};
				end

				sCol = colorA;
				if hasGroupB && strcmpi(strtrim(sGrp), strtrim(char(groupBStrain)))
					sCol = colorB;
				end

				for bi = 1:length(sd.xNumeric)
					xc = sd.xNumeric(bi);
					vals = sd.animalMeansByBin{bi};
					if isnan(xc) || isempty(vals)
						continue;
					end

					jit = off(si) + jw*(2*rand(numel(vals),1)-1);
					scatter(a, xc+jit, vals(:), 18, 'Marker', sMrk, ...
						'MarkerFaceColor', sCol, 'MarkerEdgeColor', 'none', ...
						'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
				end
			end
		end

		if ~isempty(orderedXLabels)
			xticks(a, 1:numel(orderedXLabels));
			xticklabels(a, orderedXLabels);
			xtickangle(a, 35);
			xlim(a, [0.5, numel(orderedXLabels)+0.5]);
		end

		if ~isempty(lineHandles)
			lgd = legend(a, lineHandles, lineLabels, 'Location', 'best', 'Interpreter', 'none');
			lgd.AutoUpdate = 'off';
		end

		yline(a, 0, ':k', 'LineWidth', 0.5, 'HandleVisibility', 'off');
		hold(a, 'off');

		if hasGroupB
			title(a, sprintf('[%s]\n%s vs %s', strjoin(thisStimSet, ' / '), ...
				char(groupAStrain), char(groupBStrain)), 'Interpreter', 'none');
		else
			title(a, sprintf('[%s]\n%s', strjoin(thisStimSet, ' / '), char(groupAStrain)), 'Interpreter', 'none');
		end
		xlabel(a, 'Bouts (% of session)');
		ylabel(a, sprintf('Active Duration (%s s rel. onset)\n(s)', windowLabel));
		grid(a, 'on');
	end

	% Harmonize y-limits
	if ~isempty(kvargs.YLim)
		if ~isempty(allAxes)
			ylim(allAxes, kvargs.YLim);
		end
	elseif kvargs.SameYLim
		if ~isempty(allAxes)
			ylm = NaN(numel(allAxes), 2);
			for ai = 1:numel(allAxes)
				yl = ylim(allAxes(ai));
				if all(isfinite(yl))
					ylm(ai, :) = yl;
				end
			end
			gmn = min(ylm(:,1), [], 'omitnan');
			gmx = max(ylm(:,2), [], 'omitnan');
			if isfinite(gmn) && isfinite(gmx) && gmx > gmn
				ylim(allAxes, [gmn, gmx]);
			end
		end
	end
end

function activeDuration = computeActiveDurationHysteresis(x, y, t, activeSpeedThresh, activeDurThresh, inactiveSpeedThresh, inactiveDurThresh)
	activeDuration = NaN;
	if numel(t) < 2 || numel(x) ~= numel(t) || numel(y) ~= numel(t)
		return;
	end

	dx = diff(x);
	dy = diff(y);
	dt = diff(t);
	segStart = t(1:end-1);
	segEnd = t(2:end);
	stepDist = sqrt(dx.^2 + dy.^2);
	speed = stepDist ./ dt;
	valid = isfinite(speed) & isfinite(dt) & (dt > 0);

	isActive = false;
	currentActiveStart = NaN;
	aboveRunStart = NaN;
	aboveRunDuration = 0;
	belowRunStart = NaN;
	belowRunDuration = 0;
	activeBouts = nan(0, 2);

	for k = 1:numel(speed)
		if ~valid(k)
			aboveRunStart = NaN;
			aboveRunDuration = 0;
			belowRunStart = NaN;
			belowRunDuration = 0;
			continue;
		end

		segDuration = segEnd(k) - segStart(k);
		if ~(isfinite(segDuration) && segDuration > 0)
			continue;
		end

		if ~isActive
			if speed(k) > activeSpeedThresh
				if isnan(aboveRunStart)
					aboveRunStart = segStart(k);
					aboveRunDuration = 0;
				end
				aboveRunDuration = aboveRunDuration + segDuration;
				if aboveRunDuration >= activeDurThresh
					currentActiveStart = aboveRunStart;
					isActive = true;
					belowRunStart = NaN;
					belowRunDuration = 0;
				end
			else
				aboveRunStart = NaN;
				aboveRunDuration = 0;
			end
		else
			if speed(k) < inactiveSpeedThresh
				if isnan(belowRunStart)
					belowRunStart = segStart(k);
					belowRunDuration = 0;
				end
				belowRunDuration = belowRunDuration + segDuration;
				if belowRunDuration >= inactiveDurThresh
					activeBouts(end+1, :) = [currentActiveStart, belowRunStart]; %#ok<AGROW>
					isActive = false;
					currentActiveStart = NaN;
					aboveRunStart = NaN;
					aboveRunDuration = 0;
					belowRunStart = NaN;
					belowRunDuration = 0;
				end
			else
				belowRunStart = NaN;
				belowRunDuration = 0;
			end
		end
	end

	if isActive && ~isnan(currentActiveStart)
		lastValid = find(valid, 1, 'last');
		if ~isempty(lastValid)
			activeBouts(end+1, :) = [currentActiveStart, segEnd(lastValid)]; %#ok<AGROW>
		end
	end

	if isempty(activeBouts)
		activeDuration = 0;
		return;
	end

	durs = activeBouts(:, 2) - activeBouts(:, 1);
	durs = durs(isfinite(durs) & durs > 0);
	if isempty(durs)
		activeDuration = 0;
	else
		activeDuration = sum(durs, 'omitnan');
	end
end

function mustBeWindowSpec(x)
	if numel(x) ~= 2
		error('RelativeStimOnsetWindowSeconds must be a 1x2 vector.');
	end
	if ~isfinite(x(1))
		error('RelativeStimOnsetWindowSeconds start must be finite (NaN is not allowed for start).');
	end
	if ~(isfinite(x(2)) || isnan(x(2)))
		error('RelativeStimOnsetWindowSeconds end must be finite or NaN.');
	end
	if isfinite(x(2)) && x(2) <= x(1)
		error('When finite, RelativeStimOnsetWindowSeconds must satisfy window(2) > window(1).');
	end
end
