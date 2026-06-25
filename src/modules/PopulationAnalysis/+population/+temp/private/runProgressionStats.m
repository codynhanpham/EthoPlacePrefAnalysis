function stats = runProgressionStats(mergedTable, metricType, kvargs)
    %%RUNPROGRESSIONSTATS Run LME trajectory + slope tests on progression-over-time
    %
    % stats = runProgressionStats(mergedTable, metricType)
    % stats = runProgressionStats(..., Name=Value)
    %
    % Inputs:
    %   mergedTable : struct array from population.temp.joinStdTableByStim
    %   metricType  : "state" or "distance"
    %
    % Name-Value:
    %   BinWidth                (default 1)
    %   MeanWindowFrames        (default 15)
    %   TimeBinMode             "numeric" (default) or "categorical"
    %   IncludeMovementCovariate (default true)
    %   RandomSlope             (default false)
    %   Verbose                 (default true)

    arguments
        mergedTable struct {mustBeNonempty}
        metricType (1,1) string {mustBeMember(metricType, ["state", "distance"])}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
        kvargs.MeanWindowFrames (1,1) {mustBePositive, mustBeInteger} = 15
        kvargs.TimeBinMode (1,1) string {mustBeMember(kvargs.TimeBinMode, ["numeric", "categorical"])} = "numeric"
        kvargs.IncludeMovementCovariate (1,1) logical = true
        kvargs.RandomSlope (1,1) logical = false
        kvargs.Verbose (1,1) logical = true
    end

    longTbl = extractProgressionLongTable(mergedTable, metricType, kvargs.BinWidth, kvargs.MeanWindowFrames, kvargs.IncludeMovementCovariate);

    [trajectorySummary, trajectoryDetails] = fitTrajectoryModels(longTbl, metricType, kvargs.TimeBinMode, kvargs.IncludeMovementCovariate, kvargs.RandomSlope);
    [slopeTable, slopeSummary, slopeDetails] = fitSlopeModels(longTbl, metricType, kvargs.IncludeMovementCovariate);

    stats = struct();
    stats.metricType = metricType;
    stats.longTable = longTbl;
    stats.slopeTable = slopeTable;
    stats.trajectorySummary = trajectorySummary;
    stats.slopeSummary = slopeSummary;
    stats.trajectoryDetails = trajectoryDetails;
    stats.slopeDetails = slopeDetails;

    if kvargs.Verbose
        fprintf('\n========== %s progression stats ==========' , upper(char(metricType)));
        fprintf('\nTrajectory model formulas:\n');
        for di = 1:numel(trajectoryDetails)
            if isfield(trajectoryDetails(di), 'StimsetIdx') && ~isempty(trajectoryDetails(di).StimsetIdx)
                fprintf('  Stimset %d: %s\n', trajectoryDetails(di).StimsetIdx, string(trajectoryDetails(di).Formula));
            end
        end
        fprintf('\nTrajectory model summary (effects, CI, p):\n');
        disp(trajectorySummary);
        fprintf('\nSlope model formulas:\n');
        for di = 1:numel(slopeDetails)
            if isfield(slopeDetails(di), 'StimsetIdx') && ~isempty(slopeDetails(di).StimsetIdx)
                fprintf('  Stimset %d: %s\n', slopeDetails(di).StimsetIdx, string(slopeDetails(di).Formula));
            end
        end
        fprintf('\nSlope model summary (effects, CI, p):\n');
        disp(slopeSummary);
    end
end

