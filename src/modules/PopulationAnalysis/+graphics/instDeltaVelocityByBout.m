function f = instDeltaVelocityByBout(standardizedTable, kvargs)
    %%INSTDELTAVELOCITYBYBOUT Plot average instantaneous delta velocity aligned by bout onset, binned over time
    %
    %   This function averages the instantaneous speed over time, aligned to bout onset,
    %   for each bout of stimulus presentation in the provided standardizedTable.
    %   Speed is calculated from raw XY center coordinates using frame-to-frame
    %   Euclidean displacement divided by frame-to-frame time.
    %
    %   The plotted value is relative to a reference point computed per
    %   bout/replicate as the mean speed in BaselineWindow.
    %   If BaselineWindow has no valid samples for a replicate, the nearest
    %   valid sample around time 0 (or around window start if ResponseWindow
    %   starts after 0) is used as a fallback reference.
    %
    %
    %   f = population.temp.instDeltaVelocityByBout(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'ResponseWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to analyze. Default is [-1, 6]. This range should cover the full bout duration and ends before the next bout starts.
    %       'BaselineWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to use for baseline reference calculation. Default is [-2, 0]. This should be a period before the bout starts when the animal is expected to be in a baseline state.
    %       'BinWidth' : Scalar double specifying the width of time bins (in seconds) for averaging distance data. Default is NaN, which uses the smallest time resolution available. Set to 0 or NaN for no binning, or Inf for one single bin over the whole ResponseWindow.
    %       'BoutRange' : 1x2 double array specifying which bouts to include. Default is [1, Inf] (all bouts). Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts).
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.distFromMidlineByBout, graphics.cumulativeDisplacementByBout


    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.ResponseWindow (1,2) double = [-1, 6] % in seconds, relative to bout onset
        kvargs.BaselineWindow (1,2) double = [-2, 0] % in seconds, relative to bout onset. Per-bout/replicate reference is the mean speed within this window. If no valid samples exist, fallback is nearest valid sample around time 0 (or around response-window start when ResponseWindow starts after 0).
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

    % At each bout, calculate instantaneous speed, then subtract the
    % baseline reference value (mean within BaselineWindow).
    % Bin the delta-speed data into time bins, then average across replicates/animals belonging to the same Strain/Genotype/Sex group.

    nplots = nstrains * nstimsets * ngenotypes;

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Instantaneous Delta Velocity By Bout (Bin Size: %.3f sec)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        stimPeriodTable = thisStdTable.centerpointData;
        requiredCols = {'Trial time', 'Stimulus name', 'X center', 'Y center'};
        missingCols = setdiff(requiredCols, stimPeriodTable.Properties.VariableNames, 'stable');
        if ~isempty(missingCols)
            error('centerpointData is missing required columns: { ''%s'' }', strjoin(missingCols, ''', '''));
        end
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, requiredCols));
        trialTime = stimPeriodTable{:, 'Trial time'};
        xCenterMatrix = stimPeriodTable{:, 'X center'};
        yCenterMatrix = stimPeriodTable{:, 'Y center'};
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
                    boutRangeStart = 1; % 0% means start from bout 1
                end
                boutRangeEnd = min(nBouts, round(nBouts * kvargs.BoutRange(2)));
            else
                % Use direct bout indices
                boutRangeStart = max(1, kvargs.BoutRange(1));
                boutRangeEnd = min(nBouts, kvargs.BoutRange(2));
            end

            if boutRangeEnd < boutRangeStart
                stimStartIdx = [];
                stimEndIdx = [];
                nBouts = 0;
            else
                boutIndicesToInclude = boutRangeStart:boutRangeEnd;

                % Filter bout indices based on BoutRange
                stimStartIdx = stimStartIdx(boutIndicesToInclude);
                stimEndIdx = stimEndIdx(boutIndicesToInclude);
                nBouts = length(boutIndicesToInclude); % Update nBouts to reflect filtered count
            end

            % Format the percent range string for titles: start-end %
            if nBoutsTotal > 0
                startPercent = (boutRangeStart - 1) / nBoutsTotal * 100;
                endPercent = boutRangeEnd / nBoutsTotal * 100;
            else
                startPercent = 0;
                endPercent = 0;
            end
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

                    xCenter = xCenterMatrix(:, combinedMask);
                    yCenter = yCenterMatrix(:, combinedMask);

                    % Chunk the data into bouts, then into time bins within each bout, for each stimulus in this stim set
                    for stimIdx = 1:length(stimsBouts.keys()) % Stim bout key order matches thisStimSet order
                        stimName = stimsBouts.keys{stimIdx};
                        boutInfo = stimsBouts(stimName);
                        nBouts = boutInfo.nBouts;
                        refIdx = boutInfo.startIdx;
                        responseWindowStartIdx = boutInfo.responseWindowStartIdx;
                        responseWindowEndIdx = boutInfo.responseWindowEndIdx;

                        if nBouts == 0
                            continue;
                        end

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

                        allBinnedDeltaSpeed = []; % will be nBins x nReplicates x nBouts

                        for boutIdx = 1:nBouts
                            startIdx = responseWindowStartIdx(boutIdx);
                            endIdx = responseWindowEndIdx(boutIdx);
                            boutX = xCenter(startIdx:endIdx, :); % time x replicates
                            boutY = yCenter(startIdx:endIdx, :); % time x replicates

                            boutStartTime = trialTime(refIdx(boutIdx)); % absolute time when this bout started
                            timeVector = trialTime(startIdx:endIdx);

                            % Calculate instantaneous speed from XY trajectory
                            speedSeries = calcInstantaneousSpeedFromXY(boutX, boutY, timeVector);

                            % Compute per-replicate baseline as mean speed in BaselineWindow.
                            timeRelativeToBout = timeVector - boutStartTime;
                            baselineMask = timeRelativeToBout >= kvargs.BaselineWindow(1) & ...
                                timeRelativeToBout <= kvargs.BaselineWindow(2);
                            refValues = mean(speedSeries(baselineMask, :), 1, 'omitnan');

                            % Fallback when baseline window has no valid value for a replicate.
                            if kvargs.ResponseWindow(1) > 0
                                fallbackIdxInBout = 1;
                            else
                                fallbackIdxInBout = refIdx(boutIdx) - startIdx + 1;
                                fallbackIdxInBout = max(1, min(fallbackIdxInBout, size(speedSeries, 1)));
                            end
                            fallbackRefValues = nearestValidReferenceByReplicate(speedSeries, fallbackIdxInBout);
                            missingRefMask = ~isfinite(refValues);
                            refValues(missingRefMask) = fallbackRefValues(missingRefMask);

                            deltaSpeedSeries = bsxfun(@minus, speedSeries, refValues);

                            % Bin the relative speed series into fixed bins anchored at time 0
                            binEdgesAbsolute = binEdgesRelative + boutStartTime;
                            [~, ~, binIndices] = histcounts(timeVector, binEdgesAbsolute);

                            binnedBoutDeltaSpeed = NaN(nBins, size(deltaSpeedSeries, 2)); % nBins x nReplicates
                            for binIdx = 1:nBins
                                binMask = binIndices == binIdx;
                                if any(binMask)
                                    binnedBoutDeltaSpeed(binIdx, :) = mean(deltaSpeedSeries(binMask, :), 1, 'omitnan');
                                end
                            end

                            allBinnedDeltaSpeed = cat(3, allBinnedDeltaSpeed, binnedBoutDeltaSpeed); % nBins x nReplicates x nBouts
                        end

                        nreplicates = size(allBinnedDeltaSpeed, 2);

                        % Average + SEM across bouts and replicates for this stimulus x sex combination
                        % Shape: nBins x nReplicates x nBouts -> average to nBins
                        meanDeltaSpeed = squeeze(mean(allBinnedDeltaSpeed, 3, 'omitnan')); % nBins x nReplicates
                        meanAcrossReplicates = mean(meanDeltaSpeed, 2, 'omitnan'); % nBins x 1
                        semAcrossReplicates = std(meanDeltaSpeed, 0, 2, 'omitnan') / sqrt(size(meanDeltaSpeed, 2));

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
                lineStyles = {'-', '-.'}; % solid for stim1, dashed for stim2
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
                            meanDeltaSpeed = data.mean;
                            semDeltaSpeed = data.sem;

                            % Ensure vectors are column vectors for fill function
                            binTimeCenters = binTimeCenters(:);
                            meanDeltaSpeed = meanDeltaSpeed(:);
                            semDeltaSpeed = semDeltaSpeed(:);

                            % Make sure the color matches sex
                            if strcmpi(sex, 'M') || strcmpi(sex, 'Male')
                                lineColor = colorMap{1};
                            elseif strcmpi(sex, 'F') || strcmpi(sex, 'Female')
                                lineColor = colorMap{2};
                            else
                                lineColor = [0.5, 0.5, 0.5];
                            end

                            % Add error shading (polygon envelope) - don't include in legend
                            upperBound = meanDeltaSpeed + semDeltaSpeed;
                            lowerBound = meanDeltaSpeed - semDeltaSpeed;
                            fill(a, [binTimeCenters; flipud(binTimeCenters)], ...
                                [upperBound; flipud(lowerBound)], ...
                                lineColor, ...
                                'FaceAlpha', 0.08, ...
                                'EdgeColor', 'none', ...
                                'HandleVisibility', 'off');

                            lineHandle = plot(a, binTimeCenters, meanDeltaSpeed, ...
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
                ylabel(a, 'Instantaneous Delta Velocity (cm/s)'); % Assuming standardizedTable was generated with the GUI via TrackingProvider and trial.stats.trialSummary, it should already be in physical units (cm) if the user provided the correct conversion factor during that process.

                xlim(a, kvargs.ResponseWindow);
                xticks(a, floor(kvargs.ResponseWindow(1)):1:ceil(kvargs.ResponseWindow(2)));

                if ~isempty(lineHandles)
                    legend(a, lineHandles, lineLabels, 'Location', 'southwest', 'Interpreter', 'none');
                end
                grid(a, 'on');
                hold(a, 'off');

            end

        end


    end

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

function speed = calcInstantaneousSpeedFromXY(xSeries, ySeries, timeVector)
    % Calculate instantaneous speed from XY trajectories.
    % xSeries, ySeries: N x R matrices (time x replicates)
    % timeVector: N x 1 vector of timestamps

    dt = diff(timeVector);
    dt(dt <= 0) = NaN; % protect against duplicate/non-monotonic timestamps

    speed = NaN(size(xSeries));
    dx = diff(xSeries, 1, 1);
    dy = diff(ySeries, 1, 1);
    speed(2:end, :) = sqrt(dx.^2 + dy.^2) ./ dt;
end

function refValues = nearestValidReferenceByReplicate(series, refIdx)
    % Pick per-replicate reference near refIdx.
    % Priority: first finite value at/after refIdx, then before refIdx.

    [nTime, nRep] = size(series);
    refValues = NaN(1, nRep);
    refIdx = max(1, min(refIdx, nTime));

    for repIdx = 1:nRep
        col = series(:, repIdx);

        idxAfter = find(isfinite(col(refIdx:end)), 1, 'first');
        if ~isempty(idxAfter)
            refValues(repIdx) = col(refIdx + idxAfter - 1);
            continue;
        end

        idxBefore = find(isfinite(col(1:refIdx-1)), 1, 'last');
        if ~isempty(idxBefore)
            refValues(repIdx) = col(idxBefore);
        end
    end
end