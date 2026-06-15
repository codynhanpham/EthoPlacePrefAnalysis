function idx = firstMatchingStimIndex(localNames, referenceName, hasOverride)
    idx = [];
    if isempty(localNames)
        return;
    end

    for i = 1:numel(localNames)
        if cohort.metrics.utils.localNameMatchesReference(localNames(i), referenceName, hasOverride)
            idx = i;
            return;
        end
    end
end