function longTbl = extractProgressionLongTable(mergedTable, metricType, binWidth, meanWindowFrames, includeMovementCov)
    switch metricType
        case "state"
            metricCol = 'Arena Grid Score';
        case "distance"
            metricCol = 'Distance from Midline';
    end

    stimsetIdxCol = [];
    stimsetLabelCol = strings(0,1);
    stimulusCol = strings(0,1);
    animalCol = strings(0,1);
    strainCol = strings(0,1);
    groupCol = strings(0,1);
    binIdxCol = [];
    binLabelCol = strings(0,1);
    binMeanTimeCol = [];
    progressionCol = [];
    movementCovCol = [];

    stimSets = {mergedTable.stimuliSorted};

    for stimsetIdx = 1:numel(mergedTable)
        thisStdTable = mergedTable(stimsetIdx);
        thisStimSet = stimSets{stimsetIdx};

        stimPeriodTable = graphics.filterStimulusPeriodRows(thisStdTable.centerpointData);
        if ~ismember(metricCol, stimPeriodTable.Properties.VariableNames)
            error('runProgressionStats:missingMetric', 'Missing metric column ''%s'' in stimset %d.', metricCol, stimsetIdx);
        end

        keepVars = {'Trial time', 'Stimulus name', metricCol, 'X center', 'Y center'};
        if strcmp(metricType, "state") && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
            keepVars = [keepVars, {'Distance from Midline'}]; %#ok<AGROW>
        end
        keepVars = keepVars(ismember(keepVars, stimPeriodTable.Properties.VariableNames));
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, keepVars));

        trialTime = stimPeriodTable{:, 'Trial time'};
        stimSequence = stimPeriodTable{:, 'Stimulus name'};

        metaDict = thisStdTable.animalMetadata;
        metaVals = metaDict.values();
        animalKeys = keys(metaDict);
        nmeta = length(metaVals);
        % nAnimalsA is recorded by joinStdTableByStim and tells us how many
        % widened columns belong to group A. Do NOT infer from
        % numel(stimfileName) — that field concatenates A+B and would give
        % the wrong split when the two groups have different animal counts.
        ncolsA = thisStdTable.nAnimalsA;

        allMetric = stimPeriodTable{:, metricCol};
        metricA = allMetric(:, 1:ncolsA);
        metricB = allMetric(:, ncolsA+1:end);
        hasGroupB = ~isempty(metricB) && ~all(isnan(metricB), 'all');

        if strcmp(metricType, "distance")
            metricA = normalizeSignedDistance(metricA);
            if hasGroupB
                metricB = normalizeSignedDistance(metricB);
            end
        end

        signA = ones(1, size(metricA, 2));
        signB = ones(1, size(metricB, 2));
        if strcmp(metricType, "state") && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
            allDfm = stimPeriodTable{:, 'Distance from Midline'};
            dfmA = allDfm(:, 1:ncolsA);
            signA = inferArenaTowardStim1Sign(metricA, dfmA);
            if hasGroupB && size(allDfm, 2) > ncolsA
                dfmB = allDfm(:, ncolsA+1:end);
                signB = inferArenaTowardStim1Sign(metricB, dfmB);
            end
        end

        % Optional movement covariate (per animal, across stimulus period)
        movementCov = NaN(1, nmeta);
        if includeMovementCov && ismember('X center', stimPeriodTable.Properties.VariableNames) && ismember('Y center', stimPeriodTable.Properties.VariableNames)
            allX = stimPeriodTable{:, 'X center'};
            allY = stimPeriodTable{:, 'Y center'};
            movementCov = computeTotalMovement(allX, allY);
        end

        allStimStartsInSet = [];
        for stimIdx = 1:length(thisStimSet)
            isStim = endsWith(stimSequence, thisStimSet{stimIdx});
            allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
        end
        allStimStartsInSet = sort(allStimStartsInSet);

        stimsBouts = configureDictionary("char", "struct");
        for stimIdx = 1:length(thisStimSet)
            stimName = thisStimSet{stimIdx};
            isStim = endsWith(stimSequence, stimName);
            boutStartIdx = find(diff([0; isStim]) == 1);
            nBouts = length(boutStartIdx);

            boutEndIdx = zeros(nBouts, 1);
            for boutIdx = 1:nBouts
                nxt = allStimStartsInSet(allStimStartsInSet > boutStartIdx(boutIdx));
                if isempty(nxt)
                    boutEndIdx(boutIdx) = size(stimSequence, 1);
                else
                    boutEndIdx(boutIdx) = nxt(1) - 1;
                end
            end

            nBins = ceil(nBouts / binWidth);
            binLabels = cell(nBins, 1);
            binMeanTrialTime = NaN(nBins, 1);
            for binIdx = 1:nBins
                bs = (binIdx-1)*binWidth + 1;
                be = min(binIdx*binWidth, nBouts);
                binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bs-1)/nBouts*100, be/nBouts*100);

                boutMeanTimes = NaN(be-bs+1,1);
                for localBoutIdx = bs:be
                    li = localBoutIdx - bs + 1;
                    s = boutStartIdx(localBoutIdx);
                    e = boutEndIdx(localBoutIdx);
                    boutMeanTimes(li) = mean(trialTime(s:e), 'omitnan');
                end
                binMeanTrialTime(binIdx) = mean(boutMeanTimes, 'omitnan');
            end

            if strcmp(metricType, "distance")
                progSign = -1 + 2*(stimIdx > 1);
            else
                progSign = 1 - 2*(stimIdx > 1);
            end

            stimsBouts(stimName) = struct( ...
                'nBouts', nBouts, ...
                'boutStartIdx', boutStartIdx, ...
                'boutEndIdx', boutEndIdx, ...
                'nBins', nBins, ...
                'binLabels', {binLabels}, ...
                'binMeanTrialTime', binMeanTrialTime, ...
                'progressionSign', progSign ...
            );
        end

        % Build per-group descriptors
        descriptors = buildAnimalDescriptors(metaVals, animalKeys, ncolsA);

        groups = {};
        groups{end+1} = {metricA, signA, 1:ncolsA};
        if hasGroupB
            groups{end+1} = {metricB, signB, (ncolsA+1):nmeta};
        end

        for g = 1:length(groups)
            grp = groups{g};
            dataMat = grp{1};
            towardSign = grp{2};
            globalIndices = grp{3};

            for stimIdx = 1:length(thisStimSet)
                stimName = thisStimSet{stimIdx};
                bi = stimsBouts(stimName);
                if bi.nBouts == 0
                    continue;
                end

                perBoutProgress = NaN(bi.nBouts, size(dataMat,2));
                for boutIdx = 1:bi.nBouts
                    sIdx = bi.boutStartIdx(boutIdx);
                    eIdx = bi.boutEndIdx(boutIdx);
                    swEnd = min(sIdx + meanWindowFrames - 1, size(dataMat, 1));
                    sVals = mean(dataMat(sIdx:swEnd, :), 1, 'omitnan');
                    ewStart = max(eIdx - meanWindowFrames + 1, 1);
                    eVals = mean(dataMat(ewStart:eIdx, :), 1, 'omitnan');

                    if strcmp(metricType, "distance")
                        perBoutProgress(boutIdx, :) = bi.progressionSign * (eVals - sVals);
                    else
                        perBoutProgress(boutIdx, :) = bi.progressionSign .* towardSign .* (eVals - sVals);
                    end
                end

                for binIdx = 1:bi.nBins
                    bs = (binIdx-1)*binWidth + 1;
                    be = min(binIdx*binWidth, bi.nBouts);
                    binMeans = mean(perBoutProgress(bs:be, :), 1, 'omitnan');

                    for localAnimalIdx = 1:numel(globalIndices)
                        thisVal = binMeans(localAnimalIdx);
                        if ~isfinite(thisVal)
                            continue;
                        end

                        globalAnimalIdx = globalIndices(localAnimalIdx);
                        descriptor = descriptors(globalAnimalIdx);

                        stimsetIdxCol(end+1,1) = stimsetIdx; %#ok<AGROW>
                        stimsetLabelCol(end+1,1) = string(strjoin(thisStimSet, ' / ')); %#ok<AGROW>
                        stimulusCol(end+1,1) = string(stimName); %#ok<AGROW>
                        animalCol(end+1,1) = descriptor.Animal; %#ok<AGROW>
                        strainCol(end+1,1) = descriptor.Strain; %#ok<AGROW>
                        groupCol(end+1,1) = descriptor.Group; %#ok<AGROW>
                        binIdxCol(end+1,1) = binIdx; %#ok<AGROW>
                        binLabelCol(end+1,1) = string(bi.binLabels{binIdx}); %#ok<AGROW>
                        binMeanTimeCol(end+1,1) = bi.binMeanTrialTime(binIdx); %#ok<AGROW>
                        progressionCol(end+1,1) = thisVal; %#ok<AGROW>
                        movementCovCol(end+1,1) = movementCov(globalAnimalIdx); %#ok<AGROW>
                    end
                end
            end
        end
    end

    longTbl = table(stimsetIdxCol, stimsetLabelCol, stimulusCol, animalCol, strainCol, groupCol, ...
        binIdxCol, binLabelCol, binMeanTimeCol, progressionCol, movementCovCol, ...
        'VariableNames', {'StimsetIdx','StimsetLabel','Stimulus','Animal','Strain','Group', ...
        'BinIdx','BinLabel','BinMeanTime','Progression','MovementCovariate'});
