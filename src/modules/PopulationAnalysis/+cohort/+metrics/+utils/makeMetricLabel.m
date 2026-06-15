function label = makeMetricLabel(stimName, fallbackIndex)
    stimName = string(stimName);
    if strlength(stimName) == 0
        label = sprintf('StimuliSorted(%d)', fallbackIndex);
    else
        label = char(stimName);
    end
end
