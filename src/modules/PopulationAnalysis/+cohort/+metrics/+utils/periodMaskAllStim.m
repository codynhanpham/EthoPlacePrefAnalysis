function mask = periodMaskAllStim(stimSequence, localStimNames, includeTrailingISI, period)
    if nargin < 4
        period = 'stimulus';
    end

    if isempty(stimSequence)
        mask = false(0, 1);
        return;
    end

    if strcmpi(string(period), 'pre-stimulus')
        mask = strcmpi(strtrim(string(stimSequence)), "NONE | Pre-Stimulus");
        mask = mask(:);
        return;
    end

    anyStimMask = false(numel(stimSequence), 1);
    for i = 1:numel(localStimNames)
        anyStimMask = anyStimMask | endsWith(stimSequence, localStimNames(i), 'IgnoreCase', true);
    end

    if ~includeTrailingISI
        mask = anyStimMask;
        return;
    end

    mask = cohort.metrics.utils.extendStimBoutsToNextStim(anyStimMask, anyStimMask);
end
