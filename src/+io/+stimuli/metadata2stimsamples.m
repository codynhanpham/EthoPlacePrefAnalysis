function data = metadata2stimsamples(metadata, stimulusFileOverride, kvargs)
    %%METADATA2STIMSAMPLES Given a metadata struct, return the audio samples of unique stimuli
    %   This function takes a metadata struct (as returned by io.stimuli.extractMetadata) and returns a struct containing the audio samples of each unique stimulus. If a stimulus file is provided, it will override the stimulus file path in the metadata.
    %   Note that this function uses the chapters.title to determine the unique stimuli, so if there are different stimuli sharing the same title, they will be treated as the same stimulus.
    %   Each unique stimulus is represented by the FIRST of its repeats, extracted from its chapter start sample up to (but not including) the next chapter's start sample; the last chapter runs to the end of the audio file. Repeats sharing a title are expected to be identical, so a single repeat represents the stimulus; 'repeat' and 'start_samples' record every repeat's location in the original file so the full repeated version can be reconstructed later if needed. Chapter boundaries are determined BEFORE the ExclusionRules are applied, so a retained chapter never includes the audio of a following excluded chapter (e.g. an ISI between repeats).
    %
    %   data = io.stimuli.metadata2stimsamples(metadata)
    %
    % Inputs:
    %   metadata: Struct containing the extracted metadata (as returned by io.stimuli.extractMetadata)
    %   stimulusFileOverride: (optional) Path to the stimulus file to override the stimulus file path in the metadata. If provided, this file will be used to extract the audio samples instead of the stimulus file path in the metadata.
    %
    % Name-Value Pair Arguments:
    %   'ExclusionRules': (cell array of function handles) List of functions that take a chapter title as input and return true (scalar or per-pattern logical vector) if the chapter should be excluded from the unique stimuli. The functions must accept a single text input. Default excludes chapters whose titles equal, start with, or end with 'isi', 'intro', or 'outro' (case-insensitively, after trimming whitespace). Pass in `{}` to disable all exclusions. Exclusions only remove chapters from the output; they do not shift the chapter boundaries of retained chapters.
    %
    % Outputs:
    %   data: struct array containing the audio data
    %       - 'title': title of the stimulus
    %       - 'stimfileName': file name (with extension) of the audio file the samples were read from (follows stimulusFileOverride when provided, otherwise metadata.path)
    %       - 'samples': audio samples of ONE repeat of the stimulus
    %       - 'sample_rate': sample rate of the audio file as read (a warning is issued if it differs from the metadata sample rate)
    %       - 'length': length of `samples` (one repeat) - use length/sample_rate to get the duration in seconds
    %       - 'repeat': number of chapters (repeats) of this unique stimulus in the metadata
    %       - 'start_samples': array of start sample indices (1-based) for each repeat of this unique stimulus in the metadata

    arguments
        metadata (1,1) struct
        stimulusFileOverride {validator.mustBeFileOrEmpty} = ''
        kvargs.ExclusionRules (1,:) cell = {
            @(x) ismember(lower(strtrim(x)), {'isi', 'intro', 'outro'}), ...
            @(x) endsWith(lower(strtrim(x)), {'isi', 'intro', 'outro'}), ...
            @(x) startsWith(lower(strtrim(x)), {'isi', 'intro', 'outro'}) ...
        }
    end

    % Validate that each exclusion rule is a function handle
    for r = 1:numel(kvargs.ExclusionRules)
        if ~isa(kvargs.ExclusionRules{r}, 'function_handle')
            error("io:stimuli:metadata2stimsamples:InvalidExclusionRule", ...
                "ExclusionRules{%d} must be a function handle, got a %s.", r, class(kvargs.ExclusionRules{r}));
        end
    end

    % metadata required fields
    requiredFields = {'sample_rate', 'path', 'chapters'};
    missingFields = setdiff(requiredFields, fieldnames(metadata));
    if ~isempty(missingFields)
        error("io:stimuli:metadata2stimsamples:MissingFields", "Metadata struct is missing required fields: %s", strjoin(missingFields, ", "));
    end

    % Return an empty struct array if there are no chapters
    if isempty(metadata.chapters)
        data = struct('title', {}, 'stimfileName', {}, 'samples', {}, 'sample_rate', {}, 'length', {}, 'repeat', {}, 'start_samples', {});
        return;
    end

    % Resolve the 1-based start sample of each chapter. Falls back to the
    % chapter timestamp (in seconds) when 'startsample' is absent, using the
    % metadata sample rate (the rate the chapter indices were generated at).
    nChapters = numel(metadata.chapters);
    startSamples = zeros(nChapters, 1);
    for k = 1:nChapters
        chapter = metadata.chapters(k);
        if isfield(chapter, 'startsample') && ~isempty(chapter.startsample)
            rawStart = chapter.startsample;
        elseif isfield(chapter, 'timestamp') && ~isempty(chapter.timestamp) && ~isempty(metadata.sample_rate)
            rawStart = round(double(chapter.timestamp) * double(metadata.sample_rate)) + 1;
        else
            error("io:stimuli:metadata2stimsamples:MissingStartSample", "Chapter %d has neither 'startsample' nor 'timestamp' (with a non-empty metadata sample_rate) to locate its start.", k);
        end
        startSamples(k) = localValidateStartSample(rawStart, k);
    end

    % Chapters must be in chronological order to determine segment ends
    [startSamples, order] = sort(startSamples);
    titles = {metadata.chapters(order).title};

    % Segment ends are the start of the next chapter (minus one), computed BEFORE the
    % exclusion rules: a chapter's audio must end at the next chapter even when that
    % chapter is excluded (e.g. an ISI between repeats). The last chapter is bounded
    % by the audio length, resolved after the file has been inspected below.
    endSamples = [startSamples(2:end) - 1; Inf];

    % Apply the exclusion rules to filter out unwanted chapters (e.g. ISIs,
    % intros, outros). A chapter is excluded if any rule returns true.
    excludeMask = false(numel(titles), 1);
    for k = 1:numel(titles)
        for r = 1:numel(kvargs.ExclusionRules)
            ruleResult = kvargs.ExclusionRules{r}(titles{k});
            if any(ruleResult(:))
                excludeMask(k) = true;
                break;
            end
        end
    end
    % Uncomment this if you want to log a warning about excluded chapters
    % Typically this is not necessary
    % if any(excludeMask)
    %     warning("io:stimuli:metadata2stimsamples:ChaptersExcluded", ...
    %         "Excluded %d of %d chapters based on ExclusionRules.", nnz(excludeMask), numel(titles));
    % end
    startSamples(excludeMask) = [];
    endSamples(excludeMask) = [];
    titles(excludeMask) = [];

    % Return an empty struct array if no chapters remain after exclusion
    if isempty(titles)
        data = struct('title', {}, 'stimfileName', {}, 'samples', {}, 'sample_rate', {}, 'length', {}, 'repeat', {}, 'start_samples', {});
        return;
    end

    % Determine the stimulus file to use
    if ~isempty(stimulusFileOverride)
        stimulusFile = stimulusFileOverride;
    else
        stimulusFile = metadata.path;
    end

    % Stimfile identity passed through to the outputs (file name with extension),
    % used by downstream HDF5 exports to group stimuli by their source file.
    [~, stimulusName, stimulusExt] = fileparts(char(stimulusFile));
    stimfileName = [stimulusName, stimulusExt];

    % Get audio file info (done last so all metadata validation and filtering happens
    % before this operation). Segments are read on demand below, so the whole file is
    % never buffered in memory.
    try
        audioInfo = audioinfo(stimulusFile);
    catch ME
        error("io:stimuli:metadata2stimsamples:AudioReadError", "Failed to read audio file '%s': %s", stimulusFile, getReport(ME));
    end
    totalSamples = floor(double(audioInfo.TotalSamples));
    sampleRate = audioInfo.SampleRate;
    endSamples(isinf(endSamples)) = totalSamples;

    % Warn if the audio file sample rate does not match the metadata sample rate
    if ~isempty(metadata.sample_rate) && double(metadata.sample_rate) ~= sampleRate
        warning("io:stimuli:metadata2stimsamples:SampleRateMismatch", ...
            "Audio file sample rate (%g Hz) differs from metadata sample rate (%g Hz). Start sample indices may be inaccurate.", ...
            sampleRate, double(metadata.sample_rate));
    end

    % Get unique titles (in order of first appearance) and their chapter indices
    [uniqueTitles, ~, idx] = unique(titles, 'stable');

    % Initialize the output struct array
    data = repmat(struct('title', '', 'stimfileName', stimfileName, 'samples', [], 'sample_rate', sampleRate, ...
        'length', 0, 'repeat', 0, 'start_samples', []), numel(uniqueTitles), 1);

    % Populate the samples and other fields for each unique title
    for i = 1:numel(uniqueTitles)
        % Get the chapter indices (and start samples) for this unique title
        chapterIndices = find(idx == i);
        currentStartSamples = startSamples(chapterIndices);

        % Extract the samples of the first repeat of this unique title. Repeats with
        % the same title are expected to be identical, so one repeat represents the
        % stimulus; all repeats' start samples remain available in 'start_samples' to
        % reconstruct the full repeated version from the original file if ever needed.
        startSample = currentStartSamples(1);
        endSample = endSamples(chapterIndices(1));
        if startSample < 1 || startSample > totalSamples || endSample < startSample
            warning("io:stimuli:metadata2stimsamples:StartSampleOutOfBounds", ...
                "Chapter segment [%d, %d] is out of bounds for audio data of length %d. Skipping.", ...
                startSample, endSample, totalSamples);
            samples = [];
        else
            segmentEnd = min(endSample, totalSamples);
            try
                samples = audioread(stimulusFile, [startSample, segmentEnd]);
            catch ME
                error("io:stimuli:metadata2stimsamples:AudioReadError", "Failed to read audio range [%d, %d] from '%s': %s", startSample, segmentEnd, stimulusFile, getReport(ME));
            end
        end

        % Populate the fields in the output struct
        data(i).title = uniqueTitles{i};
        data(i).stimfileName = stimfileName;
        data(i).samples = samples;
        data(i).length = size(samples, 1);
        data(i).repeat = numel(currentStartSamples);
        data(i).start_samples = currentStartSamples;
    end
end


function startSample = localValidateStartSample(rawStart, chapterIndex)
    % Chapter start samples must be positive finite integer sample indices; anything
    % else (NaN, fractional, non-numeric) would otherwise index unpredictably or fail
    % with raw MATLAB indexing errors.
    if ~isscalar(rawStart) || ~isnumeric(rawStart) || ~isfinite(rawStart) || rawStart < 1 || rawStart ~= floor(rawStart)
        if isnumeric(rawStart) || islogical(rawStart)
            valueText = mat2str(rawStart);
        else
            valueText = char(string(rawStart));
        end
        error("io:stimuli:metadata2stimsamples:InvalidStartSample", ...
            "Chapter %d has an invalid start sample value (%s). It must be a positive finite integer sample index.", ...
            chapterIndex, valueText);
    end
    startSample = double(rawStart);
end