end

function [summaryTbl, detail] = fitTrajectoryModels(longTbl, metricType, timeBinMode, includeMovementCov, randomSlope)
    detail = struct('StimsetIdx', {}, 'Formula', {}, 'Model', {}, 'Converged', {});

    summaryMetric = strings(0,1);
    summaryStimsetIdx = [];
    summaryStimsetLabel = strings(0,1);
    summaryAnalysis = strings(0,1);
    summaryTerm = strings(0,1);
    summaryFormula = strings(0,1);
    summaryEstimate = [];
    summaryCILow = [];
    summaryCIHigh = [];
    summaryP = [];

    stimsetList = unique(longTbl.StimsetIdx(:))';
    for stimsetIdx = stimsetList
        sub = longTbl(longTbl.StimsetIdx == stimsetIdx, :);
        if isempty(sub)
            continue;
        end

        sub = sub(isfinite(sub.Progression) & isfinite(sub.BinMeanTime), :);
        if height(sub) < 8
            continue;
        end

        sub.Animal = categorical(sub.Animal);
        sub.Strain = categorical(sub.Strain);
        sub.Stimulus = categorical(sub.Stimulus);

        fixedParts = {'Strain * TimeBin', 'Stimulus'};
        if timeBinMode == "numeric"
            sub.TimeBin = sub.BinIdx;
        else
            sub.TimeBin = categorical(sub.BinIdx);
        end

        useMovement = false;
        if includeMovementCov
            v = sub.MovementCovariate;
            finiteMask = isfinite(v);
            if any(finiteMask)
                vFill = v;
                vFill(~finiteMask) = mean(v(finiteMask), 'omitnan');
                if std(vFill, 0, 'omitnan') > 0
                    sub.MovementCovariateZ = (vFill - mean(vFill, 'omitnan')) ./ std(vFill, 0, 'omitnan');
                    useMovement = true;
                end
            end
        end
        if useMovement
            fixedParts{end+1} = 'MovementCovariateZ'; %#ok<AGROW>
        end

        randomPart = '(1 | Animal)';
        if randomSlope && timeBinMode == "numeric"
            randomPart = '(1 + TimeBin | Animal)';
        end

        formula = sprintf('Progression ~ %s + %s', strjoin(fixedParts, ' + '), randomPart);
        lme = [];
        converged = false;
        usedFormula = formula;

        try
            lme = fitlme(sub, formula, 'FitMethod', 'REML');
            converged = true;
        catch
            if randomSlope
                usedFormula = sprintf('Progression ~ %s + (1 | Animal)', strjoin(fixedParts, ' + '));
                try
                    lme = fitlme(sub, usedFormula, 'FitMethod', 'REML');
                    converged = true;
                catch
                    converged = false;
                end
            end
        end

        detail(end+1).StimsetIdx = stimsetIdx; %#ok<AGROW>
        detail(end).Formula = usedFormula;
        detail(end).Model = lme;
        detail(end).Converged = converged;

        if ~converged || isempty(lme)
            continue;
        end

        coef = lme.Coefficients;
        ci = coefCI(lme);

        termNames = string(coef.Name);
        keep = contains(termNames, 'Strain_') | contains(termNames, 'TimeBin:Strain_') | contains(termNames, 'Strain_:TimeBin');

        for i = find(keep)'
            summaryMetric(end+1,1) = upper(metricType); %#ok<AGROW>
            summaryStimsetIdx(end+1,1) = stimsetIdx; %#ok<AGROW>
            summaryStimsetLabel(end+1,1) = string(sub.StimsetLabel(1)); %#ok<AGROW>
            summaryAnalysis(end+1,1) = "LME-Trajectory"; %#ok<AGROW>
            summaryTerm(end+1,1) = termNames(i); %#ok<AGROW>
            summaryFormula(end+1,1) = string(usedFormula); %#ok<AGROW>
            summaryEstimate(end+1,1) = coef.Estimate(i); %#ok<AGROW>
            summaryCILow(end+1,1) = ci(i,1); %#ok<AGROW>
            summaryCIHigh(end+1,1) = ci(i,2); %#ok<AGROW>
            summaryP(end+1,1) = coef.pValue(i); %#ok<AGROW>
        end
    end

    summaryTbl = table(summaryMetric, summaryStimsetIdx, summaryStimsetLabel, summaryAnalysis, summaryTerm, ...
        summaryEstimate, summaryCILow, summaryCIHigh, summaryP, ...
        'VariableNames', {'Metric','StimsetIdx','StimsetLabel','Analysis','Term','Estimate','CILow','CIHigh','pValue'});
