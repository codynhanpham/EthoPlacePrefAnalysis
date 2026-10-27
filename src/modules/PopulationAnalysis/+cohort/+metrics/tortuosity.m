function t = tortuosity(standardizedTables, kvargs)
    %%TORTUOSITY Cohort summary of path tortuosity (path length over net displacement)
    %   Tortuosity = total path length / net displacement within a period mask.
    %   Values >= 1: 1.0 is a perfectly straight path; larger values are more
    %   tortuous. NaN when the net displacement is not positive (e.g., the
    %   subject returns to its starting point) or when no valid segments exist.
    %
    %   Reports the aggregate value during the whole active stimulus period and
    %   during each stimulus-specific active period. During the pre-stimulus
    %   period (Period='pre-stimulus'), only the aggregate column is emitted.

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
        kvargs.Period {mustBeMember(kvargs.Period, {'stimulus', 'pre-stimulus'}), mustBeTextScalar} = 'stimulus'
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

    torAllCol = nan(nRowsEstimate, 1);
    torByStimCols = nan(nRowsEstimate, nOutputStims);

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
        stimPointMasks = cell(numel(localStimNames), 1);
        for s = 1:numel(localStimNames)
            stimPointMasks{s} = cohort.metrics.utils.periodMaskForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI, kvargs.Period);
        end

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

            torAllCol(rowIdx) = tortuosityWithinMask(thisX, thisY, trialTime, allStimPointMask);

            localTor = nan(numel(localStimNames), 1);
            for s = 1:numel(localStimNames)
                localTor(s) = tortuosityWithinMask(thisX, thisY, trialTime, stimPointMasks{s});
            end
            for g = 1:nOutputStims
                torByStimCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localTor, localIdxByOutputStim(g));
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
        torAllCol = torAllCol(keep);
        torByStimCols = torByStimCols(keep, :);
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

    t.(sprintf('Tortuosity During %s (path/net)', periodPhrase)) = torAllCol;
    if ~isPreStim
        for g = 1:nOutputStims
            stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
            t.(sprintf('Tortuosity During %s (path/net)', stimLabel)) = torByStimCols(:, g);
        end
    end
end


function tor = tortuosityWithinMask(x, y, t, pointMask)
    if isempty(x) || isempty(y) || isempty(t)
        tor = NaN;
        return;
    end

    if numel(pointMask) ~= numel(t)
        pointMask = false(size(t));
    end

    validPts = pointMask(:) & isfinite(x) & isfinite(y);
    if ~any(validPts)
        tor = NaN;
        return;
    end

    xMasked = x(validPts);
    yMasked = y(validPts);

    dx = diff(x);
    dy = diff(y);
    dt = diff(t);
    stepDist = sqrt(dx.^2 + dy.^2);
    segMask = pointMask(1:end-1) & pointMask(2:end) & isfinite(stepDist) & isfinite(dt);
    pathLength = sum(stepDist(segMask), 'omitnan');

    netDisplacement = hypot(xMasked(end) - xMasked(1), yMasked(end) - yMasked(1));

    if ~isfinite(pathLength) || ~isfinite(netDisplacement) || netDisplacement <= eps
        tor = NaN;
        return;
    end

    tor = pathLength / netDisplacement;
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
    if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
        labels = string(overrideSpec{tableIdx});
    else
        labels = string(overrideSpec);
    end
    labels = labels(:);
end
