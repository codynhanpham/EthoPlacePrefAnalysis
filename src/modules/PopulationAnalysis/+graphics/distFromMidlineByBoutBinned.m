function f = distFromMidlineByBoutBinned(standardizedTable, kvargs)
    %%DISTFROMMIDLINEBYBOUTBINNED Plot distance from midline by bout bin as mean +/- SEM lines with jittered scatter
    %
    %   For each bout, computes the mean 'Distance from Midline' across all frames in that bout.
    %   A bout is defined as a contiguous sequence from a stimulus onset up to the next stimulus onset
    %   in the same stimset (i.e., stim duration + post-stim ISI). Bouts are then grouped into bins
    %   of BinWidth bouts each and displayed as stacked lines (stimulus by line style, sex by color)
    %   with SEM shading, plus jittered scatter points showing per-animal bin means.
    %
    %   The Y-axis is signed such that positive = toward the bout's currently active stimulus (whichever
    %   stimulus in the set is playing), and negative = away from the active stimulus (toward the opposite side).
    %   Stimulus identity is shown by line style, sex by color.
    %
    %   f = graphics.distFromMidlineByBoutBinned(standardizedTable, kvargs)
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
    %   See also: population.stats.populationPositionOverTime, graphics.stateMetricsByBoutBinned, graphics.distFromMidlineByTimeBinned, graphics.cumulativeDisplacementByBout

    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1 % number of bouts per bin
        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.SameYLim (1,1) logical = true % whether to harmonize y-limits across all subplots for direct comparability
        kvargs.YLim double {validateYLim} = [] % manual y-limits [min, max]; empty = auto
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

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Distance From Midline By Bout (Bin Width: %d bouts)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        stimPeriodTable = thisStdTable.centerpointData;

        if ~ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
            error('distFromMidlineByBoutBinned:missingDistanceFromMidline', ...
                'centerpointData for stimset [%s] does not contain ''Distance from Midline''.', ...
                strjoin(thisStimSet, '/'));
        end

        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Trial time', 'Stimulus name', 'Distance from Midline'}));
        stimSequence = stimPeriodTable{:, 'Stimulus name'};
        distanceFromMidlineMatrix = stimPeriodTable{:, 'Distance from Midline'}; % time x nAnimals
        if isempty(distanceFromMidlineMatrix) || all(isnan(distanceFromMidlineMatrix), 'all')
            error('distFromMidlineByBoutBinned:allDistanceFromMidlineNaN', ...
                'Distance from Midline for stimset [%s] is empty or entirely NaN.', ...
                strjoin(thisStimSet, '/'));
        end
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

        % Normalize each replicate to (-1,1) — same as distFromMidlineByTimeBinned
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

        % Collect all stim start indices across the entire stimset.
        % Used to define bout end boundaries: a bout ends just before the next stim onset in the set.
        allStimStartsInSet = [];
        for stimIdx = 1:length(thisStimSet)
            isStim = endsWith(stimSequence, thisStimSet{stimIdx});
            allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
        end
        allStimStartsInSet = sort(allStimStartsInSet);

        % Compute bout [startIdx, endIdx] and direction sign for each stimulus in the set
        % Sign convention (see cumulativeDisplacementByBout for reference):
        %   - stimuliSorted{1} is on the negative side of midline, stimuliSorted{2} on the positive side
        %   - For stim{1} (active on negative side): flip sign so that negative distance → positive (toward active stim)
        %   - For stim{2} (active on positive side): keep sign so that positive distance → positive (toward active stim)
        %   Result: positive Y always = toward the currently active stimulus, negative Y = away from it
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

            % Direction sign: positive = toward active stimulus
            % stimIdx==1 => active stim on negative side => flip sign (neg*neg=pos)
            % stimIdx==2 => active stim on positive side => keep sign (pos*pos=pos)
            if stimIdx == 1
                directionSign = -1; % flip so that negative distance → positive (toward stim{1})
            else
                directionSign = +1; % keep so that positive distance → positive (toward stim{2})
            end

            stimsBouts(stimName) = struct(...
                'nBouts', nBouts, ...
                'boutStartIdx', boutStartIdx, ...
                'boutEndIdx', boutEndIdx, ...
                'nBins', nBins, ...
                'binLabels', {binLabels}, ...
                'directionSign', directionSign ...
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

                % Store per-bin per-animal means for scatter, keyed by composite key "stimName:sex"
                scatterData = struct();
                scatterKeys = {};

                lineStyles = {'-', '-.', '--', ':'};
                lineHandles = [];
                lineLabels = {};

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
                        dirSign = boutInfo.directionSign;

                        if nBouts == 0
                            continue;
                        end

                        % Compute per-bout mean distance per animal (excluding NaN): nBouts x nAnimals
                        % Apply direction sign so positive = toward active stimulus
                        perBoutMean = NaN(nBouts, sum(combinedMask));
                        for boutIdx = 1:nBouts
                            boutData = animalDistances(boutStartIdx(boutIdx):boutEndIdx(boutIdx), :);
                            perBoutMean(boutIdx, :) = dirSign * mean(boutData, 1, 'omitnan');
                        end

                        % Bin the per-bout means
                        meanByBin = NaN(nBins, 1);
                        semByBin = NaN(nBins, 1);
                        nByBin = zeros(nBins, 1);
                        xNumeric = NaN(nBins, 1);

                        % Store per-bin per-animal means for scatter
                        animalMeansByBin = cell(nBins, 1);

                        for binIdx = 1:nBins
                            bStart = (binIdx - 1) * kvargs.BinWidth + 1;
                            bEnd = min(binIdx * kvargs.BinWidth, nBouts);
                            binMeans = mean(perBoutMean(bStart:bEnd, :), 1, 'omitnan'); % 1 x nAnimals
                            validVals = binMeans(~isnan(binMeans));

                            animalMeansByBin{binIdx} = validVals;

                            nByBin(binIdx) = numel(validVals);
                            if ~isempty(validVals)
                                meanByBin(binIdx) = mean(validVals, 'omitnan');
                                semByBin(binIdx) = std(validVals, 0, 'omitnan') / sqrt(numel(validVals));
                            end

                            xNumeric(binIdx) = find(strcmp(orderedXLabels, binLabels{binIdx}), 1);
                        end

                        % Store scatter data
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        scatterKeys{end+1} = compositeKey; %#ok<AGROW>
                        scatterData.(matlab.lang.makeValidName(compositeKey)) = struct(...
                            'xNumeric', xNumeric, ...
                            'animalMeansByBin', {animalMeansByBin} ...
                        );

                        % Plot line + SEM shading
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

                        lineStyle = lineStyles{mod(stimIdx - 1, numel(lineStyles)) + 1};
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

                % --- Add jittered scatter for per-animal bin means ---
                % Each composite key gets its own jitter offset so scatter clouds don't overlap vertically
                if kvargs.ShowDataPoints && ~isempty(scatterKeys)
                    nScatterGroups = length(scatterKeys);
                    jitterWidth = 0.15; % half-width of jitter range
                    % Offset each group so they fan out horizontally around the x-tick
                    totalSpan = jitterWidth * 2; % total horizontal spread
                    groupOffsets = linspace(-totalSpan/2, totalSpan/2, max(nScatterGroups, 1));

                    for scIdx = 1:nScatterGroups
                        cKey = scatterKeys{scIdx};
                        vname = matlab.lang.makeValidName(cKey);
                        sd = scatterData.(vname);

                        % Parse stimName:sex from composite key
                        parts = strsplit(cKey, ':');
                        scStimName = parts{1};
                        scSex = parts{2};
                        scColor = resolveSexColor(scSex);

                        % Determine marker style based on stimulus
                        stimIdxForScatter = find(strcmp(thisStimSet, scStimName), 1);
                        if isempty(stimIdxForScatter)
                            scMarker = 'o';
                        elseif stimIdxForScatter == 1
                            scMarker = 'o';
                        else
                            scMarker = '^';
                        end

                        for binIdx = 1:length(sd.xNumeric)
                            xc = sd.xNumeric(binIdx);
                            vals = sd.animalMeansByBin{binIdx};
                            if isnan(xc) || isempty(vals)
                                continue;
                            end
                            npts = length(vals);
                            % Jitter around the group offset
                            jitter = groupOffsets(scIdx) + jitterWidth * (2*rand(npts, 1) - 1);
                            scatter(a, xc + jitter, vals, 18, ...
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

                % Annotate Y-axis: positive = toward whichever stimulus is active in the bout
                ylabel(a, sprintf('Distance from Midline\n(Positive = Toward active stimulus;\n\tNegative = Away from active stimulus)'));

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
