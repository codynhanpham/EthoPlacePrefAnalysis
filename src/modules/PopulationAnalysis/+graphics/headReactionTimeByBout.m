function f = headReactionTimeByBout(standardizedTable, kvargs)
    %%HEADREACTIONTIMEBYBOUT Plot head reaction time to stimulus onset as box plots
    %
    %   For each bout of stimulus presentation in the provided standardizedTable, this function
    %   computes the instantaneous movement speed and signed acceleration of the head (defined
    %   as the midpoint of the Ear_left and Ear_right bodyparts), then infers the reaction time
    %   as the latency (in seconds, relative to bout onset) of the peak ABSOLUTE movement speed
    %   or of the peak ABSOLUTE signed acceleration within the post-onset search window, as selected by
    %   'ReactionMetric' (default: 'velocity'). Using the absolute metric means a strong
    %   braking/freeze response counts as a reaction too, and the reported latency is always
    %   the latency of the excursion that qualified the replicate as responsive.
    %
    %   By default (PeakSource = 'replicateMean'), the peak is taken on each replicate's
    %   bout-averaged trace: every replicate's baseline-corrected (and optionally smoothed)
    %   traces are averaged across its bouts on a common time grid BEFORE the argmax. This
    %   suppresses pose-estimation jitter by ~sqrt(nBouts) before peak-finding, fixing the
    %   noise-driven late bias of per-bout peaks (mean-of-peaks vs peak-of-mean), while still
    %   yielding one latency per animal so the box plots and cross-animal statistics survive.
    %   PeakSource = 'bout' keeps the legacy behavior: argmax of each single-bout trace, then
    %   the latencies are averaged per replicate. The latency estimator is selectable via
    %   LatencyMethod: 'peak' (argmax of the |metric|), 'firstCrossing' (first crossing of
    %   ResponseSDThreshold x noise floor that persists for FirstCrossingPersistenceWindow),
    %   'fractionalPeak' (first rise to FractionalPeakLevel of the peak), or 'responseEnergy'
    %   (first point where cumulative |metric|^2 reaches ResponseEnergyFraction of the window
    %   total). Threshold-based methods
    %   use a MATCHED noise floor: the SD across replicates of each replicate's bout-averaged
    %   baseline level, so k x SD is commensurate with the replicate-mean trace being tested
    %   (a pooled single-bout SD would demand far more than k sigma and filter nearly
    %   everything). Responders are counted above each group, boxes and the population
    %   triangle are restricted to responders, and the latency of the pooled responder-mean
    %   trace under the SAME LatencyMethod is drawn as a black triangle per box (opacity =
    %   pooled peak z vs the matched baseline SD).
    %
    %   The speed series is first baseline-corrected by subtracting each replicate's mean
    %   speed within BaselineWindow (default [-1, 0] s relative to bout onset), which removes
    %   pre-onset drift. This does not change the peak-speed latency (argmax is invariant to
    %   a constant offset), but it does change the peak-acceleration latency, which is now
    %   measured on the baseline-corrected speed — consistent with
    %   graphics.headAccelerationByBout().
    %
    %   An optional moving-average smoothing (SmoothWindow, in seconds) can be applied to the
    %   baseline-corrected speed before the peak search. Raw per-frame speed is dominated by
    %   pose-estimation jitter, so without smoothing the per-bout peak latency is largely
    %   noise-driven and biased late relative to the visible peak of the bout-averaged trace
    %   (mean-of-peaks vs peak-of-mean). Matching the smoothing used in
    %   graphics.headVelocityByBout() makes the two views directly comparable. Set
    %   DiagnosticPlot to true to get an extra figure showing per-bout traces, the detected
    %   per-bout peaks, and both latency definitions side by side.
    %
    %   The results are shown as box plots grouped by StimSet x Strain x Genotype, with one box
    %   per sex side by side within each stimulus group. To avoid pseudo-replication, the
    %   latency values are first averaged per replicate (animal) across its bouts, and the box
    %   plot shows the distribution across replicates.
    %
    %   f = graphics.headReactionTimeByBout(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'ResponseWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to analyze. Default is [-1, 6]. This range should cover the full bout duration and ends before the next bout starts.
    %       'PostOnsetWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) in which to search for the peak speed/acceleration. Default is [0, 1.5].
    %       'ReactionMetric' : Text scalar, 'acceleration' or 'velocity', selecting which metric's peak latency is used as the reaction time. Default is 'velocity'.
    %       'PeakSource' : Text scalar, 'replicateMean' or 'bout'. 'replicateMean' (default, recommended) takes the peak of each replicate's bout-averaged trace; 'bout' takes the peak of each single-bout trace and averages latencies across bouts (legacy, noise-sensitive). Applies symmetrically to both metrics.
    %       'BaselineWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) whose mean speed is subtracted from each replicate's speed trace before the peak search. Default is [-1, 0]. Must lie within ResponseWindow and end at or before 0.
    %       'SmoothWindow' : Scalar double specifying the moving-average smoothing window in seconds applied to the baseline-corrected speed before the peak search. Default is NaN (no smoothing). 0 or NaN disables smoothing. Applied to the speed before the acceleration derivative is taken, mirroring graphics.headAccelerationByBout().
    %       'ResponseSDThreshold' : Scalar double >= 0 (default 2; NaN disables filtering). Responder criterion: the peak absolute excursion of the replicate-mean trace within PostOnsetWindow must exceed ResponseSDThreshold x (matched noise floor), where the noise floor is the SD across replicates of each replicate's bout-averaged baseline level (speed SD for 'velocity', accel SD for 'acceleration'). Responders annotate counts (e.g., 'F 12/14, M 9/15') above each group, and BOTH the box plots and the population triangle are restricted to responders.
    %       'LatencyMethod' : Text scalar selecting the latency estimator applied to each replicate's bout-averaged |metric| trace: 'peak' (default; argmax), 'firstCrossing' (first crossing of ResponseSDThreshold x noise floor that stays above for FirstCrossingPersistenceWindow), 'fractionalPeak' (first rise to 25% of the peak), or 'responseEnergy' (first point where cumulative |metric|^2 reaches 20% of the window total). Applies to PeakSource = 'replicateMean'; 'bout' mode always uses 'peak'.
    %       'LatencyMethod' : Text scalar selecting the latency estimator applied to each replicate's bout-averaged |metric| trace: 'peak' (default; argmax), 'firstCrossing' (first crossing of ResponseSDThreshold x noise floor that stays above for FirstCrossingPersistenceWindow), 'fractionalPeak' (first rise to FractionalPeakLevel of the peak), or 'responseEnergy' (first point where cumulative |metric|^2 reaches ResponseEnergyFraction of the window total). Applies to PeakSource = 'replicateMean'; 'bout' mode always uses 'peak'.
    %       'FirstCrossingPersistenceWindow' : Scalar double in seconds; the trace must remain above threshold this long after a crossing for it to count (rejects single-frame jitter spikes). Only used by 'firstCrossing'. Default 1.
    %       'FractionalPeakLevel' : Scalar double in (0, 1]; the fraction of the trace's own peak that the trace must first rise to ('fractionalPeak' only). Default 0.25.
    %       'ResponseEnergyFraction' : Scalar double in (0, 1]; the fraction of the window's total |metric|^2 energy that must accumulate before the latency is reported ('responseEnergy' only). Default 0.2.
    %       'DiagnosticYClipSD' : Scalar double; when finite, the diagnostic figure y-axis is clipped to +/- this many matched-baseline SDs. Default NaN = auto robust clipping to the 1st-99th percentile of the plotted traces (recommended: the matched baseline SD is a cross-replicate statistic and is typically far smaller than the trace excursions, so a finite SD clip saturates the axes).
    %       'DiagnosticWindow' : 1x2 double array; time window (s relative to bout onset) shown in the diagnostic figure. Default [] = [ResponseWindow(1), PostOnsetWindow(2)], i.e. baseline plus the post-onset search window, excluding the locomotion-rich late part of the response window.
    %       'DiagnosticPlot' : Logical scalar. When true, an additional figure is generated showing per-bout baseline-corrected speed traces, the pooled mean trace, and xline markers contrasting the pooled-mean-trace peak vs the median of the reported latencies. Default is false.
    %       'BoutRange' : 1x2 double array specifying which bouts to include. Default is [1, Inf] (all bouts). Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts).
    %
    %       'Title' : Text scalar for the overall figure title. Default is '' (no title).
    %       'SameYLim' : Logical scalar indicating whether to harmonize y-limits across all subplots for direct comparability. When true, every tile gets the same data-driven limits: the full range of all plotted latency values across tiles (box values including outliers, plus the black population triangles) plus 10% padding. Default is true.
    %       'YLim' : 1x2 double array specifying manual y-limits [min, max]. Default is [] (auto). Overrides SameYLim.
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.headMovementByBout, graphics.cumulativeDisplacementByBout


    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.ResponseWindow (1,2) double = [-1, 6] % in seconds, relative to bout onset
        kvargs.PostOnsetWindow (1,2) double = [0, 1.5] % in seconds, relative to bout onset. Search window for peak speed/acceleration used for reaction time.
        kvargs.ReactionMetric {mustBeMember(kvargs.ReactionMetric, {'velocity', 'acceleration'}), mustBeTextScalar} = 'velocity' % which metric's peak latency to use as reaction time
        kvargs.PeakSource {mustBeMember(kvargs.PeakSource, {'replicateMean', 'bout'}), mustBeTextScalar} = 'replicateMean' % whether to peak each subject/replicate's bout-averaged trace ('replicateMean', recommended) or each single-bout trace ('bout', legacy)
        kvargs.ResponseSDThreshold (1,1) double = 2 % responder criterion: peak |metric change| must exceed this multiple of the matched baseline SD; NaN disables filtering
        kvargs.LatencyMethod {mustBeMember(kvargs.LatencyMethod, {'peak', 'firstCrossing', 'fractionalPeak', 'responseEnergy'}), mustBeTextScalar} = 'peak' % latency estimator applied to the replicate-mean |metric| trace
        kvargs.FirstCrossingPersistenceWindow (1,1) double = 1 % seconds the trace must stay above threshold after a crossing ('firstCrossing' only)
        kvargs.FractionalPeakLevel (1,1) double = 0.25 % fraction of the trace's own peak to first rise to ('fractionalPeak' only); in (0, 1]
        kvargs.ResponseEnergyFraction (1,1) double = 0.2 % fraction of window |metric|^2 energy to accumulate ('responseEnergy' only); in (0, 1]
        kvargs.DiagnosticYClipSD (1,1) double = NaN % diagnostic y-axis clip in matched-baseline SDs; NaN = auto robust percentile clip of the plotted traces
        kvargs.DiagnosticWindow double = [] % diagnostic time window (s relative to bout onset); empty = [ResponseWindow(1), PostOnsetWindow(2)]
        kvargs.BaselineWindow (1,2) double = [-1, 0] % in seconds, relative to bout onset. Mean speed within this window is subtracted per replicate before the peak search. Must lie within ResponseWindow and end at or before 0.
        kvargs.SmoothWindow (1,1) double = NaN % in seconds, moving-average smoothing applied to baseline-corrected speed before peak search; 0 or NaN disables smoothing
        kvargs.DiagnosticPlot (1,1) logical = false % whether to generate an extra diagnostic figure with per-bout traces and latency markers
        kvargs.BoutRange (1,2) double = [1, Inf] % which bouts to include. Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts)

        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.SameYLim (1,1) logical = true % harmonize y-limits across tiles using the pooled data-driven range (all latencies incl. outliers and triangles) + 10% padding
        kvargs.YLim double {validateYLim} = [] % manual y-limits [min, max]; empty = auto
    end

    kvargs.ReactionMetric = char(kvargs.ReactionMetric);
    kvargs.PeakSource = char(kvargs.PeakSource);
    kvargs.LatencyMethod = char(kvargs.LatencyMethod);

    kvargs.YLim = validateYLim(kvargs.YLim);

    % Make sure windows are valid
    if kvargs.ResponseWindow(2) <= kvargs.ResponseWindow(1)
        error('Invalid ResponseWindow: End time must be greater than Start time.');
    end
    if ~isempty(kvargs.DiagnosticWindow) && ~(isnumeric(kvargs.DiagnosticWindow) && numel(kvargs.DiagnosticWindow) == 2)
        error('Invalid DiagnosticWindow: Must be empty or a numeric 2-element vector [min, max].');
    end
    if ~isempty(kvargs.DiagnosticWindow) && kvargs.DiagnosticWindow(2) <= kvargs.DiagnosticWindow(1)
        error('Invalid DiagnosticWindow: End time must be greater than Start time.');
    end
    if kvargs.PostOnsetWindow(2) <= kvargs.PostOnsetWindow(1)
        error('Invalid PostOnsetWindow: End time must be greater than Start time.');
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
    if ~isnan(kvargs.ResponseSDThreshold) && kvargs.ResponseSDThreshold < 0
        error('Invalid ResponseSDThreshold: Must be >= 0, or NaN to disable filtering.');
    end
    if kvargs.FirstCrossingPersistenceWindow < 0
        error('Invalid FirstCrossingPersistenceWindow: Must be >= 0.');
    end
    if ~(kvargs.FractionalPeakLevel > 0 && kvargs.FractionalPeakLevel <= 1)
        error('Invalid FractionalPeakLevel: Must be in (0, 1].');
    end
    if ~(kvargs.ResponseEnergyFraction > 0 && kvargs.ResponseEnergyFraction <= 1)
        error('Invalid ResponseEnergyFraction: Must be in (0, 1].');
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
    % Within each plot, the stimulus (within the set) will be represented by box x-position grouping, and Sex by color within each plot
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

    % For each bout, compute the instantaneous head speed and signed acceleration from the head (ear midpoint) trajectory.
    % Reaction time = latency of the peak speed / peak signed acceleration within PostOnsetWindow after bout onset.
    % Latencies are averaged per replicate across bouts, then shown as box plots across replicates of the same Strain/Genotype/Sex group.

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', "Head Reaction Time By Bout", 'Position', figPos, 'NumberTitle', 'off');
    allLatencyVals = []; % pooled across tiles, for the SameYLim data-driven range
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = sprintf('%s', kvargs.Title);
    t.Title.FontWeight = 'bold';

    if kvargs.DiagnosticPlot
        fDiag = figure('Name', "Head Reaction Time Diagnostic", 'Position', figPos + [30, -30, 0, 0], 'NumberTitle', 'off');
        tDiag = tiledlayout(fDiag, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
        tDiag.Title.String = sprintf('%s (diagnostic)', kvargs.Title);
        tDiag.Title.FontWeight = 'bold';
    else
        tDiag = [];
    end

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
                if kvargs.DiagnosticPlot
                    aDiag = nexttile(tDiag);
                    hold(aDiag, 'on');
                end

                for sexIdx = 1:nsexes
                    sex = animalSexes{sexIdx};
                    sexMask = strcmp(columnBySexOrder, sex);
                    combinedMask = strainMask & genotypeMask & sexMask;
                    if ~any(combinedMask)
                        continue;
                    end

                    headX = headXMatrix(:, combinedMask);
                    headY = headYMatrix(:, combinedMask);


                    % Chunk the data into bouts, then compute reaction time per bout, for each stimulus in this stim set
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

                        % Per-replicate accumulators: latency to peak speed and to peak signed acceleration
                        nreplicates = size(headX, 2);
                        peakSpeedLatencies = nan(nBouts, nreplicates);
                        peakAccelLatencies = nan(nBouts, nreplicates);

                        % Trace accumulators: kept for every bout (not just diagnostics) since the
                        % 'replicateMean' PeakSource bout-averages them before the argmax, and the
                        % diagnostic figure overlays them.
                        boutTimeCells = {};
                        boutSpeedCells = {};
                        boutAccelCells = {};
                        baselineSpeedSamples = []; % baseline-window samples pooled over bouts, for the noise-floor SD
                        baselineAccelSamples = [];

                        for boutIdx = 1:nBouts
                            startIdx = responseWindowStartIdx(boutIdx);
                            endIdx = responseWindowEndIdx(boutIdx);
                            boutX = headX(startIdx:endIdx, :); % time x replicates
                            boutY = headY(startIdx:endIdx, :); % time x replicates

                            boutStartTime = trialTime(refIdx(boutIdx)); % absolute time when this bout started
                            timeVector = trialTime(startIdx:endIdx);
                            timeRelativeToBout = timeVector - boutStartTime;

                            % Instantaneous head speed from the ear-midpoint trajectory
                            speedSeries = calcInstantaneousSpeedFromXY(boutX, boutY, timeVector);

                            % Baseline-correct the speed: subtract each replicate's mean speed within
                            % BaselineWindow. Peak-speed latency is unchanged (argmax is invariant to a
                            % constant offset), but the acceleration derived below no longer carries
                            % pre-onset drift — consistent with graphics.headAccelerationByBout().
                            baselineMask = timeRelativeToBout >= kvargs.BaselineWindow(1) & timeRelativeToBout <= kvargs.BaselineWindow(2);
                            if any(baselineMask)
                                baselineSpeed = mean(speedSeries(baselineMask, :), 1, 'omitnan');
                                speedSeries = speedSeries - baselineSpeed; % implicit broadcast: 1 x nReplicates
                            end

                            % Optional moving-average smoothing over time (per replicate), applied
                            % identically to graphics.headVelocityByBout()/headAccelerationByBout().
                            % Raw per-frame speed is dominated by pose-estimation jitter; without
                            % smoothing the per-bout peak latency is largely noise-driven.
                            if ~isnan(kvargs.SmoothWindow) && kvargs.SmoothWindow > 0
                                speedSeries = smoothBySeconds(speedSeries, timeVector, kvargs.SmoothWindow);
                            end

                            % Signed acceleration = derivative of speed
                            dt = diff(timeVector);
                            dt(dt <= 0) = NaN; % protect against duplicate/non-monotonic timestamps
                            accelSeries = NaN(size(speedSeries));
                            accelSeries(2:end, :) = diff(speedSeries, 1, 1) ./ dt;

                            boutTimeCells{end+1} = timeRelativeToBout; %#ok<AGROW>
                            boutSpeedCells{end+1} = speedSeries; %#ok<AGROW>
                            boutAccelCells{end+1} = accelSeries; %#ok<AGROW>

                            % Pool baseline-window samples (post-correction) across bouts for the
                            % group's noise-floor SD used by the responder criterion
                            baselineSpeedSamples = [baselineSpeedSamples; speedSeries(baselineMask, :)]; %#ok<AGROW>
                            baselineAccelSamples = [baselineAccelSamples; accelSeries(baselineMask, :)]; %#ok<AGROW>

                            % Restrict the peak search to the post-onset window
                            searchMask = timeRelativeToBout >= kvargs.PostOnsetWindow(1) & ...
                                timeRelativeToBout <= kvargs.PostOnsetWindow(2);
                            searchIdx = find(searchMask);
                            if isempty(searchIdx)
                                continue;
                            end

                            % Latency to peak |speed| per replicate (abs argmax: braking counts too)
                            speedInWindow = speedSeries(searchIdx, :);
                            [~, maxSpeedIdx] = max(abs(speedInWindow), [], 1, 'omitnan');
                            for repIdx = 1:nreplicates
                                thisIdx = maxSpeedIdx(repIdx);
                                if isfinite(speedInWindow(thisIdx, repIdx))
                                    peakSpeedLatencies(boutIdx, repIdx) = timeRelativeToBout(searchIdx(thisIdx));
                                end
                            end

                            % Latency to peak |acceleration| per replicate (abs argmax)
                            accelInWindow = accelSeries(searchIdx, :);
                            [~, maxAccelIdx] = max(abs(accelInWindow), [], 1, 'omitnan');
                            for repIdx = 1:nreplicates
                                thisIdx = maxAccelIdx(repIdx);
                                if isfinite(accelInWindow(thisIdx, repIdx))
                                    peakAccelLatencies(boutIdx, repIdx) = timeRelativeToBout(searchIdx(thisIdx));
                                end
                            end
                        end

                        % Average latencies per replicate across bouts (avoid pseudo-replication).
                        % 'bout' mode: mean of the per-bout peak latencies. 'replicateMean' mode:
                        % peak of each replicate's bout-averaged trace on a common time grid —
                        % bout-averaging suppresses pose jitter (~sqrt(nBouts)) BEFORE the argmax,
                        % fixing the noise-driven late bias of per-bout peaks while keeping one
                        % latency per replicate for the box plots. Also stored: the peak amplitude
                        % of each replicate's mean speed trace (for responder flagging) and the
                        % peak of the pooled group-mean trace (population marker).
                        meanPeakSpeedLatency = mean(peakSpeedLatencies, 1, 'omitnan'); % 1 x nreplicates
                        meanPeakAccelLatency = mean(peakAccelLatencies, 1, 'omitnan'); % 1 x nreplicates

                        % Matched noise floor: SD across replicates of each replicate's bout-averaged
                        % baseline level. This matches the noise statistic to the replicate-mean
                        % trace the responder test is applied to (bout-averaging shrinks jitter by
                        % ~sqrt(nBouts), so a pooled single-bout SD would demand far more than
                        % k sigma and filter nearly everything). Falls back to the pooled
                        % single-bout SD when bouts have inconsistent baseline sample counts.
                        nBaseRows = size(baselineSpeedSamples, 1);
                        if nBaseRows > 0 && nBouts > 0 && mod(nBaseRows, nBouts) == 0
                            % baselineSpeedSamples is [nRowsPerBout x nreplicates x nBouts] stacked
                            % vertically per bout. Average over bouts (dim 3) AND baseline rows
                            % (dim 1) to get each replicate's bout-averaged baseline level, then
                            % take the SD ACROSS replicates (scalar). The final reshape guarantees a
                            % 1 x nreplicates row even when nreplicates == 1.
                            baseBlockSpeed = reshape(baselineSpeedSamples, [], nreplicates, nBouts);
                            baseBlockAccel = reshape(baselineAccelSamples, [], nreplicates, nBouts);
                            repMeanBaseSpeed = reshape(mean(mean(baseBlockSpeed, 3, 'omitnan'), 1, 'omitnan'), 1, []);
                            repMeanBaseAccel = reshape(mean(mean(baseBlockAccel, 3, 'omitnan'), 1, 'omitnan'), 1, []);
                            baselineSpeedSD = std(repMeanBaseSpeed, 0, 2, 'omitnan');
                            baselineAccelSD = std(repMeanBaseAccel, 0, 2, 'omitnan');
                        else
                            baselineSpeedSD = std(baselineSpeedSamples(:), 'omitnan');
                            baselineAccelSD = std(baselineAccelSamples(:), 'omitnan');
                        end

                        repMeanSpeedLatencies = nan(1, nreplicates);
                        repMeanAccelLatencies = nan(1, nreplicates);
                        tracePeakAmplitude = nan(1, nreplicates);
                        tracePeakAmplitudeAccel = nan(1, nreplicates);
                        responderAmp = tracePeakAmplitude;
                        populationSpeedPeakLatency = NaN;
                        populationAccelPeakLatency = NaN;
                        populationSpeedPeakZ = NaN; % pooled-peak amplitude / matched baseline SD
                        populationAccelPeakZ = NaN;

                        nGrid = 300;
                        gridT = linspace(kvargs.PostOnsetWindow(1), kvargs.PostOnsetWindow(2), nGrid)';
                        nTraces = length(boutTimeCells);
                        if nTraces > 0
                            speedStack = nan(nGrid, nreplicates, nTraces);
                            accelStack = nan(nGrid, nreplicates, nTraces);
                            for traceIdx = 1:nTraces
                                tThis = boutTimeCells{traceIdx};
                                sGrid = nan(nGrid, nreplicates);
                                aGrid = nan(nGrid, nreplicates);
                                for repIdx = 1:nreplicates
                                    validMask = isfinite(boutSpeedCells{traceIdx}(:, repIdx));
                                    if nnz(validMask) >= 2
                                        tu = tThis(validMask);
                                        su = boutSpeedCells{traceIdx}(validMask, repIdx);
                                        [tu, iu] = unique(tu);
                                        sGrid(:, repIdx) = interp1(tu, su(iu), gridT, 'linear', NaN);
                                    end
                                    validMaskA = isfinite(boutAccelCells{traceIdx}(:, repIdx));
                                    if nnz(validMaskA) >= 2
                                        tu = tThis(validMaskA);
                                        au = boutAccelCells{traceIdx}(validMaskA, repIdx);
                                        [tu, iu] = unique(tu);
                                        aGrid(:, repIdx) = interp1(tu, au(iu), gridT, 'linear', NaN);
                                    end
                                end
                                speedStack(:, :, traceIdx) = sGrid;
                                accelStack(:, :, traceIdx) = aGrid;
                            end

                            repMeanSpeedTrace = mean(speedStack, 3, 'omitnan'); % grid x nreplicates
                            repMeanAccelTrace = mean(accelStack, 3, 'omitnan'); % grid x nreplicates

                            searchMaskGrid = gridT >= kvargs.PostOnsetWindow(1) & gridT <= kvargs.PostOnsetWindow(2);
                            searchGridT = gridT(searchMaskGrid);

                            % Per-replicate latency + peak amplitude on the replicate-mean traces,
                            % using the selected LatencyMethod (always on the absolute metric so
                            % braking counts). Amplitudes stay the peak |excursion| regardless of
                            % method, so the responder criterion is method-independent.
                            if isfinite(kvargs.ResponseSDThreshold)
                                currentK = kvargs.ResponseSDThreshold;
                            else
                                currentK = 2; % default multiple used by threshold-based latency methods
                            end
                            [repMeanSpeedLatencies, tracePeakAmplitude] = computeLatencyPerReplicate( ...
                                abs(repMeanSpeedTrace(searchMaskGrid, :)), searchGridT, kvargs.LatencyMethod, ...
                                currentK * baselineSpeedSD, kvargs.FirstCrossingPersistenceWindow, ...
                                kvargs.FractionalPeakLevel, kvargs.ResponseEnergyFraction);
                            [repMeanAccelLatencies, tracePeakAmplitudeAccel] = computeLatencyPerReplicate( ...
                                abs(repMeanAccelTrace(searchMaskGrid, :)), searchGridT, kvargs.LatencyMethod, ...
                                currentK * baselineAccelSD, kvargs.FirstCrossingPersistenceWindow, ...
                                kvargs.FractionalPeakLevel, kvargs.ResponseEnergyFraction);

                            % Responder criterion: peak |change| of the replicate-mean trace vs
                            % ResponseSDThreshold x baseline SD (metric-specific noise floor). When
                            % enabled, BOTH the box-plot latencies and the pooled population trace
                            % (black triangle) are restricted to responders.
                            if isfinite(kvargs.ResponseSDThreshold)
                                if strcmpi(kvargs.ReactionMetric, 'velocity')
                                    noiseSD = baselineSpeedSD;
                                    responderAmp = tracePeakAmplitude;
                                else
                                    noiseSD = baselineAccelSD;
                                    responderAmp = tracePeakAmplitudeAccel;
                                end
                                if isfinite(noiseSD) && noiseSD > 0
                                    responderMask = responderAmp >= kvargs.ResponseSDThreshold * noiseSD;
                                else
                                    responderMask = true(1, nreplicates); % no estimable noise floor: do not filter
                                end
                            else
                                responderMask = true(1, nreplicates);
                            end

                            % Pooled group-mean trace over RESPONDERS only: population latency.
                            % The SAME LatencyMethod as the box-plot latencies is applied to the
                            % pooled responder-mean trace (1-column), so the black triangle follows
                            % the same detection rule as the boxes (e.g. 'fractionalPeak' marks the
                            % onset of the pooled rise, not its argmax). The pooled peak |amplitude|
                            % (method-independent, like the per-replicate amplitudes) still drives
                            % the triangle's z-score opacity, distinguishing a true population
                            % reaction (high z) from a noise-driven peak of a near-baseline mean
                            % (low z). Peak/amplitude detection is direction-agnostic (|metric|).
                            if any(responderMask)
                                pooledSpeedTrace = mean(reshape(speedStack(:, responderMask, :), nGrid, []), 2, 'omitnan');
                                pooledAccelTrace = mean(reshape(accelStack(:, responderMask, :), nGrid, []), 2, 'omitnan');
                                [populationSpeedPeakLatency, pooledSpeedPeakAmp] = computeLatencyPerReplicate( ...
                                    abs(pooledSpeedTrace), searchGridT, kvargs.LatencyMethod, ...
                                    currentK * baselineSpeedSD, kvargs.FirstCrossingPersistenceWindow, ...
                                    kvargs.FractionalPeakLevel, kvargs.ResponseEnergyFraction);
                                [populationAccelPeakLatency, pooledAccelPeakAmp] = computeLatencyPerReplicate( ...
                                    abs(pooledAccelTrace), searchGridT, kvargs.LatencyMethod, ...
                                    currentK * baselineAccelSD, kvargs.FirstCrossingPersistenceWindow, ...
                                    kvargs.FractionalPeakLevel, kvargs.ResponseEnergyFraction);
                                populationSpeedPeakLatency = populationSpeedPeakLatency(1);
                                populationAccelPeakLatency = populationAccelPeakLatency(1);
                                if isfinite(baselineSpeedSD) && baselineSpeedSD > 0
                                    populationSpeedPeakZ = pooledSpeedPeakAmp / baselineSpeedSD;
                                end
                                if isfinite(baselineAccelSD) && baselineAccelSD > 0
                                    populationAccelPeakZ = pooledAccelPeakAmp / baselineAccelSD;
                                end
                            end
                        else
                            % No traces collected: everything is a non-responder by definition
                            responderMask = false(1, nreplicates);
                        end

                        if strcmpi(kvargs.PeakSource, 'replicateMean')
                            meanPeakSpeedLatency = repMeanSpeedLatencies;
                            meanPeakAccelLatency = repMeanAccelLatencies;
                        end

                        % Store results for this stimulus and sex
                        % Use a composite key: "stimName:sex" to handle stimulus names with spaces
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        genotypeSexData(compositeKey) = struct(...
                            'peakSpeedLatency', meanPeakSpeedLatency, ...
                            'peakAccelLatency', meanPeakAccelLatency, ...
                            'boutPeakLatencies', peakSpeedLatencies, ...
                            'repMeanSpeedLatencies', repMeanSpeedLatencies, ...
                            'repMeanAccelLatencies', repMeanAccelLatencies, ...
                            'tracePeakAmplitude', tracePeakAmplitude, ...
                            'tracePeakAmplitudeAccel', tracePeakAmplitudeAccel, ...
                            'responderAmp', responderAmp, ...
                            'responderMask', responderMask, ...
                            'baselineSpeedSD', baselineSpeedSD, ...
                            'populationSpeedPeakLatency', populationSpeedPeakLatency, ...
                            'populationAccelPeakLatency', populationAccelPeakLatency, ...
                            'populationSpeedPeakZ', populationSpeedPeakZ, ...
                            'populationAccelPeakZ', populationAccelPeakZ, ...
                            'nreplicates', nreplicates, ...
                            'boutTimeCells', {boutTimeCells}, ...
                            'boutSpeedCells', {boutSpeedCells} ...
                        );
                    end
                end


                % Plot the results for this strain x genotype as box plots
                % One box per sex, side by side within each stimulus group, using the selected ReactionMetric
                colorMap = {'blue', 'red'}; % blue for M, red for F

                % Pre-compute the max pooled-population peak z-score across ALL stimulus x sex
                % combos of this tile, so triangle opacities are normalized within the tile:
                % z = maxZ -> fully opaque, z -> 0 -> 5% opacity (near-invisible = noise peak).
                maxPopPeakZ = 0;
                keyListAll = genotypeSexData.keys();
                for keyIdx = 1:numel(keyListAll)
                    dHere = genotypeSexData(keyListAll{keyIdx});
                    if strcmpi(kvargs.ReactionMetric, 'velocity')
                        thisZ = dHere.populationSpeedPeakZ;
                    else
                        thisZ = dHere.populationAccelPeakZ;
                    end
                    if isfinite(thisZ)
                        maxPopPeakZ = max(maxPopPeakZ, thisZ);
                    end
                end

                boxHandles = [];
                legendHandles = [];
                tileLatencyVals = []; % every latency value plotted in this tile (boxes + triangles), for data-driven y-limits
                sexLegendSeen = containers.Map('KeyType', 'char', 'ValueType', 'any'); % one legend entry per unique sex (color-sex definition only)
                % Determine x positions: one group per stimulus, with sex boxes side by side within the group
                nstim = length(stimsBouts.keys());
                sexSpacing = 0.28; % spacing between sex boxes within a stimulus group
                xTickPos = [];
                xTickLabels = {};

                for stimIdx = 1:nstim
                    stimName = stimsBouts.keys{stimIdx};

                    % Collect the sexes that actually have data for this stimulus, keeping animalSexes order
                    presentSexIdx = [];
                    for sexPlotIdx = 1:nsexes
                        sex = animalSexes{sexPlotIdx};
                        sexMask = strcmp(columnBySexOrder, sex);
                        combinedMask = strainMask & genotypeMask & sexMask;
                        if ~any(combinedMask)
                            continue;
                        end
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        if isKey(genotypeSexData, compositeKey)
                            presentSexIdx(end+1) = sexPlotIdx; %#ok<AGROW>
                        end
                    end

                    % Center the sex boxes around the stimulus group center
                    nsexInGroup = length(presentSexIdx);
                    sexOffsets = ((1:nsexInGroup) - (nsexInGroup + 1) / 2) * sexSpacing;

                    for k = 1:nsexInGroup
                        sexPlotIdx = presentSexIdx(k);
                        sex = animalSexes{sexPlotIdx};
                        compositeKey = sprintf('%s:%s', stimName, sex);
                        data = genotypeSexData(compositeKey);

                        % Make sure the color matches sex
                        if strcmpi(sex, 'M') || strcmpi(sex, 'Male')
                            lineColor = colorMap{1};
                        elseif strcmpi(sex, 'F') || strcmpi(sex, 'Female')
                            lineColor = colorMap{2};
                        else
                            % Gray for unknown (should not happen, i hope....)
                            lineColor = [0.5, 0.5, 0.5];
                        end

                        if strcmpi(kvargs.ReactionMetric, 'velocity')
                            latencyValues = data.peakSpeedLatency;
                            popLatency = data.populationSpeedPeakLatency;
                            popPeakZ = data.populationSpeedPeakZ;
                        else
                            latencyValues = data.peakAccelLatency;
                            popLatency = data.populationAccelPeakLatency;
                            popPeakZ = data.populationAccelPeakZ;
                        end

                        % Restrict the box to responders when a threshold is set (the population
                        % triangle was already computed from responders-only traces upstream).
                        if isfinite(kvargs.ResponseSDThreshold)
                            latencyValues = latencyValues(data.responderMask);
                        end

                        % Track every plotted latency (box values incl. outliers, and the black
                        % triangle) so the y-axis can cover the full data range with padding.
                        tileLatencyVals = [tileLatencyVals, latencyValues(isfinite(latencyValues))]; %#ok<AGROW>
                        if isfinite(popLatency)
                            tileLatencyVals = [tileLatencyVals, popLatency]; %#ok<AGROW>
                        end

                        boxX = stimIdx + sexOffsets(k);

                        % Population marker: peak latency of the pooled group-mean trace.
                        % Opacity encodes the pooled peak's z-score vs the matched baseline SD
                        % (number of SDs above baseline): high z = solid black (true reaction),
                        % low z = nearly invisible (peak of a noisy, near-baseline mean).
                        % Opacity range: 5% (z = 0) to 100% (z = maxPopPeakZ of this tile).
                        % scatter is used because plot's MarkerFaceColor does not accept RGBA.
                        if isfinite(popLatency)
                            if maxPopPeakZ > 0 && isfinite(popPeakZ)
                                triAlpha = 0.05 + 0.95 * min(1, max(0, popPeakZ / maxPopPeakZ));
                            else
                                triAlpha = 1; % no z available: keep fully opaque
                            end
                            scatter(a, boxX, popLatency, 60, [0, 0, 0], 'filled', ...
                                'Marker', '^', 'MarkerFaceAlpha', triAlpha, ...
                                'MarkerEdgeColor', [0, 0, 0], 'MarkerEdgeAlpha', triAlpha, ...
                                'HandleVisibility', 'off');
                        end

                        % Legend: axis + tick labels already identify stim and metric, so only map color -> sex
                        hBox = drawBoxPlot(a, boxX, latencyValues, lineColor, true, '');
                        if ~isempty(hBox)
                            boxHandles = [boxHandles; hBox]; %#ok<AGROW>
                            if ~isKey(sexLegendSeen, sex)
                                hBox.DisplayName = sex;
                                legendHandles = [legendHandles; hBox]; %#ok<AGROW>
                                sexLegendSeen(sex) = hBox;
                            end
                        end
                    end

                    % Responder annotation: one count text per stimulus group, drawn INSIDE the
                    % axes near the top. IMPORTANT: this must NOT be appended to the x tick
                    % labels — xticklabels() does not support multi-line char vectors; an
                    % embedded newline makes MATLAB flatten the label cell into a char matrix
                    % and each ROW becomes a separate tick label, shifting every label onto
                    % the wrong tick (observed as 'responders >= ...' replacing stimulus names).
                    %
                    % Centering: axes xlim is [0.5, nstim + 0.5], so stimulus group center
                    % stimIdx maps to normalized x = (stimIdx - 0.5) / nstim exactly.
                    if isfinite(kvargs.ResponseSDThreshold)
                        fracStr = '';
                        for kk = 1:numel(presentSexIdx)
                            sexK = animalSexes{presentSexIdx(kk)};
                            dataK = genotypeSexData(sprintf('%s:%s', stimName, sexK));
                            nResp = nnz(dataK.responderMask);
                            nTotal = nnz(isfinite(dataK.responderAmp));
                            fracStr = [fracStr, sprintf(' %s %d/%d,', upper(sexK(1)), nResp, nTotal)]; %#ok<AGROW>
                        end
                        text(a, 'Units', 'normalized', ...
                            'Position', [(stimIdx - 0.5) / nstim, 0.97, 0], ...
                            'String', sprintf('resp >= %g baseline SD,%s', kvargs.ResponseSDThreshold, strtrim(fracStr(1:end-1))), ...
                            'FontSize', 8, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
                            'BackgroundColor', [1, 1, 1, 0.6], 'Margin', 1, 'Interpreter', 'none', ...
                            'HandleVisibility', 'off');
                    end
                    xTickLabels{end+1} = stimName; %#ok<AGROW>
                    xTickPos(end+1) = stimIdx; %#ok<AGROW>
                end

                if strcmpi(kvargs.PeakSource, 'replicateMean')
                    peakSourceLabel = 'replicate bout-averaged trace';
                else
                    peakSourceLabel = 'single-bout trace';
                end
                switch lower(kvargs.LatencyMethod)
                    case 'peak'
                        methodLabel = 'peak';
                    case 'firstcrossing'
                        methodLabel = sprintf('first crossing (persist %.2f s)', kvargs.FirstCrossingPersistenceWindow);
                    case 'fractionalpeak'
                        methodLabel = sprintf('%.0f%%-of-peak rise', kvargs.FractionalPeakLevel * 100);
                    case 'responseenergy'
                        methodLabel = sprintf('%.0f%% response energy', kvargs.ResponseEnergyFraction * 100);
                    otherwise
                        methodLabel = kvargs.LatencyMethod;
                end
                title(a, sprintf('[%s]\n%s  %s\n%s, %s method (%s)\nBlack triangle = pooled responder-mean latency (same method; opacity = peak z vs baseline SD) | (Bout Range = %s)', strjoin(thisStimSet, ' / '), strain, genotype, [upper(kvargs.ReactionMetric(1)), lower(kvargs.ReactionMetric(2:end))], methodLabel, peakSourceLabel, percentRangeStr), 'Interpreter', 'none');
                xlabel(a, 'Stimulus');
                ylabel(a, sprintf('Reaction Latency (%s) (s)\nSearch Window = [%.2f, %.2f] s, Baseline = [%.2f, %.2f] s', kvargs.ReactionMetric, kvargs.PostOnsetWindow(1), kvargs.PostOnsetWindow(2), kvargs.BaselineWindow(1), kvargs.BaselineWindow(2)));

                if ~isempty(xTickPos)
                    xticks(a, xTickPos);
                    xticklabels(a, xTickLabels);
                end
                xlim(a, [0.5, max(1, nstim) + 0.5]);

                if ~isempty(legendHandles)
                    legend(a, legendHandles, 'Location', 'southwest', 'Interpreter', 'none');
                end
                grid(a, 'on');
                hold(a, 'off');

                % Data-driven y-limits for this tile: cover every plotted latency value (box
                % values including outliers, and the black population triangles) plus 10%
                % padding. With SameYLim these per-tile limits are overwritten by the pooled
                % range at the end; with manual YLim they are overridden there too.
                if ~isempty(tileLatencyVals)
                    yLoTile = min(tileLatencyVals);
                    yHiTile = max(tileLatencyVals);
                    spanTile = yHiTile - yLoTile;
                    if spanTile <= 0
                        spanTile = max(abs([yLoTile, yHiTile]));
                        if spanTile <= 0
                            spanTile = 1;
                        end
                    end
                    padTile = 0.1 * spanTile;
                    ylim(a, [yLoTile - padTile, yHiTile + padTile]);
                end
                allLatencyVals = [allLatencyVals, tileLatencyVals]; %#ok<AGROW>

                % Diagnostic tile: per-replicate BOUT-AVERAGED baseline-corrected speed traces
                % (thin, faded; one line per animal), the pooled mean trace (bold), the
                % median/IQR band across replicates, and xline markers contrasting the peak of
                % the mean trace vs the median of the reported latencies. Plotting bout-averaged
                % (rather than raw single-bout) traces keeps the line count at nreplicates per
                % stim x sex and removes the per-frame jitter that previously saturated the
                % axes into an unreadable solid block (nBouts x nReplicates overlapping
                % low-alpha lines + a y-clip sized for bout-averaged noise).
                if kvargs.DiagnosticPlot
                    % Diagnostic color scheme: within each sex, 'VBS Normal' keeps the sex's
                    % base color (M = blue, F = red) and any other stimulus gets a darker
                    % variant (M = dark green, F = dark orange), so stimuli are distinguishable
                    % at a glance. Line style additionally encodes the stimulus index.
                    stimStyles = {'-', '--', ':', '-.'}; % one line style per stimulus

                    % Common time grid over the diagnostic window (default: baseline plus the
                    % post-onset search window) so the mean trace and band span the same range
                    % as the plotted traces; the peak-of-mean marker is still searched only
                    % within the post-onset window.
                    if isempty(kvargs.DiagnosticWindow)
                        diagWindow = [kvargs.ResponseWindow(1), kvargs.PostOnsetWindow(2)];
                    else
                        diagWindow = kvargs.DiagnosticWindow;
                    end
                    gridT = linspace(diagWindow(1), diagWindow(2), 400)';
                    searchMaskDiag = gridT >= kvargs.PostOnsetWindow(1) & gridT <= kvargs.PostOnsetWindow(2);
                    plottedVals = []; % pooled finite samples of all plotted traces, for robust y-limits

                    for stimDiagIdx = 1:nstim
                        stimNameDiag = stimsBouts.keys{stimDiagIdx};
                        stimStyleDiag = stimStyles{mod(stimDiagIdx - 1, numel(stimStyles)) + 1};
                        for sexDiagIdx = 1:nsexes
                            sexDiag = animalSexes{sexDiagIdx};
                            compositeKeyDiag = sprintf('%s:%s', stimNameDiag, sexDiag);
                            if ~isKey(genotypeSexData, compositeKeyDiag)
                                continue;
                            end
                            dataDiag = genotypeSexData(compositeKeyDiag);
                            if isempty(dataDiag.boutTimeCells)
                                continue;
                            end

                            traceColor = dealColorFor(contains(stimNameDiag, 'VBS Normal'), upper(sexDiag(1)));
                            fadedColor = 1 - 0.7 * (1 - traceColor); % mix with white for per-replicate traces

                            % Bout-average each replicate's traces on the common grid FIRST,
                            % then draw ONE (smooth) line per replicate. Line transparency: pass
                            % a 4-element RGBA color (Line has no 'ColorAlpha' property; RGBA
                            % 'Color' is supported since R2022a).
                            nBoutTraces = length(dataDiag.boutTimeCells);
                            nRepDiag = size(dataDiag.boutSpeedCells{1}, 2);
                            repTraces = nan(numel(gridT), nRepDiag);
                            for repDiagIdx = 1:nRepDiag
                                boutTraces = nan(numel(gridT), nBoutTraces);
                                for boutDiagIdx = 1:nBoutTraces
                                    timesThis = dataDiag.boutTimeCells{boutDiagIdx};
                                    speedsThis = dataDiag.boutSpeedCells{boutDiagIdx};
                                    if repDiagIdx > size(speedsThis, 2)
                                        continue;
                                    end
                                    su = speedsThis(:, repDiagIdx);
                                    validMask = isfinite(su);
                                    if nnz(validMask) < 2
                                        continue;
                                    end
                                    tu = timesThis(validMask);
                                    su = su(validMask);
                                    [tu, iu] = unique(tu);
                                    boutTraces(:, boutDiagIdx) = interp1(tu, su(iu), gridT, 'linear', NaN);
                                end
                                repTraces(:, repDiagIdx) = mean(boutTraces, 2, 'omitnan');
                            end
                            hasTraceMask = any(isfinite(repTraces), 1);
                            plottedVals = [plottedVals; repTraces(isfinite(repTraces))]; %#ok<AGROW>

                            % Per-replicate bout-averaged traces, drawn at low opacity so the
                            % pooled mean trace stays legible when overlaid.
                            for repDiagIdx = find(hasTraceMask)
                                plot(aDiag, gridT, repTraces(:, repDiagIdx), stimStyleDiag, ...
                                    'Color', [fadedColor, 0.15], 'LineWidth', 0.5, 'HandleVisibility', 'off');
                            end

                            % Markers: peak of pooled mean trace vs median of reported latencies.
                            % Peak of the mean is direction-agnostic (argmax of |mean|) so a
                            % strong downward (braking) reaction is marked too. The mean trace and
                            % band are drawn after the individual traces and brought to the top of
                            % the draw order so they are never hidden.
                            latencyOfMeanTrace = NaN;
                            meanTrace = mean(repTraces, 2, 'omitnan');
                            if any(isfinite(meanTrace))
                                searchValsDiag = meanTrace(searchMaskDiag);
                                if any(isfinite(searchValsDiag))
                                    [~, pkIdxDiag] = max(abs(searchValsDiag), [], 1, 'omitnan');
                                    latencyOfMeanTrace = gridT(searchMaskDiag);
                                    latencyOfMeanTrace = latencyOfMeanTrace(pkIdxDiag);
                                end
                                hMean = plot(aDiag, gridT, meanTrace, '-', 'Color', traceColor, 'LineWidth', 2.5, 'HandleVisibility', 'off');
                                uistack(hMean, 'top');
                            end
                            % Median + IQR band across replicates, drawn under the mean trace so
                            % the group spread stays legible under the individual traces
                            if any(hasTraceMask)
                                medianTrace = median(repTraces, 2, 'omitnan');
                                q1Trace = prctile(repTraces, 25, 2);
                                q3Trace = prctile(repTraces, 75, 2);
                                hBand = fill(aDiag, [gridT; flipud(gridT)], [q3Trace; flipud(q1Trace)], traceColor, ...
                                    'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                                uistack(hBand, 'top');
                                hMed = plot(aDiag, gridT, medianTrace, '--', 'Color', traceColor, 'LineWidth', 1.5, 'HandleVisibility', 'off');
                                uistack(hMed, 'top');
                            end
                            % Median of the latencies the box plot actually shows
                            if strcmpi(kvargs.PeakSource, 'replicateMean')
                                medianReported = median(dataDiag.repMeanSpeedLatencies(:), 'omitnan');
                            else
                                medianReported = median(dataDiag.peakSpeedLatency(:), 'omitnan');
                            end

                            if isfinite(latencyOfMeanTrace)
                                xline(aDiag, latencyOfMeanTrace, '-', 'Color', traceColor, 'LineWidth', 2, 'HandleVisibility', 'off');
                            end
                            if isfinite(medianReported)
                                xline(aDiag, medianReported, '--', 'Color', traceColor, 'LineWidth', 2, 'HandleVisibility', 'off');
                            end
                        end
                    end

                    xline(aDiag, kvargs.PostOnsetWindow(1), ':', 'Color', [0.3, 0.3, 0.3], 'HandleVisibility', 'off');
                    xline(aDiag, kvargs.PostOnsetWindow(2), ':', 'Color', [0.3, 0.3, 0.3], 'HandleVisibility', 'off');
                    % Light dotted reference at y = 0 (the baseline, since traces are
                    % baseline-corrected within BaselineWindow)
                    yline(aDiag, 0, ':', 'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.8, 'HandleVisibility', 'off');

                    % Y-axis limits: by default (DiagnosticYClipSD = NaN) clip robustly to the
                    % 1st-99th percentile of the actually-plotted bout-averaged traces so a few
                    % large locomotion excursions do not flatten everything else. A finite
                    % DiagnosticYClipSD instead clips to +/- that many matched-baseline SDs.
                    maxBaseSD = 0;
                    keyList = genotypeSexData.keys();
                    for keyIdx = 1:numel(keyList)
                        dHere = genotypeSexData(keyList{keyIdx});
                        if isfield(dHere, 'baselineSpeedSD') && isfinite(dHere.baselineSpeedSD)
                            maxBaseSD = max(maxBaseSD, dHere.baselineSpeedSD);
                        end
                    end
                    if isfinite(kvargs.DiagnosticYClipSD) && maxBaseSD > 0
                        ylim(aDiag, [-kvargs.DiagnosticYClipSD * maxBaseSD, kvargs.DiagnosticYClipSD * maxBaseSD]);
                    elseif ~isfinite(kvargs.DiagnosticYClipSD)
                        if numel(plottedVals) > 10
                            yLo = prctile(plottedVals, 1);
                            yHi = prctile(plottedVals, 99);
                            if yHi > yLo
                                padDiag = 0.05 * (yHi - yLo);
                                ylim(aDiag, [yLo - padDiag, yHi + padDiag]);
                            end
                        end
                    end

                    title(aDiag, sprintf('[%s] %s  %s\nColor: M blue/dark-green, F red/dark-orange (dark = non-VBS-Normal stim) | style = stim\nBold = mean | Band = median/IQR | Solid xline = peak of mean | Dashed xline = median reported', strain, genotype, strjoin(thisStimSet, ' / ')), 'Interpreter', 'none');
                    xlabel(aDiag, 'Time (s) relative to Bout Onset');
                    ylabel(aDiag, sprintf('Baseline-corrected Head Speed\nSmoothWindow = %.3f s', kvargs.SmoothWindow));
                    xlim(aDiag, diagWindow);
                    grid(aDiag, 'on');
                    hold(aDiag, 'off');
                end

        end

    end
    if ~isempty(kvargs.YLim)
        allAxes = findall(t, 'Type', 'Axes');
        if ~isempty(allAxes)
            ylim(allAxes, kvargs.YLim);
        end
    elseif kvargs.SameYLim
        % Harmonize y-limits across all tile axes using the same data-driven rule as the
        % per-tile limits: the full range of all plotted latency values across the whole
        % figure (box values including outliers, plus the black population triangles)
        % plus 10% padding, applied identically to every tile.
        allAxes = findall(t, 'Type', 'Axes');
        if ~isempty(allAxes) && ~isempty(allLatencyVals)
            yLoAll = min(allLatencyVals);
            yHiAll = max(allLatencyVals);
            spanAll = yHiAll - yLoAll;
            if spanAll <= 0
                spanAll = max(abs([yLoAll, yHiAll]));
                if spanAll <= 0
                    spanAll = 1;
                end
            end
            padAll = 0.1 * spanAll;
            ylim(allAxes, [yLoAll - padAll, yHiAll + padAll]);
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

function colorOut = dealColorFor(isVBSNormalStim, sexChar)
% Diagnostic trace color: sex base color for 'VBS Normal', darker variant otherwise.
%   Male:   blue [0,0,1] for VBS Normal, dark green [0,0.45,0] otherwise
%   Female: red  [1,0,0] for VBS Normal, dark orange [0.85,0.4,0] otherwise
%   Unknown sex: gray
    if sexChar(1) == 'M'
        if isVBSNormalStim
            colorOut = [0, 0, 1];
        else
            colorOut = [0, 0.45, 0];
        end
    elseif sexChar(1) == 'F'
        if isVBSNormalStim
            colorOut = [1, 0, 0];
        else
            colorOut = [0.85, 0.4, 0];
        end
    else
        colorOut = [0.5, 0.5, 0.5];
    end
end

function h = drawBoxPlot(ax, xCenter, values, boxColor, isFilled, displayName)
% Draw a simple IQR box plot (no Statistics Toolbox) at x position xCenter.
% Box = 25th-75th percentile, whiskers = 1.5*IQR, outliers plotted as points.
% Returns a patch handle for the legend (empty if no valid values).

    values = values(isfinite(values));
    if isempty(values)
        h = [];
        return;
    end

    q1 = prctile(values, 25);
    q3 = prctile(values, 75);
    iqr = q3 - q1;
    whiskerLow = max(min(values), q1 - 1.5 * iqr);
    whiskerHigh = min(max(values), q3 + 1.5 * iqr);
    outliers = values(values < whiskerLow | values > whiskerHigh);
    inliers = values(values >= whiskerLow & values <= whiskerHigh);

    boxWidth = 0.2;

    % Whiskers
    plot(ax, [xCenter, xCenter], [whiskerLow, q1], 'Color', boxColor, 'LineWidth', 1, 'HandleVisibility', 'off');
    plot(ax, [xCenter, xCenter], [q3, whiskerHigh], 'Color', boxColor, 'LineWidth', 1, 'HandleVisibility', 'off');
    plot(ax, [xCenter - boxWidth/2, xCenter + boxWidth/2], [whiskerLow, whiskerLow], 'Color', boxColor, 'LineWidth', 1, 'HandleVisibility', 'off');
    plot(ax, [xCenter - boxWidth/2, xCenter + boxWidth/2], [whiskerHigh, whiskerHigh], 'Color', boxColor, 'LineWidth', 1, 'HandleVisibility', 'off');

    % Box
    h = patch(ax, xCenter + boxWidth/2 * [-1, 1, 1, -1], [q1, q1, q3, q3], boxColor, ...
        'FaceAlpha', 0.35, 'EdgeColor', boxColor, 'LineWidth', 1.2, 'DisplayName', displayName);

    % Median line
    med = median(values);
    plot(ax, [xCenter - boxWidth/2, xCenter + boxWidth/2], [med, med], 'k-', 'LineWidth', 1.5, 'HandleVisibility', 'off');

    % Outliers
    if ~isempty(outliers)
        plot(ax, xCenter * ones(size(outliers)), outliers, 'o', ...
            'MarkerSize', 4, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', boxColor, 'HandleVisibility', 'off');
    end

    % Jittered raw data points
    n = numel(inliers);
    if n > 0
        jitter = (rand(n, 1) - 0.5) * boxWidth * 0.8;
        scatter(ax, xCenter + jitter, inliers, 6, boxColor, 'filled', ...
            'MarkerFaceAlpha', 0.4, 'HandleVisibility', 'off');
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
    % Mirrors the smoothBySeconds helper in graphics.headVelocityByBout().
    % For each sample, average all samples within +/- windowSec/2 of it.

    nSamples = size(values, 1);
    smoothed = NaN(size(values));
    halfWindow = windowSec / 2;

    for sampleIdx = 1:nSamples
        windowMask = abs(timeAxis - timeAxis(sampleIdx)) <= halfWindow;
        smoothed(sampleIdx, :) = mean(values(windowMask, :), 1, 'omitnan');
    end
end

function [latencies, amplitudes] = computeLatencyPerReplicate(absTrace, timeGrid, method, thresholdAbs, persistenceSec, fractionalPeakLevel, responseEnergyFraction)
% Compute one latency per replicate from the absolute metric trace within the search window.
% absTrace: nT x nRep matrix of |metric|; timeGrid: nT x 1 search-window timestamps.
% thresholdAbs: crossing threshold in metric units (used by threshold-based methods;
% NaN disables them -> NaN latencies). amplitudes = peak |metric| (method-independent).
% fractionalPeakLevel / responseEnergyFraction: method parameters, in (0, 1].
% Methods:
%   'peak'           - argmax of |metric|
%   'firstCrossing'  - first crossing of thresholdAbs that stays above for persistenceSec
%   'fractionalPeak' - first rise to fractionalPeakLevel of the trace's own peak
%   'responseEnergy' - first point where cumulative |metric|^2 reaches responseEnergyFraction
%                      of the window total

    nT = size(absTrace, 1);
    nRep = size(absTrace, 2);
    latencies = nan(1, nRep);
    amplitudes = max(absTrace, [], 1, 'omitnan');

    switch lower(method)
        case 'peak'
            [~, pkIdx] = max(absTrace, [], 1, 'omitnan');
            for repIdx = 1:nRep
                if isfinite(absTrace(pkIdx(repIdx), repIdx))
                    latencies(repIdx) = timeGrid(pkIdx(repIdx));
                end
            end

        case 'firstcrossing'
            if ~isfinite(thresholdAbs)
                return; % no estimable threshold: no crossing latencies
            end
            nPersist = max(1, round(persistenceSec / mean(diff(timeGrid))));
            nPersist = min(nPersist, nT);
            for repIdx = 1:nRep
                above = absTrace(:, repIdx) >= thresholdAbs;
                for sampleIdx = 1:(nT - nPersist + 1)
                    if all(above(sampleIdx:(sampleIdx + nPersist - 1)))
                        latencies(repIdx) = timeGrid(sampleIdx);
                        break;
                    end
                end
            end

        case 'fractionalpeak'
            for repIdx = 1:nRep
                thisAmp = amplitudes(repIdx);
                if ~isfinite(thisAmp) || thisAmp <= 0
                    continue;
                end
                above = find(absTrace(:, repIdx) >= fractionalPeakLevel * thisAmp, 1, 'first');
                if ~isempty(above)
                    latencies(repIdx) = timeGrid(above(1));
                end
            end

        case 'responseenergy'
            energy = cumsum(absTrace.^2, 1, 'omitnan');
            totalEnergy = energy(end, :);
            for repIdx = 1:nRep
                if ~isfinite(totalEnergy(repIdx)) || totalEnergy(repIdx) <= 0
                    continue;
                end
                idxE = find(energy(:, repIdx) >= responseEnergyFraction * totalEnergy(repIdx), 1, 'first');
                if ~isempty(idxE)
                    latencies(repIdx) = timeGrid(idxE(1));
                end
            end
    end
end
