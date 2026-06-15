function f = speedOverTime(standardizedTables, kvargs)
	%%SPEEDOVERTIME Plot instantaneous speed over time for each standardized table.
	%
	% Creates one tile per standardized table. Each tile can show per-subject
	% traces plus an optional mean +/- SEM overlay.

	arguments
		standardizedTables struct {sdTable.mustBeStandardizedTable}
		kvargs.Title string = ""
		kvargs.ShowSubjects (1,1) logical = true
		kvargs.ShowMean (1,1) logical = true
		kvargs.ShowSEM (1,1) logical = true
		kvargs.SmoothWindowSec (1,1) double {mustBeNonnegative} = 0
	end

	if isempty(standardizedTables)
		f = figure('Name', 'Speed Over Time', 'NumberTitle', 'off');
		return;
	end

	nTables = numel(standardizedTables);
	ncols = ceil(sqrt(nTables));
	nrows = ceil(nTables / ncols);

	[screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols / nrows);
	[figW, figH] = ui.dynamicFigureSize(videoaspect, 0);
	figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

	f = figure('Name', 'Speed Over Time', 'Position', figPos, 'NumberTitle', 'off');
	t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
	if strlength(kvargs.Title) > 0
		t.Title.String = kvargs.Title;
		t.Title.FontWeight = 'bold';
	end

	for i = 1:nTables
		stdTable = standardizedTables(i);
		cp = stdTable.centerpointData;

		trialTime = cp{:, 'Trial time'};
		xData = cp{:, 'X center'};
		yData = cp{:, 'Y center'};
		stimSequence = string(cp{:, 'Stimulus name'});

		[speedTime, speedMat] = instantaneousSpeedMatrix(xData, yData, trialTime);
		if isempty(speedTime)
			speedTime = nan(0, 1);
			speedMat = nan(0, max(size(xData, 2), 1));
		end

		if kvargs.SmoothWindowSec > 0
			speedMat = smoothBySeconds(speedMat, speedTime, kvargs.SmoothWindowSec);
		end

		a = nexttile(t);
		hold(a, 'on');

		if kvargs.ShowSubjects && ~isempty(speedMat)
			plot(a, speedTime, speedMat, 'Color', [0.55, 0.55, 0.55, 0.35], 'LineWidth', 0.8, 'HandleVisibility', 'off');
		end

		meanHandle = gobjects(0);
		if kvargs.ShowMean && ~isempty(speedMat)
			speedMean = mean(speedMat, 2, 'omitnan');
			nPerTime = sum(isfinite(speedMat), 2);
			speedSEM = std(speedMat, 0, 2, 'omitnan') ./ sqrt(max(nPerTime, 1));
			speedSEM(nPerTime == 0) = NaN;

			if kvargs.ShowSEM
				plotSemPatch(a, speedTime, speedMean, speedSEM, [0.1, 0.1, 0.1], 0.15);
			end
			meanHandle = plot(a, speedTime, speedMean, 'k-', 'LineWidth', 1.8, 'DisplayName', 'Mean speed');
		end

		% Draw stimulus blocks after limits are initialized by line data.
		drawStimulusPatches(a, trialTime, stimSequence, string(stdTable.stimuliSorted));

		if ~isempty(meanHandle) && isgraphics(meanHandle)
			uistack(meanHandle, 'top');
		end

		xlabel(a, 'Time (s)');
		ylabel(a, 'Speed (cm/s)');
		title(a, tileTitle(stdTable));
		grid(a, 'on');
		box(a, 'on');

		if any(isfinite(speedMat), 'all')
			maxY = max(speedMat, [], 'all', 'omitnan');
			if isfinite(maxY) && maxY > 0
				a.YLim = [0, maxY * 1.1];
			end
		end

		if ~isempty(meanHandle) && isgraphics(meanHandle)
			legend(a, 'Location', 'best');
		end

		enableDefaultInteractivity(a);
		axtoolbar(a, {'export', 'pan', 'zoomin', 'zoomout', 'restoreview'});
		hold(a, 'off');
	end
end


