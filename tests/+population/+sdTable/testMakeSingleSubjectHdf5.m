function tests = testMakeSingleSubjectHdf5
%TESTMAKESINGLESUBJECTHDF5 Tests for sdTable.makeSingleSubjectHdf5
    tests = functiontests(localfunctions);
end

%% Fixtures

function standardizedTables = makeStandardizedTables(nRows, nSubjects, nTables)
    % Build a synthetic standardizedTable struct array with known values.
    % Subject j has X center = j, Y center = 10 + j, Distance from Midline = 100 + j,
    % Arena Grid Score = 1000 + j, and bodypart X/Y = 2000 + j / 3000 + j.
    arguments
        nRows (1,1) double {mustBePositive}
        nSubjects (1,1) double {mustBePositive}
        nTables (1,1) double {mustBeNonnegative}
    end

    standardizedTables = struct([]);
    for tableIdx = 1:nTables
        trialTime = ((1:nRows)' - ceil(nRows/2)) / 30; % centered on 0
        stimulusNames = repmat(["NONE | Pre-Stimulus"; "Stim A"; "Stim B"; "NONE | Post-Stimulus"], ceil(nRows/4), 1);
        stimulusNames = stimulusNames(1:nRows);

        centerpointData = table();
        centerpointData.('Trial time') = trialTime;
        centerpointData.('Stimulus name') = stimulusNames;
        centerpointData.('X center') = repmat((1:nSubjects), nRows, 1);
        centerpointData.('Y center') = repmat(10 + (1:nSubjects), nRows, 1);
        centerpointData.('Arena Grid Score') = repmat(1000 + (1:nSubjects), nRows, 1);
        centerpointData.('Distance from Midline') = repmat(100 + (1:nSubjects), nRows, 1);

        bodyparts = table();
        bodyparts.('Trial time') = trialTime;
        bodyparts.('Stimulus name') = stimulusNames;
        bodyparts.('X nose') = repmat(2000 + (1:nSubjects), nRows, 1);
        bodyparts.('Y nose') = repmat(3000 + (1:nSubjects), nRows, 1);

        animalMetadata = configureDictionary("string", "struct");
        for subjectIdx = 1:nSubjects
            animalMetadata(sprintf('key%d', subjectIdx)) = makeSubjectMetadata(subjectIdx);
        end

        standardizedTables(tableIdx).stimfileName = sprintf('stimfile%d.flac', tableIdx);
        standardizedTables(tableIdx).stimuliSorted = ["Stim A", "Stim B"];
        standardizedTables(tableIdx).animalMetadata = animalMetadata;
        standardizedTables(tableIdx).fps = 30;
        standardizedTables(tableIdx).px2cm = 0.05;
        standardizedTables(tableIdx).centerpointData = centerpointData;
        standardizedTables(tableIdx).bodyparts = bodyparts;
    end
end

function metadata = makeSubjectMetadata(subjectIdx)
    metadata = struct( ...
        'sex', sprintf('Sex%d', subjectIdx), ...
        'genotype', sprintf('Geno%d', subjectIdx), ...
        'strain', sprintf('Strain%d', subjectIdx), ...
        'age', 60 + subjectIdx, ...
        'dob', datetime(2024, 1, subjectIdx), ...
        'cagecode', sprintf('Cage%d', subjectIdx), ...
        'id', sprintf('ID%d', subjectIdx), ...
        'source', sprintf('Src%d', subjectIdx));
end

%% Tests

function testWritesCenterpointAndBodyparts(testCase)
    standardizedTables = makeStandardizedTables(12, 3, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    [status, message] = sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(2), outputPath);
    testCase.verifyTrue(status);
    testCase.verifyTrue(isstring(message) || ischar(message));
    testCase.verifyTrue(isfile(outputPath));

    % Root attributes
    testCase.verifyEqual(h5readatt(outputPath, '/', 'format_version'), int32(1));
    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "stimfile1.flac");

    % /obs metadata (string datasets read back as string)
    testCase.verifyEqual(string(h5read(outputPath, '/obs/id')), "ID2");
    testCase.verifyEqual(string(h5read(outputPath, '/obs/sex')), "Sex2");
    testCase.verifyEqual(h5read(outputPath, '/obs/age'), 62);
    testCase.verifyEqual(string(h5read(outputPath, '/obs/dob')), "2024-01-02");

    % /uns metadata
    testCase.verifyEqual(h5read(outputPath, '/uns/fps'), 30);
    testCase.verifyEqual(h5read(outputPath, '/uns/px2cm'), 0.05);

    % Data group: shared time dataset at group root
    groupPath = '/stimfile1.flac';
    time = h5read(outputPath, [groupPath '/time']);
    testCase.verifyEqual(numel(time), 12);
end

