function boutMasks = stimBoutMasksForStim(stimSequence, stimName, allStimNames, includeTrailingISI)
%STIMBOUTMASKSFORSTIM Return one point-mask per detected stimulus bout.
% Each bout starts at a source-stimulus onset. If includeTrailingISI is true,
% the bout extends until the sample before the next stimulus onset.

    n = numel(stimSequence);
    boutMasks = {};
    if n == 0
        return;
    end

    stimMask = endsWith(stimSequence, stimName, 'IgnoreCase', true);
    if ~any(stimMask)
        return;
    end

    if includeTrailingISI
        anyStimMask = false(n, 1);
        for i = 1:numel(allStimNames)
            anyStimMask = anyStimMask | endsWith(stimSequence, allStimNames(i), 'IgnoreCase', true);
        end

        starts = find(diff([false; stimMask]) == 1);
        anyStarts = find(diff([false; anyStimMask]) == 1);
        boutMasks = cell(numel(starts), 1);
        for k = 1:numel(starts)
            startIdx = starts(k);
            nextStart = anyStarts(find(anyStarts > startIdx, 1, 'first'));
            if isempty(nextStart)
                endIdx = n;
            else
                endIdx = nextStart - 1;
            end

            mask = false(n, 1);
            mask(startIdx:endIdx) = true;
            boutMasks{k} = mask;
        end
        return;
    end

    runStarts = find(diff([false; stimMask; false]) == 1);
    runEnds = find(diff([false; stimMask; false]) == -1) - 1;
    boutMasks = cell(numel(runStarts), 1);
    for k = 1:numel(runStarts)
        mask = false(n, 1);
        mask(runStarts(k):runEnds(k)) = true;
        boutMasks{k} = mask;
    end
end