end

function [slopeTbl, summaryTbl, detail] = fitSlopeModels(longTbl, metricType, includeMovementCov)
    detail = struct('StimsetIdx', {}, 'Formula', {}, 'Model', {}, 'Converged', {});

    slopeRows = table('Size', [0 9], ...
        'VariableTypes', {'double','string','string','string','string','double','double','double','double'}, ...
        'VariableNames', {'StimsetIdx','StimsetLabel','Stimulus','Animal','Strain','MovementCovariate','Slope','NSupport','MeanTime'});

    stimsetList = unique(longTbl.StimsetIdx(:))';
    for stimsetIdx = stimsetList
        subStim = longTbl(longTbl.StimsetIdx == stimsetIdx, :);
        if isempty(subStim)
            continue;
        end

        animals = unique(subStim.Animal);
        stims = unique(subStim.Stimulus);
        for ai = 1:numel(animals)
            for si = 1:numel(stims)
                q = subStim(strcmp(subStim.Animal, animals(ai)) & strcmp(subStim.Stimulus, stims(si)), :);
                if isempty(q)
                    continue;
                end
                q = sortrows(q, 'BinIdx');
                x = q.BinMeanTime;
                y = q.Progression;
                valid = isfinite(x) & isfinite(y);
                x = x(valid);
                y = y(valid);
                if numel(x) < 2 || numel(unique(x)) < 2
                    continue;
                end
                p = polyfit(x, y, 1);
                slopeVal = p(1);

                moveCov = q.MovementCovariate(find(valid, 1, 'first'));
                if isempty(moveCov)
                    moveCov = NaN;
                end

                slopeRows = [slopeRows; {stimsetIdx, string(q.StimsetLabel(1)), string(stims(si)), string(animals(ai)), ...
                    string(q.Strain(find(valid, 1, 'first'))), moveCov, slopeVal, numel(x), mean(x, 'omitnan')}]; %#ok<AGROW>
            end
        end
    end

    slopeTbl = slopeRows;

    summaryMetric = strings(0,1);
    summaryStimsetIdx = [];
    summaryStimsetLabel = strings(0,1);
    summaryAnalysis = strings(0,1);
    summaryTerm = strings(0,1);
    summaryFormula = strings(0,1);
    summaryEstimate = [];
    summaryCILow = [];
    summaryCIHigh = [];
    summaryP = [];

    for stimsetIdx = unique(slopeTbl.StimsetIdx(:))'
        sub = slopeTbl(slopeTbl.StimsetIdx == stimsetIdx, :);
        if height(sub) < 6
            continue;
        end

        sub.Animal = categorical(sub.Animal);
        sub.Strain = categorical(sub.Strain);
        sub.Stimulus = categorical(sub.Stimulus);

        fixedParts = {'Strain', 'Stimulus'};
        useMovement = false;
        if includeMovementCov
            v = sub.MovementCovariate;
            finiteMask = isfinite(v);
            if any(finiteMask)
                vFill = v;
                vFill(~finiteMask) = mean(v(finiteMask), 'omitnan');
                if std(vFill, 0, 'omitnan') > 0
                    sub.MovementCovariateZ = (vFill - mean(vFill, 'omitnan')) ./ std(vFill, 0, 'omitnan');
                    useMovement = true;
                end
            end
        end
        if useMovement
            fixedParts{end+1} = 'MovementCovariateZ'; %#ok<AGROW>
        end

        formula = sprintf('Slope ~ %s + (1 | Animal)', strjoin(fixedParts, ' + '));
        lme = [];
        converged = false;
        try
            lme = fitlme(sub, formula, 'FitMethod', 'REML');
            converged = true;
        catch
            converged = false;
        end

        detail(end+1).StimsetIdx = stimsetIdx; %#ok<AGROW>
        detail(end).Formula = formula;
        detail(end).Model = lme;
        detail(end).Converged = converged;

        if ~converged || isempty(lme)
            continue;
        end

        coef = lme.Coefficients;
        ci = coefCI(lme);
        termNames = string(coef.Name);
        keep = contains(termNames, 'Strain_');

        for i = find(keep)'
            summaryMetric(end+1,1) = upper(metricType); %#ok<AGROW>
            summaryStimsetIdx(end+1,1) = stimsetIdx; %#ok<AGROW>
            summaryStimsetLabel(end+1,1) = string(sub.StimsetLabel(1)); %#ok<AGROW>
            summaryAnalysis(end+1,1) = "LME-Slope"; %#ok<AGROW>
            summaryTerm(end+1,1) = termNames(i); %#ok<AGROW>
            summaryFormula(end+1,1) = string(formula); %#ok<AGROW>
            summaryEstimate(end+1,1) = coef.Estimate(i); %#ok<AGROW>
            summaryCILow(end+1,1) = ci(i,1); %#ok<AGROW>
            summaryCIHigh(end+1,1) = ci(i,2); %#ok<AGROW>
            summaryP(end+1,1) = coef.pValue(i); %#ok<AGROW>
        end
    end

    summaryTbl = table(summaryMetric, summaryStimsetIdx, summaryStimsetLabel, summaryAnalysis, summaryTerm, ...
        summaryEstimate, summaryCILow, summaryCIHigh, summaryP, ...
        'VariableNames', {'Metric','StimsetIdx','StimsetLabel','Analysis','Term','Estimate','CILow','CIHigh','pValue'});
