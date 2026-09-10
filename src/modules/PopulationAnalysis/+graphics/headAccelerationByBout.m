function f = headAccelerationByBout(standardizedTable, kvargs)
    %%HEADACCELERATIONBYBOUT Plot signed head acceleration aligned by bout onset, binned over time
    %
    %   This function computes the signed acceleration of the head (defined as the midpoint
    %   of the Ear_left and Ear_right bodyparts) over time, aligned to bout onset, for each
    %   bout of stimulus presentation in the provided standardizedTable.
    %   Acceleration is the time derivative of the instantaneous head speed (magnitude of
    %   the XY ear-midpoint velocity), kept in PHYSICAL units (cm/s^2, via px2cm) — no
    %   per-replicate normalization. This makes the plot a direct visual counterpart of
    %   graphics.headReactionTimeByBout(), which finds the latency of the peak signed
    %   acceleration within the post-onset window.
    %
    %   The speed feeding the derivative is first baseline-corrected by subtracting each
    %   replicate's mean speed within BaselineWindow (default [-1, 0] s relative to bout
    %   onset), which removes pre-onset drift from the acceleration trace. (A constant
    %   speed offset would not change the derivative, but correcting the speed first
    %   removes slow drift that would otherwise leak into it.) An optional moving-average
    %   smoothing (SmoothWindow, in seconds) can be applied to tame per-frame noise.
    %
    %   f = graphics.headAccelerationByBout(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'ResponseWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to analyze. Default is [-1, 6]. This range should cover the full bout duration and ends before the next bout starts.
    %       'BinWidth' : Scalar double specifying the width of time bins (in seconds) for averaging acceleration data. Default is NaN, which uses the smallest time resolution available. Set to 0 or NaN for no binning, or Inf for one single bin over the whole ResponseWindow.
    %       'BoutRange' : 1x2 double array specifying which bouts to include. Default is [1, Inf] (all bouts). Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts).
    %       'BaselineWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) whose mean speed is subtracted from each replicate's speed trace before differentiating. Default is [-1, 0]. Must lie within ResponseWindow and end at or before 0.
    %       'SmoothWindow' : Scalar double specifying the moving-average smoothing window in seconds. Default is NaN (no smoothing). 0 or NaN disables smoothing. Applied to the speed series before differentiation.
    %
    %       'Title' : Text scalar for the overall figure title. Default is '' (no title).
    %       'SameYLim' : Logical scalar indicating whether to harmonize y-limits across all subplots for direct comparability. Default is true.
    %       'YLim' : 1x2 double array specifying manual y-limits [min, max]. Default is [] (auto). Overrides SameYLim.
    %       'ShowDataPoints' : Logical scalar indicating whether to overlay jittered scatter of per-animal bin means. Default is false, since with the default BinWidth (NaN = frame resolution) the per-bin replicate means are essentially raw per-frame samples and would drown out the mean + SEM envelope. Set to true together with a coarser BinWidth to inspect per-animal spread.
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.headReactionTimeByBout, graphics.headVelocityByBout, graphics.headMovementByBout


    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.ResponseWindow (1,2) double = [-1, 6] % in seconds, relative to bout onset
        kvargs.BinWidth (1,1) double = NaN % in seconds, set to 0 or NaN for no binning (use the smallest time resolution available), or Infinity for one single bin over the whole ResponseWindow. BinWidth is clamped to be at most the size of ResponseWindow.
        kvargs.BoutRange (1,2) double = [1, Inf] % which bouts to include. Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts)
        kvargs.BaselineWindow (1,2) double = [-1, 0] % in seconds, relative to bout onset. Mean speed within this window is subtracted per replicate before differentiation. Must lie within ResponseWindow and end at or before 0.
        kvargs.SmoothWindow (1,1) double = NaN % in seconds, moving-average smoothing window applied to speed before differentiation; 0 or NaN disables smoothing

        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.SameYLim (1,1) logical = true % whether to harmonize y-limits across all subplots for direct comparability
        kvargs.YLim double {validateYLim} = [] % manual y-limits [min, max]; empty = auto
        kvargs.ShowDataPoints (1,1) logical = false % whether to overlay jittered scatter of per-animal bin means. Off by default: with frame-resolution bins this plots every raw sample and obscures the mean + SEM.
    end

    kvargs.YLim = validateYLim(kvargs.YLim);

    % Make sure windows are valid
    if kvargs.ResponseWindow(2) <= kvargs.ResponseWindow(1)
        error('Invalid ResponseWindow: End time must be greater than Start time.');
    end
    if kvargs.BaselineWindow(2) <= kvargs.BaselineWindow(1)
        error('Invalid BaselineWindow: End time must be greater than Start time.');
    end
    if kvargs.BaselineWindow(1) < kvargs.ResponseWindow(1) || kvargs.BaselineWindow(2) > kvargs.ResponseWindow(2)
        error('Invalid BaselineWindow: Must lie within ResponseWindow.');
    end
    if kvargs.BaselineWindow(2) > 0
        error('Invalid BaselineWindow: End time must be at or before 0 (bout onset).');
    end
    if ~isnan(kvargs.SmoothWindow) && kvargs.SmoothWindow ~= 0 && kvargs.SmoothWindow <= 0
        error('Invalid SmoothWindow: Must be positive, or 0/NaN to disable smoothing.');
    end

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


    % Each plot will be by Per StimSet x Strain x Genotype
    % Within each plot, the stimulus (within the set) will be represented by line style, and Sex by color within each plot
    % With 2 stimuli per set, there will be 2 line styles (e.g., solid for stim that includes 'normal', dashed for the other stimulus --> 4 lines per plot
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

    % At the onset of each bout, track the signed head acceleration (d/dt of the
    % baseline-corrected ear-midpoint speed) over time. Acceleration is kept in physical
    % units (cm/s^2 via px2cm, or px/s^2 if px2cm is unavailable) — no normalization, so
    % magnitudes are directly interpretable and comparable with
    % graphics.headReactionTimeByBout()'s peak-acceleration search.

    NORMAL_LINE_STYLE = {'-'}; % stimuliSorted should place 'normal' stimulus first
    OTHER_LINE_STYLE = {'-.', '--', ':'}; % for additional stimuli, each gets a different non-solid line style
    knownOtherStimLineStyles = configureDictionary('char', 'char'); % Map known non-normal stimulus keywords to specific line styles (e.g., 'inverted' -> '-.', 'white noise' -> '--', etc.)

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Head Acceleration By Bout (Bin Size: %.3f sec)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        bodypartTable = thisStdTable.bodyparts;
        bodypartTable = graphics.filterStimulusPeriodRows(bodypartTable);
        bodypartTable = graphics.private.getHeadPositionMatrix(bodypartTable);
        trialTime = bodypartTable{:, 'Trial time'};
        headXMatrix = bodypartTable{:, 'Head X'};
        headYMatrix = bodypartTable{:, 'Head Y'};
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

        % Head coordinates are in pixels; px2cm converts to cm. Fall back to pixel units
        % (with a label note) when px2cm is unavailable (NaN).
        thisPx2cm = thisStdTable.px2cm;
        if isfinite(thisPx2cm)
            speedUnitScale = thisPx2cm; % px/s -> cm/s; accel gets px2cm^2 -> cm/s^2
            unitLabel = 'cm/s^2';
        else
            speedUnitScale = 1; % stay in px/s; accel in px/s^2
            unitLabel = 'px/s^2 (px2cm unavailable)';
        end

        % Pre-process the stim sequence into bouts for this stim set
        stimSequence = bodypartTable{:, 'Stimulus name'};
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

        for comboIdx = 1:length(existingCombos)
            combo = existingCombos{comboIdx};
            if combo{1} ~= stimsetIdx
                continue;
            end
            strain = combo{2};
            genotype = combo{3};

            strainMask = strcmp(columnByStrainOrder, strain);
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

                    headX = headXMatrix(:, combinedMask);
                    headY = headYMatrix(:, combinedMask);

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

                        allBinnedAccels = []; % will be nBins x nReplicates x nBouts

                        for boutIdx = 1:nBouts
                            startIdx = responseWindowStartIdx(boutIdx);
                            endIdx = responseWindowEndIdx(boutIdx);
                            boutX = headX(startIdx:endIdx, :); % time x replicates
                            boutY = headY(startIdx:endIdx, :); % time x replicates

                            boutStartTime = trialTime(refIdx(boutIdx)); % absolute time when this bout started
                            timeVector = trialTime(startIdx:endIdx);
                            timeRelativeToBout = timeVector - boutStartTime;

                            % Instantaneous head speed from the ear-midpoint trajectory,
                            % converted to physical units (cm/s; px/s if px2cm unavailable)
                            speedSeries = calcInstantaneousSpeedFromXY(boutX, boutY, timeVector) * speedUnitScale;

                            % Baseline-correct the speed before differentiating: subtract each
                            % replicate's mean speed within BaselineWindow. A constant offset would
                            % not change the derivative, but this removes slow pre-onset drift that
                            % would otherwise leak into the acceleration trace.
                            baselineMask = timeRelativeToBout >= kvargs.BaselineWindow(1) & timeRelativeToBout <= kvargs.BaselineWindow(2);
                            if any(baselineMask)
                                baselineSpeed = mean(speedSeries(baselineMask, :), 1, 'omitnan');
                                speedSeries = speedSeries - baselineSpeed; % implicit broadcast: 1 x nReplicates
                            end

                            % Optional moving-average smoothing over time (per replicate),
                            % applied to speed BEFORE differentiation to tame per-frame noise
                            if ~isnan(kvargs.SmoothWindow) && kvargs.SmoothWindow > 0
                                speedSeries = smoothBySeconds(speedSeries, timeVector, kvargs.SmoothWindow);
                            end

                            % Signed acceleration = derivative of speed
                            dt = diff(timeVector);
                            dt(dt <= 0) = NaN; % protect against duplicate/non-monotonic timestamps
                            accelSeries = NaN(size(speedSeries));
                            accelSeries(2:end, :) = diff(speedSeries, 1, 1) ./ dt;

                            % Bin the accelSeries into fixed bins anchored at time 0
                            binEdgesAbsolute = binEdgesRelative + boutStartTime;
                            [~, ~, binIndices] = histcounts(timeVector, binEdgesAbsolute);

                            binnedBoutAccels = NaN(nBins, size(accelSeries, 2)); % nBins x nReplicates
                            for binIdx = 1:nBins
                                binMask = binIndices == binIdx;
                                if any(binMask)
                                    binnedBoutAccels(binIdx, :) = mean(accelSeries(binMask, :), 1, 'omitnan');
                                end
                            end

                            allBinnedAccels = cat(3, allBinnedAccels, binnedBoutAccels); % nBins x nReplicates x nBouts
                        end

                        nreplicates = size(allBinnedAccels, 2);

                        % Average + SEM across bouts and replicates for this stimulus x sex combination
                        % Shape: nBins x nReplicates x nBouts -> average to nBins
                        meanAccel = squeeze(mean(allBinnedAccels, 3, 'omitnan')); % nBins x nReplicates
                        meanAcrossReplicates = mean(meanAccel, 2, 'omitnan'); % nBins x 1
                        semAcrossReplicates = std(meanAccel, 0, 2, 'omitnan') / sqrt(size(meanAccel, 2));

                        % Store results for this stimulus and sex
                        % Use a composite key: "stimName:sex" to handle stimulus names with spaces
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        genotypeSexData(compositeKey) = struct(...
                            'mean', meanAcrossReplicates, ...
                            'sem', semAcrossReplicates, ...
                            'binTimeCenters', binTimeCenters, ...
                            'replicateMeans', meanAccel, ...
                            'nreplicates', nreplicates ...
                        );
                    end
                end


                % Plot the results for this strain x genotype
                colorMap = {'blue', 'red'}; % blue for M, red for F

                lineHandles = [];
                lineLabels = [];

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

                        % Determine line style for this stimulus
                        if stimIdx == 1
                            lineStyle = NORMAL_LINE_STYLE{1}; % normal stimulus gets solid line
                        else
                            assignedStyle = false;
                            if isKey(knownOtherStimLineStyles, stimName)
                                lineStyle = knownOtherStimLineStyles(stimName);
                                assignedStyle = true;
                            end
                            if ~assignedStyle
                                % If no known keyword matches, assign a line style based on this stimulus's index among the non-normal stimuli
                                currentKnownOtherStimIndex = length(knownOtherStimLineStyles.keys()) + 1; % index for this new unknown stimulus
                                lineStyle = OTHER_LINE_STYLE{mod(currentKnownOtherStimIndex-1, length(OTHER_LINE_STYLE)) + 1}; % cycle through OTHER_LINE_STYLE
                                knownOtherStimLineStyles(stimName) = lineStyle;
                            end
                        end

                        compositeKey = sprintf('%s:%s', stimName, sex);
                        if isKey(genotypeSexData, compositeKey)
                            data = genotypeSexData(compositeKey);
                            binTimeCenters = data.binTimeCenters;
                            meanAccel = data.mean;
                            semAccel = data.sem;
                            replicateMeans = data.replicateMeans;

                            % Ensure vectors are column vectors for fill function
                            binTimeCenters = binTimeCenters(:);
                            meanAccel = meanAccel(:);
                            semAccel = semAccel(:);

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
                            upperBound = meanAccel + semAccel;
                            lowerBound = meanAccel - semAccel;
                            fill(a, [binTimeCenters; flipud(binTimeCenters)], ...
                                [upperBound; flipud(lowerBound)], ...
                                lineColor, ...
                                'FaceAlpha', 0.08, ...
                                'EdgeColor', 'none', ...
                                'HandleVisibility', 'off');

                            lineHandle = plot(a, binTimeCenters, meanAccel, ...
                                'LineStyle', lineStyle, ...
                                'Color', lineColor, ...
                                'LineWidth', 2, ...
                                'DisplayName', sprintf('%s - %s', stimName, sex));

                            if kvargs.ShowDataPoints
                                scatterMarker = resolveStimulusMarker(stimIdx);
                                jitterWidth = resolveTimeJitterWidth(binTimeCenters, kvargs.ResponseWindow);
                                for binIdx = 1:length(binTimeCenters)
                                    vals = replicateMeans(binIdx, :);
                                    vals = vals(isfinite(vals));
                                    if isempty(vals)
                                        continue;
                                    end

                                    jitter = (rand(numel(vals), 1) - 0.5) * 2 * jitterWidth;
                                    scatter(a, binTimeCenters(binIdx) + jitter, vals(:), 16, ...
                                        'Marker', scatterMarker, ...
                                        'MarkerFaceColor', lineColor, ...
                                        'MarkerEdgeColor', 'none', ...
                                        'MarkerFaceAlpha', 0.25, ...
                                        'HandleVisibility', 'off');
                                end
                            end

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
                ylabel(a, sprintf('Head Acceleration (signed, %s)\nd/dt of baseline-corrected speed', unitLabel));
                if ~isempty(lineHandles)
                    legend(a, lineHandles, lineLabels, 'Location', 'southwest', 'Interpreter', 'none');
                end
                grid(a, 'on');
                hold(a, 'off');

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

function marker = resolveStimulusMarker(stimIdx)
    markerOptions = {'o', '^', 's', 'd'};
    marker = markerOptions{mod(stimIdx - 1, numel(markerOptions)) + 1};
end

function jitterWidth = resolveTimeJitterWidth(binTimeCenters, responseWindow)
    validCenters = binTimeCenters(isfinite(binTimeCenters));
    if numel(validCenters) >= 2
        jitterWidth = 0.15 * min(diff(validCenters));
    else
        jitterWidth = 0.02 * max(diff(responseWindow), eps);
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

function smoothed = smoothBySeconds(values, timeAxis, windowSec)
    % Centered moving-average smoothing along rows (time dimension).
    % values: N x R matrix (time x replicates); timeAxis: N x 1 timestamps.
    % Mirrors the smoothBySeconds helper in +cohort/+metrics/+plot/speedOverTime.m.
    % For each sample, average all samples within +/- windowSec/2 of it.

    nSamples = size(values, 1);
    smoothed = NaN(size(values));
    halfWindow = windowSec / 2;

    for sampleIdx = 1:nSamples
        windowMask = abs(timeAxis - timeAxis(sampleIdx)) <= halfWindow;
        smoothed(sampleIdx, :) = mean(values(windowMask, :), 1, 'omitnan');
    end
end
