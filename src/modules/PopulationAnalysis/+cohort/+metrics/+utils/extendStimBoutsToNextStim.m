function extendedMask = extendStimBoutsToNextStim(sourceStimMask, anyStimMask)
    n = numel(sourceStimMask);
    extendedMask = false(n, 1);

    sourceStimMask = logical(sourceStimMask(:));
    anyStimMask = logical(anyStimMask(:));

    sourceStarts = find(diff([false; sourceStimMask]) == 1);
    anyStarts = find(diff([false; anyStimMask]) == 1);
    anyEnds = find(diff([anyStimMask; false]) == -1);

    for k = 1:numel(sourceStarts)
        startIdx = sourceStarts(k);
        nextStartCandidates = anyStarts(anyStarts > startIdx);
        if isempty(nextStartCandidates)
            thisStimEndIdx = anyEnds(find(anyEnds >= startIdx, 1, 'first'));
            if isempty(thisStimEndIdx)
                endIdx = startIdx;
            else
                endIdx = thisStimEndIdx;
            end
        else
            endIdx = nextStartCandidates(1) - 1;
        end
        extendedMask(startIdx:endIdx) = true;
    end
end
