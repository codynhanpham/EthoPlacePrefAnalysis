function t = speedSlope(standardizedTables, kvargs)
    %%SPEEDSLOPE Cohort summary of the speed trend across a period
    %   Computes the OLS slope of per-bin median instantaneous speed (cm/s)
    %   within the period mask, reported in cm/s per minute. Bins are
    %   SlopeBinSec seconds wide, anchored at the first masked sample time.
    %   Negative values indicate slowing (e.g., habituation) across the
    %   period; positive values indicate speeding up (e.g., sensitization).
    %   NaN when fewer than 3 bins contain valid segments.
    %
    %   Only the aggregate column is emitted (for both stimulus and
    %   pre-stimulus periods).

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
        kvargs.Period {mustBeMember(kvargs.Period, {'stimulus', 'pre-stimulus'}), mustBeTextScalar} = 'stimulus'
        kvargs.SlopeBinSec (1,1) double {mustBePositive, mustBeFinite} = 60
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

    nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);
    [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);

    slopeAllCol = nan(nRowsEstimate, 1);

    rowIdx = 0;
    for i = 1:length(standardizedTables)
        stdTable = standardizedTables(i);
        cp = stdTable.centerpointData;

        trialTime = cp{:, 'Trial time'};
        stimSequence = string(cp{:, 'Stimulus name'});
        xData = cp{:, 'X center'};
        yData = cp{:, 'Y center'};
        nAnimals = size(xData, 2);

        localStimNames = string(stdTable.stimuliSorted);
        localStimNames = localStimNames(:);

        allStimPointMask = cohort.metrics.utils.periodMaskAllStim(stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI, kvargs.Period);

        animalKeys = keys(stdTable.animalMetadata);
        for col = 1:nAnimals
            rowIdx = rowIdx + 1;

            md = struct();
            if col <= numel(animalKeys)
                md = stdTable.animalMetadata(animalKeys{col});
            end
            [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
                cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stdTable.stimfileName);

            thisX = xData(:, col);
            thisY = yData(:, col);
            slopeAllCol(rowIdx) = speedSlopeWithinMask(thisX, thisY, trialTime, allStimPointMask, kvargs.SlopeBinSec);
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
        slopeAllCol = slopeAllCol(keep);
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

    t.(sprintf('Speed Slope During %s (cm/s per min)', periodPhrase)) = slopeAllCol;
end


function slopePerMin = speedSlopeWithinMask(x, y, t, pointMask, binSec)
    if isempty(x) || isempty(y) || isempty(t) || numel(t) < 2
        slopePerMin = NaN;
        return;
    end

    if numel(pointMask) ~= numel(t)
        pointMask = false(size(t));
    end

    dx = diff(x);
    dy = diff(y);
    dt = diff(t);
    stepDist = sqrt(dx.^2 + dy.^2);
    instSpeed = stepDist ./ dt;

    segMask = pointMask(1:end-1) & pointMask(2:end) & isfinite(instSpeed) & isfinite(dt) & (dt > 0);
    if ~any(segMask)
        slopePerMin = NaN;
        return;
    end

    segStartTimes = t(1:end-1);
    maskedStartTimes = segStartTimes(segMask);
    maskedSpeeds = instSpeed(segMask);

    t0 = maskedStartTimes(1);
    binIdx = floor((maskedStartTimes - t0) / binSec);
    uniqueBins = unique(binIdx);
    if numel(uniqueBins) < 3
        slopePerMin = NaN;
        return;
    end

    binMedians = nan(numel(uniqueBins), 1);
    for b = 1:numel(uniqueBins)
        binMedians(b) = median(maskedSpeeds(binIdx == uniqueBins(b)), 'omitnan');
    end

    binCentersSec = (uniqueBins(:) + 0.5) * binSec;
    p = polyfit(binCentersSec, binMedians, 1);
    slopePerMin = p(1) * 60;
end