function testCenterpointValuesMatchSubject(testCase)
    standardizedTables = makeStandardizedTables(12, 3, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(2), outputPath);

    groupPath = '/stimfile1.flac';
    data = h5read(outputPath, [groupPath '/centerpoint']); % NxC, same shape as written
    columns = string(h5read(outputPath, [groupPath '/centerpoint_columns']));

    testCase.verifyEqual(size(data, 2), 4); % 4 data variables
    testCase.verifyEqual(numel(columns), 4);
    testCase.verifyEqual(columns, ["X center"; "Y center"; "Arena Grid Score"; "Distance from Midline"]);

    % Subject 2 column values: X=2, Y=12, Grid=1002, Dist=102 (constant across frames)
    testCase.verifyEqual(data(:, 1), repmat(2, 12, 1));
    testCase.verifyEqual(data(:, 2), repmat(12, 12, 1));
    testCase.verifyEqual(data(:, 3), repmat(1002, 12, 1));
    testCase.verifyEqual(data(:, 4), repmat(102, 12, 1));
end

function testBodypartsValuesMatchSubject(testCase)
    standardizedTables = makeStandardizedTables(12, 3, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(3), outputPath);

    groupPath = '/stimfile1.flac';
    data = h5read(outputPath, [groupPath '/bodyparts']); % NxC, same shape as written
    columns = string(h5read(outputPath, [groupPath '/bodyparts_columns']));

    testCase.verifyEqual(size(data, 2), 2);
    testCase.verifyEqual(columns, ["X nose"; "Y nose"]);
    testCase.verifyEqual(data(:, 1), repmat(2003, 12, 1));
    testCase.verifyEqual(data(:, 2), repmat(3003, 12, 1));
end

function testStimulusCategoricalEncoding(testCase)
    standardizedTables = makeStandardizedTables(12, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath);

    groupPath = '/stimfile1.flac';
    codes = h5read(outputPath, [groupPath '/stimulus']);
    categories = string(h5read(outputPath, [groupPath '/stimulus_categories']));

    testCase.verifyEqual(class(codes), 'int32');
    testCase.verifyEqual(numel(codes), 12);
    testCase.verifyTrue(all(codes >= 1 & codes <= numel(categories)));

    % Reconstruct names and compare against the source table
    reconstructed = categories(codes);
    sourceNames = string(standardizedTables(1).centerpointData{:, 'Stimulus name'});
    testCase.verifyEqual(reconstructed(:), sourceNames(:));
end

function testTimeRangeSubsetting(testCase)
    standardizedTables = makeStandardizedTables(12, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath, ...
        TimeRange=[-0.1, 0.1]);

    groupPath = '/stimfile1.flac';
    time = h5read(outputPath, [groupPath '/time']);
    data = h5read(outputPath, [groupPath '/centerpoint']);

    testCase.verifyTrue(all(time >= -0.1 & time <= 0.1));
    testCase.verifyEqual(size(data, 1), numel(time));
end

function testDataTableSelection(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPathCenterpoint = [tempname, '_cp.hdf5'];
    outputPathBodyparts = [tempname, '_bp.hdf5'];
    cleanup = onCleanup(@() localDeleteBoth(outputPathCenterpoint, outputPathBodyparts));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPathCenterpoint, ...
        DataTable='centerpointData');
    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPathBodyparts, ...
        DataTable='bodyparts');

    % Centerpoint-only file: no bodyparts group datasets
    info = h5info(outputPathCenterpoint, '/stimfile1.flac');
    datasetNames = string({info.Datasets.Name});
    testCase.verifyTrue(any(datasetNames == "centerpoint"));
    testCase.verifyFalse(any(datasetNames == "bodyparts"));

    % Bodyparts-only file: no centerpoint group datasets
    info = h5info(outputPathBodyparts, '/stimfile1.flac');
    datasetNames = string({info.Datasets.Name});
    testCase.verifyTrue(any(datasetNames == "bodyparts"));
    testCase.verifyFalse(any(datasetNames == "centerpoint"));
end

function testArenaBackgroundWritten(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    background = randi(255, 16, 24);
    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath, ...
        ArenaBackgound=background);

    written = h5read(outputPath, '/uns/arenaBackground');
    testCase.verifyEqual(written, background);
end

function testMultiTableSubjectMergedAcrossStimfiles(testCase)
    standardizedTables = makeStandardizedTables(8, 3, 2);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    [status, message] = sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(2), outputPath);
    testCase.verifyTrue(status);
    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "stimfile1.flac;stimfile2.flac");

    testCase.verifyEqual(h5read(outputPath, '/stimfile1.flac/centerpoint'), ...
        h5read(outputPath, '/stimfile2.flac/centerpoint'));
end

function testSkipsTablesWithoutSubject(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 2);
    % Remove subject 2 from the second table's metadata dictionary
    keysList = keys(standardizedTables(2).animalMetadata);
    standardizedTables(2).animalMetadata = remove(standardizedTables(2).animalMetadata, keysList(2));

    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    [status, message] = sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(2), outputPath);
    testCase.verifyTrue(status);
    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "stimfile1.flac");

    info = h5info(outputPath);
    groupNames = string({info.Groups.Name});
    testCase.verifyEqual(sort(groupNames), sort(["/stimfile1.flac", "/uns", "/obs"]));
