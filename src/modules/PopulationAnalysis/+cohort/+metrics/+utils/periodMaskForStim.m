function mask = periodMaskForStim(stimSequence, stimName, allStimNames, includeTrailingISI, period)
    if nargin < 5
        period = 'stimulus';
    end

    if isempty(stimSequence)
        mask = false(0, 1);
        return;
    end

    if strcmpi(string(period), 'pre-stimulus')
        % During the pre-stimulus window there is no stimulus-specific time
        % structure: every "per-stim" window is the full pre-stimulus block.
        mask = strcmpi(strtrim(string(stimSequence)), "NONE | Pre-Stimulus");
        mask = mask(:);
        return;
    end

    stimMask = endsWith(stimSequence, stimName, 'IgnoreCase', true);
    if ~includeTrailingISI
        mask = stimMask;
        return;
    end

    anyStimMask = false(numel(stimSequence), 1);
    for i = 1:numel(allStimNames)
        % The stimName might have [Ch#] or similar prefixes, so match by endsWith
        anyStimMask = anyStimMask | endsWith(stimSequence, allStimNames(i), 'IgnoreCase', true);
    end

    mask = cohort.metrics.utils.extendStimBoutsToNextStim(stimMask, anyStimMask);
end
