function mask = periodMaskForStim(stimSequence, stimName, allStimNames, includeTrailingISI)
    if isempty(stimSequence)
        mask = false(0, 1);
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
