function spectrogramDb = precompute(samples, fs, kvargs)
    %%PRECOMPUTE Pre-compute a compact, self-describing spectrogram database struct from audio samples.
    %   Converts a single audio segment into a spectrogram database struct designed for
    %   HDF5 storage. This function computes the database in memory only; a future writer
    %   maps its fields 1:1 onto HDF5 datasets following the repository's HDF5 conventions.
    %
    %   Design properties:
    %       - COMPACT: the spectrogram is stored as dB quantized to uint8 by default
    %         (256 levels spanning ['DbFloor', 0] dB relative to the global peak), which is
    %         smaller than the raw 16-bit audio while keeping the full DC-to-Nyquist
    %         frequency band (no bins are dropped).
    %       - PIXEL-SPACE DECOUPLED: the full time x frequency grid is stored as data,
    %         not as an image; zooming in/out and any pixel-space aggregation happen
    %         downstream at display time.
    %       - NYQUIST ACCURATE: all bins from DC up to and including Nyquist are kept,
    %         with the frequency vector returned alongside.
    %       - CONTROLLED TIME RESOLUTION: the frame hop defaults to 1 ms
    %         ('TimeResolution') and becomes coarser only when limited by the audio input
    %         (segments shorter than one hop).
    %       - AMPLITUDE: per-frame RMS, peak (max-abs), and signed min/max are stored on
    %         the same time grid, so spectrogram and amplitude views stay aligned.
    %
    %   USAGE:
    %       spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs)
    %       spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs, 'TimeResolution', 0.010)
    %
    %   INPUTS:
    %       samples: N x C numeric matrix of audio samples (N samples, C channels). Matches
    %           the 'samples' output of io.stimuli.metadata2stimsamples. Typically in
    %           [-1, 1] from audioread, or in native integer format; converted to double
    %           internally. Amplitude values (RMS, peak, min, max) are reported in the
    %           input's scale. A vector input is treated as N x 1 mono.
    %       fs: sample rate in Hz.
    %
    %   Name-Value Pair Arguments:
    %       'TimeResolution': (double) Frame hop duration in seconds. Default 0.001 (1 ms).
    %           Clamped to at least 1 sample, and to the input length when the audio is
    %           shorter than one hop.
    %       'WindowSeconds': (double) Hann window duration in seconds. Default is
    %           2 x 'TimeResolution' (50% overlap). Sets the frequency resolution to
    %           fs/windowSamples. Clamped to the input length when the audio is shorter
    %           than the window; a single input sample is zero-padded to the 2-sample
    %           minimum window.
    %       'ChannelMode': (text) 'all' computes one spectrogram per input channel
    %           (default); 'mono' averages the channels before the STFT.
    %       'Precision': (text) 'uint8' stores dB quantized to 256 levels spanning
    %           ['DbFloor', 0] dB (default, smallest, display-grade); 'single' or 'double'
    %           stores dB values as floats without quantization (analysis-grade, larger).
    %       'DbFloor': (double) dB below the global peak where uint8 quantization starts
    %           clipping. Default -80. Quantization step is -DbFloor/255 (~0.31 dB).
    %       'DisplayFloorPercentile': (double) Percentile (0-100) of each channel's dB
    %           values used to estimate the noise floor for display contrast. The result
    %           is stored in params.displayFloor as a non-destructive hint: viewers
    %           (io.stimuli.spectrogram.plot) use it as the default color-limit floor so
    %           quiet areas render white instead of mid-gray. Default 50 (the median, a
    %           robust noise-floor estimate). Set 0 to use the
    %           quietest value; the stored spectrogram is never modified by this option.
    %       'StimfileName': (text) File name (with extension) of the stimulus file the
    %           samples came from (e.g. the 'stimfileName' output of
    %           io.stimuli.metadata2stimsamples). Passed through to the output and used
    %           by io.stimuli.spectrogram.exportHdf5 for group nesting. Default "".
    %       'Title': (text) Title of the stimulus (e.g. the 'title' output of
    %           io.stimuli.metadata2stimsamples). Passed through to the output and used
    %           by io.stimuli.spectrogram.exportHdf5 for group nesting. Default "".
    %
    %   OUTPUTS:
    %       spectrogramDb: struct containing the pre-computed database:
    %           fs: sample rate (Hz).
    %           stimfileName: pass-through stimulus file name (with extension); "" when
    %               'StimfileName' was not provided.
    %           title: pass-through stimulus title; "" when 'Title' was not provided.
    %           time: F x 1 double, frame-center times in seconds relative to the segment
    %               start (0 = first sample).
    %           frequency: B x 1 double, bin-center frequencies in Hz from 0 to Nyquist
    %               inclusive (B = nfft/2 + 1).
    %           spectrogram: B x F x C array (bins x time-frames x channels). uint8
    %               quantized dB when Precision='uint8'; single/double dB values otherwise.
    %               All-silent inputs are stored at the floor: level 0 (uint8) or -Inf dB
    %               (single/double), instead of a misleading full-scale value.
    %           dbFloor: dB value of quantization level 0.
    %           dbStep: dB per uint8 level (-dbFloor/255).
    %           amplitudeRms: F x C double, per-frame RMS (window-power corrected).
    %           amplitudePeak: F x C double, per-frame max |x| (from raw frame samples).
    %           amplitudeMin: F x C double, per-frame signed minimum (raw frame samples).
    %           amplitudeMax: F x C double, per-frame signed maximum (raw frame samples).
    %           params: struct with all computation parameters (hopSamples, windowSamples,
    %               windowFunction, overlapRatio, nfft, nChannels, channelMode,
    %               timeResolution, precision, dbFloor, dbStep, reference, displayFloor,
    %               created).
    %
    %   Dequantization (Precision='uint8'):
    %       dB = dbFloor + double(spectrogram) * dbStep
    %
    %   On-disk note for the future HDF5 writer: write the spectrogram transposed so
    %   external readers see (time, frequency[, channel]) per the repository's
    %   hdf5_axis_order convention (MATLAB h5read reverses axes), with gzip compression
    %   and chunks along the time axis.
    %
    %   See also: io.stimuli.metadata2stimsamples, io.stimuli.spectrogram.exportHdf5, sdTable.makeSingleSubjectHdf5

    arguments
        samples {mustBeNonempty, mustBeNumeric, mustBeFinite}
        fs (1,1) {mustBePositive, mustBeFinite}
        kvargs.TimeResolution (1,1) double {mustBePositive, mustBeFinite} = 0.001
        kvargs.WindowSeconds double = []
        kvargs.ChannelMode {mustBeTextScalar} = "all"
        kvargs.Precision {mustBeTextScalar} = "uint8"
        kvargs.DbFloor (1,1) double {mustBeNegative, mustBeFinite} = -80
        kvargs.DisplayFloorPercentile (1,1) double {mustBeInRange(kvargs.DisplayFloorPercentile, 0, 100)} = 50
        kvargs.StimfileName {mustBeTextScalar} = ""
        kvargs.Title {mustBeTextScalar} = ""
    end

    channelMode = localValidateChoice(kvargs.ChannelMode, {'all', 'mono'});
    precisionMode = localValidateChoice(kvargs.Precision, {'uint8', 'single', 'double'});
    fs = double(fs);

    windowSeconds = kvargs.WindowSeconds;
    if isempty(windowSeconds)
        windowSeconds = 2 * kvargs.TimeResolution;
    end
    if ~isscalar(windowSeconds) || ~isnumeric(windowSeconds) || ~isfinite(windowSeconds) || windowSeconds <= 0
        error("io:stimuli:spectrogram:precompute:InvalidWindowSeconds", ...
            "'WindowSeconds' must be a positive scalar duration in seconds. Got: %s", ...
            mat2str(windowSeconds));
    end

    samples = double(samples);
    if isvector(samples)
        samples = samples(:);
    end
    if strcmpi(channelMode, 'mono')
        samples = mean(samples, 2);
    end
    [nSamples, nChannels] = size(samples);

    hopSamples = max(1, round(fs * kvargs.TimeResolution));
    if nSamples < hopSamples
        hopSamples = nSamples;
    end
    windowSamples = max(2, round(fs * windowSeconds));
    if nSamples < windowSamples
        if nSamples >= 2
            windowSamples = nSamples;
        else
            samples = [zeros(1, nChannels); samples];
            windowSamples = 2;
            nSamples = windowSamples;
        end
    end
    nfft = windowSamples;
    nBins = floor(nfft / 2) + 1;

    frameCount = floor((nSamples - windowSamples) / hopSamples) + 1;
    time = ((0:frameCount - 1)' * hopSamples + windowSamples / 2) / fs;
    frequency = ((0:nBins - 1)' * fs) / nfft;

    window = 0.5 * (1 - cos(2 * pi * (0:windowSamples - 1)' / windowSamples));

    chunkFrames = max(1, ceil(2^18 / windowSamples));
    magnitudes = zeros(nBins, frameCount, nChannels, 'single');
    amplitudeRms = zeros(frameCount, nChannels);
    amplitudePeak = zeros(frameCount, nChannels);
    amplitudeMin = zeros(frameCount, nChannels);
    amplitudeMax = zeros(frameCount, nChannels);
    windowPowerCorrection = mean(window.^2);

    for c = 1:nChannels
        channelSamples = samples(:, c);
        for chunkStart = 1:chunkFrames:frameCount
            chunkEnd = min(chunkStart + chunkFrames - 1, frameCount);
            chunkLength = chunkEnd - chunkStart + 1;
            frames = zeros(windowSamples, chunkLength);
            for f = 1:chunkLength
                frameStart = (chunkStart + f - 2) * hopSamples + 1;
                frames(:, f) = channelSamples(frameStart:frameStart + windowSamples - 1);
            end
            windowed = frames .* window;
            spectrum = fft(windowed, [], 1);
            magnitudes(:, chunkStart:chunkEnd, c) = abs(spectrum(1:nBins, :));
            minima = min(frames, [], 1).';
            maxima = max(frames, [], 1).';
            amplitudeMin(chunkStart:chunkEnd, c) = minima;
            amplitudeMax(chunkStart:chunkEnd, c) = maxima;
            amplitudePeak(chunkStart:chunkEnd, c) = max(maxima, -minima);
            amplitudeRms(chunkStart:chunkEnd, c) = sqrt(mean(windowed.^2, 1) / windowPowerCorrection).';
        end
    end

    dbFloor = kvargs.DbFloor;
    dbStep = -dbFloor / 255;
    peakMagnitude = double(max(magnitudes(:)));
    if peakMagnitude <= eps
        switch precisionMode
            case 'uint8'
                spectrogram = zeros(nBins, frameCount, nChannels, 'uint8');
            case 'single'
                spectrogram = repmat(single(-Inf), nBins, frameCount, nChannels);
            otherwise
                spectrogram = repmat(-Inf, nBins, frameCount, nChannels);
        end
    else
        switch precisionMode
            case 'uint8'
                spectrogram = zeros(nBins, frameCount, nChannels, 'uint8');
            case 'single'
                spectrogram = zeros(nBins, frameCount, nChannels, 'single');
            otherwise
                spectrogram = zeros(nBins, frameCount, nChannels, 'double');
        end
        for c = 1:nChannels
            for chunkStart = 1:chunkFrames:frameCount
                chunkEnd = min(chunkStart + chunkFrames - 1, frameCount);
                spectrogram(:, chunkStart:chunkEnd, c) = localEncodeTile( ...
                    magnitudes(:, chunkStart:chunkEnd, c), peakMagnitude, dbFloor, dbStep, precisionMode);
            end
        end
    end

    % MATLAB drops explicitly-created trailing singleton dimensions, so mono outputs
    % are normalized back to 3-D (bins x time-frames x channels) here.
    spectrogram = reshape(spectrogram, nBins, frameCount, nChannels);

    % Noise-floor hint for display contrast: the 'DisplayFloorPercentile' percentile of
    % each channel's stored dB values. Non-destructive: the stored dB values are not
    % modified; viewers use this as the default color-limit floor so quiet areas map to
    % the colormap's quiet end (white) instead of mid-gray.
    displayFloor = zeros(1, nChannels);
    for c = 1:nChannels
        encodedValues = double(reshape(spectrogram(:, :, c), [], 1));
        if strcmpi(precisionMode, 'uint8')
            encodedValues = dbFloor + encodedValues * dbStep;
        end
        percentileIndex = max(1, ceil(kvargs.DisplayFloorPercentile / 100 * numel(encodedValues)));
        sortedValues = sort(encodedValues);
        displayFloor(c) = min(max(sortedValues(percentileIndex), dbFloor), 0);
    end

    spectrogramDb = struct();
    spectrogramDb.fs = fs;
    spectrogramDb.stimfileName = char(string(kvargs.StimfileName));
    spectrogramDb.title = char(string(kvargs.Title));
    spectrogramDb.time = time;
    spectrogramDb.frequency = frequency;
    spectrogramDb.spectrogram = spectrogram;
    spectrogramDb.dbFloor = dbFloor;
    spectrogramDb.dbStep = dbStep;
    spectrogramDb.amplitudeRms = amplitudeRms;
    spectrogramDb.amplitudePeak = amplitudePeak;
    spectrogramDb.amplitudeMin = amplitudeMin;
    spectrogramDb.amplitudeMax = amplitudeMax;
    spectrogramDb.params = struct( ...
        'hopSamples', hopSamples, ...
        'windowSamples', windowSamples, ...
        'windowFunction', 'hann', ...
        'overlapRatio', 1 - hopSamples / windowSamples, ...
        'nfft', nfft, ...
        'nChannels', nChannels, ...
        'channelMode', channelMode, ...
        'timeResolution', hopSamples / fs, ...
        'precision', precisionMode, ...
        'dbFloor', dbFloor, ...
        'dbStep', dbStep, ...
        'reference', 'peak', ...
        'displayFloor', displayFloor, ...
        'displayFloorPercentile', kvargs.DisplayFloorPercentile, ...
        'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
end


function tile = localEncodeTile(magnitudesTile, peakMagnitude, dbFloor, dbStep, precisionMode)
    magnitudesDb = 20 * log10(max(magnitudesTile, eps) ./ peakMagnitude);
    switch precisionMode
        case 'uint8'
            levels = round((magnitudesDb - dbFloor) / dbStep);
            tile = uint8(min(max(levels, 0), 255));
        case 'single'
            tile = single(magnitudesDb);
        otherwise
            tile = magnitudesDb;
    end
end


function choice = localValidateChoice(value, allowed)
    choice = lower(char(string(value)));
    if ~ismember(choice, allowed)
        error("io:stimuli:spectrogram:precompute:InvalidChoice", ...
            "Invalid choice '%s'. Must be one of: %s.", ...
            char(string(value)), strjoin(allowed, ', '));
    end
end
