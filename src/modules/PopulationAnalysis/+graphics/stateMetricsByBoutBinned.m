function f = stateMetricsByBoutBinned(standardizedTable, kvargs)
    %%STATEMETRICSBYBUTBINNED Plot state metrics (Arena Grid Score) by bout bin as mean +/- SEM lines
    %
    %   For each bout, computes the mean 'Arena Grid Score' across all frames in that bout.
    %   A bout is defined as a contiguous sequence from a stimulus onset up to the next stimulus onset
    %   in the same stimset (i.e., stim duration + post-stim ISI). Bouts are then grouped into bins
    %   of BinWidth bouts each and displayed as stacked lines (stimulus by line style, sex by color)
    %   with SEM shading.
    %
    %   f = graphics.stateMetricsByBoutBinned(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'BinWidth' : Positive integer specifying the number of bouts per bin. Default is 1 (each bout is its own bin). A bin width of 2 averages every 2 consecutive bouts into a single box.
    %       'Title' : Text scalar for the overall figure title. Default is '' (no title).
    %       'SameYLim' : Logical scalar indicating whether to harmonize y-limits across all subplots for direct comparability. Default is true.
    %       'YLim' : 1x2 double array specifying manual y-limits [min, max]. Default is [] (auto). Overrides SameYLim.
    %       'ShowDataPoints' : Logical scalar indicating whether to overlay jittered scatter of per-animal bin means. Default is true.
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.distFromMidlineByBout, graphics.cumulativeDisplacementByBout

    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1 % number of bouts per bin
        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.YLim double {validateYLim} = [] % manual y-limits [min, max]; empty = auto
        kvargs.SameYLim (1,1) logical = true % whether to harmonize y-limits across all subplots for direct comparability
        kvargs.ShowDataPoints (1,1) logical = true % whether to overlay jittered scatter of per-animal bin means
    end

    kvargs.YLim = validateYLim(kvargs.YLim);

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', 'centerpointData'};
    missing = setdiff(requiredFields, fieldnames(standardizedTable), 'stable');
    if ~isempty(missing)
        error('The provided standardizedTable is missing required fields: { ''%s'' }', strjoin(missing, ''', '''));
    end

    stimSets = {standardizedTable.stimuliSorted};
    nstimsets = length(stimSets);

    animalSexes = cellfun(@(x) {x.values().sex}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalSexes = unique([animalSexes{:}]);
    nsexes = length(animalSexes);


    % Each plot is grouped by StimSet x Strain x Genotype.
    % Within each plot, stimulus is represented by line style and sex by color.
    % Only plot combinations that actually exist in the data.

    % Pre-scan: collect (stimsetIdx, strain, genotype) tuples that have data
    existingCombos = {};
    for si = 1:nstimsets
        thisMeta = standardizedTable(si).animalMetadata;
        theseStrains = {thisMeta.values().strain};
        theseGenotypes = {thisMeta.values().genotype};
        for ai = 1:length(theseStrains)
            existingCombos{end+1} = {si, theseStrains{ai}, theseGenotypes{ai}}; %#ok<AGROW>
        end
    end
    % De-duplicate
    [~, uniqueIdx] = unique(cellfun(@(c) sprintf('%d|%s|%s', c{1}, c{2}, c{3}), existingCombos, 'UniformOutput', false), 'stable');
    existingCombos = existingCombos(uniqueIdx);

    nplots = length(existingCombos);

    NORMAL_LINE_STYLE = {'-'}; % stimuliSorted should place 'normal' stimulus first
    OTHER_LINE_STYLE = {'-.', '--', ':'}; % for additional stimuli, each gets a different non-solid line style
    knownOtherStimLineStyles = configureDictionary('char', 'char'); % Map known non-normal stimulus keywords to specific line styles (e.g., 'inverted' -> '-.', 'white noise' -> '--', etc.)

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("State Metrics By Bout (Bin Width: %d bouts)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        stimPeriodTable = thisStdTable.centerpointData;
        stimPeriodTable = graphics.filterStimulusPeriodRows(stimPeriodTable);

        if ~ismember('Arena Grid Score', stimPeriodTable.Properties.VariableNames)
            error('stateMetricsByBoutBinned:missingArenaGridScore', ...
                'centerpointData for stimset [%s] does not contain ''Arena Grid Score''.', ...
                strjoin(thisStimSet, '/'));
        end

        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Trial time', 'Stimulus name', 'Arena Grid Score'}));
        stimSequence = stimPeriodTable{:, 'Stimulus name'};
        arenaGridScoreMatrix = stimPeriodTable{:, 'Arena Grid Score'}; % time x nAnimals
        if isempty(arenaGridScoreMatrix) || all(isnan(arenaGridScoreMatrix), 'all')
            error('stateMetricsByBoutBinned:allArenaGridScoreNaN', ...
                'Arena Grid Score for stimset [%s] is empty or entirely NaN.', ...
                strjoin(thisStimSet, '/'));
        end
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

        % Collect all stim start indices across the entire stimset.
        % Used to define bout end boundaries: a bout ends just before the next stim onset in the set.
        allStimStartsInSet = [];
        for stimIdx = 1:length(thisStimSet)
            isStim = endsWith(stimSequence, thisStimSet{stimIdx});
            allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
        end
        allStimStartsInSet = sort(allStimStartsInSet);

        % Compute bout [startIdx, endIdx] for each stimulus in the set
        stimsBouts = configureDictionary("char", "struct");
        for stimIdx = 1:length(thisStimSet)
            stimName = thisStimSet{stimIdx};
            isStim = endsWith(stimSequence, stimName);
            boutStartIdx = find(diff([0; isStim]) == 1);
            nBouts = length(boutStartIdx);

            boutEndIdx = zeros(nBouts, 1);
            for boutIdx = 1:nBouts
                % Bout ends just before the next stim onset in the stimset (any stim, including self)
                nextStarts = allStimStartsInSet(allStimStartsInSet > boutStartIdx(boutIdx));
                if isempty(nextStarts)
                    boutEndIdx(boutIdx) = size(stimSequence, 1);
                else
                    boutEndIdx(boutIdx) = nextStarts(1) - 1;
                end
            end

            % Pre-compute bin labels (x-axis labels as % of session)
            nBins = ceil(nBouts / kvargs.BinWidth);
            binLabels = cell(nBins, 1);
            for binIdx = 1:nBins
                bStart = (binIdx - 1) * kvargs.BinWidth + 1;
                bEnd = min(binIdx * kvargs.BinWidth, nBouts);
                binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bStart - 1) / nBouts * 100, bEnd / nBouts * 100);
            end

            stimsBouts(stimName) = struct(...
                'nBouts', nBouts, ...
                'boutStartIdx', boutStartIdx, ...
                'boutEndIdx', boutEndIdx, ...
                'nBins', nBins, ...
                'binLabels', {binLabels} ...
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

                % Build a consistent x-axis label order across all stimuli in this stimset.
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

                    animalScores = arenaGridScoreMatrix(:, combinedMask); % time x nAnimals
                    lineColor = resolveSexColor(sex);

                    for stimIdx = 1:length(thisStimSet)
                        stimName = thisStimSet{stimIdx};
                        boutInfo = stimsBouts(stimName);
                        nBouts = boutInfo.nBouts;
                        boutStartIdx = boutInfo.boutStartIdx;
                        boutEndIdx = boutInfo.boutEndIdx;
                        nBins = boutInfo.nBins;
                        binLabels = boutInfo.binLabels;

                        if nBouts == 0
                            continue;
                        end

                        % Compute per-bout mean Arena Grid Score per animal (excluding NaN time points): nBouts x nAnimals
                        perBoutMean = NaN(nBouts, sum(combinedMask));
                        for boutIdx = 1:nBouts
                            boutData = animalScores(boutStartIdx(boutIdx):boutEndIdx(boutIdx), :);
                            perBoutMean(boutIdx, :) = mean(boutData, 1, 'omitnan'); % This is the same as sum(stateValue each timepoint in bout)/number of timepoints, but ensure removing NaN from being included
                        end

                        % Sign the score so that POSITIVE always means "toward the active stimulus side"
                        % Arena Grid Score max is already oriented toward stimuliSorted(1).
                        % For stimuliSorted(2) bouts: negate so positive means toward that side.
                        % Of course this does assume the range is symmetric and the midline is actually at zero AND center of arena
                        if stimIdx ~= 1
                            perBoutMean = -perBoutMean;
                        end

                        meanByBin = NaN(nBins, 1);
                        semByBin = NaN(nBins, 1);
                        nByBin = zeros(nBins, 1);
                        xNumeric = NaN(nBins, 1);

                        for binIdx = 1:nBins
                            bStart = (binIdx - 1) * kvargs.BinWidth + 1;
                            bEnd = min(binIdx * kvargs.BinWidth, nBouts);
                            binMeans = mean(perBoutMean(bStart:bEnd, :), 1, 'omitnan'); % 1 x nAnimals
                            validVals = binMeans(~isnan(binMeans));

                            animalMeansByBin{binIdx} = validVals;

                            nByBin(binIdx) = numel(validVals);
                            if ~isempty(validVals)
                                meanByBin(binIdx) = mean(validVals, 'omitnan'); % mean of animal means
                                semByBin(binIdx) = std(validVals, 0, 'omitnan') / sqrt(numel(validVals));
                            end

                            xNumeric(binIdx) = find(strcmp(orderedXLabels, binLabels{binIdx}), 1);
                        end

                        compositeKey = sprintf('%s:%s', stimName, sex);
                        scatterKeys{end+1} = compositeKey; %#ok<AGROW>
                        scatterData.(matlab.lang.makeValidName(compositeKey)) = struct(...
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
                    groupOffsets = linspace(-totalSpan/2, totalSpan/2, max(nScatterGroups, 1));

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
                title(a, sprintf('[%s]\n%s  %s\n(Bin = %d bouts, Mean per Animal)', strjoin(thisStimSet, ' / '), strain, genotype, kvargs.BinWidth), 'Interpreter', 'none');
                xlabel(a, 'Bouts (% of session)');
                ylabel(a, sprintf('State Metric Score\n(Positive = toward active stimulus;\n\tNegative = away from active stimulus)'));
                grid(a, 'on');
        end
    end
    if ~isempty(kvargs.YLim)
        allAxes = findall(t, 'Type', 'Axes');
        if ~isempty(allAxes)
            ylim(allAxes, kvargs.YLim);
        end
    elseif kvargs.SameYLim
        % Harmonize y-limits across all tile axes so subplots are directly comparable.
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

function color = resolveSexColor(sexLabel)
    if strcmpi(sexLabel, 'M') || strcmpi(sexLabel, 'Male')
        color = [0 0.447 0.741];
    elseif strcmpi(sexLabel, 'F') || strcmpi(sexLabel, 'Female')
        color = [0.850 0.325 0.098];
    else
        color = [0.5 0.5 0.5];
    end
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

function marker = resolveStimulusMarker(stimIdx)
    if isempty(stimIdx)
        marker = 'o';
        return;
    end

    markerOptions = {'o', '^', 's', 'd'};
    marker = markerOptions{mod(stimIdx - 1, numel(markerOptions)) + 1};
end