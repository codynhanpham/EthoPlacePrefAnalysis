function databases = importHdf5(hdf5FilePath, kvargs)
    %IMPORTHDF5 Import spectrogram databases from an HDF5 file written by exportHdf5.
    %   Reads the databases stored by io.stimuli.spectrogram.exportHdf5 back into
    %   spectrogram database struct(s) with the shape produced by
    %   io.stimuli.spectrogram.precompute, so they can be plotted with
    %   io.stimuli.spectrogram.plot or processed further in MATLAB. Each stimulus
    %   group /<stimfileName>/<title> becomes one element of the returned struct
    %   array.
    %
    %   uint8-quantized spectrograms are returned quantized (levels 0..255 with
    %   'dbFloor' and 'dbStep'), exactly as stored; dequantize with
    %   dB = dbFloor + double(spectrogram) * dbStep. Protocols stored under
    %   /<stimfileName>/protocol are not imported.
    %
    %   Stimulus identities are recovered from the group names, which are sanitized
    %   on export (HDF5 names cannot contain '/'): a stimfileName is restored from
    %   the file's 'stimfileNames' root attribute when possible, while titles are
    %   returned in their sanitized form (and as 'untitled' when missing at export
    %   time).
    %
    %   USAGE:
    %       databases = io.stimuli.spectrogram.importHdf5('spectrograms.hdf5')
    %       databases = io.stimuli.spectrogram.importHdf5(file, 'Stimfile', 'noise.flac')
    %       io.stimuli.spectrogram.plot(io.stimuli.spectrogram.importHdf5(file, 'Title', 'white noise'))
    %
    %   INPUTS:
    %       hdf5FilePath: Path to an HDF5 file written by
    %           io.stimuli.spectrogram.exportHdf5.
    %
    %   Name-Value Pair Arguments:
    %       'Stimfile': (text) Return only databases whose stimfile group matches this
    %           name (case-insensitive). Default "" returns all stimfiles.
    %       'Title': (text) Return only databases whose title group matches this name
    %           (case-insensitive). Default "" returns all titles.
    %
    %   OUTPUTS:
    %       databases: Struct array of spectrogram databases, one element per stimulus
    %           group, with the fields of io.stimuli.spectrogram.precompute's output
    %           (fs, stimfileName, title, time, frequency, spectrogram, dbFloor, dbStep,
    %           amplitudeRms, amplitudePeak, amplitudeMin, amplitudeMax, params).
    %
    %   See also: io.stimuli.spectrogram.plot, io.stimuli.spectrogram.validateDatabase, io.stimuli.spectrogram.exportHdf5, io.stimuli.spectrogram.precompute

    arguments
        hdf5FilePath {mustBeTextScalar}
        kvargs.Stimfile {mustBeTextScalar} = ""
        kvargs.Title {mustBeTextScalar} = ""
    end

    if ~isfile(hdf5FilePath)
        error("io:stimuli:spectrogram:importHdf5:FileNotFound", ...
            "HDF5 file not found: %s", hdf5FilePath);
    end
    try
        layout = char(string(h5readatt(hdf5FilePath, '/', 'hdf5_layout')));
    catch
        error("io:stimuli:spectrogram:importHdf5:InvalidLayout", ...
            "File %s has no 'hdf5_layout' root attribute and is not a spectrogram database written by io.stimuli.spectrogram.exportHdf5.", hdf5FilePath);
    end
    if ~strcmpi(layout, 'spectrogramdb')
        error("io:stimuli:spectrogram:importHdf5:InvalidLayout", ...
            "File %s has hdf5_layout '%s', expected 'spectrogramdb'.", hdf5FilePath, layout);
    end
    formatVersion = double(h5readatt(hdf5FilePath, '/', 'format_version'));
    if formatVersion > 1
        warning("io:stimuli:spectrogram:importHdf5:UnknownFormatVersion", ...
            "File %s has format_version %d, which is newer than the supported version 1; attempting to read anyway.", hdf5FilePath, formatVersion);
    end

    % /uns: the DSP configuration shared by every database in the file.
    fs = double(h5read(hdf5FilePath, '/uns/fs'));
    dbFloor = double(h5read(hdf5FilePath, '/uns/db_floor'));
    dbStep = double(h5read(hdf5FilePath, '/uns/db_step'));
    shared = struct( ...
        'hopSamples', double(h5read(hdf5FilePath, '/uns/hop_samples')), ...
        'windowSamples', double(h5read(hdf5FilePath, '/uns/window_samples')), ...
        'windowFunction', localReadText(hdf5FilePath, '/uns/window_function'), ...
        'overlapRatio', double(h5read(hdf5FilePath, '/uns/overlap_ratio')), ...
        'nfft', double(h5read(hdf5FilePath, '/uns/nfft')), ...
        'channelMode', localReadText(hdf5FilePath, '/uns/channel_mode'), ...
        'precision', localReadText(hdf5FilePath, '/uns/precision'), ...
        'reference', localReadText(hdf5FilePath, '/uns/reference'), ...
        'displayFloorPercentile', double(h5read(hdf5FilePath, '/uns/display_floor_percentile')));
    fileCreated = char(string(h5readatt(hdf5FilePath, '/', 'created')));

    % Enumerate stimulus groups /<stimfileName>/<title>, skipping the reserved
    % 'protocol' groups, and restore the unsanitized stimfile names. h5info reports
    % groups recursively with full-path names, so groups are classified by depth:
    % one '/' = stimfile group, two '/' = title group under that stimfile.
    originalStimfiles = strsplit(char(string(h5readatt(hdf5FilePath, '/', 'stimfileNames'))), ';');
    allGroups = sort(localCollectGroups(h5info(hdf5FilePath).Groups));
    stimfileGroups = allGroups(count(allGroups, '/') == 1);
    databaseList = {};
    for s = 1:numel(stimfileGroups)
        stimfileGroup = char(stimfileGroups(s));
        stimfileName = localRestoreStimfile(stimfileGroup(2:end), originalStimfiles);
        if ~localMatches(kvargs.Stimfile, stimfileGroup(2:end))
            continue;
        end
        titlePaths = allGroups(startsWith(allGroups, [stimfileGroup, '/']) & count(allGroups, '/') == 2);
        for t = 1:numel(titlePaths)
            title = char(extractAfter(titlePaths(t), [stimfileGroup, '/']));
            if strcmpi(title, 'protocol') || ~localMatches(kvargs.Title, title)
                continue;
            end
            databaseList{end+1, 1} = localReadDatabase(hdf5FilePath, ...
                [stimfileGroup, '/', title], stimfileName, title, ...
                shared, fs, dbFloor, dbStep, fileCreated); %#ok<AGROW>
        end
    end
    if isempty(databaseList)
        error("io:stimuli:spectrogram:importHdf5:NoDatabases", ...
            "No spectrogram database groups matched in %s (Stimfile='%s', Title='%s'). The file contains no exported stimuli or the selection is wrong.", ...
            hdf5FilePath, char(string(kvargs.Stimfile)), char(string(kvargs.Title)));
    end

    databases = [databaseList{:}];
    for k = 1:numel(databases)
        io.stimuli.spectrogram.validateDatabase(databases(k));
    end
