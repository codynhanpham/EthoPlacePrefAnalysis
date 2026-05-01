function eventTable = extractLedTimings(videoFilePath, options)
    %%EXTRACTLEDTIMINGS Extracts LED event timings from a video file.
    % The default parameters are set to work with typical top-mounted IR LED in the current Place Preference setup at Oviedo Lab

    
    arguments
        videoFilePath {mustBeTextScalar, mustBeFile}
        options.RoiXRange (1,2) double {mustBeInRange(options.RoiXRange, 0, 1)} = [0.5-1/16, 0.5+1/16] % Location of ROI/LED in normalized coordinates (centered around middle of frame by default)
        options.RoiYRange (1,2) double {mustBeInRange(options.RoiYRange, 0, 1)} = [0.08, 0.215] % Location of ROI/LED in normalized coordinates (default is typical for top-mounted IR LED in 16:9 videos)
        options.ScanStepSize (1,1) double {mustBeInteger, mustBePositive} = 4*30 % Scan every 4 seconds at 30fps for initial detection
        options.BaselineFrames (1,:) double {mustBeInteger, mustBePositive} = 6:35 % 1s at 30fps after first 5 frames
        options.StdThreshold (1,1) double {mustBePositive} = 6.5
        options.StdNoiseFloor (1,1) double {mustBePositive} = 5
        options.BaselinePercentile (1,1) double {mustBeInRange(options.BaselinePercentile, 0, 50)} = 10
        options.AbsoluteDffThreshold (1,1) double {mustBeNonnegative} = 0.001

        options.Debug (1,1) logical = false % If true, will show intermediate plots and outputs for debugging
    end
    
    v = VideoReader(videoFilePath);
    W = v.Width; H = v.Height;
    
    % ROI conversion
    x1 = max(1, round(options.RoiXRange(1) * W));
    x2 = min(W, round(options.RoiXRange(2) * W));
    y1 = max(1, round(options.RoiYRange(1) * H));
    y2 = min(H, round(options.RoiYRange(2) * H));

    if options.Debug
        figure('Name', 'LED Timing Extraction - ROI Confirmation');
        imshow(read(v, options.BaselineFrames(1))); hold on;
        rectangle('Position', [x1, y1, x2-x1, y2-y1], 'EdgeColor', 'r', 'LineWidth', 2);
        title('Red Box Shows the ROI Used for LED Timing Extraction');
        drawnow;
    end
    
    % Baseline Analysis (metric = mean ROI intensity, normalized to dF/F0)
    % Use rough estimate from baseline frames for first pass
    baseChunk = read(v, [min(options.BaselineFrames), max(options.BaselineFrames)]);
    baseGray = squeeze(mean(baseChunk(y1:y2, x1:x2, :, :), 3));
    baseIntensities = squeeze(mean(baseGray, [1 2]));
    roughF0 = mean(baseIntensities);
    dffDenom = max(roughF0, eps);
    
    % Starting after baseline
    startMacro = max(options.BaselineFrames) + 1;
    scanFrames = startMacro:options.ScanStepSize:v.NumFrames;
    numScanFrames = numel(scanFrames);
    
    % ========== PASS 1: Collect dF/F0 trace ==========
    dffTrace = zeros(numScanFrames, 1);
    frameTrace = scanFrames(:);
    
    for idx = 1:numScanFrames
        k = scanFrames(idx);
        frame = read(v, k);
        roiPixels = mean(frame(y1:y2, x1:x2, :), 3);
        currentMean = mean(roiPixels(:));
        currentDff = (currentMean - roughF0) / dffDenom;
        dffTrace(idx) = currentDff;
    end
    
    % ========== Compute robust baseline from percentile of collected trace ==========
    baselineF0_percentile = prctile(dffTrace, options.BaselinePercentile);
    
    % Recompute dF/F0 relative to percentile baseline
    dffTrace = dffTrace - baselineF0_percentile;
    
    % Compute thresholds anchored to zero baseline using baseline-like samples
    baselineCut = prctile(dffTrace, options.BaselinePercentile);
    baselineSamples = dffTrace(dffTrace <= baselineCut);
    if numel(baselineSamples) < 2
        baselineSamples = dffTrace;
    end
    baselineSigma = std(baselineSamples);
    baselineMu = 0;
    
    T_trigger = max(options.StdThreshold * baselineSigma, options.AbsoluteDffThreshold);
    T_riseNoise = options.StdNoiseFloor * baselineSigma;
    
    if options.Debug
        fprintf('--- LED Detection Thresholds (Robust Percentile-Based) ---\n');
        fprintf('Baseline percentile: %d%%\n', options.BaselinePercentile);
        fprintf('Baseline dF/F0 level: %.6f\n', baselineF0_percentile);
        fprintf('Stats (after normalization): mu=%.6f, sigma=%.6f\n', baselineMu, baselineSigma);
        fprintf('T_trigger: %.6f (max of: %.3f*sigma, absolute floor %.6f)\n', T_trigger, options.StdThreshold, options.AbsoluteDffThreshold);
        fprintf('T_riseNoise: %.6f (%.3f*sigma)\n', T_riseNoise, options.StdNoiseFloor);
    end
    
    % ========== PASS 2: Event detection on normalized trace ==========
    % Results Storage
    events = struct('onFrame', {}, 'offFrame', {}, 'onTime', {}, 'offTime', {});
    eventCount = 0;
    state = 'SEARCHING_ON';
    currentOnFrame = [];
    onLevelMu = NaN;
    
    for idx = 1:numel(dffTrace)
        currentDff = dffTrace(idx);
        k = frameTrace(idx);
        
        switch state
            case 'SEARCHING_ON'
                if currentDff > T_trigger
                    % Micro-scan for exact Start of Rise
                    chunkStart = max(1, k - options.ScanStepSize);
                    chunk = read(v, [chunkStart, k]);
                    roiChunk = mean(chunk(y1:y2, x1:x2, :, :), 3);
                    chunkMeans = squeeze(mean(roiChunk, [1 2]));
                    chunkDff = ((chunkMeans - roughF0) / dffDenom) - baselineF0_percentile;
                    
                    lastOffIdx = find(chunkDff <= T_riseNoise, 1, 'last');
                    if isempty(lastOffIdx), currentOnFrame = chunkStart;
                    else, currentOnFrame = chunkStart + lastOffIdx; end
                    
                    onLevelMu = currentDff;
                    state = 'SEARCHING_OFF';
                end
                
            case 'SEARCHING_OFF'
                % Track the ON intensity for a relative fall threshold
                onLevelMu = 0.9 * onLevelMu + 0.1 * currentDff;
                T_fallNoise = onLevelMu - (options.StdNoiseFloor * baselineSigma);
                
                if currentDff < T_trigger
                    % Micro-scan for exact Start of Fall
                    chunkStart = max(currentOnFrame, k - options.ScanStepSize);
                    chunk = read(v, [chunkStart, k]);
                    roiChunk = mean(chunk(y1:y2, x1:x2, :, :), 3);
                    chunkMeans = squeeze(mean(roiChunk, [1 2]));
                    chunkDff = ((chunkMeans - roughF0) / dffDenom) - baselineF0_percentile;
                    
                    % First frame that drops below the high noise floor
                    firstDropIdx = find(chunkDff < T_fallNoise, 1, 'first');
                    if isempty(firstDropIdx), currentOffFrame = chunkStart;
                    else, currentOffFrame = chunkStart + firstDropIdx - 2; end
                    
                    % Log the Event
                    eventCount = eventCount + 1;
                    events(eventCount).onFrame = currentOnFrame;
                    events(eventCount).offFrame = currentOffFrame;
                    events(eventCount).onTime = (currentOnFrame - 1) / v.FrameRate;
                    events(eventCount).offTime = (currentOffFrame - 1) / v.FrameRate;
                    
                    state = 'SEARCHING_ON'; % Look for next pulse
                end
        end
    end
    
    if options.Debug
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