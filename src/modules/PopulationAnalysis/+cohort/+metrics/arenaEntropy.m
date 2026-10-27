function t = arenaEntropy(standardizedTables, kvargs)
    %%ARENAENTROPY Cohort summary of arena occupancy entropy (exploration span)
    %   Occupancy entropy is the Shannon entropy (in bits) of the 2-D position
    %   occupancy histogram over square bins of BinSizeCm (cm), computed from
    %   the standardized X/Y center coordinates within each period mask. Bin
    %   edges are shared across animals within a standardizedTable (derived
    %   from the table-wide coordinate range), so values are comparable across
    %   animals of the same table. Higher values indicate more spread-out
    %   exploration of the arena.
    %
    %   Reports the aggregate value during the whole active stimulus period and
    %   during each stimulus-specific active period. During the pre-stimulus
    %   period (Period='pre-stimulus'), only the aggregate column is emitted.

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
        kvargs.Period {mustBeMember(kvargs.Period, {'stimulus', 'pre-stimulus'}), mustBeTextScalar} = 'stimulus'
        kvargs.EntropyBinSizeCm (1,1) double {mustBePositive, mustBeFinite} = 5
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

    entAllCol = nan(nRowsEstimate, 1);
    entByStimCols = nan(nRowsEstimate, nOutputStims);

    rowIdx = 0;
    for i = 1:length(standardizedTables)
        stdTable = standardizedTables(i);
        cp = stdTable.centerpointData;

        stimSequence = string(cp{:, 'Stimulus name'});
        xData = cp{:, 'X center'};
        yData = cp{:, 'Y center'};
        nAnimals = size(xData, 2);

        localStimNames = string(stdTable.stimuliSorted);
        localStimNames = localStimNames(:);

        allStimPointMask = cohort.metrics.utils.periodMaskAllStim(stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI, kvargs.Period);
        stimPointMasks = cell(numel(localStimNames), 1);
        for s = 1:numel(localStimNames)
            stimPointMasks{s} = cohort.metrics.utils.periodMaskForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI, kvargs.Period);
        end

        % Shared bin edges across animals of this table for comparability.
        [xEdges, yEdges] = occupancyEdges(xData, yData, kvargs.EntropyBinSizeCm);

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

            entAllCol(rowIdx) = occupancyEntropy(thisX, thisY, allStimPointMask, xEdges, yEdges);

            localEnt = nan(numel(localStimNames), 1);
            for s = 1:numel(localStimNames)
                localEnt(s) = occupancyEntropy(thisX, thisY, stimPointMasks{s}, xEdges, yEdges);
            end
            for g = 1:nOutputStims
                entByStimCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localEnt, localIdxByOutputStim(g));
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
        entAllCol = entAllCol(keep);
        entByStimCols = entByStimCols(keep, :);
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

    t.(sprintf('Occupancy Entropy During %s (bits)', periodPhrase)) = entAllCol;
    if ~isPreStim
        for g = 1:nOutputStims
            stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
            t.(sprintf('Occupancy Entropy During %s (bits)', stimLabel)) = entByStimCols(:, g);
        end
    end
end


function [xEdges, yEdges] = occupancyEdges(xData, yData, binSizeCm)
    finiteX = xData(isfinite(xData));
    finiteY = yData(isfinite(yData));
    if isempty(finiteX) || isempty(finiteY)
        xEdges = [];
        yEdges = [];
        return;
    end

    xLo = floor(min(finiteX(:)) / binSizeCm) * binSizeCm;
    xHi = ceil(max(finiteX(:)) / binSizeCm) * binSizeCm;
    yLo = floor(min(finiteY(:)) / binSizeCm) * binSizeCm;
    yHi = ceil(max(finiteY(:)) / binSizeCm) * binSizeCm;

    xEdges = xLo:binSizeCm:max(xHi, xLo + binSizeCm);
    yEdges = yLo:binSizeCm:max(yHi, yLo + binSizeCm);
end


function H = occupancyEntropy(x, y, pointMask, xEdges, yEdges)
    if isempty(xEdges) || isempty(yEdges)
        H = NaN;
        return;
    end

    mask = pointMask(:) & isfinite(x) & isfinite(y);
    if ~any(mask)
        H = NaN;
        return;
    end

    counts = histcounts2(x(mask), y(mask), xEdges, yEdges);
    totalCount = sum(counts(:));
    if totalCount <= 1
        H = NaN;
        return;
    end

    p = counts(:) / totalCount;
    p = p(p > 0);
    H = -sum(p .* log2(p));
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
    if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
        labels = string(overrideSpec{tableIdx});
    else
        labels = string(overrideSpec);
    end
    labels = labels(:);
end