end


function database = localReadDatabase(filePath, groupPath, stimfileName, title, shared, fs, dbFloor, dbStep, fileCreated)
    % Reads one /<stimfileName>/<title> group. MATLAB's high-level HDF5 API reverses
    % axes on read, undoing the transpositions applied by exportHdf5's writers.
    time = double(h5read(filePath, [groupPath, '/time']));           % 1 x F (reversed)
    frequency = double(h5read(filePath, [groupPath, '/frequency'])); % 1 x B (reversed)
    nFrames = numel(time);
    nBins = numel(frequency);
    displayFloor = reshape(double(h5read(filePath, [groupPath, '/display_floor'])), 1, []); % C x 1 on disk -> 1 x C
    nChannels = numel(displayFloor);
    spectrogram = reshape(permute(h5read(filePath, [groupPath, '/spectrogram']), [2, 3, 1]), ...
        nBins, nFrames, nChannels);                                  % C x B x F -> B x F x C

    database = struct();
    database.fs = fs;
    database.stimfileName = stimfileName;
    database.title = title;
    database.time = time(:);
    database.frequency = frequency(:);
    database.spectrogram = spectrogram;
    database.dbFloor = dbFloor;
    database.dbStep = dbStep;
    database.amplitudeRms = localReadAmplitude(filePath, [groupPath, '/amplitude_rms'], nFrames, nChannels);
    database.amplitudePeak = localReadAmplitude(filePath, [groupPath, '/amplitude_peak'], nFrames, nChannels);
    database.amplitudeMin = localReadAmplitude(filePath, [groupPath, '/amplitude_min'], nFrames, nChannels);
    database.amplitudeMax = localReadAmplitude(filePath, [groupPath, '/amplitude_max'], nFrames, nChannels);
    database.params = struct( ...
        'hopSamples', shared.hopSamples, ...
        'windowSamples', shared.windowSamples, ...
        'windowFunction', shared.windowFunction, ...
        'overlapRatio', shared.overlapRatio, ...
        'nfft', shared.nfft, ...
        'nChannels', nChannels, ...
        'channelMode', shared.channelMode, ...
        'timeResolution', shared.hopSamples / fs, ...
        'precision', shared.precision, ...
        'dbFloor', dbFloor, ...
        'dbStep', dbStep, ...
        'reference', shared.reference, ...
        'displayFloor', displayFloor, ...
        'displayFloorPercentile', shared.displayFloorPercentile, ...
        'created', fileCreated);
end


function matrix = localReadAmplitude(filePath, datasetPath, nFrames, nChannels)
    % On disk F x C (rows = time frames); MATLAB h5read returns C x F.
    raw = h5read(filePath, datasetPath);
    matrix = reshape(double(raw.'), nFrames, nChannels);
end


function text = localReadText(filePath, datasetPath)
    text = char(string(h5read(filePath, datasetPath)));
end


function groupPaths = localCollectGroups(groupStructs)
    % Recursively collects the full-path names of every group h5info reports,
    % deduplicated (h5info lists groups both nested and flattened).
    groupPaths = strings(0, 1);
    for k = 1:numel(groupStructs)
        name = char(string(groupStructs(k).Name));
        if ~any(groupPaths == name)
            groupPaths(end+1, 1) = string(name); %#ok<AGROW>
        end
        groupPaths = [groupPaths; localCollectGroups(groupStructs(k).Groups)]; %#ok<AGROW>
    end
end


function name = localRestoreStimfile(groupName, originalStimfiles)
    name = groupName;
    for k = 1:numel(originalStimfiles)
        candidate = char(originalStimfiles(k));
        if strcmp(localSanitizeGroupName(candidate), groupName)
            name = candidate;
            return;
        end
    end
end


function tf = localMatches(filterText, groupName)
    filterText = char(string(filterText));
    tf = strtrim(filterText) == "" || strcmpi(localSanitizeGroupName(filterText), groupName);
end


function groupName = localSanitizeGroupName(name)
    % Same sanitization as exportHdf5: HDF5 group names cannot contain '/' or NUL.
    groupName = char(string(name));
    groupName(groupName == '/') = '_';
    groupName(strtrim(groupName) == "") = '_';
    groupName = strtrim(groupName);
end
