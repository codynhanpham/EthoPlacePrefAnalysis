function [status, message] = audio2hdf5(audioFiles, hdf5File, kvargs)
    %%AUDIO2HDF5 End-to-end conversion of audio files to precomputed spectrograms stored in HDF5 format.
    %   This function takes one or more audio stimulus files, extracts their chapter
    %   metadata, splits them into unique stimuli (the first repeat of each chapter
    %   title), pre-computes their spectrogram databases, and exports everything into
    %   a single HDF5 file with groups nested /<stimfileName>/<title> (see
    %   io.stimuli.spectrogram.exportHdf5 for the format).
    %
    %   All audio files are required to be of the same sample rate, since the exported
    %   spectrograms must share a single frequency/time domain scaling; otherwise an
    %   error is raised and the files should be exported into separate HDF5 files.
    %
    %   Audio files that contain no chapter metadata yield no stimuli and are skipped
    %   with a warning; if no stimuli are found at all, an error is raised.
    %
    %   Each file's chapter metadata is stored storage-efficiently as its protocol
    %   under /<stimfileName>/protocol (repeated chapter titles and descriptions are
    %   deduplicated into int32 codes + category lists; see io.stimuli.spectrogram.exportHdf5).
    %
    %   This function requires either the 'nidaq_audioplayer' or 'metadata_extract'
    %   binary to be available for metadata extraction (see io.stimuli.extractMetadata).
    %
    %   USAGE:
    %       [status, message] = io.stimuli.spectrogram.audio2hdf5(audioFiles, hdf5File)
    %       [status, message] = io.stimuli.spectrogram.audio2hdf5({'a.flac', 'b.flac'}, 'spectrograms.hdf5', 'TimeResolution', 0.005)
    %
    %   Inputs:
    %       audioFiles: A path or a cell array of paths to audio files to be converted. Duplicate paths are converted once.
    %       hdf5File: A path to the HDF5 file where the precomputed spectrograms will be stored.
    %
    %   Name-Value Pair Arguments:
    %       Metadata extraction (passed to io.stimuli.extractMetadata):
    %           'Config': Configuration struct for detecting the extraction binary.
    %           'BinaryPath': Explicit path to the extraction binary.
    %       Spectrogram computation (passed to io.stimuli.spectrogram.precompute):
    %           'TimeResolution': Frame hop duration in seconds. Default 0.001 (1 ms).
    %           'WindowSeconds': Hann window duration in seconds. Default 2 x 'TimeResolution'.
    %           'ChannelMode': 'all' (default, per-channel spectrograms) or 'mono'.
    %           'Precision': 'uint8' (default), 'single', or 'double'.
    %           'DbFloor': Quantization floor in dB below peak. Default -80.
    %           'DisplayFloorPercentile': Noise-floor percentile for display contrast. Default 50.
    %       Export (passed to io.stimuli.spectrogram.exportHdf5):
    %           'Overwrite': Whether to replace an existing output file. Default false.
    %
    %   Outputs:
    %       status: A logical indicating whether the conversion was successful.
    %       message: A string containing a message about the operation.
    %
    %   See also: io.stimuli.extractMetadata, io.stimuli.metadata2stimsamples, io.stimuli.spectrogram.precompute, io.stimuli.spectrogram.exportHdf5

    arguments
        audioFiles {mustBeNonempty}
        hdf5File {validator.mustBeValidFilepath}
        kvargs.Config (1,1) struct = struct()
        kvargs.BinaryPath {mustBeTextScalar} = ""
        kvargs.TimeResolution (1,1) double {mustBePositive, mustBeFinite} = 0.001
        kvargs.WindowSeconds double = []
        kvargs.ChannelMode {mustBeTextScalar} = "all"
        kvargs.Precision {mustBeTextScalar} = "uint8"
        kvargs.DbFloor (1,1) double {mustBeNegative, mustBeFinite} = -80
        kvargs.DisplayFloorPercentile (1,1) double {mustBeInRange(kvargs.DisplayFloorPercentile, 0, 100)} = 50
        kvargs.Overwrite (1,1) logical = false
    end

    % Normalize the input into a deduplicated list of existing audio files.
    if ischar(audioFiles)
        audioFiles = cellstr(audioFiles);
    elseif isstring(audioFiles)
        audioFiles = cellstr(audioFiles(:));
    elseif ~iscell(audioFiles)
        error("io:stimuli:spectrogram:audio2hdf5:InvalidInput", ...
            "audioFiles must be a path or a cell/string array of paths to audio files.");
    end
    audioFiles = unique(cellstr(audioFiles(:)), 'stable');
    for f = 1:numel(audioFiles)
        if ~isfile(audioFiles{f})
            error("io:stimuli:spectrogram:audio2hdf5:FileNotFound", ...
                "Audio file not found: %s", audioFiles{f});
        end
    end

    % Extract metadata first (cheap) so the shared sample rate can be verified before
    % any expensive audio processing. Exported spectrograms must share one scaling.
    metadataList = cell(numel(audioFiles), 1);
    for f = 1:numel(audioFiles)
        metadataList{f} = io.stimuli.extractMetadata(audioFiles{f}, ...
            'Config', kvargs.Config, 'BinaryPath', kvargs.BinaryPath);
    end
    emptySampleRates = cellfun(@(m) isempty(m.sample_rate), metadataList);
    if any(emptySampleRates)
        error("io:stimuli:spectrogram:audio2hdf5:MissingSampleRate", ...
            "Metadata for audio file(s) %s has no sample rate.", ...
            strjoin(audioFiles(emptySampleRates), ', '));
    end
    sampleRates = cellfun(@(m) double(m.sample_rate), metadataList);
    if any(sampleRates ~= sampleRates(1))
        mismatchedFiles = audioFiles(sampleRates ~= sampleRates(1));
        error("io:stimuli:spectrogram:audio2hdf5:SampleRateMismatch", ...
            "All audio files must share the same sample rate to be exported into one HDF5 file: %s is %g Hz, but %s is %g Hz. Export them into separate HDF5 files.", ...
            audioFiles{1}, sampleRates(1), mismatchedFiles{1}, sampleRates(find(sampleRates ~= sampleRates(1), 1)));
    end

    % Convert each file's unique stimuli into spectrogram databases, collecting each
    % file's chapter metadata as its protocol for the HDF5 export.
    databases = {};
    protocols = struct('stimfileName', {}, 'chapters', {});
    for f = 1:numel(audioFiles)
        stimuli = io.stimuli.metadata2stimsamples(metadataList{f});
        if isempty(stimuli)
            warning("io:stimuli:spectrogram:audio2hdf5:NoStimuliInFile", ...
                "Audio file %s contains no stimulus chapters; skipping.", audioFiles{f});
            continue;
        end
        fprintf('(%d/%d) %s: %d unique stimuli\n', f, numel(audioFiles), audioFiles{f}, numel(stimuli));
        protocols(end+1).stimfileName = stimuli(1).stimfileName; %#ok<AGROW>
        protocols(end).chapters = metadataList{f}.chapters; %#ok<AGROW>
        for s = 1:numel(stimuli)
            databases{end+1, 1} = io.stimuli.spectrogram.precompute(stimuli(s).samples, stimuli(s).sample_rate, ...
                'StimfileName', stimuli(s).stimfileName, 'Title', stimuli(s).title, ...
                'TimeResolution', kvargs.TimeResolution, 'WindowSeconds', kvargs.WindowSeconds, ...
                'ChannelMode', kvargs.ChannelMode, 'Precision', kvargs.Precision, ...
                'DbFloor', kvargs.DbFloor, 'DisplayFloorPercentile', kvargs.DisplayFloorPercentile); %#ok<AGROW>
        end
    end
    if isempty(databases)
        error("io:stimuli:spectrogram:audio2hdf5:NoStimuli", ...
            "None of the provided audio files contain stimulus chapters. Nothing to export.");
    end

    [status, message] = io.stimuli.spectrogram.exportHdf5(databases, hdf5File, ...
        'Overwrite', kvargs.Overwrite, 'Protocols', protocols);
end
