function tests = testSpectrogramPrecompute
%TESTSPECTROGRAMPRECOMPUTE Tests for io.stimuli.spectrogram.precompute
    tests = functiontests(localfunctions);
end

%% Fixtures

function samples = makeSine(fs, frequencyHz, amplitude, durationSeconds)
    t = (0:round(fs * durationSeconds) - 1)' / fs;
    samples = amplitude * sin(2 * pi * frequencyHz * t);
end

%% Frequency domain

function testSineTonePeakBin(testCase)
    fs = 48000;
    spectrogramDb = io.stimuli.spectrogram.precompute(makeSine(fs, 1000, 0.8, 5), fs);

    testCase.verifyEqual(spectrogramDb.fs, fs);
    testCase.verifyEqual(spectrogramDb.frequency(1), 0);
    testCase.verifyEqual(spectrogramDb.frequency(end), fs / 2, 'AbsTol', 1e-9);
    testCase.verifyEqual(spectrogramDb.frequency(2) - spectrogramDb.frequency(1), ...
        fs / spectrogramDb.params.nfft, 'AbsTol', 1e-9);
    testCase.verifyEqual(size(spectrogramDb.time, 1), size(spectrogramDb.spectrogram, 2));

    [~, peakBin] = max(mean(spectrogramDb.spectrogram, 2));
    testCase.verifyEqual(spectrogramDb.frequency(peakBin), 1000);
end

function testNyquistToneStored(testCase)
    fs = 48000;
    spectrogramDb = io.stimuli.spectrogram.precompute(makeSine(fs, 20000, 0.8, 5), fs);

    [~, peakBin] = max(mean(spectrogramDb.spectrogram, 2));
    testCase.verifyEqual(spectrogramDb.frequency(peakBin), 20000);
    testCase.verifyEqual(spectrogramDb.frequency(end), fs / 2);
end

%% Time domain

function testTimeGridResolution(testCase)
    fs = 48000;
    samples = 0.1 * randn(fs, 1);
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    testCase.verifyEqual(spectrogramDb.time(1), ...
        spectrogramDb.params.windowSamples / 2 / fs, 'AbsTol', 1e-12);
    testCase.verifyEqual(spectrogramDb.time(2) - spectrogramDb.time(1), 0.001, 'AbsTol', 1e-12);
    testCase.verifyEqual(numel(spectrogramDb.time), ...
        floor((fs - spectrogramDb.params.windowSamples) / spectrogramDb.params.hopSamples) + 1);
    testCase.verifyEqual(all(diff(spectrogramDb.time) > 0), true);

    finer = io.stimuli.spectrogram.precompute(samples, fs, 'TimeResolution', 0.005);
    testCase.verifyEqual(finer.params.hopSamples, 240);
    testCase.verifyEqual(finer.time(2) - finer.time(1), 0.005, 'AbsTol', 1e-12);
end

function testShortInputClampsToSingleFrame(testCase)
    fs = 1000;
    samples = [0.1; -0.2; 0.3; -0.4; 0.5];
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    testCase.verifyEqual(numel(spectrogramDb.time), 4);
    testCase.verifyEqual(spectrogramDb.params.hopSamples, 1);
    testCase.verifyEqual(spectrogramDb.params.windowSamples, 2);
    testCase.verifyEqual(size(spectrogramDb.spectrogram, 1), 2);

    clamped = io.stimuli.spectrogram.precompute(samples(1:3), fs, 'WindowSeconds', 0.05);
    testCase.verifyEqual(numel(clamped.time), 1);
    testCase.verifyEqual(clamped.params.hopSamples, 1);
    testCase.verifyEqual(clamped.params.windowSamples, 3);

    singleSample = io.stimuli.spectrogram.precompute(0.5, fs);
    testCase.verifyEqual(numel(singleSample.time), 1);
    testCase.verifyEqual(singleSample.params.windowSamples, 2);
    testCase.verifyEqual(size(singleSample.spectrogram, 1), 2);
    testCase.verifyEqual(singleSample.spectrogram(:), 255 * ones(numel(singleSample.spectrogram), 1, 'uint8'));
    testCase.verifyEqual(singleSample.amplitudePeak(1), 0.5);

    silentSingle = io.stimuli.spectrogram.precompute(0, fs);
    testCase.verifyEqual(silentSingle.spectrogram(:), zeros(numel(silentSingle.spectrogram), 1, 'uint8'));
end

function testSilentInputStoredAtFloor(testCase)
    fs = 48000;
    samples = zeros(fs, 1);

    quantized = io.stimuli.spectrogram.precompute(samples, fs);
    testCase.verifyEqual(quantized.spectrogram(:), zeros(numel(quantized.spectrogram), 1, 'uint8'));
    testCase.verifyEqual(quantized.amplitudePeak(:), zeros(numel(quantized.amplitudePeak), 1));
    testCase.verifyEqual(quantized.dbFloor + double(quantized.spectrogram(1)) * quantized.dbStep, quantized.dbFloor);

    floats = io.stimuli.spectrogram.precompute(samples, fs, 'Precision', 'double');
    testCase.verifyEqual(floats.spectrogram(:), -Inf * ones(numel(floats.spectrogram), 1));
