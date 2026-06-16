function t = distanceTravel(standardizedTables, kvargs)
    %%DISTANCETRAVEL
    %
    % - distance during prestim (if prestim period exists, otherwise NaN)
    % - distance during stim
    % - distance during stimuliSorted(1) only, normalized by total duration of stimuliSorted(1)
    % - distance during stimuliSorted(2) only, normalized by total duration of stimuliSorted(2)
    % - distance during poststim (if poststim period exists, otherwise NaN)


    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true % whether the immediately following ISI after a stimulus should be included in the stimulus period
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}
    end

    %% Common Headers:

    % Animal metadata mapping + order
    % id -> Mouse_ID
    % strain -> Gene
    % cagecode -> Cage #
    % {{parseMouseId}} -> Gene_ID
    % sex -> Sex$
    % genotype -> Genotype$ 
    % {{parseMouseId}} -> Litter
    % {{parseMouseId}} -> Toe_ID
    % dob -> DOB
    % age -> Age

    % Each mouse has length({standardizedTables.stimfileName}) rows
    % {{standardizedTables.stimfileName}} -> Stimulus Protocol


    %% Distance Metrics:
    % - Total Distance During Stimulus: sum of distances between consecutive center points across the entire trial period
    % - Average Distance During StimuliSorted(1): sum of distances between consecutive center points during periods when the stimulus is stimuliSorted(1), normalized by total duration of stimuliSorted(1)
    % - Average Distance During StimuliSorted(2): sum of distances between consecutive center points during periods when the stimulus is stimuliSorted(2), normalized by total duration of stimuliSorted(2)
    % * handles title header override for stimuliSorted(1) and stimuliSorted(2) if the override is not empty
    % * Since this is an aggregate table across multiple standardizedTables, stimuliSorted(i) are not guaranteed to be matching across tables. If no match, simply set NaN for that metric for that table's entries
    % * matching of stimuliSorted(i) is done on the override name if provided, otherwise on the original stimuliSorted(i) name



    if isempty(standardizedTables)
        t = table();
        return;
    end

    hasOverride = ~isempty(kvargs.StimuliSortedColumnNameDisplayOverride);
    overrideSpec = sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
    outputStimNames = cohort.metrics.utils.getOutputStimNames(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride);
    nOutputStims = numel(outputStimNames);

    nRowsEstimate = cohort.metrics.utils.estimateRows(standardizedTables);

    [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = cohort.metrics.utils.initCommonColumns(nRowsEstimate);

    distDuringStimCol = nan(nRowsEstimate, 1);
    distDuringPreStimCol = nan(nRowsEstimate, 1);
    distDuringPostStimCol = nan(nRowsEstimate, 1);
    distByStimNormCols = nan(nRowsEstimate, nOutputStims);
    distByStimFirstBoutNormCols = nan(nRowsEstimate, nOutputStims);
    distByStimLastBoutNormCols = nan(nRowsEstimate, nOutputStims);
    distByStimDeltaLastFirstNormCols = nan(nRowsEstimate, nOutputStims);

    preStimTables = sdTable.subsetByStimBlock(standardizedTables, 'pre-stimulus');
    postStimTables = sdTable.subsetByStimBlock(standardizedTables, 'post-stimulus');

    rowIdx = 0;
    for i = 1:length(standardizedTables)
        stdTable = standardizedTables(i);
        cp = stdTable.centerpointData;
        preCp = preStimTables(i).centerpointData;
        postCp = postStimTables(i).centerpointData;

        trialTime = cp{:, 'Trial time'};
        stimSequence = string(cp{:, 'Stimulus name'});
        xData = cp{:, 'X center'};
        yData = cp{:, 'Y center'};
        nAnimals = size(xData, 2);

        if ~isempty(preCp)
            preTrialTime = preCp{:, 'Trial time'};
            preXData = preCp{:, 'X center'};
            preYData = preCp{:, 'Y center'};
        else
            preTrialTime = [];
            preXData = [];
            preYData = [];
        end

        if ~isempty(postCp)
            postTrialTime = postCp{:, 'Trial time'};
            postXData = postCp{:, 'X center'};
            postYData = postCp{:, 'Y center'};
        else
            postTrialTime = [];
            postXData = [];
            postYData = [];
        end

        localStimNames = string(stdTable.stimuliSorted);
        localStimNames = localStimNames(:);

        % Precompute masks and local->reference stimulus index mapping once per table.
        allStimMask = cohort.metrics.utils.periodMaskAllStim(stimSequence, localStimNames, kvargs.StimulusIncludesTrailingISI);
        stimMasks = cell(numel(localStimNames), 1);
        for s = 1:numel(localStimNames)
            stimMasks{s} = cohort.metrics.utils.periodMaskForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
        end
        stimBoutMasks = cell(numel(localStimNames), 1);
        for s = 1:numel(localStimNames)
            stimBoutMasks{s} = cohort.metrics.utils.stimBoutMasksForStim(stimSequence, localStimNames(s), localStimNames, kvargs.StimulusIncludesTrailingISI);
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

            % Metadata columns
            md = struct();
            if col <= numel(animalKeys)
                md = stdTable.animalMetadata(animalKeys{col});
            end

            [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = ...
                cohort.metrics.utils.fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stdTable.stimfileName);

            % Distance metrics for this animal (column)
            thisX = xData(:, col);
            thisY = yData(:, col);

            if ~isempty(preTrialTime)
                [distPre, ~] = distanceWithinMask(preXData(:, col), preYData(:, col), preTrialTime, true(size(preTrialTime)));
                distDuringPreStimCol(rowIdx) = distPre;
            end

            if ~isempty(postTrialTime)
                [distPost, ~] = distanceWithinMask(postXData(:, col), postYData(:, col), postTrialTime, true(size(postTrialTime)));
                distDuringPostStimCol(rowIdx) = distPost;
            end

            [distTotal, ~] = distanceWithinMask(thisX, thisY, trialTime, ...
                allStimMask);
            distDuringStimCol(rowIdx) = distTotal;

            % Compute normalized distance for each locally available stimulus
            localStimNorm = nan(numel(localStimNames), 1);
            localStimNormFirst = nan(numel(localStimNames), 1);
            localStimNormLast = nan(numel(localStimNames), 1);
            for s = 1:numel(localStimNames)
                [distStim, durStim] = distanceWithinMask(thisX, thisY, trialTime, stimMasks{s});
                if isfinite(durStim) && durStim > 0
                    localStimNorm(s) = distStim / durStim;
                else
                    localStimNorm(s) = NaN;
                end

                thisBoutMasks = stimBoutMasks{s};
                if ~isempty(thisBoutMasks)
                    [distFirst, durFirst] = distanceWithinMask(thisX, thisY, trialTime, thisBoutMasks{1});
                    if isfinite(durFirst) && durFirst > 0
                        localStimNormFirst(s) = distFirst / durFirst;
                    end

                    [distLast, durLast] = distanceWithinMask(thisX, thisY, trialTime, thisBoutMasks{end});
                    if isfinite(durLast) && durLast > 0
                        localStimNormLast(s) = distLast / durLast;
                    end
                end
            end

            % Map local stimulus metrics onto global output stimulus columns.
            for g = 1:nOutputStims
                distByStimNormCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimNorm, localIdxByOutputStim(g));
                distByStimFirstBoutNormCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimNormFirst, localIdxByOutputStim(g));
                distByStimLastBoutNormCols(rowIdx, g) = cohort.metrics.utils.metricByIndex(localStimNormLast, localIdxByOutputStim(g));
                distByStimDeltaLastFirstNormCols(rowIdx, g) = distByStimLastBoutNormCols(rowIdx, g) - distByStimFirstBoutNormCols(rowIdx, g);
            end
        end
    end

    % Trim any over-allocation if a table has mismatched metadata/columns.
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
        distDuringPreStimCol = distDuringPreStimCol(keep);
        distDuringPostStimCol = distDuringPostStimCol(keep);
        distDuringStimCol = distDuringStimCol(keep);
        distByStimNormCols = distByStimNormCols(keep, :);
        distByStimFirstBoutNormCols = distByStimFirstBoutNormCols(keep, :);
        distByStimLastBoutNormCols = distByStimLastBoutNormCols(keep, :);
        distByStimDeltaLastFirstNormCols = distByStimDeltaLastFirstNormCols(keep, :);
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

    t.('Distance During Pre-Stimulus (cm)') = distDuringPreStimCol;
    t.('Distance During Stimulus (cm)') = distDuringStimCol;
    t.('Distance During Post-Stimulus (cm)') = distDuringPostStimCol;
    for g = 1:nOutputStims
        stimLabel = cohort.metrics.utils.makeMetricLabel(outputStimNames(g), g);
        t.(sprintf('Average Distance During %s (cm/s)', stimLabel)) = distByStimNormCols(:, g);
        t.(sprintf('Average Distance During First %s Bout (cm/s)', stimLabel)) = distByStimFirstBoutNormCols(:, g);
        t.(sprintf('Average Distance During Last %s Bout (cm/s)', stimLabel)) = distByStimLastBoutNormCols(:, g);
        t.(sprintf('Average Distance Last-First During %s Bouts (cm/s)', stimLabel)) = distByStimDeltaLastFirstNormCols(:, g);
    end
end


function labels = localOverrideLabels(overrideSpec, tableIdx)
    if iscell(overrideSpec) && ~isempty(overrideSpec) && any(cellfun(@iscell, overrideSpec))
        labels = string(overrideSpec{tableIdx});
    else
        labels = string(overrideSpec);
    end
    labels = labels(:);
end


function [distance, duration] = distanceWithinMask(x, y, t, pointMask)
    if isempty(x) || isempty(y) || isempty(t)
        distance = NaN;
        duration = NaN;
        return;
    end

    if numel(pointMask) ~= numel(t)
        pointMask = false(size(t));
    end

    dx = diff(x);
    dy = diff(y);
    dt = diff(t);

    stepDist = sqrt(dx.^2 + dy.^2);
    segMask = pointMask(1:end-1) & pointMask(2:end);
    valid = segMask & isfinite(stepDist) & isfinite(dt);

    distance = sum(stepDist(valid), 'omitnan');
    duration = sum(dt(valid), 'omitnan');
end
