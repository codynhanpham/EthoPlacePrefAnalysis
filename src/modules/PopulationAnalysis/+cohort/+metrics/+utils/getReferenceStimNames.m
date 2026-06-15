function referenceStimNames = getReferenceStimNames(standardizedTables, override)
    overrideNames = string(sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, override));
    overrideNames = overrideNames(:);
    if ~isempty(overrideNames)
        referenceStimNames = overrideNames(1:2);
        return;
    end

    referenceStimNames = string(standardizedTables(1).stimuliSorted);
    if isempty(referenceStimNames)
        referenceStimNames = strings(0, 1);
    else
        referenceStimNames = referenceStimNames(:);
    end
end