end

function testChunkBoundariesKeepTimeAlignment(testCase)
    fs = 48000;
    t = (0:5 * fs - 1)' / fs;
    samples = zeros(5 * fs, 1);
    samples(t < 2.5) = 0.5 * sin(2 * pi * 1000 * t(t < 2.5));
    samples(t >= 2.5) = 0.5 * sin(2 * pi * 4000 * t(t >= 2.5));
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    testCase.verifyGreaterThan(size(spectrogramDb.spectrogram, 2), 273);
    [~, firstBin] = max(mean(spectrogramDb.spectrogram(:, spectrogramDb.time < 2.5, 1), 2));
    [~, secondBin] = max(mean(spectrogramDb.spectrogram(:, spectrogramDb.time >= 2.6, 1), 2));
    testCase.verifyEqual(spectrogramDb.frequency(firstBin), 1000);
    testCase.verifyEqual(spectrogramDb.frequency(secondBin), 4000);
end

%% Channels

function testStereoChannelHandling(testCase)
    fs = 48000;
    left = makeSine(fs, 500, 0.5, 0.5);
    right = makeSine(fs, 3000, 0.25, 0.5);

    both = io.stimuli.spectrogram.precompute([left, right], fs);
    testCase.verifyEqual(both.params.nChannels, 2);
    testCase.verifyEqual(size(both.spectrogram, 3), 2);
    testCase.verifyEqual(size(both.amplitudeRms, 2), 2);

    mono = io.stimuli.spectrogram.precompute([left, right], fs, 'ChannelMode', 'mono');
    testCase.verifyEqual(mono.params.nChannels, 1);
    testCase.verifyEqual(size(mono.spectrogram, 3), 1);
    testCase.verifyEqual(size(mono.amplitudePeak, 2), 1);

    identical = io.stimuli.spectrogram.precompute([left, left], fs);
    identicalMono = io.stimuli.spectrogram.precompute([left, left], fs, 'ChannelMode', 'mono');
    testCase.verifyEqual(identicalMono.spectrogram, identical.spectrogram(:, :, 1));
end

%% Encoding and size

function testQuantizationRoundTrip(testCase)
    fs = 48000;
    rng(42);
    t = (0:fs - 1)' / fs;
    samples = 0.9 * sin(2 * pi * 700 * t) + 0.1 * sin(2 * pi * 5000 * t) + 1e-9 * randn(fs, 1);

    quantized = io.stimuli.spectrogram.precompute(samples, fs);
    testCase.verifyClass(quantized.spectrogram, 'uint8');

    floats = io.stimuli.spectrogram.precompute(samples, fs, 'Precision', 'double');
    dequantized = quantized.dbFloor + double(quantized.spectrogram) * quantized.dbStep;

    inRange = floats.spectrogram >= quantized.dbFloor;
    clippedMask = ~inRange;
    testCase.verifyTrue(any(clippedMask(:)));
    testCase.verifyEqual(dequantized(clippedMask), quantized.dbFloor * ones(nnz(clippedMask), 1));

    maxError = max(abs(dequantized(inRange) - floats.spectrogram(inRange)));
    testCase.verifyLessThan(maxError, quantized.dbStep / 2 + 1e-6);

    testCase.verifyEqual(max(dequantized(:)), 0, 'AbsTol', 1e-9);
    testCase.verifyGreaterThanOrEqual(min(dequantized(:)), quantized.dbFloor);
end

function testPrecisionSingle(testCase)
    fs = 48000;
    spectrogramDb = io.stimuli.spectrogram.precompute(makeSine(fs, 1000, 0.5, 1), fs, ...
        'Precision', 'single');

    testCase.verifyClass(spectrogramDb.spectrogram, 'single');
    [~, peakBin] = max(max(spectrogramDb.spectrogram, [], 2));
    testCase.verifyEqual(spectrogramDb.frequency(peakBin), 1000);
    testCase.verifyEqual(double(max(spectrogramDb.spectrogram(:))), 0, 'AbsTol', 1e-5);
end

function testOutputSmallerThanRawAudio(testCase)
    fs = 48000;
    samples = 0.5 * rand(fs, 1);
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    spectrogramBytes = numel(spectrogramDb.spectrogram);
    testCase.verifyLessThan(spectrogramBytes, 2 * numel(samples));
    testCase.verifyLessThan(spectrogramBytes, 8 * numel(samples));
end

%% Amplitude representation

