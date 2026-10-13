function [status, message] = exportHdf5(spectrogramDb, outputFilePath, kvargs)
    %%EXPORTHDF5 Export spectrogram database struct(s) to an HDF5 file.
    %   Writes one or more spectrogram databases (as returned by
    %   io.stimuli.spectrogram.precompute) into a single size-optimized HDF5 file
    %   following the repository's HDF5 conventions (see the companion
    %   exportHdf5.md for the full format specification).
    %
    %   The input may be a single database struct or a struct array of databases.
    %   When exporting a list, all databases must share the same DSP configuration
    %   (fs, hop, window, nfft, window function, channel mode, precision, db floor,
    %   and db step) so they can share the same domain scaling stored under /uns;
    %   durations and channel counts may differ. If the configurations differ, an
    %   error is raised suggesting to save them as separate files.
    %
    %   Groups are nested by stimulus file name first, then by stimulus title:
    %   /<stimfileName>/<title>. The identities come from the databases themselves
    %   (set via the 'StimfileName' and 'Title' arguments of
    %   io.stimuli.spectrogram.precompute). A missing title falls back to
    %   'untitled'; a missing stimfileName is an error.
    %
    %   USAGE:
    %       [status, message] = io.stimuli.spectrogram.exportHdf5(spectrogramDb, outputFilePath)
    %       [status, message] = io.stimuli.spectrogram.exportHdf5(databases, outputFilePath, 'Overwrite', true)
    %
    %   INPUTS:
    %       spectrogramDb: scalar struct, struct array, or cell array of spectrogram
    %           databases produced by io.stimuli.spectrogram.precompute (with
    %           'StimfileName' and 'Title' set for group placement). A cell array is
    %           required when the databases have different channel counts, since MATLAB
    %           struct arrays cannot hold differently shaped fields.
    %       outputFilePath: Path to the output HDF5 file. A '.hdf5' extension is
    %           appended when missing.
    %
    %   Name-Value Pair Arguments:
    %       'Overwrite': (logical) Whether to replace an existing output file.
    %           Default false: an existing file is an error.
    %
    %   OUTPUTS:
    %       status: logical indicating success.
    %       message: string message about the operation.
    %
    %   See also: io.stimuli.spectrogram.precompute, io.stimuli.spectrogram.validateDatabase, sdTable.makeSingleSubjectHdf5

    arguments
        spectrogramDb {mustBeNonempty}
        outputFilePath {validator.mustBeValidFilepath}
        kvargs.Overwrite (1,1) logical = false
    end

    if isstruct(spectrogramDb)
        databases = arrayfun(@(k) spectrogramDb(k), 1:numel(spectrogramDb), 'UniformOutput', false);
    elseif iscell(spectrogramDb)
        databases = spectrogramDb(:);
    else
        error("io:stimuli:spectrogram:exportHdf5:InvalidInput", ...
            "spectrogramDb must be a struct, struct array, or cell array of spectrogram databases.");
    end
    for k = 1:numel(databases)
        io.stimuli.spectrogram.validateDatabase(databases{k});
    end

    % All databases in one file must share the domain scaling (frequency axis and dB
    % quantization). Durations and channel counts may differ per database.
    configFields = {'fs', 'hopSamples', 'windowSamples', 'nfft', 'windowFunction', ...
        'channelMode', 'precision', 'dbFloor', 'dbStep'}; %#ok<NASGU>
    referenceConfig = localConfigOf(databases{1});
    for k = 2:numel(databases)
        candidateConfig = localConfigOf(databases{k});
        mismatchedFields = strings(0, 1);
        for fieldName = fieldnames(referenceConfig).'
            referenceValue = referenceConfig.(fieldName{1});
            candidateValue = candidateConfig.(fieldName{1});
            if ischar(candidateValue) || isstring(candidateValue)
                differs = ~strcmpi(char(candidateValue), char(referenceValue));
            else
                differs = ~isequal(referenceValue, candidateValue);
            end
            if differs
                mismatchedFields(end+1, 1) = string(fieldName{1}); %#ok<AGROW>
            end
        end
        if ~isempty(mismatchedFields)
            error("io:stimuli:spectrogram:exportHdf5:ConfigMismatch", ...
                "All spectrogram databases must share the same configuration to be exported into one file, but database %d differs on: %s (expected %s, got %s). Save them as separate files or recompute with matching settings.", ...
                k, strjoin(mismatchedFields, ', '), ...
                localConfigText(referenceConfig, mismatchedFields), localConfigText(candidateConfig, mismatchedFields));
        end
    end

    % Group placement: /<stimfileName>/<title>, both sanitized for HDF5.
    groupPaths = strings(numel(databases), 1);
    stimfileNames = strings(numel(databases), 1);
    for k = 1:numel(databases)
        stimfileName = char(string(databases{k}.stimfileName));
        if strtrim(stimfileName) == ""
            error("io:stimuli:spectrogram:exportHdf5:MissingGroupIdentity", ...
                "Database %d has no 'stimfileName'. Provide it via io.stimuli.spectrogram.precompute(..., 'StimfileName', ...).", k);
        end
        title = char(string(databases{k}.title));
        if strtrim(title) == ""
            title = 'untitled';
        end
        stimfileNames(k) = string(stimfileName);
        groupPaths(k) = string(['/' localSanitizeGroupName(stimfileName) '/' localSanitizeGroupName(title)]);
    end
    sortedPaths = sort(groupPaths);
    isDuplicate = [false; sortedPaths(2:end) == sortedPaths(1:end-1)];
    if any(isDuplicate)
        error("io:stimuli:spectrogram:exportHdf5:DuplicateGroup", ...
            "Duplicate stimulus identity in the input: %s maps to the same group. Each (stimfileName, title) pair must be unique.", ...
            sortedPaths(find(isDuplicate, 1)));
    end

    % Normalize the output path and refuse to overwrite unless asked.
    outputFilePath = char(string(outputFilePath));
    [outputFolder, outputName, outputExt] = fileparts(outputFilePath);
    if isempty(outputExt)
        outputExt = '.hdf5';
    end
    if isempty(outputFolder)
        outputFolder = pwd;
    end
    finalPath = fullfile(outputFolder, [outputName, outputExt]);
    if isfile(finalPath) && ~kvargs.Overwrite
        error("io:stimuli:spectrogram:exportHdf5:FileExists", ...
            "Output file already exists: %s. Pass 'Overwrite', true to replace it.", finalPath);
    end

    % Write atomically: everything goes to a temporary file which is moved into
    % place only after a successful write.
    tempPath = [tempname(outputFolder), '.hdf5.tmp'];
    cleanupTemp = onCleanup(@() localDeleteIfExists(tempPath));
    createFid = H5F.create(tempPath, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
    H5F.close(createFid);

    h5writeatt(tempPath, '/', 'format_version', int32(1));
    h5writeatt(tempPath, '/', 'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    h5writeatt(tempPath, '/', 'hdf5_layout', 'spectrogramdb');
    h5writeatt(tempPath, '/', 'stimfileNames', char(strjoin(unique(stimfileNames), ';')));

    % /uns: shared DSP configuration (identical across all exported databases).
    reference = databases{1};
    writeScalarDataset(tempPath, '/uns/fs', reference.fs);
    writeScalarDataset(tempPath, '/uns/hop_samples', reference.params.hopSamples);
    writeScalarDataset(tempPath, '/uns/window_samples', reference.params.windowSamples);
    writeScalarDataset(tempPath, '/uns/overlap_ratio', reference.params.overlapRatio);
    writeScalarDataset(tempPath, '/uns/nfft', reference.params.nfft);
    writeScalarDataset(tempPath, '/uns/db_floor', reference.dbFloor);
    writeScalarDataset(tempPath, '/uns/db_step', reference.dbStep);
    writeScalarDataset(tempPath, '/uns/display_floor_percentile', reference.params.displayFloorPercentile);
    writeTextDataset(tempPath, '/uns/window_function', reference.params.windowFunction);
    writeTextDataset(tempPath, '/uns/channel_mode', reference.params.channelMode);
    writeTextDataset(tempPath, '/uns/precision', reference.params.precision);
    writeTextDataset(tempPath, '/uns/reference', reference.params.reference);

    % One group per database: /<stimfileName>/<title>/...
    chunkFrames = max(1, ceil(2^18 / max(1, numel(databases{1}.frequency) * size(databases{1}.spectrogram, 3))));
    for k = 1:numel(databases)
        database = databases{k};
        groupPath = char(groupPaths(k));
        nFrames = numel(database.time);
        nChannels = size(database.spectrogram, 3);

        writeVectorDataset(tempPath, [groupPath, '/time'], database.time);
        writeVectorDataset(tempPath, [groupPath, '/frequency'], database.frequency);
        writeVectorDataset(tempPath, [groupPath, '/display_floor'], database.params.displayFloor(:));

        datasetPath = [groupPath, '/spectrogram'];
        [nBins, ~, ~] = size(database.spectrogram);
        matlabDims = [nChannels, nBins, nFrames];
        chunk = [nChannels, nBins, min(nFrames, chunkFrames)];
        h5create(tempPath, datasetPath, matlabDims, 'DataType', class(database.spectrogram), 'ChunkSize', chunk, 'Deflate', 6);
        h5write(tempPath, datasetPath, permute(database.spectrogram, [3, 1, 2]));
        h5writeatt(tempPath, datasetPath, 'hdf5_axis_order', 'dim1=time frames, dim2=frequency bins, dim3=channels');
        h5writeatt(tempPath, datasetPath, 'units', 'dB');
        h5writeatt(tempPath, datasetPath, 'reference', 'peak');
        if strcmpi(database.params.precision, 'uint8')
            h5writeatt(tempPath, datasetPath, 'quantization', ...
                'uint8 levels 0..255; dB = db_floor + level * db_step; all-silent bins are stored at level 0');
        end

        amplitudeFields = {'amplitudeRms', 'amplitudePeak', 'amplitudeMin', 'amplitudeMax'};
        amplitudeNames = {'amplitude_rms', 'amplitude_peak', 'amplitude_min', 'amplitude_max'};
        for f = 1:numel(amplitudeFields)
            writeMatrixDataset(tempPath, [groupPath, '/', amplitudeNames{f}], database.(amplitudeFields{f}));
        end
    end

    % Move the temp file into its final location.
    movefile(tempPath, finalPath, 'f');
    clear cleanupTemp;

    status = true;
    message = sprintf('Exported %d spectrogram database(s) for stimfiles [%s] to %s', ...
        numel(databases), strjoin(unique(stimfileNames), ', '), finalPath);
end


function config = localConfigOf(database)
    config = struct();
    config.fs = database.fs;
    config.hopSamples = database.params.hopSamples;
    config.windowSamples = database.params.windowSamples;
    config.nfft = database.params.nfft;
    config.windowFunction = lower(char(database.params.windowFunction));
    config.channelMode = lower(char(database.params.channelMode));
    config.precision = lower(char(database.params.precision));
    config.dbFloor = database.dbFloor;
    config.dbStep = database.dbStep;
end


function text = localConfigText(config, fields)
    text = strjoin(arrayfun(@(f) sprintf('%s=%s', f, string(config.(char(f)))), fields, 'UniformOutput', false), ', ');
end


function groupName = localSanitizeGroupName(name)
    % HDF5 group names cannot contain '/' or NUL. Replace with '_' and trim.
    groupName = char(string(name));
    groupName(groupName == '/') = '_';
    groupName(strtrim(groupName) == "") = '_';
    groupName = strtrim(groupName);
end


function localDeleteIfExists(path)
    if exist(path, 'file')
        delete(path);
    end
end


function writeScalarDataset(filePath, datasetPath, value)
    % Write a scalar double dataset with gzip compression
    h5create(filePath, datasetPath, [1 1], 'DataType', 'double', 'ChunkSize', [1 1], 'Deflate', 6);
    h5write(filePath, datasetPath, double(value));
end


function writeTextDataset(filePath, datasetPath, value)
    % Write a single string as a 1x1 variable-length UTF-8 string dataset.
    h5create(filePath, datasetPath, [1 1], 'DataType', 'string');
    h5write(filePath, datasetPath, string(value));
end


function writeVectorDataset(filePath, datasetPath, values)
    % MATLAB's high-level HDF5 API reverses axes on disk. Write a row vector here
    % so external readers see an N-by-1 column vector.
    values = double(values(:).');
    n = numel(values);
    h5create(filePath, datasetPath, [1 n], 'DataType', 'double', 'ChunkSize', [1 min(n, 4096)], 'Deflate', 6);
    h5write(filePath, datasetPath, values);
end


function writeMatrixDataset(filePath, datasetPath, matrix)
    % MATLAB's high-level HDF5 API reverses axes on disk. Transpose before writing
    % so external readers see rows as time frames and columns as channels.
    matrix = double(matrix).';
    dims = size(matrix);
    chunk = [dims(1) min(dims(2), 4096)];
    h5create(filePath, datasetPath, dims, 'DataType', 'double', 'ChunkSize', chunk, 'Deflate', 6);
    h5write(filePath, datasetPath, matrix);
    h5writeatt(filePath, datasetPath, 'hdf5_axis_order', 'rows=time frames, columns=channels');
end
