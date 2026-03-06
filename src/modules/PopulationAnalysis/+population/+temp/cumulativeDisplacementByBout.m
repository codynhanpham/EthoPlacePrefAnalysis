function f = cumulativeDisplacementByBout(standardizedTable, kvargs)
    %%CUMULATIVEDISPLACEMENTBYBOUT Plot cumulative distance from midline aligned by bout onset, binned over time
    %
    %   This function accumulates the signed distance from midline over time, aligned to bout onset,
    %   for each bout of stimulus presentation in the provided standardizedTable.
    %   Positive preference (moving toward the active stimulus side) results in positive cumulative distance,
    %   while negative preference (moving away from the active stimulus side) results in negative cumulative distance.
    %
    %   WARNING: What this plot style doesn't show: If the animal is already at the max distance from midline on the stimulus side at bout onset, no further movement toward that side is possible. This accumulation method rewards movement toward the stimulus side, but under-represents cases where the animal is already at the max distance from midline on that side.
    %
    %   f = population.temp.cumulativeDisplacementByBout(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'ResponseWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to analyze. Default is [-1, 6]. This range should cover the full bout duration and ends before the next bout starts.
    %       'BinWidth' : Scalar double specifying the width of time bins (in seconds) for averaging distance data. Default is NaN, which uses the smallest time resolution available. Set to 0 or NaN for no binning, or Inf for one single bin over the whole ResponseWindow.
    %       'BoutRange' : 1x2 double array specifying which bouts to include. Default is [1, Inf] (all bouts). Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts).
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.distFromMidlineByTimeBinned


    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.ResponseWindow (1,2) double = [-1, 6] % in seconds, relative to bout onset
        kvargs.BinWidth (1,1) double = NaN % in seconds, set to 0 or NaN for no binning (use the smallest time resolution available), or Infinity for one single bin over the whole ResponseWindow. BinWidth is clamped to be at most the size of ResponseWindow.
        kvargs.BoutRange (1,2) double = [1, Inf] % which bouts to include. Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts)

        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
    end

    % Make sure response window is valid: end > start
    if kvargs.ResponseWindow(2) <= kvargs.ResponseWindow(1)
        error('Invalid ResponseWindow: End time must be greater than Start time.');
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


    % Each plot will be by Per StimSet x Strain x Genotype
    % Within each plot, the stimulus (within the set) will be represented by line style, and Sex by color within each plot
    % With 2 stimuli per set, there will be 2 line styles (e.g., solid for stim that includes 'normal', dashed for the other stimulus --> 4 lines per plot

    % At the onset of each bout, start tracking the distance of the subject from midline over time
    % Using the current position at bout onset as the zero point (i.e., how the animal displaces from its initial position due to stimulus)
    % Keep track of direction and stimulus type, so that the resulting result: toward the same side as stimulus = positive displacement, away from stimulus = negative displacement
    % (do able as centerpointData "Distance from Midline" is signed, with negative values towards stimuliSorted{1} side, positive values towards stimuliSorted{2} side)
    % For each bout, bin the distance data into time bins of (BinWidth)s, then average + sem across replicates/animals belonging to the same Strain/Genotype/Sex group


    nplots = nstrains * nstimsets * ngenotypes;

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Cumulative Displacement By Bout (Bin Size: %.3f sec)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        stimPeriodTable = thisStdTable.centerpointData;
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Trial time', 'Stimulus name', 'Distance from Midline'} ));
        trialTime = stimPeriodTable{:, 'Trial time'};
        distanceFromMidlineMatrix = stimPeriodTable{:, 'Distance from Midline'};
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

        % Pre-process the stim sequence into bouts for this stim set
        stimSequence = stimPeriodTable{:, 'Stimulus name'};
        stimsBouts = configureDictionary("char", "struct"); % struct with fields 'nBouts', 'startIdx', 'endIdx', 'responseWindowStartIdx', 'responseWindowEndIdx'
        for stimIdx = 1:length(thisStimSet)
            stimName = thisStimSet{stimIdx};
            % Determine where in the stim sequence this stimulus occurs
            % Since the raw audio often includes the [Ch#] channel number, need to match by endsWith
            isStim = endsWith(stimSequence, stimName);

            % Find stimulus start and end indices
            stimStartIdx = find(diff([0; isStim]) == 1);
            stimEndIdx = find(diff([isStim; 0]) == -1);
            nBouts = length(stimStartIdx);
            nBoutsTotal = nBouts; % Save original total for percentage calculation

            % Apply BoutRange filter to select which bouts to include
            % Check if using percentage mode (any float value AND range in [0,1])
            isPercentageMode = (any(mod(kvargs.BoutRange, 1) ~= 0) && all(kvargs.BoutRange >= 0) && all(kvargs.BoutRange <= 1));
            
            if isPercentageMode
                % Convert percentage to bout indices
                boutRangeStart = max(1, round(nBouts * kvargs.BoutRange(1)) + 1); % +1 because percentage 0 should start at bout 1
                if kvargs.BoutRange(1) == 0
                    boutRangeStart = 1; % !!!! 0% means start from bout 1
                end
                boutRangeEnd = min(nBouts, round(nBouts * kvargs.BoutRange(2)));
            else
                % Use direct bout indices
                boutRangeStart = max(1, kvargs.BoutRange(1));
                boutRangeEnd = min(nBouts, kvargs.BoutRange(2));
            end
            
            boutIndicesToInclude = boutRangeStart:boutRangeEnd;
            
            % Filter bout indices based on BoutRange
            stimStartIdx = stimStartIdx(boutIndicesToInclude);
            stimEndIdx = stimEndIdx(boutIndicesToInclude);
            nBouts = length(boutIndicesToInclude); % Update nBouts to reflect filtered count

            % Format the percent range string for titles: start-end %
            startPercent = (boutRangeStart - 1) / nBoutsTotal * 100;
            endPercent = boutRangeEnd / nBoutsTotal * 100;
            percentRangeStr = sprintf('%.1f-%.1f%% = %d reps', startPercent, endPercent, nBouts);

            % The time for each bout response window will be in ref to the start index of that bout == time 0s,
            % Chunk into ResponseWindow by ('Trial time'), which is in seconds
            % Find the closest indices in 'Trial time' to the desired ResponseWindow
            responseWindowStartIdx = zeros(nBouts, 1);
            responseWindowEndIdx = zeros(nBouts, 1);
            for boutIdx = 1:nBouts
                boutStartTime = trialTime(stimStartIdx(boutIdx));
                desiredWindowStartTime = boutStartTime + kvargs.ResponseWindow(1);
                desiredWindowEndTime = boutStartTime + kvargs.ResponseWindow(2);

                % Find closest indices
                [~, responseWindowStartIdx(boutIdx)] = min(abs(trialTime - desiredWindowStartTime));
                [~, responseWindowEndIdx(boutIdx)] = min(abs(trialTime - desiredWindowEndTime));
            end

            stimsBouts(stimName) = struct(...
                'nBouts', nBouts, ...
                'startIdx', stimStartIdx, ...
                'endIdx', stimEndIdx, ...
                'responseWindowStartIdx', responseWindowStartIdx, ...
                'responseWindowEndIdx', responseWindowEndIdx, ...
                'percentRangeStr', percentRangeStr ...
            );
        end


        for strainIdx = 1:nstrains
            strain = animalStrains{strainIdx};
            strainMask = strcmp(columnByStrainOrder, strain);

            for genotypeIdx = 1:ngenotypes
                genotype = animalGenotypes{genotypeIdx};
                genotypeMask = strcmp(columnByGenotypeOrder, genotype);
                genotypeSexData = dictionary(); % Use dictionary to handle stimulus names with spaces

                % One tile per StimSet x Strain x Genotype combination.
                a = nexttile(t);
                hold(a, 'on');

                for sexIdx = 1:nsexes
                    sex = animalSexes{sexIdx};
                    sexMask = strcmp(columnBySexOrder, sex);
                    combinedMask = strainMask & genotypeMask & sexMask;
                    if ~any(combinedMask)
                        continue;
                    end

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


                    % Chunk the data into bouts, then into time bins within each bout, for each stimulus in this stim set
                    for stimIdx = 1:length(stimsBouts.keys()) % Stim bout key order matches thisStimSet order
                        stimName = stimsBouts.keys{stimIdx};
                        boutInfo = stimsBouts(stimName);
                        nBouts = boutInfo.nBouts;
                        refIdx = boutInfo.startIdx; % At this index, distance = 0
                        responseWindowStartIdx = boutInfo.responseWindowStartIdx;
                        responseWindowEndIdx = boutInfo.responseWindowEndIdx;

                        % Determine bin width
                        if isnan(kvargs.BinWidth) || kvargs.BinWidth == 0
                            binWidth = mean(diff(trialTime)); % use the smallest time resolution available
                        elseif isinf(kvargs.BinWidth) || kvargs.BinWidth >= (kvargs.ResponseWindow(2) - kvargs.ResponseWindow(1))
                            binWidth = kvargs.ResponseWindow(2) - kvargs.ResponseWindow(1); % one single bin over the whole ResponseWindow
                        else
                            binWidth = kvargs.BinWidth;
                        end

                        % Create fixed bins centered around time 0 (bout onset), covering the full ResponseWindow
                        nBinsBefore = ceil(abs(kvargs.ResponseWindow(1)) / binWidth);
                        nBinsAfter = ceil(kvargs.ResponseWindow(2) / binWidth);
                        binEdgesRelative = ((-nBinsBefore-0.5):1:(nBinsAfter+0.5)) * binWidth;
                        nBins = length(binEdgesRelative) - 1;
                        binTimeCenters = (binEdgesRelative(1:nBins) + binEdgesRelative(2:nBins+1)) / 2;

                        allBinnedDisplacements = []; % will be nBins x nReplicates x nBouts
                        
                        for boutIdx = 1:nBouts
                            startIdx = responseWindowStartIdx(boutIdx);
                            endIdx = responseWindowEndIdx(boutIdx);
                            boutData = distanceFromMidline(startIdx:endIdx, :); % time x replicates

                            refIdxInBout = refIdx(boutIdx) - startIdx + 1; % index within boutData corresponding to bout onset (time 0s)
                            boutStartTime = trialTime(refIdx(boutIdx)); % absolute time when this bout started

                            % Calculate cumulative displacement as signed absolute differences
                            % Displacement accumulates based on movement direction relative to stimulus
                            % Stimulus side determines cumulation sign: toward active stimulus = positive, away from active stimulus = negative
                            
                            % Initialize cumulative displacement series
                            displacementSeries = zeros(size(boutData));
                            
                            % Calculate cumulative displacement from consecutive differences
                            for timeIdx = 2:size(boutData, 1)
                                prevDistances = boutData(timeIdx - 1, :);
                                currDistances = boutData(timeIdx, :);
                                absDiff = abs(currDistances - prevDistances);
                                
                                % Determine sign based on movement direction relative to stimulus
                                if stimIdx == 1
                                    % Stim1 is on left (negative side), as per stimuliSorted order
                                    % If moving left (current < previous), add to cumulative (toward stimulus)
                                    % If moving right (current > previous), subtract from cumulative (away from stimulus)
                                    directionSign = ones(size(absDiff));
                                    directionSign(currDistances > prevDistances) = -1;
                                else
                                    % Stim2 is on right (positive side)
                                    % If moving right (current > previous), add to cumulative (toward stimulus)
                                    % If moving left (current < previous), subtract from cumulative (away from stimulus)
                                    directionSign = ones(size(absDiff));
                                    directionSign(currDistances < prevDistances) = -1;
                                end
                                
                                % Accumulate signed displacement
                                displacementSeries(timeIdx, :) = displacementSeries(timeIdx - 1, :) + (absDiff .* directionSign);
                            end
                            
                            % Translate so that at bout onset (refIdxInBout), displacement = 0
                            displacementSeries = displacementSeries - displacementSeries(refIdxInBout, :);

                            % Bin the displacementSeries into fixed bins anchored at time 0
                            timeVector = trialTime(startIdx:endIdx);
                            binEdgesAbsolute = binEdgesRelative + boutStartTime;
                            [~, ~, binIndices] = histcounts(timeVector, binEdgesAbsolute);
                            
                            binnedBoutDisplacements = NaN(nBins, size(displacementSeries, 2)); % nBins x nReplicates
                            for binIdx = 1:nBins
                                binMask = binIndices == binIdx;
                                if any(binMask)
                                    binnedBoutDisplacements(binIdx, :) = mean(displacementSeries(binMask, :), 1, 'omitnan');
                                end
                            end
                            
                            allBinnedDisplacements = cat(3, allBinnedDisplacements, binnedBoutDisplacements); % nBins x nReplicates x nBouts
                        end

                        nreplicates = size(allBinnedDisplacements, 2);
                        
                        % Average + SEM across bouts and replicates for this stimulus x sex combination
                        % Shape: nBins x nReplicates x nBouts -> average to nBins
                        meanDisplacement = squeeze(mean(allBinnedDisplacements, 3, 'omitnan')); % nBins x nReplicates
                        meanAcrossReplicates = mean(meanDisplacement, 2, 'omitnan'); % nBins x 1
                        semAcrossReplicates = std(meanDisplacement, 0, 2, 'omitnan') / sqrt(size(meanDisplacement, 2));
                        
                        % Store results for this stimulus and sex
                        % Use a composite key: "stimName:sex" to handle stimulus names with spaces
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        genotypeSexData(compositeKey) = struct(...
                            'mean', meanAcrossReplicates, ...
                            'sem', semAcrossReplicates, ...
                            'binTimeCenters', binTimeCenters, ...
                            'nreplicates', nreplicates ...
                        );
                    end
                end


                % Plot the results for this strain x genotype
                % Different line styles for different stimuli, different colors for different sexes
                lineStyles = {'-', '-.'}; % solid for stim1, dashed for stim2 (as stimuliSorted should place 'normal' first, normal stimulus gets solid line)
                colorMap = {'blue', 'red'}; % blue for M, red for F
                
                lineHandles = [];
                lineLabels = {};
                
                for sexPlotIdx = 1:nsexes
                    sex = animalSexes{sexPlotIdx};
                    sexMask = strcmp(columnBySexOrder, sex);
                    combinedMask = strainMask & genotypeMask & sexMask;
                    if ~any(combinedMask)
                        continue;
                    end
                    
                    % Plot lines for each stimulus
                    for stimIdx = 1:length(stimsBouts.keys())
                        stimName = stimsBouts.keys{stimIdx};
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        if isKey(genotypeSexData, compositeKey)
                            data = genotypeSexData(compositeKey);
                            binTimeCenters = data.binTimeCenters;
                            meanDisplacement = data.mean;
                            semDisplacement = data.sem;
                            
                            % Ensure vectors are column vectors for fill function
                            binTimeCenters = binTimeCenters(:);
                            meanDisplacement = meanDisplacement(:);
                            semDisplacement = semDisplacement(:);

                            % Make sure the color matches sex
                            if strcmpi(sex, 'M') || strcmpi(sex, 'Male')
                                lineColor = colorMap{1};
                            elseif strcmpi(sex, 'F') || strcmpi(sex, 'Female')
                                lineColor = colorMap{2};
                            else
                                % Gray for unknown (should not happen, i hope....)
                                lineColor = [0.5, 0.5, 0.5];
                            end
                            
                            % Add error shading (polygon envelope) - don't include in legend
                            upperBound = meanDisplacement + semDisplacement;
                            lowerBound = meanDisplacement - semDisplacement;
                            fill(a, [binTimeCenters; flipud(binTimeCenters)], ...
                                [upperBound; flipud(lowerBound)], ...
                                lineColor, ...
                                'FaceAlpha', 0.08, ...
                                'EdgeColor', 'none', ...
                                'HandleVisibility', 'off');

                            lineHandle = plot(a, binTimeCenters, meanDisplacement, ...
                                'LineStyle', lineStyles{stimIdx}, ...
                                'Color', lineColor, ...
                                'LineWidth', 2, ...
                                'DisplayName', sprintf('%s - %s', stimName, sex));
                            
                            % Collect line handle for legend
                            lineHandles = [lineHandles; lineHandle]; %#ok<AGROW>
                            lineLabels{end+1} = sprintf('%s - %s (n=%d)', stimName, sex, data.nreplicates); %#ok<AGROW>
                        end
                    end
                end
                
                yline(a, 0, 'k--', 'LineWidth', 1);
                xline(a, 0, '--', 'LineWidth', 1, 'Color', [0.3, 0.3, 0.3]);
                    
                title(a, sprintf('[%s]\n%s  %s\n(Bin = %.2fs, Bout Range = %s)', strjoin(thisStimSet, ' / '), strain, genotype, kvargs.BinWidth, percentRangeStr), 'Interpreter', 'none');
                xlabel(a, 'Time (s) relative to Bout Onset');
                ylabel(a, sprintf('Cumulative Displacement (normalized)\nPositive = toward stimulus, Negative = away from stimulus'));
                if ~isempty(lineHandles)
                    legend(a, lineHandles, lineLabels, 'Location', 'southwest', 'Interpreter', 'none');
                end
                grid(a, 'on');
                hold(a, 'off');

            end

        end

    end

end