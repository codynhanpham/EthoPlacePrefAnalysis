function eventTable = extractLedTimings(videoFilePath, options)
    %%EXTRACTLEDTIMINGS Extracts LED event timings from a video file.
    % The algorithm mirrors lib/trigger-extract Rust logic for parity.

    arguments
        videoFilePath {mustBeTextScalar, mustBeFile}
        options.RoiXRange (1,2) double {mustBeInRange(options.RoiXRange, 0, 1)} = [0.5-1/16, 0.5+1/16] % Location of ROI/LED in normalized coordinates (centered around middle of frame by default)
        options.RoiYRange (1,2) double {mustBeInRange(options.RoiYRange, 0, 1)} = [0.08, 0.215] % Location of ROI/LED in normalized coordinates (default is typical for top-mounted IR LED in 16:9 videos)
        options.DecodeMode (1,1) string {mustBeMember(options.DecodeMode, ["SparseSeek", "StreamingRing"])} = "SparseSeek"
        options.PulsePolarity (1,1) string {mustBeMember(options.PulsePolarity, ["OnPulses", "OffPulses"])} = "OnPulses"
        options.ScanStepSize (1,1) double {mustBeInteger, mustBePositive} = 60*30 % Rust default: sparse probe step
        options.ThresholdCalibrationStepSize (1,1) double {mustBeInteger, mustBePositive} = 2*30
        options.BaselineFramesRange (1,2) double {mustBeInteger, mustBePositive} = [6, 35]
        options.BaselineFrames (1,:) double {mustBeInteger, mustBePositive} = [] % Backward compatibility shim
        options.StdThreshold (1,1) double {mustBePositive} = 6.5
        options.StdNoiseFloor (1,1) double {mustBePositive} = 5
        options.BaselinePercentile (1,1) double {mustBeInRange(options.BaselinePercentile, 0, 100)} = 10
        options.AbsoluteDffThreshold (1,1) double {mustBeNonnegative} = 0.001

        options.Debug (1,1) logical = false
    end

    v = VideoReader(videoFilePath);
    W = v.Width; H = v.Height;
    frameRate = v.FrameRate;
    frameCount = floor(v.Duration * frameRate);

    if frameCount <= 0
        eventTable = struct2table(struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {}));
        return;
    end

    if ~isempty(options.BaselineFrames)
        baseStart = min(options.BaselineFrames);
        baseEnd = max(options.BaselineFrames);
    else
        baseStart = options.BaselineFramesRange(1);
        baseEnd = options.BaselineFramesRange(2);
    end

    baseStart = max(1, min(frameCount, round(baseStart)));
    baseEnd = max(baseStart, min(frameCount, round(baseEnd)));

    if options.PulsePolarity == "OnPulses"
        polaritySign = 1;
    else
        polaritySign = -1;
    end
    
    % ROI conversion
    x1 = max(1, round(options.RoiXRange(1) * W));
    x2 = min(W, round(options.RoiXRange(2) * W));
    y1 = max(1, round(options.RoiYRange(1) * H));
    y2 = min(H, round(options.RoiYRange(2) * H));

    if options.Debug
        figure('Name', 'LED Timing Extraction - ROI Confirmation');
        imshow(read(v, baseStart)); hold on;
        rectangle('Position', [x1, y1, x2-x1, y2-y1], 'EdgeColor', 'r', 'LineWidth', 2);
        title('Red Box Shows the ROI Used for LED Timing Extraction');
        drawnow;
    end

    % Baseline Analysis (metric = mean ROI intensity, normalized to dF/F0)
    baseIntensities = readIntensitiesRange(v, x1, x2, y1, y2, baseStart, baseEnd);
    if isempty(baseIntensities)
        eventTable = struct2table(struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {}));
        return;
    end

    roughF0 = mean(baseIntensities);
    dffDenom = max(roughF0, eps);

    % Starting after baseline
    startMacro = min(frameCount, baseEnd + 1);
    if startMacro > frameCount
        eventTable = struct2table(struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {}));
        return;
    end

    scanStepSize = max(1, round(options.ScanStepSize));
    microScanWindowSize = scanStepSize;
    thresholdCalibrationStepSize = max(1, round(options.ThresholdCalibrationStepSize));

    scanFrames = startMacro:scanStepSize:frameCount;
    numScanFrames = numel(scanFrames);

    if numScanFrames == 0
        eventTable = struct2table(struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {}));
        return;
    end

    % PASS 1: Collect sparse dF/F0 trace
    dffTrace = zeros(numScanFrames, 1);
    frameTrace = scanFrames(:);

    for idx = 1:numScanFrames
        k = scanFrames(idx);
        currentMean = meanRoiIntensity(v, x1, x2, y1, y2, k);
        currentDff = polaritySign * ((currentMean - roughF0) / dffDenom);
        dffTrace(idx) = currentDff;
    end

    thresholdFrames = startMacro:thresholdCalibrationStepSize:frameCount;
    thresholdTrace = zeros(numel(thresholdFrames), 1);
    for idx = 1:numel(thresholdFrames)
        k = thresholdFrames(idx);
        currentMean = meanRoiIntensity(v, x1, x2, y1, y2, k);
        thresholdTrace(idx) = polaritySign * ((currentMean - roughF0) / dffDenom);
    end
    if isempty(thresholdTrace)
        thresholdTrace = dffTrace;
    end

    % PASS 2: Baseline and thresholds from calibration trace
    baselineF0_percentile = percentileLikeRust(thresholdTrace, options.BaselinePercentile);

    dffTrace = dffTrace - baselineF0_percentile;

    thresholdTrace = thresholdTrace - baselineF0_percentile;

    baselineCut = percentileLikeRust(thresholdTrace, options.BaselinePercentile);
    baselineSamples = thresholdTrace(thresholdTrace <= baselineCut);

    if numel(baselineSamples) < 2
        baselineSigma = std(thresholdTrace, 1);
    else
        baselineSigma = std(baselineSamples, 1);
    end

    T_trigger = max(options.StdThreshold * baselineSigma, options.AbsoluteDffThreshold);
    T_riseNoise = options.StdNoiseFloor * baselineSigma;

    if options.Debug
        fprintf('--- LED Detection Thresholds (Robust Percentile-Based) ---\n');
        fprintf('Baseline percentile: %.2f%%\n', options.BaselinePercentile);
        fprintf('Baseline dF/F0 level: %.6f\n', baselineF0_percentile);
        fprintf('Stats (after normalization): mu=%.6f, sigma=%.6f\n', 0, baselineSigma);
        fprintf('T_trigger: %.6f (max of: %.3f*sigma, absolute floor %.6f)\n', T_trigger, options.StdThreshold, options.AbsoluteDffThreshold);
        fprintf('T_riseNoise: %.6f (%.3f*sigma)\n', T_riseNoise, options.StdNoiseFloor);
    end

    % PASS 3: Event detection
    % Results Storage
    events = struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {});
    eventCount = 0;
    state = 'SEARCHING_ON';
    currentOnFrame = 1;
    onLevelMu = NaN;

    switch options.DecodeMode
        case "SparseSeek"
            for idx = 1:numel(dffTrace)
                currentDff = dffTrace(idx);
                k = frameTrace(idx);

                if strcmp(state, 'SEARCHING_ON')
                    if currentDff > T_trigger
                        chunkStart = max(1, k - microScanWindowSize);
                        chunkMeans = readIntensitiesRange(v, x1, x2, y1, y2, chunkStart, k);
                        chunkDff = (polaritySign * ((chunkMeans - roughF0) / dffDenom)) - baselineF0_percentile;

                        lastOffIdx = find(chunkDff <= T_riseNoise, 1, 'last');
                        if isempty(lastOffIdx)
                            currentOnFrame = chunkStart;
                        else
                            currentOnFrame = chunkStart + lastOffIdx;
                        end
                        currentOnFrame = min(frameCount, currentOnFrame);

                        onLevelMu = currentDff;
                        state = 'SEARCHING_OFF';
                    end
                else
                    onLevelMu = 0.9 * onLevelMu + 0.1 * currentDff;
                    T_fallNoise = onLevelMu - (options.StdNoiseFloor * baselineSigma);

                    if currentDff < T_trigger
                        chunkStart = max(currentOnFrame, k - microScanWindowSize);
                        chunkMeans = readIntensitiesRange(v, x1, x2, y1, y2, chunkStart, k);
                        chunkDff = (polaritySign * ((chunkMeans - roughF0) / dffDenom)) - baselineF0_percentile;

                        firstDropIdx = find(chunkDff < T_fallNoise, 1, 'first');
                        if isempty(firstDropIdx)
                            currentOffFrame = chunkStart;
                        else
                            currentOffFrame = chunkStart + firstDropIdx - 1;
                        end
                        currentOffFrame = min(frameCount, currentOffFrame);

                        eventCount = eventCount + 1;
                        events(eventCount).onFrame = currentOnFrame;
                        events(eventCount).offFrame = currentOffFrame;
                        events(eventCount).onTime = (currentOnFrame - 1) / frameRate;
                        events(eventCount).offTime = (currentOffFrame - 1) / frameRate;

                        state = 'SEARCHING_ON';
                    end
                end
            end

        case "StreamingRing"
            ringStart = max(1, startMacro - microScanWindowSize);
            ringFrames = zeros(0, 1);
            ringValues = zeros(0, 1);
            sampleIdx = 1;

            for frameIdx = ringStart:frameCount
                intensity = meanRoiIntensity(v, x1, x2, y1, y2, frameIdx);
                ringFrames(end+1, 1) = frameIdx;
                ringValues(end+1, 1) = intensity;

                if numel(ringFrames) > (microScanWindowSize + 1)
                    ringFrames(1) = [];
                    ringValues(1) = [];
                end

                while sampleIdx <= numel(frameTrace) && frameTrace(sampleIdx) < frameIdx
                    sampleIdx = sampleIdx + 1;
                end

                if sampleIdx <= numel(frameTrace) && frameTrace(sampleIdx) == frameIdx
                    currentDff = dffTrace(sampleIdx);
                    k = frameIdx;

                    if strcmp(state, 'SEARCHING_ON')
                        if currentDff > T_trigger
                            chunkStart = max(1, k - microScanWindowSize);
                            mask = ringFrames >= chunkStart;
                            ringDff = (polaritySign * ((ringValues(mask) - roughF0) / dffDenom)) - baselineF0_percentile;
                            ringF = ringFrames(mask);

                            lastOffIdx = find(ringDff <= T_riseNoise, 1, 'last');
                            if isempty(lastOffIdx)
                                currentOnFrame = chunkStart;
                            else
                                currentOnFrame = min(frameCount, ringF(lastOffIdx) + 1);
                            end

                            onLevelMu = currentDff;
                            state = 'SEARCHING_OFF';
                        end
                    else
                        onLevelMu = 0.9 * onLevelMu + 0.1 * currentDff;
                        T_fallNoise = onLevelMu - (options.StdNoiseFloor * baselineSigma);

                        if currentDff < T_trigger
                            chunkStart = max(currentOnFrame, k - microScanWindowSize);
                            mask = ringFrames >= chunkStart;
                            ringDff = (polaritySign * ((ringValues(mask) - roughF0) / dffDenom)) - baselineF0_percentile;
                            ringF = ringFrames(mask);

                            firstDropIdx = find(ringDff < T_fallNoise, 1, 'first');
                            if isempty(firstDropIdx)
                                currentOffFrame = chunkStart;
                            else
                                currentOffFrame = max(chunkStart, ringF(firstDropIdx) - 1);
                            end
                            currentOffFrame = min(frameCount, currentOffFrame);

                            eventCount = eventCount + 1;
                            events(eventCount).onFrame = currentOnFrame;
                            events(eventCount).offFrame = currentOffFrame;
                            events(eventCount).onTime = (currentOnFrame - 1) / frameRate;
                            events(eventCount).offTime = (currentOffFrame - 1) / frameRate;

                            state = 'SEARCHING_ON';
                        end
                    end

                    sampleIdx = sampleIdx + 1;
                end
            end
    end

    if strcmp(state, 'SEARCHING_OFF')
        currentOffFrame = frameCount;
        eventCount = eventCount + 1;
        events(eventCount).onFrame = currentOnFrame;
        events(eventCount).offFrame = currentOffFrame;
        events(eventCount).onTime = (currentOnFrame - 1) / frameRate;
        events(eventCount).offTime = (currentOffFrame - 1) / frameRate;
    end
    
    if options.Debug && ~isempty(frameTrace)
        % Debug plot: dF/F0 trace with detected events
        figure('Name', 'LED dF/F0 Trace and Detected Events');
        hold on;
        xBand = [frameTrace(1), frameTrace(end), frameTrace(end), frameTrace(1)];
        yBand = [-baselineSigma, -baselineSigma, baselineSigma, baselineSigma];
        patch(xBand, yBand, [0.85, 0.85, 0.85], 'FaceAlpha', 0.35, 'EdgeColor', 'none');
        plot(frameTrace, dffTrace, 'b-', 'LineWidth', 1.5);
        yline(T_trigger, 'r--', 'T\_trigger', 'LineWidth', 1.5);
        yline(T_riseNoise, 'g--', 'T\_riseNoise', 'LineWidth', 1.5);
        yline(0, 'k-', 'Baseline', 'LineWidth', 0.5);
        
        % Mark detected events as shaded regions
        for i = 1:eventCount
            onF = events(i).onFrame;
            offF = events(i).offFrame;
            yLim = ylim();
            patch([onF, offF, offF, onF], [yLim(1), yLim(1), yLim(2), yLim(2)], ...
                'yellow', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        end
        
        xlabel('Frame Number');
        ylabel('dF/F_0');
        title(sprintf('LED Event Detection (Percentile Baseline): %d events found', eventCount));
        legend('Baseline \pm 1\sigma', 'dF/F0 trace', 'T\_trigger', 'T\_riseNoise', 'Baseline', 'Detected events');
        grid on;
    end


    eventTable = struct2table(events);
end

function intensity = meanRoiIntensity(v, x1, x2, y1, y2, frameIdx)
    frame = read(v, frameIdx);
    roiPixels = mean(frame(y1:y2, x1:x2, :), 3);
    intensity = mean(roiPixels(:));
end

function intensities = readIntensitiesRange(v, x1, x2, y1, y2, startFrame, endFrame)
    if endFrame < startFrame
        intensities = zeros(0, 1);
        return;
    end

    n = endFrame - startFrame + 1;
    intensities = zeros(n, 1);
    writeIdx = 1;
    for frameIdx = startFrame:endFrame
        intensities(writeIdx) = meanRoiIntensity(v, x1, x2, y1, y2, frameIdx);
        writeIdx = writeIdx + 1;
    end
end

function p = percentileLikeRust(data, percentile)
    data = data(:);
    if isempty(data)
        p = NaN;
        return;
    end

    sortedData = sort(data);
    idx = round((percentile / 100) * (numel(sortedData) - 1)) + 1;
    idx = min(max(idx, 1), numel(sortedData));
    p = sortedData(idx);
end