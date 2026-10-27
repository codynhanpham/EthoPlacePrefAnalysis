function t = zoneOccupancy(standardizedTables, kvargs)
    %%ZONEOCCUPANCY Cohort summary of percent time near the arena midline
    %   Reports the interval-weighted percent of time the center point spends
    %   within MidlineZoneHalfWidthCm (cm) of the midline (|Distance from
    %   Midline| < half-width) during each period mask. The half-width is a
    %   name-value parameter and is NOT embedded in the output column names.
    %
    %   Reports the aggregate value during the whole active stimulus period and
    %   during each stimulus-specific active period. During the pre-stimulus
    %   period (Period='pre-stimulus'), only the aggregate column is emitted.

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
        kvargs.Period {mustBeMember(kvargs.Period, {'stimulus', 'pre-stimulus'}), mustBeTextScalar} = 'stimulus'
        kvargs.MidlineZoneHalfWidthCm (1,1) double {mustBePositive, mustBeFinite} = 10
    end

    if isempty(standardizedTables)
        t = table();
        return;
    end

    isPreStim = strcmpi(kvargs.Period, 'pre-stimulus');
    if isPreStim
        periodPhrase = 'Pre-Stimulus';
    else
        periodPhrase = 'Stimulus';
    end

    hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
    overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
    outputStimNames = cohort.metrics.utils.getOutputStimNames(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
    nOutputStims = numel(outputStimNames);

    nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);
    [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);

    zoneAllCol = nan(nRowsEstimate, 1);
    zoneByStimCols = nan(nRowsEstimate, nOutputStims);

    rowIdx = 0;
    for i = 1:length(standardizedTables)
        stdTable = standardizedTables(i);
        midlineInfo = cohort.metrics.utils.getMidlineSideInfo(stdTable, StimulusIncludesTrailingISI=kvargs.StimulusIncludesTrailingISI, Period=kvargs.Period);

        localStimNames = midlineInfo.localStimNames;

        localIdxByOutputStim = zeros(nOutputStims, 1);
        if hasOverride
            localDisplayNames = localOverrideLabels(overrideSpec, i);
            for g = 1:nOutputStims
                idx = find(strcmpi(localDisplayNames, outputStimNames(g)), 1, 'first');
                if isempty(idx)
                    localIdxByOutputStim(g) = 0;
                else
                    localIdxByOutputStim(g) = idx;
                end
            end
        else
            for g = 1:nOutputStims
                idx = cohort.metrics.utils.firstMatchingStimIndex(localStimNames, outputStimNames(g), hasOverride);
                if isempty(idx)
                    localIdxByOutputStim(g) = 0;
                else
                    localIdxByOutputStim(g) = idx;
                end
            end
        end

        animalKeys = keys(stdTable.animalMetadata);
        nAnimals = size(midlineInfo.distanceFromMidline, 2);

        for col = 1:nAnimals
            rowIdx = rowIdx + 1;

            md = struct();
            if col <= numel(animalKeys)
                md = stdTable.animalMetadata(animalKeys{col});
            end
            [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
                cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stdTable.stimfileName);

            distanceVec = midlineInfo.distanceFromMidline(:, col);
            zoneAllCol(rowIdx) = percentTimeNearMidline(distanceVec, midlineInfo.trialTime, midlineInfo.allStimMask, kvargs.MidlineZoneHalfWidthCm);

            localZone = nan(numel(localStimNames), 1);
            for s = 1:numel(localStimNames)
                localZone(s) = percentTimeNearMidline(distanceVec, midlineInfo.trialTime, midlineInfo.stimMasks{s}, kvargs.MidlineZoneHalfWidthCm);
            end
            for g = 1:nOutputStims
                zoneByStimCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localZone, localIdxByOutputStim(g));
            end
        end
    end

    if rowIdx < nRowsEstimate
        keep = 1:rowIdx;
        mouseIdCol = mouseIdCol(keep);
        geneCol = geneCol(keep);
        cageCodeCol = cageCodeCol(keep);
        geneIdCol = geneIdCol(keep);
        sexCol = sexCol(keep);
        genotypeCol = genotypeCol(keep);
        litterCol = litterCol(keep);
        toeIdCol = toeIdCol(keep);
        dobCol = dobCol(keep);
        ageCol = ageCol(keep);
        stimProtocolCol = stimProtocolCol(keep);
        zoneAllCol = zoneAllCol(keep);
        zoneByStimCols = zoneByStimCols(keep, :);
    end

    t = table();
    t.('Mouse_ID') = mouseIdCol;
    t.('Gene') = geneCol;
    t.('Cage #') = cageCodeCol;
    t.('Gene_ID') = geneIdCol;
    t.('Sex$') = sexCol;
    t.('Genotype$') = genotypeCol;
    t.('Litter') = litterCol;
    t.('Toe_ID') = toeIdCol;
    t.('DOB') = dobCol;
    t.('Age') = ageCol;
    t.('Stimulus Protocol') = stimProtocolCol;

    t.(sprintf('Percent Time Near Midline During %s (%%)', periodPhrase)) = zoneAllCol;
    if ~isPreStim
        for g = 1:nOutputStims
            stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
            t.(sprintf('Percent Time Near Midline During %s (%%)', stimLabel)) = zoneByStimCols(:, g);
        end
    end
end


function pct = percentTimeNearMidline(distanceVec, trialTime, activeMask, halfWidthCm)
    if isempty(distanceVec) || isempty(trialTime) || isempty(activeMask)
        pct = NaN;
        return;
    end

    distanceVec = distanceVec(:);
    trialTime = trialTime(:);
    activeMask = activeMask(:) & isfinite(distanceVec) & isfinite(trialTime);
    if numel(distanceVec) ~= numel(trialTime) || numel(activeMask) ~= numel(trialTime)
        pct = NaN;
        return;
    end

    intervalMask = activeMask(1:end-1) & activeMask(2:end);
    dt = diff(trialTime);
    validIntervals = intervalMask & isfinite(dt) & (dt > 0);
    activeTime = sum(dt(validIntervals), 'omitnan');
    if ~(isfinite(activeTime) && activeTime > 0)
        pct = NaN;
        return;
    end

    inZone = abs(distanceVec) < halfWidthCm;
    zoneIntervals = validIntervals & inZone(1:end-1) & inZone(2:end);
    zoneTime = sum(dt(zoneIntervals), 'omitnan');
    pct = 100 * zoneTime / activeTime;
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
    if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
        labels = string(overrideSpec{tableIdx});
    else
        labels = string(overrideSpec);
    end
    labels = labels(:);
end
