function eventTable = ledPulses(videoFilePath, options)
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

    libraryName = 'trigger_extract';

    % Debug mode always uses MATLAB for plotting
    if options.Debug
        eventTable = runMatlabFallback(videoFilePath, options);
        return
    end

    % In non-debug mode, try to use FFI, otherwise fall back to MATLAB implementation
    ffiLibraryLoaded = false;
    try
        triggerExtract.loadFFILib();
        ffiLibraryLoaded = true;
    catch ME
        warning('Failed to load FFI library, falling back to MATLAB implementation.\nError: %s', getReport(ME));
    end

    if ffiLibraryLoaded
        try
            cOptions = buildCOptions(options);
            [resultPtr, ~] = calllib( ...
                libraryName, ...
                'led_pulses_extract', ...
                char(videoFilePath), ...
                cOptions.roi_x_start, ...
                cOptions.roi_x_end, ...
                cOptions.roi_y_start, ...
                cOptions.roi_y_end, ...
                cOptions.decode_mode, ...
                cOptions.pulse_polarity, ...
                cOptions.scan_step_size, ...
                cOptions.threshold_calibration_step_size, ...
                cOptions.baseline_frame_start, ...
                cOptions.baseline_frame_end, ...
                cOptions.std_threshold, ...
                cOptions.std_noise_floor, ...
                cOptions.baseline_percentile, ...
                cOptions.absolute_dff_threshold ...
            );

            if isempty(resultPtr) || resultPtr.isNull
                error('triggerExtract:ledPulses:FfiNullResult', ...
                    'FFI extraction returned a null result pointer.');
            end

            cResult = resultPtr.Value;
            statusCode = double(cResult.status_code);

            if statusCode ~= 0
                errMsg = readCErrorMessage(cResult);
                if strlength(errMsg) == 0
                    errMsg = sprintf('FFI status code: %d', statusCode);
                end

                calllib(libraryName, 'led_pulses_free_owned_result', resultPtr);
                error('triggerExtract:ledPulses:FfiFailure', 'FFI extraction failed: %s', errMsg);
            end

            eventTable = cResultToTable(cResult);
            calllib(libraryName, 'led_pulses_free_owned_result', resultPtr);

        catch ME
            warning('FFI extraction failed.\nFalling back to MATLAB implementation.\nError: %s', getReport(ME));
            eventTable = runMatlabFallback(videoFilePath, options);
        end
    else
        eventTable = runMatlabFallback(videoFilePath, options);
    end
end

function eventTable = runMatlabFallback(videoFilePath, options)
    matlabArgs = namedargs2cell(options);
    eventTable = extractLedTimings(videoFilePath, matlabArgs{:});
end

function cOptions = buildCOptions(options)
    cOptions = libstruct('LedPulseOptionsC');

    cOptions.roi_x_start = options.RoiXRange(1);
    cOptions.roi_x_end = options.RoiXRange(2);
    cOptions.roi_y_start = options.RoiYRange(1);
    cOptions.roi_y_end = options.RoiYRange(2);
    cOptions.decode_mode = int32(decodeModeToCode(options.DecodeMode));
    cOptions.pulse_polarity = int32(polarityToCode(options.PulsePolarity));
    cOptions.scan_step_size = uint64(options.ScanStepSize);
    cOptions.threshold_calibration_step_size = uint64(options.ThresholdCalibrationStepSize);

    % Rust baseline_frames_range is 0-based inclusive, convert from MATLAB's 1-based inputs.
    if ~isempty(options.BaselineFrames)
        baseStart = min(options.BaselineFrames);
        baseEnd = max(options.BaselineFrames);
    else
        baseStart = options.BaselineFramesRange(1);
        baseEnd = options.BaselineFramesRange(2);
    end

    cOptions.baseline_frame_start = uint64(max(0, round(baseStart) - 1));
    cOptions.baseline_frame_end = uint64(max(0, round(baseEnd) - 1));
    cOptions.std_threshold = options.StdThreshold;
    cOptions.std_noise_floor = options.StdNoiseFloor;
    cOptions.baseline_percentile = options.BaselinePercentile;
    cOptions.absolute_dff_threshold = options.AbsoluteDffThreshold;
end

function code = decodeModeToCode(decodeMode)
    if decodeMode == "SparseSeek"
        code = 0;
    else
        code = 1;
    end
end

function code = polarityToCode(polarity)
    if polarity == "OnPulses"
        code = 0;
    else
        code = 1;
    end
end

function eventTable = cResultToTable(cResult)
    eventCount = double(cResult.len);
    if eventCount == 0
        eventTable = emptyEventTable();
        return;
    end

    eventData = cResult.events;
    if isempty(eventData)
        eventTable = emptyEventTable();
        return;
    end

    if isa(eventData, 'lib.pointer')
        try
            setdatatype(eventData, 'LedEventC', eventCount, 1);
        catch
            setdatatype(eventData, 'LedEventCPtr', eventCount, 1);
        end
        cEvents = eventData.Value;
    elseif isstruct(eventData)
        cEvents = eventData;
    else
        error('triggerExtract:ledPulses:UnexpectedEventsType', ...
            'Unexpected FFI events field type: %s', class(eventData));
    end

    onFrame = reshape(double([cEvents.on_frame]), [], 1);
    offFrame = reshape(double([cEvents.off_frame]), [], 1);
    onTime = reshape(double([cEvents.on_time]), [], 1);
    offTime = reshape(double([cEvents.off_time]), [], 1);

    eventTable = table(onFrame, offFrame, onTime, offTime, ...
        'VariableNames', {'onFrame', 'offFrame', 'onTime', 'offTime'});
end

function errMsg = readCErrorMessage(cResult)
    errMsg = "";

    if ~isfield(cResult, 'error_message') || isempty(cResult.error_message)
        return;
    end

    errorField = cResult.error_message;
    if ischar(errorField)
        errMsg = string(errorField);
        return;
    elseif isstring(errorField)
        errMsg = errorField;
        return;
    elseif ~isa(errorField, 'lib.pointer')
        return;
    end

    try
        setdatatype(errorField, 'cstring');
        raw = errorField.Value;
        if ischar(raw)
            errMsg = string(raw);
        end
    catch
        try
            setdatatype(errorField, 'int8Ptr', 1, 2048);
            raw = errorField.Value;
            raw = raw(:)';
            nulIdx = find(raw == 0, 1, 'first');
            if isempty(nulIdx)
                nulIdx = numel(raw) + 1;
            end
            errMsg = string(char(raw(1:nulIdx-1)));
        catch
            % Keep empty error message when pointer conversion fails.
        end
    end
end

function eventTable = emptyEventTable()
    eventTable = table(zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
        'VariableNames', {'onFrame', 'offFrame', 'onTime', 'offTime'});
end
