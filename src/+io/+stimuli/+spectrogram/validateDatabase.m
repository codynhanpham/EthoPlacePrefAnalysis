function validateDatabase(spectrogramDb)
    %%VALIDATEDATABASE Validate that a struct is a spectrogram database from io.stimuli.spectrogram.precompute.
    %   Validates the struct shape produced by io.stimuli.spectrogram.precompute:
    %   required fields, spectrogram size (B x F x C), and amplitude sizes (F x C).
    %   Raises io:stimuli:spectrogram:validateDatabase:InvalidDatabase on failure.
    %
    %   USAGE:
    %       io.stimuli.spectrogram.validateDatabase(spectrogramDb)
    %
    %   See also: io.stimuli.spectrogram.precompute, io.stimuli.spectrogram.plot, io.stimuli.spectrogram.exportHdf5

    requiredFields = {'fs', 'time', 'frequency', 'spectrogram', 'dbFloor', 'dbStep', ...
        'amplitudeRms', 'amplitudePeak', 'amplitudeMin', 'amplitudeMax', 'params'};
    if ~isstruct(spectrogramDb) || numel(spectrogramDb) ~= 1
        error("io:stimuli:spectrogram:validateDatabase:InvalidDatabase", ...
            "spectrogramDb must be a scalar struct returned by io.stimuli.spectrogram.precompute.");
    end
    missingFields = setdiff(requiredFields, fieldnames(spectrogramDb));
    if ~isempty(missingFields)
        error("io:stimuli:spectrogram:validateDatabase:InvalidDatabase", ...
            "spectrogramDb is missing required fields: %s. Was it produced by io.stimuli.spectrogram.precompute?", ...
            strjoin(missingFields, ', '));
    end
    nFrames = numel(spectrogramDb.time);
    nChannels = size(spectrogramDb.amplitudeRms, 2);
    if size(spectrogramDb.spectrogram, 1) ~= numel(spectrogramDb.frequency) ...
            || size(spectrogramDb.spectrogram, 2) ~= nFrames ...
            || size(spectrogramDb.spectrogram, 3) ~= nChannels
        error("io:stimuli:spectrogram:validateDatabase:InvalidDatabase", ...
            "spectrogramDb.spectrogram must be B x F x C (bins x time-frames x channels). Got size [%s].", ...
            num2str(size(spectrogramDb.spectrogram)));
    end
    amplitudeFields = {'amplitudeRms', 'amplitudePeak', 'amplitudeMin', 'amplitudeMax'};
    for f = 1:numel(amplitudeFields)
        if size(spectrogramDb.(amplitudeFields{f}), 1) ~= nFrames ...
                || size(spectrogramDb.(amplitudeFields{f}), 2) ~= nChannels
            error("io:stimuli:spectrogram:validateDatabase:InvalidDatabase", ...
                "spectrogramDb.%s must be F x C (time-frames x channels). Got size [%s].", ...
                amplitudeFields{f}, num2str(size(spectrogramDb.(amplitudeFields{f}))));
        end
    end
end