function [speedTime, speedMat] = instantaneousSpeedMatrix(xData, yData, trialTime)
	if isempty(trialTime) || numel(trialTime) < 2 || isempty(xData) || isempty(yData)
		speedTime = nan(0, 1);
		speedMat = nan(0, 0);
		return;
	end

	dt = diff(trialTime(:));
	speedTime = trialTime(2:end);

	dx = diff(xData, 1, 1);
	dy = diff(yData, 1, 1);
	dist = sqrt(dx.^2 + dy.^2);

	speedMat = dist ./ dt;
	invalid = ~isfinite(speedMat) | ~isfinite(dt) | (dt <= 0);
	speedMat(invalid) = NaN;
end


function out = smoothBySeconds(values, timeAxis, windowSec)
	out = values;
	if isempty(values) || numel(timeAxis) < 2 || windowSec <= 0
		return;
	end

	dt = median(diff(timeAxis), 'omitnan');
	if ~isfinite(dt) || dt <= 0
		return;
	end

	win = max(1, round(windowSec / dt));
	out = movmean(values, win, 1, 'omitnan');
end


function plotSemPatch(ax, x, y, sem, color, alphaVal)
	valid = isfinite(x) & isfinite(y) & isfinite(sem);
	if ~any(valid)
		return;
	end

	xv = x(valid);
	yv = y(valid);
	sv = sem(valid);
	fillX = [xv(:); flipud(xv(:))];
	fillY = [yv(:) + sv(:); flipud(yv(:) - sv(:))];
	patch(ax, fillX, fillY, color, 'FaceAlpha', alphaVal, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end


function drawStimulusPatches(ax, trialTime, stimSequence, stimuliSorted)
	if isempty(trialTime) || isempty(stimSequence)
		return;
	end

	yLim = ax.YLim;
	if ~all(isfinite(yLim)) || yLim(1) == yLim(2)
		return;
	end

	stims = string(stimSequence);
	uniqueStims = unique(stims(~ismissing(stims)));
	for j = 1:numel(uniqueStims)
		thisStim = uniqueStims(j);
		idx = find(strcmp(stims, thisStim));
		if isempty(idx)
			continue;
		end

		blocks = consecutiveBlocks(idx);
		color = stimColor(thisStim, stimuliSorted);

		for b = 1:size(blocks, 1)
			xStart = trialTime(blocks(b, 1));
			xEnd = trialTime(blocks(b, 2));
			patch(ax, [xStart, xEnd, xEnd, xStart], [yLim(1), yLim(1), yLim(2), yLim(2)], color, ...
				'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');
		end
	end
end


function blocks = consecutiveBlocks(idxs)
	if isempty(idxs)
		blocks = nan(0, 2);
		return;
	end

	blockStart = idxs(1);
	blocks = nan(0, 2);
	for k = 2:numel(idxs)
		if idxs(k) ~= idxs(k - 1) + 1
			blocks(end+1, :) = [blockStart, idxs(k - 1)]; %#ok<AGROW>
			blockStart = idxs(k);
		end
	end
	blocks(end+1, :) = [blockStart, idxs(end)]; %#ok<AGROW>
end


function c = stimColor(stimName, stimuliSorted)
	stimText = normalizeStimLabel(string(stimName));
	sorted = string(stimuliSorted);
	sorted = arrayfun(@normalizeStimLabel, sorted);

	if contains(stimText, ["intro", "outro", "isi"], 'IgnoreCase', true)
		c = [0.5, 0.5, 0.5];
		return;
	end

	idx = find(strcmpi(sorted, stimText), 1, 'first');
	switch idx
		case 1
			c = [0, 0, 1];
		case 2
			c = [1, 0, 0];
		otherwise
			c = [0.5, 0.5, 0.5];
	end
end


function label = normalizeStimLabel(label)
	label = strtrim(string(label));
	if startsWith(label, "[Ch1] ", 'IgnoreCase', true)
		label = extractAfter(label, strlength("[Ch1] "));
	elseif startsWith(label, "[Ch2] ", 'IgnoreCase', true)
		label = extractAfter(label, strlength("[Ch2] "));
	end
	label = strtrim(label);
end


function ttl = tileTitle(stdTable)
	stimFile = "";
	if isfield(stdTable, 'stimfileName')
		stimFile = string(stdTable.stimfileName);
	end

	nSubjects = size(stdTable.centerpointData{:, 'X center'}, 2);
	if strlength(stimFile) > 0
		ttl = sprintf('%s (n=%d)', stimFile, nSubjects);
	else
		ttl = sprintf('n=%d', nSubjects);
	end
end
