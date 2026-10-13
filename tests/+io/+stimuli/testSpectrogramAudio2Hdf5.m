function tests = testSpectrogramAudio2Hdf5
%TESTSPECTROGRAMAUDIO2HDF5 Tests for io.stimuli.spectrogram.audio2hdf5
    tests = functiontests(localfunctions);
end

%% Fixtures

function [wavFiles, binaryFile, cleanup] = makeAudioFixture(fileSpecs)
    % Creates small wav files plus a fake 'metadata_extract' binary (a .bat that
    % echoes canned JSON metadata matching the requested input file), so the
    % end-to-end pipeline can run without real chaptered .flac recordings.
    folder = fullfile(tempdir, sprintf('testAudio2Hdf5_%d', round(rand * 1e9)));
    if ~exist(folder, 'dir'), mkdir(folder); end
    cleanup = onCleanup(@() localRmdirIfExists(folder));

    wavFiles = cell(numel(fileSpecs), 1);
    batLines = {'@echo off'};
    for k = 1:numel(fileSpecs)
        spec = fileSpecs(k);
        wavFile = fullfile(folder, sprintf('%s.wav', spec.fileTag));
        t = (0:3 * spec.fs - 1)' / spec.fs;
        audiowrite(wavFile, 0.5 * sin(2 * pi * 1000 * t), spec.fs);
        wavFiles{k} = wavFile;

        jsonPath = strrep(wavFile, '\', '\\');
        chapterJson = strjoin(arrayfun(@(c) sprintf('{"title": "%s", "startsample": %d, "timestamp": %.6f, "description": []}', c.title, c.start, c.timestamp), spec.chapters, 'UniformOutput', false), ', ');
        batLines{end+1} = sprintf('if /I "%%~2"=="%s" echo {"sample_rate": %d, "path": "%s", "chapters": [%s]}', ...
            wavFile, spec.fs, jsonPath, chapterJson);
    end
    binaryFile = fullfile(folder, 'fake_metadata_extract.bat');
    fid = fopen(binaryFile, 'w');
    fprintf(fid, '%s\r\n', batLines{:});
    fclose(fid);
end

function localRmdirIfExists(folder)
    if exist(folder, 'dir')
        try
            rmdir(folder, 's');
        catch
        end
    end
end

function path = localTempFilePath()
    path = fullfile(tempdir, sprintf('testAudio2Hdf5_%d.hdf5', round(rand * 1e9)));
end

function localDeleteIfExists(path)
    if isfile(path)
        delete(path);
    end
end

%% End-to-end

function testEndToEndExport(testCase)
    fs = 8000;
    fileSpecs = struct( ...
        'fs', {fs, fs}, ...
        'fileTag', {'fake1', 'fake2'}, ...
        'chapters', { ...
            struct('title', {'Alpha', 'isi', 'Beta'}, 'start', {1, 8001, 16001}, 'timestamp', {0, 5, 10.5}), ...
            struct('title', {'Gamma'}, 'start', {1}, 'timestamp', {0})});
    [wavFiles, binaryFile, cleanup] = makeAudioFixture(fileSpecs); %#ok<ASGLU>

    outputFilePath = localTempFilePath();
    cleanupFile = onCleanup(@() localDeleteIfExists(outputFilePath)); %#ok<NASGU>

    [status, message] = io.stimuli.spectrogram.audio2hdf5(wavFiles, outputFilePath, 'BinaryPath', binaryFile);
    testCase.verifyTrue(status);
    testCase.verifyTrue(isfile(outputFilePath));
    testCase.verifyTrue(contains(message, 'fake1.wav'));

    info = h5info(outputFilePath);
    stimNames = string({info.Groups.Name});
    testCase.verifyTrue(any(stimNames == "/fake1.wav") && any(stimNames == "/fake2.wav"));
    groupInfo = h5info(outputFilePath, '/fake1.wav');
    testCase.verifyTrue(any(string({groupInfo.Groups.Name}) == "/fake1.wav/Alpha"));
    testCase.verifyTrue(any(string({groupInfo.Groups.Name}) == "/fake1.wav/Beta"));

    [wavData1, ~] = audioread(wavFiles{1});
    expectedAlpha = io.stimuli.spectrogram.precompute(wavData1(1:8000, :), fs, 'StimfileName', 'fake1.wav', 'Title', 'Alpha');
    expectedBeta = io.stimuli.spectrogram.precompute(wavData1(16001:24000, :), fs, 'StimfileName', 'fake1.wav', 'Title', 'Beta');
    testCase.verifyEqual(permute(h5read(outputFilePath, '/fake1.wav/Alpha/spectrogram'), [2, 3, 1]), expectedAlpha.spectrogram);
    testCase.verifyEqual(h5read(outputFilePath, '/fake1.wav/Alpha/time'), expectedAlpha.time(:).');
    testCase.verifyEqual(h5read(outputFilePath, '/fake1.wav/Alpha/amplitude_rms').', expectedAlpha.amplitudeRms);
    testCase.verifyEqual(permute(h5read(outputFilePath, '/fake1.wav/Beta/spectrogram'), [2, 3, 1]), expectedBeta.spectrogram);

    [wavData2, ~] = audioread(wavFiles{2});
    expectedGamma = io.stimuli.spectrogram.precompute(wavData2, fs, 'StimfileName', 'fake2.wav', 'Title', 'Gamma');
    testCase.verifyEqual(permute(h5read(outputFilePath, '/fake2.wav/Gamma/spectrogram'), [2, 3, 1]), expectedGamma.spectrogram);

    protocolPath = '/fake1.wav/protocol';
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_start_sample'])), [1, 8001, 16001]);
    testCase.verifyEqual(h5read(outputFilePath, [protocolPath, '/chapter_timestamp']), [0, 5, 10.5], 'AbsTol', 1e-6);
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_title'])), [1, 2, 3]);
    testCase.verifyEqual(string(h5read(outputFilePath, [protocolPath, '/title_categories'])), ["Alpha", "isi", "Beta"]);
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_description'])), [1, 1, 1]);
end

%% Validation and errors

function testSampleRateMismatchErrors(testCase)
    fileSpecs = struct( ...
        'fs', {8000, 16000}, ...
        'fileTag', {'low', 'high'}, ...
        'chapters', { ...
            struct('title', {'Alpha'}, 'start', {1}, 'timestamp', {0}), ...
            struct('title', {'Gamma'}, 'start', {1}, 'timestamp', {0})});
    [wavFiles, binaryFile, cleanup] = makeAudioFixture(fileSpecs); %#ok<ASGLU>
    try
        io.stimuli.spectrogram.audio2hdf5(wavFiles, localTempFilePath(), 'BinaryPath', binaryFile);
        testCase.verifyFail('Expected a SampleRateMismatch error.');
    catch ME
        testCase.verifyEqual(ME.identifier, 'io:stimuli:spectrogram:audio2hdf5:SampleRateMismatch');
        testCase.verifyTrue(contains(ME.message, 'separate HDF5 files'));
    end
end

function testNoStimuliErrors(testCase)
    fileSpecs = struct('fs', {8000}, 'fileTag', {'empty'}, 'chapters', {struct('title', {}, 'start', {})});
    [wavFiles, binaryFile, cleanup] = makeAudioFixture(fileSpecs); %#ok<ASGLU>
    testCase.verifyError(@() testCase.verifyWarning(...
        @() io.stimuli.spectrogram.audio2hdf5(wavFiles, localTempFilePath(), 'BinaryPath', binaryFile), ...
        'io:stimuli:spectrogram:audio2hdf5:NoStimuliInFile'), ...
        'io:stimuli:spectrogram:audio2hdf5:NoStimuli');
end

function testDeduplication(testCase)
    fileSpecs = struct( ...
        'fs', {8000}, ...
        'fileTag', {'fake1'}, ...
        'chapters', {struct('title', {'Alpha'}, 'start', {1}, 'timestamp', {0})});
    [wavFiles, binaryFile, cleanup] = makeAudioFixture(fileSpecs); %#ok<ASGLU>
    outputFilePath = localTempFilePath();
    cleanupFile = onCleanup(@() localDeleteIfExists(outputFilePath)); %#ok<NASGU>
    [status, message] = io.stimuli.spectrogram.audio2hdf5([wavFiles; wavFiles], outputFilePath, 'BinaryPath', binaryFile);
    testCase.verifyTrue(status);
    testCase.verifyTrue(contains(message, '1 spectrogram database(s)'));
end

function testInvalidInputsErrors(testCase)
    testCase.verifyError(@() io.stimuli.spectrogram.audio2hdf5(123, localTempFilePath()), ...
        'io:stimuli:spectrogram:audio2hdf5:InvalidInput');
    testCase.verifyError(@() io.stimuli.spectrogram.audio2hdf5('definitely_missing_audio.wav', localTempFilePath()), ...
        'io:stimuli:spectrogram:audio2hdf5:FileNotFound');
end
