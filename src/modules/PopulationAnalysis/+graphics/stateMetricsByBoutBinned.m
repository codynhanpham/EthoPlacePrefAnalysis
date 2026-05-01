function f = stateMetricsByBoutBinned(standardizedTable, kvargs)
    %%STATEMETRICSBYBUTBINNED Plot state metrics (Arena Grid Score) grouped by bout, binned across the session
    %
    %   For each bout, computes the mean 'Arena Grid Score' across all frames in that bout.
    %   A bout is defined as a contiguous sequence from a stimulus onset up to the next stimulus onset
    %   in the same stimset (i.e., stim duration + post-stim ISI). Bouts are then grouped into bins
    %   of BinWidth bouts each and displayed as grouped box-and-whisker plots, with one group of boxes
    %   per bin on the x-axis.
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
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.distFromMidlineByBout, graphics.cumulativeDisplacementByBout

    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1 % number of bouts per bin
        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.SameYLim (1,1) logical = true % whether to harmonize y-limits across all subplots for direct comparability
    end

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', 'centerpointData'};
    missing = setdiff(requiredFields, fieldnames(standardizedTable), 'stable');
    if ~isempty(missing)
        error('The provided standardizedTable is missing required fields: { ''%s'' }', strjoin(missing, ''', '''));
    end

    stimSets = {standardizedTable.stimuliSorted};
    nstimsets = length(stimSets);

    animalStrains = cellfun(@(x) {x.values().strain}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalStrains = unique([animalStrains{:}]);
    nstrains = length(animalStrains);

    animalGenotypes = cellfun(@(x) {x.values().genotype}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalGenotypes = unique([animalGenotypes{:}]);
    ngenotypes = length(animalGenotypes);

    animalSexes = cellfun(@(x) {x.values().sex}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalSexes = unique([animalSexes{:}]);
    nsexes = length(animalSexes);


    % Plot tiles grouped by StimSet x Strain x Genotype.
    % Within each tile, boxes are grouped by bin on the x-axis, and colored by Sex x Stimulus.

    nplots = nstrains * nstimsets * ngenotypes;

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
        for strainIdx = 1:nstrains
            strain = animalStrains{strainIdx};
            strainMask = strcmp(columnByStrainOrder, strain);

            for genotypeIdx = 1:ngenotypes
                genotype = animalGenotypes{genotypeIdx};
                genotypeMask = strcmp(columnByGenotypeOrder, genotype);

                a = nexttile(t);
                hold(a, 'on');

                % Build data arrays for boxchart
                allYData = [];
                allXGroup = {};    % bin label (x-axis position)
                allColorGroup = {}; % "sex stimName" (GroupByColor)
                orderedXLabels = {}; % track x label insertion order for reordercats
                orderedColorGroups = {};

                for stimIdx = 1:length(thisStimSet)
                    stimName = thisStimSet{stimIdx};
                    boutInfo = stimsBouts(stimName);
                    nBouts = boutInfo.nBouts;
                    boutStartIdx = boutInfo.boutStartIdx;
                    boutEndIdx = boutInfo.boutEndIdx;
                    nBins = boutInfo.nBins;
                    binLabels = boutInfo.binLabels;

                    % Track x-label order (first occurrence wins)
                    for binIdx = 1:nBins
                        if ~ismember(binLabels{binIdx}, orderedXLabels)
                            orderedXLabels{end+1} = binLabels{binIdx}; %#ok<AGROW>
                        end
                    end

                    for sexIdx = 1:nsexes
                        sex = animalSexes{sexIdx};
                        sexMask = strcmp(columnBySexOrder, sex);
                        combinedMask = strainMask & genotypeMask & sexMask;
                        if ~any(combinedMask)
                            continue;
                        end

                        animalScores = arenaGridScoreMatrix(:, combinedMask); % time x nAnimals

                        % Compute per-bout mean Arena Grid Score per animal: nBouts x nAnimals
                        perBoutMean = NaN(nBouts, sum(combinedMask));
                        for boutIdx = 1:nBouts
                            boutData = animalScores(boutStartIdx(boutIdx):boutEndIdx(boutIdx), :);
                            perBoutMean(boutIdx, :) = mean(boutData, 1, 'omitnan');
                        end

                        % Aggregate into bins: average bouts within each bin per animal
                        groupLabel = sprintf('%s %s', sex, stimName);
                        if ~ismember(groupLabel, orderedColorGroups)
                            orderedColorGroups{end+1} = groupLabel; %#ok<AGROW>
                        end
                        for binIdx = 1:nBins
                            bStart = (binIdx - 1) * kvargs.BinWidth + 1;
                            bEnd = min(binIdx * kvargs.BinWidth, nBouts);
                            binMeans = mean(perBoutMean(bStart:bEnd, :), 1, 'omitnan'); % 1 x nAnimals
                            nAnimals = numel(binMeans);
                            allYData = [allYData; binMeans(:)]; %#ok<AGROW>
                            allXGroup = [allXGroup; repmat({binLabels{binIdx}}, nAnimals, 1)]; %#ok<AGROW>
                            allColorGroup = [allColorGroup; repmat({groupLabel}, nAnimals, 1)]; %#ok<AGROW>
                        end
                    end
                end

                if ~isempty(allYData)
                    xCat = reordercats(categorical(allXGroup), orderedXLabels);
                    colorCat = categorical(allColorGroup, orderedColorGroups, 'Ordinal', true);
                    bc = boxchart(a, xCat, allYData, 'GroupByColor', colorCat, 'BoxWidth', 0.7, 'MarkerStyle', '.');

                    % Apply sex-based colors and lighten successive stimuli within a stimset.
                    colorCategories = categories(colorCat);
                    for bcIdx = 1:numel(bc)
                        categoryLabel = colorCategories{min(bcIdx, numel(colorCategories))};
                        tokens = strsplit(categoryLabel, ' ');
                        sexLabel = tokens{1};
                        stimLabel = strjoin(tokens(2:end), ' ');
                        stimOrderIdx = find(strcmp(thisStimSet, stimLabel), 1);
                        if isempty(stimOrderIdx)
                            stimOrderIdx = 1;
                        end

                        c = resolveStimSexColor(sexLabel, stimOrderIdx);
                        bc(bcIdx).BoxFaceColor = c;
                        bc(bcIdx).MarkerColor = c;
                        bc(bcIdx).WhiskerLineColor = c;
                    end

                    legend(a, 'Location', 'best', 'Interpreter', 'none');
                end

                yline(a, 0.5, ':k', 'LineWidth', 0.5);
                hold(a, 'off');
                title(a, sprintf('[%s]\n%s  %s\n(Bin = %d bouts, Mean per Animal)', strjoin(thisStimSet, ' / '), strain, genotype, kvargs.BinWidth), 'Interpreter', 'none');
                xlabel(a, 'Bouts (% of session)');
                ylabel(a, 'Arena Grid Score');
                grid(a, 'on');
            end
        end
    end

    if kvargs.SameYLim
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

function color = resolveStimSexColor(sexLabel, stimOrderIdx)
    if strcmpi(sexLabel, 'M') || strcmpi(sexLabel, 'Male')
        baseColor = [0 0.447 0.741];
    elseif strcmpi(sexLabel, 'F') || strcmpi(sexLabel, 'Female')
        baseColor = [0.850 0.325 0.098];
    else
        baseColor = [0.5 0.5 0.5];
    end

    if stimOrderIdx <= 1
        color = baseColor;
        return;
    end

    lightenStep = 0.38;
    maxLighten = 0.9;
    color = lightenColor(baseColor, min(maxLighten, (stimOrderIdx - 1) * lightenStep));
end

function color = lightenColor(baseColor, amount)
    color = baseColor + (1 - baseColor) * amount;
end