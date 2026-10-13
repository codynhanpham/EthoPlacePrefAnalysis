function tests = testSpectrogramExportHdf5
%TESTSPECTROGRAMEXPORTHDF5 Tests for io.stimuli.spectrogram.exportHdf5
    tests = functiontests(localfunctions);
end

%% Fixtures

function [databases, outputFilePath, cleanup] = makeExportFixture(nDatabases)
    fs = 8000;
    t = (0:fs - 1)' / fs;
    base = 0.5 * sin(2 * pi * 1000 * t) + 0.01 * randn(fs, 1);

    databases = {};
    databases{1} = io.stimuli.spectrogram.precompute(base, fs, 'StimfileName', 'stimA.flac', 'Title', 'Stim A');
    databases{2} = io.stimuli.spectrogram.precompute([base, base * 0.5], fs, 'StimfileName', 'stimA.flac', 'Title', 'Stim B');
    if nDatabases >= 3
        databases{3} = io.stimuli.spectrogram.precompute(0.25 * base, fs, 'StimfileName', 'stimB.wav', 'Title', 'Stim A');
    end

    outputFilePath = fullfile(tempdir, sprintf('testSpectrogramExportHdf5_%d.hdf5', round(rand * 1e9)));
    cleanup = onCleanup(@() localDeleteIfExists(outputFilePath));
end

function path = localTempPath()
    path = fullfile(tempdir, sprintf('testSpectrogramExportHdf5_%d.hdf5', round(rand * 1e9)));
end

function localDeleteIfExists(path)
    if isfile(path)
        delete(path);
    end
end

%% Round trip