end

function testStimfileNameFilter(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 2);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath, ...
        StimfileName='stimfile2.flac');

    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "stimfile2.flac");
end

function testStimfileNameFilterNoMatchErrors(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    testCase.verifyError(@() sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(1), outputPath, ...
        StimfileName='nonexistent.flac'), ...
        'sdTable:makeSingleSubjectHdf5:NoMatchingStimfile');
end

function testSubjectNotFoundErrors(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    wrongSubject = makeSubjectMetadata(1);
    wrongSubject.id = 'UNKNOWN_ID';
    testCase.verifyError(@() sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, wrongSubject, outputPath), ...
        'sdTable:makeSingleSubjectHdf5:SubjectNotFound');
end

function testTimeRangeWithNoDataErrors(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    testCase.verifyError(@() sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(1), outputPath, ...
        TimeRange=[100, 200]), ...
        'sdTable:makeSingleSubjectHdf5:NoDataInRange');
end

function testInvalidTimeRangeErrors(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath));

    testCase.verifyError(@() sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(1), outputPath, ...
        TimeRange=[10, -10]), ...
        'sdTable:makeSingleSubjectHdf5:InvalidTimeRange');
end

function testJoinedStimfileNameCellArray(testCase)
    % A joined standardizedTable (population.temp.joinStdTableByStim) stores
    % stimfileName as a cell array; the HDF5 group name and stimfileNames attribute
    % must use the elements joined with '++'.
    standardizedTables = makeStandardizedTables(8, 2, 1);
    standardizedTables(1).stimfileName = {'output1.flac'; 'output2.flac'};
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath)); %#ok<NASGU>

    [status, message] = sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(1), outputPath);
    testCase.verifyTrue(status);

    expectedGroup = '/output1.flac++output2.flac';
    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "output1.flac++output2.flac");

    info = h5info(outputPath);
    groupNames = string({info.Groups.Name});
    testCase.verifyTrue(any(groupNames == expectedGroup));

    % Data readable under the joined group name
    data = h5read(outputPath, [expectedGroup '/centerpoint']);
    testCase.verifyEqual(size(data, 1), 8);
    testCase.verifyEqual(data(:, 1), repmat(1, 8, 1)); % subject 1 X center
end

function testJoinedStimfileNameFilterMatchesJoinedForm(testCase)
    % The StimfileName filter must match the joined form: a single string with '++'
    % or a cell array whose elements joined with '++' equal the table's joined name.
    standardizedTables = makeStandardizedTables(8, 2, 2);
    standardizedTables(1).stimfileName = {'output1.flac'; 'output2.flac'};
    outputPath = [tempname, '.hdf5'];
    cleanup = onCleanup(@() localDeleteIfExists(outputPath)); %#ok<NASGU>

    % Filter by cell array (same elements as the joined table)
    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath, ...
        StimfileName={'output1.flac', 'output2.flac'});
    testCase.verifyEqual(string(h5readatt(outputPath, '/', 'stimfileNames')), "output1.flac++output2.flac");

    % Filter by the joined string form
    outputPath2 = [tempname, '.hdf5'];
    cleanup2 = onCleanup(@() localDeleteIfExists(outputPath2)); %#ok<NASGU>
    sdTable.makeSingleSubjectHdf5(standardizedTables, makeSubjectMetadata(1), outputPath2, ...
        StimfileName='output1.flac++output2.flac');
    testCase.verifyEqual(string(h5readatt(outputPath2, '/', 'stimfileNames')), "output1.flac++output2.flac");

    % A single constituent name alone must NOT match the joined table
    testCase.verifyError(@() sdTable.makeSingleSubjectHdf5( ...
        standardizedTables, makeSubjectMetadata(1), outputPath, ...
        StimfileName='output1.flac'), ...
        'sdTable:makeSingleSubjectHdf5:NoMatchingStimfile');
end

function testNoTempFileLeftOnError(testCase)
    standardizedTables = makeStandardizedTables(8, 2, 1);
    outputFolder = tempname;
    mkdir(outputFolder);
    cleanup = onCleanup(@() rmdir(outputFolder, 's'));
    outputPath = fullfile(outputFolder, 'subject.hdf5');

    wrongSubject = makeSubjectMetadata(1);
    wrongSubject.id = 'UNKNOWN_ID';
    try
        sdTable.makeSingleSubjectHdf5(standardizedTables, wrongSubject, outputPath);
        testCase.verifyFail('Expected SubjectNotFound error.');
    catch
        % Expected
    end

    % Only the output folder itself should remain (no temp files)
    remaining = dir(outputFolder);
    remaining = remaining(~ismember({remaining.name}, {'.', '..'}));
    testCase.verifyEmpty(remaining);
end

%% Local helpers

function localDeleteIfExists(path)
    if exist(path, 'file')
        delete(path);
    end
end

function localDeleteBoth(pathA, pathB)
    localDeleteIfExists(pathA);
    localDeleteIfExists(pathB);
end