end

function descriptors = buildAnimalDescriptors(metaVals, animalKeys, ncolsA)
    n = length(metaVals);
    descriptors = repmat(struct('Animal', "", 'Strain', "Unknown", 'Group', ""), n, 1);

    if numel(animalKeys) ~= n
        animalKeys = arrayfun(@(i) sprintf('Animal_%d', i), 1:n, 'UniformOutput', false);
    end

    for i = 1:n
        descriptors(i).Animal = string(animalKeys{i});
        descriptors(i).Strain = getFieldOr(metaVals(i), 'strain', "Unknown");
        if i <= ncolsA
            descriptors(i).Group = "GroupA";
        else
            descriptors(i).Group = "GroupB";
        end
    end
end

function val = getFieldOr(s, fieldName, defaultVal)
    if isfield(s, fieldName)
        v = s.(fieldName);
        if isstring(v)
            val = v(1);
        elseif ischar(v)
            val = string(v);
        else
            val = string(v);
        end
    else
        val = defaultVal;
    end
end

function signedMat = normalizeSignedDistance(mat)
    signedMat = mat;
    for colIdx = 1:size(signedMat, 2)
        c = signedMat(:, colIdx);
        mx = max(c, [], 'omitnan');
        mn = min(c, [], 'omitnan');
        if mx > 0 && ~isnan(mx)
            c(c > 0) = c(c > 0) / mx;
        end
        if mn < 0 && ~isnan(mn)
            c(c < 0) = c(c < 0) / abs(mn);
        end
        signedMat(:, colIdx) = c;
    end
end

function signVec = inferArenaTowardStim1Sign(metricMat, dfmMat)
    signVec = ones(1, size(metricMat, 2));
    if ~isequal(size(metricMat), size(dfmMat))
        return;
    end
    for i = 1:size(metricMat, 2)
        m = metricMat(:, i);
        d = dfmMat(:, i);
        valid = isfinite(m) & isfinite(d);
        if nnz(valid) < 3
            continue;
        end
        c = corr(m(valid), d(valid));
        if isfinite(c) && c ~= 0
            signVec(i) = sign(-c);
        end
    end
end

function totalMove = computeTotalMovement(allX, allY)
    nCols = size(allX, 2);
    totalMove = NaN(1, nCols);
    for c = 1:nCols
        x = allX(:, c);
        y = allY(:, c);
        dx = diff(x);
        dy = diff(y);
        valid = isfinite(dx) & isfinite(dy);
        stepDist = sqrt(dx(valid).^2 + dy(valid).^2);
        if ~isempty(stepDist)
            totalMove(c) = sum(stepDist, 'omitnan');
        end
    end
end