function testScalarExportAndRoundTrip(testCase)
    [databases, outputFilePath, cleanup] = makeExportFixture(1); %#ok<ASGLU>
    [status, message] = io.stimuli.spectrogram.exportHdf5(databases{1}, outputFilePath);
    testCase.verifyTrue(status);
    testCase.verifyTrue(isfile(outputFilePath));
    testCase.verifyTrue(contains(message, 'stimA.flac'));

    groupPath = '/stimA.flac/Stim A';
    info = h5info(outputFilePath);
    testCase.verifyTrue(any(string({info.Groups.Name}) == "/stimA.flac"));
    groupInfo = h5info(outputFilePath, '/stimA.flac');
    testCase.verifyTrue(any(string({groupInfo.Groups.Name}) == groupPath));

    db = databases{1};
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/time']), db.time(:).');
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/frequency']), db.frequency(:).');
    testCase.verifyEqual(permute(h5read(outputFilePath, [groupPath, '/spectrogram']), [2, 3, 1]), db.spectrogram);
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/display_floor']), db.params.displayFloor);
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/amplitude_rms']).', db.amplitudeRms);
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/amplitude_peak']).', db.amplitudePeak);
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/amplitude_min']).', db.amplitudeMin);
    testCase.verifyEqual(h5read(outputFilePath, [groupPath, '/amplitude_max']).', db.amplitudeMax);

    testCase.verifyEqual(h5read(outputFilePath, '/uns/fs'), db.fs);
    testCase.verifyEqual(h5read(outputFilePath, '/uns/hop_samples'), db.params.hopSamples);
    testCase.verifyEqual(h5read(outputFilePath, '/uns/nfft'), db.params.nfft);
    testCase.verifyEqual(h5read(outputFilePath, '/uns/db_floor'), db.dbFloor);
    testCase.verifyEqual(h5read(outputFilePath, '/uns/db_step'), db.dbStep);
    testCase.verifyEqual(char(h5read(outputFilePath, '/uns/precision')), 'uint8');
    testCase.verifyEqual(char(h5read(outputFilePath, '/uns/channel_mode')), 'all');
    testCase.verifyEqual(h5read(outputFilePath, '/uns/display_floor_percentile'), db.params.displayFloorPercentile);

    testCase.verifyEqual(h5readatt(outputFilePath, '/', 'format_version'), int32(1));
    testCase.verifyEqual(char(h5readatt(outputFilePath, '/', 'hdf5_layout')), 'spectrogramdb');
    testCase.verifyEqual(char(h5readatt(outputFilePath, [groupPath, '/spectrogram'], 'units')), 'dB');
    testCase.verifyTrue(~isempty(char(h5readatt(outputFilePath, [groupPath, '/spectrogram'], 'quantization'))));
end

function testListExportNesting(testCase)
    [databases, outputFilePath, cleanup] = makeExportFixture(3); %#ok<ASGLU>
    [status, message] = io.stimuli.spectrogram.exportHdf5(databases, outputFilePath);
    testCase.verifyTrue(status);

    info = h5info(outputFilePath);
    stimNames = string({info.Groups.Name});
    testCase.verifyTrue(any(stimNames == "/stimA.flac"));
    testCase.verifyTrue(any(stimNames == "/stimB.wav"));

    groupInfo = h5info(outputFilePath, '/stimA.flac');
    titles = string({groupInfo.Groups.Name});
    testCase.verifyTrue(any(titles == "/stimA.flac/Stim A"));
    testCase.verifyTrue(any(titles == "/stimA.flac/Stim B"));

    testCase.verifyEqual(permute(h5read(outputFilePath, '/stimA.flac/Stim B/spectrogram'), [2, 3, 1]), ...
        databases{2}.spectrogram);
    testCase.verifyEqual(h5read(outputFilePath, '/stimA.flac/Stim B/display_floor'), databases{2}.params.displayFloor);
    testCase.verifyEqual(char(h5readatt(outputFilePath, '/', 'stimfileNames')), 'stimA.flac;stimB.wav');
    testCase.verifyTrue(contains(message, '3'));
end

function testStructArrayInput(testCase)
    [databases, ~, ~] = makeExportFixture(3);
    asStructArray = [databases{1}, databases{3}];
    outputFilePath = localTempPath();
    cleanup = onCleanup(@() localDeleteIfExists(outputFilePath)); %#ok<NASGU>
    [status, ~] = io.stimuli.spectrogram.exportHdf5(asStructArray, outputFilePath);
    testCase.verifyTrue(status);
    info = h5info(outputFilePath);
    stimNames = string({info.Groups.Name});
    testCase.verifyTrue(any(stimNames == "/stimA.flac") && any(stimNames == "/stimB.wav"));
end

%% Protocols

function testProtocolExport(testCase)
    [databases, outputFilePath, cleanup] = makeExportFixture(3); %#ok<ASGLU>
    chapterData = struct( ...
        'title', {'Alpha', 'isi', 'Beta', 'Alpha'}, ...
        'startsample', {1, 8001, 16001, 24001}, ...
        'timestamp', {0, 5, 10.5, 15}, ...
        'description', {[], [], [], []});
    protocols = struct('stimfileName', {'stimA.flac'}, 'chapters', {chapterData});

    [status, ~] = io.stimuli.spectrogram.exportHdf5(databases, outputFilePath, 'Protocols', protocols);
    testCase.verifyTrue(status);

    protocolPath = '/stimA.flac/protocol';
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_title'])), [1, 2, 3, 1]);
    testCase.verifyEqual(string(h5read(outputFilePath, [protocolPath, '/title_categories'])), ["Alpha", "isi", "Beta"]);
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_start_sample'])), [1, 8001, 16001, 24001]);
    testCase.verifyEqual(h5read(outputFilePath, [protocolPath, '/chapter_timestamp']), [0, 5, 10.5, 15], 'AbsTol', 1e-6);
    testCase.verifyEqual(double(h5read(outputFilePath, [protocolPath, '/chapter_description'])), [1, 1, 1, 1]);
    testCase.verifyEqual(string(h5read(outputFilePath, [protocolPath, '/description_categories'])), "[]");

    stimBInfo = h5info(outputFilePath, '/stimB.wav');
    testCase.verifyTrue(~any(string({stimBInfo.Groups.Name}) == "/stimB.wav/protocol"));
end

function testProtocolOrphanWarning(testCase)
    [databases, outputFilePath, cleanup] = makeExportFixture(1); %#ok<ASGLU>
    protocols = struct('stimfileName', {'missing.wav'}, 'chapters', {struct('title', {'X'}, 'startsample', {1})});
    testCase.verifyWarning(...
        @() io.stimuli.spectrogram.exportHdf5(databases, outputFilePath, 'Protocols', protocols), ...
        'io:stimuli:spectrogram:exportHdf5:ProtocolWithoutStimuli');
    info = h5info(outputFilePath);
    testCase.verifyTrue(~any(string({info.Groups.Name}) == "/missing.wav"));
end

function testReservedTitleErrors(testCase)
    fs = 8000;
    db = io.stimuli.spectrogram.precompute(0.1 * randn(fs, 1), fs, 'StimfileName', 'stimA.flac', 'Title', 'protocol');
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(db, localTempPath()), ...
        'io:stimuli:spectrogram:exportHdf5:ReservedTitle');