function testAmplitudeVectorsTrackBurst(testCase)
    fs = 48000;
    t = (0:fs - 1)' / fs;
    samples = zeros(fs, 1);
    burstMask = t >= 0.4 & t < 0.6;
    samples(burstMask) = 0.5 * sin(2 * pi * 2000 * t(burstMask));
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    silentFrames = spectrogramDb.time >= 0.1 & spectrogramDb.time <= 0.3;
    burstFrames = spectrogramDb.time >= 0.42 & spectrogramDb.time <= 0.58;

    testCase.verifyEqual(max(spectrogramDb.amplitudePeak(silentFrames)), 0);
    testCase.verifyEqual(max(abs(spectrogramDb.amplitudeMin(silentFrames))), 0);
    testCase.verifyEqual(max(abs(spectrogramDb.amplitudeMax(silentFrames))), 0);
    testCase.verifyEqual(max(spectrogramDb.amplitudeRms(silentFrames)), 0, 'AbsTol', 1e-12);

    testCase.verifyLessThan(min(spectrogramDb.amplitudeMin(burstFrames)), -0.4);
    testCase.verifyGreaterThan(max(spectrogramDb.amplitudeMax(burstFrames)), 0.4);
    testCase.verifyGreaterThan(min(spectrogramDb.amplitudePeak(burstFrames)), 0.45);
    testCase.verifyLessThan( ...
        abs(mean(spectrogramDb.amplitudeRms(burstFrames)) - 0.5 / sqrt(2)), 0.02);
end

%% Parameters and validation

function testParamsDefaults(testCase)
    fs = 48000;
    spectrogramDb = io.stimuli.spectrogram.precompute(0.1 * randn(2 * fs, 1), fs);

    testCase.verifyEqual(spectrogramDb.params.hopSamples, 48);
    testCase.verifyEqual(spectrogramDb.params.windowSamples, 96);
    testCase.verifyEqual(spectrogramDb.params.nfft, 96);
    testCase.verifyEqual(spectrogramDb.params.overlapRatio, 0.5);
    testCase.verifyEqual(spectrogramDb.params.windowFunction, 'hann');
    testCase.verifyEqual(spectrogramDb.params.channelMode, 'all');
    testCase.verifyEqual(spectrogramDb.params.precision, 'uint8');
    testCase.verifyEqual(spectrogramDb.params.reference, 'peak');
    testCase.verifyEqual(spectrogramDb.params.timeResolution, 0.001, 'AbsTol', 1e-12);
    testCase.verifyEqual(spectrogramDb.dbStep, 80 / 255);
    testCase.verifyEqual(spectrogramDb.dbFloor, -80);
    testCase.verifyEqual(spectrogramDb.params.displayFloorPercentile, 50);
end

function testIdentityPassthrough(testCase)
    fs = 48000;
    identified = io.stimuli.spectrogram.precompute(0.1 * randn(fs, 1), fs, ...
        'StimfileName', 'stimA.flac', 'Title', 'Stim A');
    testCase.verifyEqual(identified.stimfileName, 'stimA.flac');
    testCase.verifyEqual(identified.title, 'Stim A');

    bare = io.stimuli.spectrogram.precompute(0.1 * randn(fs, 1), fs);
    testCase.verifyEqual(bare.stimfileName, '');
    testCase.verifyEqual(bare.title, '');
end

function testDisplayFloorHint(testCase)
    fs = 48000;
    t = (0:fs - 1)' / fs;
    samples = 0.5 * sin(2 * pi * 1000 * t) + 0.005 * randn(fs, 1);
    spectrogramDb = io.stimuli.spectrogram.precompute(samples, fs);

    testCase.verifyEqual(numel(spectrogramDb.params.displayFloor), 1);
    testCase.verifyLessThan(spectrogramDb.params.displayFloor(1), -20);
    testCase.verifyGreaterThanOrEqual(spectrogramDb.params.displayFloor(1), spectrogramDb.dbFloor);

    stereo = io.stimuli.spectrogram.precompute([samples, samples], fs);
    testCase.verifyEqual(numel(stereo.params.displayFloor), 2);
    testCase.verifyEqual(stereo.params.displayFloor(1), spectrogramDb.params.displayFloor(1));

    silent = io.stimuli.spectrogram.precompute(zeros(fs, 1), fs);
    testCase.verifyEqual(silent.params.displayFloor(1), silent.dbFloor);

    noStretch = io.stimuli.spectrogram.precompute(samples, fs, 'DisplayFloorPercentile', 0);
    testCase.verifyLessThanOrEqual(noStretch.params.displayFloor(1), spectrogramDb.params.displayFloor(1));
end

function testInvalidChoiceErrors(testCase)
    testCase.verifyError(@() io.stimuli.spectrogram.precompute(zeros(100, 1), 48000, ...
        'ChannelMode', 'bogus'), 'io:stimuli:spectrogram:precompute:InvalidChoice');
    testCase.verifyError(@() io.stimuli.spectrogram.precompute(zeros(100, 1), 48000, ...
        'Precision', 'float16'), 'io:stimuli:spectrogram:precompute:InvalidChoice');
end
