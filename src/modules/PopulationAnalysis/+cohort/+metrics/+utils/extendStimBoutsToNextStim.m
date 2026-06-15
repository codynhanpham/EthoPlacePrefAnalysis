function extendedMask = extendStimBoutsToNextStim(sourceStimMask, anyStimMask)
    n = numel(sourceStimMask);
    extendedMask = false(n, 1);

    sourceStarts = find(diff([false; sourceStimMask]) == 1);
    anyStarts = find(diff([false; anyStimMask]) == 1);

    for k = 1:numel(sourceStarts)
        startIdx = sourceStarts(k);
        nextStartCandidates = anyStarts(anyStarts > startIdx);
        if isempty(nextStartCandidates)
            endIdx = n;
        else
            endIdx = nextStartCandidates(1) - 1;
        end
        extendedMask(startIdx:endIdx) = true;
    end
end