end

function testInvalidProtocolsErrors(testCase)
    [databases, ~, ~] = makeExportFixture(1);
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(databases, localTempPath(), 'Protocols', 5), ...
        'io:stimuli:spectrogram:exportHdf5:InvalidProtocols');
end

%% Validation and errors

function testConfigMismatchErrors(testCase)
    [databases, ~, cleanup] = makeExportFixture(2); %#ok<ASGLU>
    clear cleanup;
    databases{2}.dbFloor = -70;
    try
        io.stimuli.spectrogram.exportHdf5(databases, localTempPath());
        testCase.verifyFail('Expected a ConfigMismatch error.');
    catch ME
        testCase.verifyEqual(ME.identifier, 'io:stimuli:spectrogram:exportHdf5:ConfigMismatch');
        testCase.verifyTrue(contains(ME.message, 'separate files'));
        testCase.verifyTrue(contains(ME.message, 'dbFloor'));
    end
end

function testDuplicateGroupErrors(testCase)
    [databases, ~, cleanup] = makeExportFixture(2); %#ok<ASGLU>
    clear cleanup;
    databases{2}.title = 'Stim A';
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(databases, localTempPath()), ...
        'io:stimuli:spectrogram:exportHdf5:DuplicateGroup');
end

function testMissingIdentityErrors(testCase)
    fs = 8000;
    bare = io.stimuli.spectrogram.precompute(0.1 * randn(fs, 1), fs);
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(bare, localTempPath()), ...
        'io:stimuli:spectrogram:exportHdf5:MissingGroupIdentity');
end

function testUntitledFallback(testCase)
    fs = 8000;
    db = io.stimuli.spectrogram.precompute(0.1 * randn(fs, 1), fs, 'StimfileName', 'stimA.flac');
    outputFilePath = localTempPath();
    cleanup = onCleanup(@() localDeleteIfExists(outputFilePath)); %#ok<NASGU>
    io.stimuli.spectrogram.exportHdf5(db, outputFilePath);
    groupInfo = h5info(outputFilePath, '/stimA.flac');
    testCase.verifyTrue(any(string({groupInfo.Groups.Name}) == "/stimA.flac/untitled"));
end

function testOverwriteGuard(testCase)
    [databases, outputFilePath, cleanup] = makeExportFixture(1); %#ok<ASGLU>
    io.stimuli.spectrogram.exportHdf5(databases{1}, outputFilePath);
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(databases{1}, outputFilePath), ...
        'io:stimuli:spectrogram:exportHdf5:FileExists');
    [status, ~] = io.stimuli.spectrogram.exportHdf5(databases{1}, outputFilePath, 'Overwrite', true);
    testCase.verifyTrue(status);
    testCase.verifyTrue(isfile(outputFilePath));
end

function testInvalidInputErrors(testCase)
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5({struct()}, localTempPath()), ...
        'io:stimuli:spectrogram:validateDatabase:InvalidDatabase');
    testCase.verifyError(@() io.stimuli.spectrogram.exportHdf5(struct('foo', 1), localTempPath()), ...
        'io:stimuli:spectrogram:validateDatabase:InvalidDatabase');
end
