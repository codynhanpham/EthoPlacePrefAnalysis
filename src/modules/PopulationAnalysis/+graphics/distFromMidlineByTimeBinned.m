function f = distFromMidlineByTimeBinned(standardizedTable,binSizeSec, kvargs)
    %%DISTANCEFROMMIDLINEBYTIMEBINNED Distance from midline over time, binned by specified bin size in seconds
    %
    %   Inputs:
    %       standardizedTables - struct array of standardized tables, generated via population.stats.populationPositionByStim()
    %       binSizeSec - scalar positive integer specifying the size of time bins in seconds for averaging the distance from midline data. Default is 10 seconds.
    %
    %   Name-Value Pair Arguments:
    %       'MainApp' - handle to the main PlacePrefDataGUI_main app (for additional configs + syncing)
    %
    %   Outputs:
    %       f - handle to the generated figure
    %
    %   See also: population.stats.populationPositionByStim


    arguments
        standardizedTable struct {mustBeNonempty}
        binSizeSec (1,1) {mustBePositive, mustBeInteger} = 10

        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
    end

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', 'centerpointData'};
    % requiredFields = {'stimfileName', 'stimuliSorted', 'centerpointData'}; % !!! OVERRIDE FOR TESTING ONLY !!! THIS WORKS FOR OLD OUTPUT FORMAT WITHOUT ANIMAL METADATA
    missing = setdiff(requiredFields, fieldnames(standardizedTable), 'stable');
    if ~isempty(missing)
        error('The provided standardizedTable is missing required fields: { ''%s'' }', strjoin(missing, ''', '''));
    end

    stimSets = {standardizedTable.stimuliSorted};
    nstims = length(stimSets);

    animalStrains = cellfun(@(x) {x.values().strain}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    % animalStrains = repmat({{'C57BL/6J'}}, 1, nstims); % !!! OVERRIDE FOR TESTING ONLY !!!
    animalStrains = unique([animalStrains{:}]);
    nstrains = length(animalStrains);

    animalGenotypes = cellfun(@(x) {x.values().genotype}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    % animalGenotypes = repmat({{'WT'}}, 1, nstims); % !!! OVERRIDE FOR TESTING ONLY !!!
    animalGenotypes = unique([animalGenotypes{:}]);
    ngenotypes = length(animalGenotypes);

    animalSexes = cellfun(@(x) {x.values().sex}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    % animalSexes = {{'Female', 'Male'}}; % !!! OVERRIDE FOR TESTING ONLY !!!
    animalSexes = unique([animalSexes{:}]);
    nsexes = length(animalSexes);


    % Plot by Stimulus Set and Strain
    % Each plot will contain sexes and genotypes within a strain
    nplots = nstrains * nstims;

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Distance from Midline Binned (Bin Size: %d sec)", binSizeSec), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    plotIdx = 1;

    for stimIdx = 1:nstims
        thisStdTable = standardizedTable(stimIdx);
        stimPeriodTable = thisStdTable.centerpointData;
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Trial time', 'Stimulus name', 'Distance from Midline'} ));
        distanceFromMidlineMatrix = stimPeriodTable{:, 'Distance from Midline'};
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};
        
        % % !!! OVERRIDE !!!! TESTING ONLY!!!!
        % columnByStrainOrder = repmat({'C57BL/6J'}, 1, 10);
        % columnByGenotypeOrder = repmat({'WT'}, 1, 10);
        % columnBySexOrder = [repmat({'Female'}, 1, 5), repmat({'Male'}, 1, 5)];
        % ;;;;;;;;;;
        % % !!! END OVERRIDE !!!!

        for strainIdx = 1:nstrains
            strain = animalStrains{strainIdx};
            strainMask = strcmp(columnByStrainOrder, strain);
            
            a = nexttile(t);
            hold(a, 'on');
            legendEntries = {};
            for genotypeIdx = 1:ngenotypes
                genotype = animalGenotypes{genotypeIdx};
                genotypeMask = strcmp(columnByGenotypeOrder, genotype);
                genotypeSexData = struct();

                for sexIdx = 1:nsexes
                    sex = animalSexes{sexIdx};
                    sexMask = strcmp(columnBySexOrder, sex);
                    combinedMask = strainMask & genotypeMask & sexMask;
                    if ~any(combinedMask)
                        continue;
                    end
                    % Subset the distanceFromMidline data
                    trialTime = stimPeriodTable{:, 'Trial time'};
                    distanceFromMidline = distanceFromMidlineMatrix(:, combinedMask);

                    % Normalize each replicate to (-1,1) where [-1,0] if negative and [0-1] if positive
                    % This is necessary as different trials may use a slightly different arena size, so the max distance from midline may vary
                    for replicateIdx = 1:size(distanceFromMidline, 2)
                        colData = distanceFromMidline(:, replicateIdx);
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
                        distanceFromMidline(:, replicateIdx) = colData;
                    end




                    % Toggle commenting this block to include/exclude neutral zone
                    % Before binning, set all abs(distance) < neutralThreshold to 0 (neutral zone)
                    neutralThreshold = 0.33333; % The hallway is roughly 1/3 of the arena width
                    neutralMask = abs(distanceFromMidline) < neutralThreshold;
                    distanceFromMidline(neutralMask) = NaN;




                    % Bin the data by binSizeSec
                    maxTime = max(trialTime);
                    binEdges = 0:binSizeSec:maxTime;
                    binCenters = binEdges(1:end-1) + binSizeSec/2;
                    binnedDistance = zeros(length(binCenters), 1);
                    binnedSEM = zeros(length(binCenters), 1);
                    binnedReplicates = cell(length(binCenters), 1);

                    for binIdx = 1:length(binCenters)
                        binMask = trialTime >= binEdges(binIdx) & trialTime < binEdges(binIdx+1);
                        if any(binMask)
                            % Get all data points in this bin across all replicates
                            binData = distanceFromMidline(binMask, :);
                            
                            % Calculate mean per replicate first (per animal, within this bin)
                            replicateMeans = mean(binData, 1, 'omitnan');
                            binnedReplicates{binIdx} = replicateMeans;
                            
                            % Calculate mean across replicates (Mean of Means, across animals)
                            binnedDistance(binIdx) = mean(replicateMeans, 'omitnan');
                            
                            % Calculate SEM across replicates
                            currentN = sum(~isnan(replicateMeans));
                            if currentN > 0
                                binnedSEM(binIdx) = std(replicateMeans, 0, 'omitnan') / sqrt(currentN);
                            else
                                binnedSEM(binIdx) = NaN;
                            end
                        else
                            binnedDistance(binIdx) = NaN;
                            binnedSEM(binIdx) = NaN;
                            binnedReplicates{binIdx} = [];
                        end
                    end

                    % Plot shaded SEM area                  
                    % Create polygon points
                    xConf = [binCenters, fliplr(binCenters)];
                    yConf = [binnedDistance + binnedSEM; flipud(binnedDistance - binnedSEM)];
                    
                    % Remove NaNs for filling
                    validFill = ~isnan(xConf) & ~isnan(yConf');
                    xConf = xConf(validFill);
                    yConf = yConf(validFill);
                    
                    if strcmpi(sex, 'male') || strcmpi(sex, 'm')
                        lineColor = 'b';
                    else
                        lineColor = 'r';
                    end  
                    if ~isempty(xConf)
                        fill(a, xConf, yConf, lineColor, 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    end

                    % Plot the binned data
                    if strcmpi(genotype, 'WT') || strcmpi(genotype, 'wildtype')
                        lineStyle = '-';
                    elseif strcmpi(genotype, 'HET') || strcmpi(genotype, 'het')
                        lineStyle = '-.';
                    elseif strcmpi(genotype, 'HOM') || strcmpi(genotype, 'KO') || strcmpi(genotype, 'knockout')
                        lineStyle = '--';
                    else
                        lineStyle = ':';
                    end                    
                    plot(a, binCenters, binnedDistance, 'Color', lineColor, 'LineStyle', lineStyle, 'LineWidth', 1.5);
                    legendEntries{end+1} = sprintf("%s %s %s (n=%d)", strain, genotype, capitalize(sex), sum(combinedMask)); %#ok<AGROW>

                    % Store data for stat test later
                    sData = struct();
                    sData.binCenters = binCenters;
                    sData.binnedReplicates = binnedReplicates;
                    sData.meanByBin = binnedDistance;
                    sData.semByBin = binnedSEM;
                    
                    if strcmpi(sex, 'male') || strcmpi(sex, 'm')
                        key = 'Male';
                    elseif strcmpi(sex, 'female') || strcmpi(sex, 'f')
                        key = 'Female';
                    else
                        key = sex;
                    end
                    genotypeSexData.(key) = sData;
                end

                % Run t-test between Male and Female if both exist
                % For now only t-test between Sexes
                % Need to add Genotypes, at that point mixed effects model would be better
                if isfield(genotypeSexData, 'Male') && isfield(genotypeSexData, 'Female')
                    mD = genotypeSexData.Male;
                    fD = genotypeSexData.Female;
                    
                    nBinsCenter = min(length(mD.binCenters), length(fD.binCenters));
                    coordXCenters = mD.binCenters(1:nBinsCenter);
                    
                    for bIdx = 1:nBinsCenter
                        valsM = mD.binnedReplicates{bIdx};
                        valsF = fD.binnedReplicates{bIdx};
                        
                        % Need at least 2 points for t-test
                        if numel(valsM) >= 2 && numel(valsF) >= 2
                            [~, p] = ttest2(valsM, valsF);
                            
                            if ~isnan(p)
                                if p < 0.05
                                    if p < 0.0001
                                        tStr = 'p<0.0001';
                                    else
                                        tStr = sprintf('p=%.4f', p);
                                    end
                                else
                                    tStr = ''; % OR 'ns'
                                end
                                
                                % Y Position: Higher of the two + SEM, or 0.2
                                yHigh = max([ ...
                                        mD.meanByBin(bIdx) + mD.semByBin(bIdx), ...
                                        fD.meanByBin(bIdx) + fD.semByBin(bIdx), ...
                                        0.2 ...
                                    ], [], 'omitnan');
                                
                                text(a, coordXCenters(bIdx), yHigh + 0.1, tStr, ...
                                    'HorizontalAlignment', 'center', ...
                                    'FontSize', 11);
                            end
                        end
                    end
                end
            end

            yline(a, 0, ':k', 'LineWidth', 0.5);

            hold(a, 'off');
            title(a, sprintf("%s  %s\n(Bin = %ds, Mean±SEM)", strcat('[',strjoin(stimSets{stimIdx}, '/'), '] '), strain, binSizeSec), 'Interpreter', 'none');
            xlabel(a, 'Time (sec)');
            ylabel(a, 'Preference Index');

            % Annotate the stimulus side at -1 and +1:
            % Negative distance is towards stimuliSorted{1}, Positive distance is towards stimuliSorted{2}
            stimNames = stimSets{stimIdx};
            xl = xlim(a);
            xPos = xl(1) + 0.05 * range(xl);

            if numel(stimNames) >= 1
                text(a, xPos, -0.92, stimNames{1}, 'VerticalAlignment', 'bottom', ...
                    'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
            end
            if numel(stimNames) >= 2
                text(a, xPos, 0.92, stimNames{2}, 'VerticalAlignment', 'top', ...
                    'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
            end
            ymax = max(ylim(a)); % just in case Mean + SEM exceeds 1
            ylim(a, [-1, max([ymax, 1])]);
            legend(a, legendEntries, 'Location', 'best', 'Interpreter', 'none');
            plotIdx = plotIdx + 1;

        end
        plotIdx = plotIdx + 1;


    end



end

function output = capitalize(str)
    arguments
        str {mustBeText}
    end
    
    S = string(str);
    S = lower(S);
    
    % Capitalize first letter where applicable
    hasContent = strlength(S) > 0;
    S(hasContent) = upper(extractBetween(S(hasContent), 1, 1)) + extractAfter(S(hasContent), 1);
    
    % Return char if scalar (single string/char vector input), otherwise cellstr
    if isscalar(S)
        output = char(S);
    else
        output = cellstr(S);
    end
end