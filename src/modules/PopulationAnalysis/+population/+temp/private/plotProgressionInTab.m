function tbl = plotProgressionInTab(parent, mergedTable, metricType, kvargs)
    %%PLOTPROGRESSIONINTAB Plot strain-comparison progression into a tiledlayout
    %
    %   plotProgressionInTab(parent, mergedTable, metricType)
    %
    %   Renders one tile per stimset. Within each tile, each strain (from the merged
    %   animalMetadata groups) is plotted as a separate set of lines using strainColorMap.
    %
    %   Inputs:
    %       parent      : uitab or uipanel to render into
    %       mergedTable : Merged standardizedTable (output of joinStdTableByStim).
    %                      Data columns are widened: N x (Ka+Kb) within the same column name.
    %       metricType  : 'state' or 'distance'
    %
    %   Name-Value Pair Arguments:
    %       'BinWidth', 'MeanWindowFrames', 'SameYLim', 'YLim', 'ShowDataPoints'
    %
    %   Outputs:
    %       tbl : Per animal progression summary table. 
    %           - n rows = nAnimals * nStimuliSet * nStimulusNamesWithinEachSet
    %           - Columns for mean progression within each bin
    %           - Cols: 
    %               + Common: Mouse_ID, Gene, Cage #, Gene_ID, Sex$, Genotype$, Litter, Toe_ID, DOB, Age, Stimulus Protocol, Stimulus Name
    %               + Progression: TimeBin_1__{perc_range%}, TimeBin_2__{perc_range%}, ..., TimeBin_N__{perc_range%}

    arguments
        parent (1,1)
        mergedTable struct {mustBeNonempty}
        metricType (1,1) string {mustBeMember(metricType, ["state", "distance"])}

        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
        kvargs.MeanWindowFrames (1,1) {mustBePositive, mustBeInteger} = 15
        kvargs.SameYLim (1,1) logical = true
        kvargs.YLim double = []
        kvargs.ShowDataPoints (1,1) logical = true
    end

    switch metricType
        case 'state'
            metricCol = 'Arena Grid Score';
            ylabelStr = 'State Progression Score\n(Positive = moved toward active stimulus;\nNegative = moved away)';
        case 'distance'
            metricCol = 'Distance from Midline';
            ylabelStr = 'Distance-from-Midline Progression\n(Positive = moved toward active stimulus;\nNegative = moved away)';
    end

    stimSets = {mergedTable.stimuliSorted};
    nstimsets = length(stimSets);

    % Determine group colors from animalMetadata across stimsets.
    % mergedTable is a 1xN struct array; metadata is the same in each element,
    % so index into the first one.  In joinStdTableByStim output, metadata has
    % A keys first, then B keys.
    metaDict = mergedTable(1).animalMetadata;
    metaVals = metaDict.values();
    nmeta = length(metaVals);
    % nAnimalsA is recorded by joinStdTableByStim and tells us how many widened
    % columns belong to group A. Do NOT infer from numel(stimfileName) — that
    % field concatenates A+B and would give the wrong split when the two
    % groups have different animal counts.
    ncolsA = mergedTable(1).nAnimalsA;
    ncolsB = nmeta - ncolsA;              % columns from second file (C57 WT)

    groupAStrains = {metaVals(1:ncolsA).strain};
    groupBStrains = {metaVals(ncolsA+1:end).strain};
    % Each group should be homogeneous for strain, so take the first value.
    groupAStrain = string(groupAStrains{1});
    groupBStrain = string(groupBStrains{1});
    colorA = graphics.strainColorMap(char(groupAStrain));
    colorB = graphics.strainColorMap(char(groupBStrain));

    ncols = min(nstimsets, 2);
    nrowsBase = ceil(nstimsets / ncols);
    nrows = nrowsBase * 2; % progression row-block + slope row-block
    t = tiledlayout(parent, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');

    progressionAxes = gobjects(0);
    slopeAxes = gobjects(0);

    NORMAL_LINE_STYLE = {'-'};
    OTHER_LINE_STYLE = {'-.', '--', ':'};
    knownOtherStimLineStyles = configureDictionary('char', 'char');

    %% Export table collection (pre-allocate)
    nRowsEstimate = 0;
    for si = 1:nstimsets
        nRowsEstimate = nRowsEstimate + numel(stimSets{si}) * nmeta;
    end
    [expMouseId, expGene, expCageCode, expGeneId, expSex, expGenotype, ...
     expLitter, expToeId, expDob, expAge, expStimProtocol] = ...
        cohort.metrics.utils.initCommonColumns(nRowsEstimate);
    expStimulusName = strings(nRowsEstimate, 1);
    expStimsetIdx = zeros(nRowsEstimate, 1);
    expGroup = strings(nRowsEstimate, 1);
    expBinValues = cell(nRowsEstimate, 1);
    expBinLabels = cell(nRowsEstimate, 1);
    expRowIdx = 0;

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = mergedTable(stimsetIdx);

        % Prepare centerpointData
        stimPeriodTable = thisStdTable.centerpointData;
        stimPeriodTable = graphics.filterStimulusPeriodRows(stimPeriodTable);

        % Check metric column exists
        if ~ismember(metricCol, stimPeriodTable.Properties.VariableNames)
            error('Missing ''%s'' in centerpointData.', metricCol);
        end

        % Keep only needed columns
        keepVars = {'Trial time', 'Stimulus name', metricCol};
        if strcmp(metricType, 'state') && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
            keepVars = [keepVars, {'Distance from Midline'}];
        end
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, keepVars));

        trialTime = stimPeriodTable{:, 'Trial time'};
        stimSequence = stimPeriodTable{:, 'Stimulus name'};
        % The metric column is widened: N x (ncolsA + ncolsB). Split it.
        allMetric = stimPeriodTable{:, metricCol};
        metricMatrixA = allMetric(:, 1:ncolsA);
        metricMatrixB = allMetric(:, ncolsA+1:end);
        hasGroupB = ~isempty(metricMatrixB) && ~all(isnan(metricMatrixB), 'all');

        if isempty(metricMatrixA) || all(isnan(metricMatrixA), 'all')
            error('''%s'' for stimset %d is empty or all NaN.', metricCol, stimsetIdx);
        end

        % Normalize distance columns to (-1, 1)
        if strcmp(metricType, 'distance')
            for colIdx = 1:size(metricMatrixA, 2)
                c = metricMatrixA(:, colIdx);
                mx = max(c, [], 'omitnan'); mn = min(c, [], 'omitnan');
                if mx > 0 && ~isnan(mx); c(c>0) = c(c>0) / mx; end
                if mn < 0 && ~isnan(mn); c(c<0) = c(c<0) / abs(mn); end
                metricMatrixA(:, colIdx) = c;
            end
            if hasGroupB && ~isempty(metricMatrixB)
                for colIdx = 1:size(metricMatrixB, 2)
                    c = metricMatrixB(:, colIdx);
                    mx = max(c, [], 'omitnan'); mn = min(c, [], 'omitnan');
                    if mx > 0 && ~isnan(mx); c(c>0) = c(c>0) / mx; end
                    if mn < 0 && ~isnan(mn); c(c<0) = c(c<0) / abs(mn); end
                    metricMatrixB(:, colIdx) = c;
                end
            end
        end

        % For state: compute Arena Grid Score orientation using Distance from Midline.
        % DFM column is also widened by joinStdTableByStim — split by column index.
        arenaTowardStim1SignA = ones(1, size(metricMatrixA, 2));
        arenaTowardStim1SignB = [];
        if strcmp(metricType, 'state') && ismember('Distance from Midline', stimPeriodTable.Properties.VariableNames)
            allDfm = stimPeriodTable{:, 'Distance from Midline'};
            dfmA = allDfm(:, 1:ncolsA);
            if size(dfmA, 2) == size(metricMatrixA, 2)
                for ai = 1:size(metricMatrixA, 2)
                    ags = metricMatrixA(:, ai); dfm = dfmA(:, ai);
                    v = isfinite(ags) & isfinite(dfm);
                    if nnz(v) >= 3
                        c = corr(ags(v), dfm(v));
                        if isfinite(c) && c ~= 0
                            arenaTowardStim1SignA(ai) = sign(-c);
                        end
                    end
                end
            end
            if hasGroupB && size(allDfm, 2) > ncolsA
                dfmB = allDfm(:, ncolsA+1:end);
                arenaTowardStim1SignB = ones(1, size(metricMatrixB, 2));
                if size(dfmB, 2) == size(metricMatrixB, 2)
                    for ai = 1:size(metricMatrixB, 2)
                        ags = metricMatrixB(:, ai); dfm = dfmB(:, ai);
                        v = isfinite(ags) & isfinite(dfm);
                        if nnz(v) >= 3
                            c = corr(ags(v), dfm(v));
                            if isfinite(c) && c ~= 0
                                arenaTowardStim1SignB(ai) = sign(-c);
                            end
                        end
                    end
                end
            end
        end

        % Collect all stimulus starts in this stimset
        allStimStartsInSet = [];
        for stimIdx = 1:length(thisStimSet)
            isStim = endsWith(stimSequence, thisStimSet{stimIdx});
            allStimStartsInSet = [allStimStartsInSet; find(diff([0; isStim]) == 1)]; %#ok<AGROW>
        end
        allStimStartsInSet = sort(allStimStartsInSet);

        % Build bout metadata per stimulus
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
            nBins = ceil(nBouts / kvargs.BinWidth);
            binLabels = cell(nBins, 1);
            binMeanTrialTime = NaN(nBins, 1);
            for binIdx = 1:nBins
                bs = (binIdx-1)*kvargs.BinWidth + 1;
                be = min(binIdx*kvargs.BinWidth, nBouts);
                binLabels{binIdx} = sprintf('%.0f-%.0f%%', (bs-1)/nBouts*100, be/nBouts*100);

                thisBoutMeanTimes = NaN(be - bs + 1, 1);
                for localBoutIdx = bs:be
                    localIdx = localBoutIdx - bs + 1;
                    localStart = boutStartIdx(localBoutIdx);
                    localEnd = boutEndIdx(localBoutIdx);
                    thisBoutMeanTimes(localIdx) = mean(trialTime(localStart:localEnd), 'omitnan');
                end
                binMeanTrialTime(binIdx) = mean(thisBoutMeanTimes, 'omitnan');
            end
            if strcmp(metricType, 'distance')
                progSign = -1 + 2*(stimIdx > 1); % -1 for stim1, +1 for stim2
            else
                progSign = 1 - 2*(stimIdx > 1);  % +1 for stim1, -1 for stim2
            end
            stimsBouts(stimName) = struct(...
                'nBouts', nBouts, 'boutStartIdx', boutStartIdx, ...
                'boutEndIdx', boutEndIdx, 'nBins', nBins, ...
                'binLabels', {binLabels}, 'binMeanTrialTime', binMeanTrialTime, ...
                'progressionSign', progSign);
        end

        progressionTileIdx = stimsetIdx;
        slopeTileIdx = stimsetIdx + ncols * nrowsBase;

        a = nexttile(t, progressionTileIdx);
        aSlope = nexttile(t, slopeTileIdx);
        hold(a, 'on');
        hold(aSlope, 'on');

        progressionAxes(end+1) = a;
        slopeAxes(end+1) = aSlope;

        orderedXLabels = {};
        for stimIdx = 1:length(thisStimSet)
            bi = stimsBouts(thisStimSet{stimIdx});
            for binIdx = 1:bi.nBins
                if ~ismember(bi.binLabels{binIdx}, orderedXLabels)
                    orderedXLabels{end+1} = bi.binLabels{binIdx}; %#ok<AGROW>
                end
            end
        end

        lineHandles = [];
        lineLabels = {};
        slopeLineHandles = [];
        slopeLineLabels = {};

        % Define groups to plot: {dataMatrix, color, displayName, signVec}
        groupADisp = char(groupAStrain);
        groups = {{metricMatrixA, colorA, groupADisp, arenaTowardStim1SignA}};
        if hasGroupB && ~isempty(metricMatrixB)
            groupBDisp = char(groupBStrain);
            groups{end+1} = {metricMatrixB, colorB, groupBDisp, arenaTowardStim1SignB};
        end

        scatterData = struct();
        scatterKeys = {};

        for g = 1:length(groups)
            grp = groups{g};
            dataMat = grp{1};
            grpColor = grp{2};
            grpName = grp{3};
            towardSign = grp{4};

            for stimIdx = 1:length(thisStimSet)
                stimName = thisStimSet{stimIdx};
                bi = stimsBouts(stimName);
                if bi.nBouts == 0; continue; end

                timeByBin = bi.binMeanTrialTime;

                perBoutProgress = NaN(bi.nBouts, size(dataMat, 2));
                for boutIdx = 1:bi.nBouts
                    sIdx = bi.boutStartIdx(boutIdx);
                    eIdx = bi.boutEndIdx(boutIdx);
                    swEnd = min(sIdx + kvargs.MeanWindowFrames - 1, size(dataMat, 1));
                    sVals = mean(dataMat(sIdx:swEnd, :), 1, 'omitnan');
                    ewStart = max(eIdx - kvargs.MeanWindowFrames + 1, 1);
                    eVals = mean(dataMat(ewStart:eIdx, :), 1, 'omitnan');
                    if strcmp(metricType, 'distance')
                        perBoutProgress(boutIdx, :) = bi.progressionSign * (eVals - sVals);
                    else
                        perBoutProgress(boutIdx, :) = bi.progressionSign .* towardSign .* (eVals - sVals);
                    end
                end

                meanByBin = NaN(bi.nBins, 1);
                semByBin = NaN(bi.nBins, 1);
                nByBin = zeros(bi.nBins, 1);
                xNumeric = NaN(bi.nBins, 1);
                animalMeansByBin = cell(bi.nBins, 1);

                for binIdx = 1:bi.nBins
                    bs = (binIdx-1)*kvargs.BinWidth + 1;
                    be = min(binIdx*kvargs.BinWidth, bi.nBouts);
                    bm = mean(perBoutProgress(bs:be, :), 1, 'omitnan');
                    vv = bm(~isnan(bm));
                    animalMeansByBin{binIdx} = vv;
                    nByBin(binIdx) = numel(vv);
                    if ~isempty(vv)
                        meanByBin(binIdx) = mean(vv, 'omitnan');
                        semByBin(binIdx) = std(vv, 0, 'omitnan') / sqrt(numel(vv));
                    end
                    xNumeric(binIdx) = find(strcmp(orderedXLabels, bi.binLabels{binIdx}), 1);
                end

                ck = sprintf('%s:%s', stimName, grpName);
                scatterKeys{end+1} = ck; %#ok<AGROW>
                scatterData.(matlab.lang.makeValidName(ck)) = struct(...
                    'xNumeric', xNumeric, 'animalMeansByBin', {animalMeansByBin});

                %% Collect per-animal bin means for export table
                animalKeys = keys(thisStdTable.animalMetadata);
                for animalIdx = 1:size(dataMat, 2)
                    globalAnimalIdx = animalIdx;
                    if g == 2
                        globalAnimalIdx = ncolsA + animalIdx;
                    end
                    if globalAnimalIdx > numel(animalKeys)
                        continue;
                    end
                    md = thisStdTable.animalMetadata(animalKeys{globalAnimalIdx});

                    expRowIdx = expRowIdx + 1;
                    [expMouseId, expGene, expCageCode, expGeneId, expSex, ...
                     expGenotype, expLitter, expToeId, expDob, expAge, ...
                     expStimProtocol] = cohort.metrics.utils.fillCommonColumns(...
                        expMouseId, expGene, expCageCode, expGeneId, expSex, ...
                        expGenotype, expLitter, expToeId, expDob, expAge, ...
                        expStimProtocol, expRowIdx, md, thisStdTable.stimfileName);
                    expStimulusName(expRowIdx) = string(stimName);
                    expStimsetIdx(expRowIdx) = stimsetIdx;
                    expGroup(expRowIdx) = grpName;
                    expBinLabels{expRowIdx} = bi.binLabels;
                    animalVals = NaN(bi.nBins, 1);
                    for binIdx = 1:bi.nBins
                        vv = animalMeansByBin{binIdx};
                        if animalIdx <= numel(vv)
                            animalVals(binIdx) = vv(animalIdx);
                        end
                    end
                    expBinValues{expRowIdx} = animalVals;
                end

                validPlotMask = ~isnan(xNumeric) & ~isnan(meanByBin);
                if ~any(validPlotMask); continue; end

                xV = xNumeric(validPlotMask);
                yV = meanByBin(validPlotMask);
                sV = semByBin(validPlotMask);
                sV(isnan(sV)) = 0;

                fill(a, [xV; flipud(xV)], [yV+sV; flipud(yV-sV)], ...
                    grpColor, 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                if stimIdx == 1
                    ls = NORMAL_LINE_STYLE{1};
                else
                    if isKey(knownOtherStimLineStyles, stimName)
                        ls = knownOtherStimLineStyles(stimName);
                    else
                        idx = length(knownOtherStimLineStyles.keys()) + 1;
                        ls = OTHER_LINE_STYLE{mod(idx-1, length(OTHER_LINE_STYLE))+1};
                        knownOtherStimLineStyles(stimName) = ls;
                    end
                end

                lh = plot(a, xV, yV, 'Color', grpColor, 'LineStyle', ls, ...
                    'LineWidth', 2, 'Marker', 'o', 'MarkerFaceColor', grpColor, ...
                    'DisplayName', sprintf('%s - %s', stimName, grpName));
                lineHandles = [lineHandles; lh]; %#ok<AGROW>
                lineLabels{end+1} = sprintf('%s - %s (n=%d)', stimName, grpName, max(nByBin)); %#ok<AGROW>

                % Complementary slope-over-time plot using per-bin mean trial time (X)
                % and per-bin progression mean (Y).
                validTimeAndYMask = validPlotMask & isfinite(timeByBin);
                tVals = timeByBin(validTimeAndYMask);
                yValsSlope = meanByBin(validTimeAndYMask);
                if numel(tVals) >= 2
                    dt = diff(tVals);
                    dy = diff(yValsSlope);
                    validSlopeMask = isfinite(dt) & isfinite(dy) & dt > 0;
                    slopeX = (tVals(1:end-1) + tVals(2:end)) / 2;
                    slopeY = dy ./ dt;
                    slopeX = slopeX(validSlopeMask);
                    slopeY = slopeY(validSlopeMask);

                    if ~isempty(slopeX)
                        lhSlope = plot(aSlope, slopeX, slopeY, 'Color', grpColor, 'LineStyle', ls, ...
                            'LineWidth', 2, 'Marker', 'o', 'MarkerFaceColor', grpColor, ...
                            'DisplayName', sprintf('%s - %s', stimName, grpName));
                        slopeLineHandles = [slopeLineHandles; lhSlope]; %#ok<AGROW>
                        slopeLineLabels{end+1} = sprintf('%s - %s', stimName, grpName); %#ok<AGROW>
                    end
                end
            end
        end

        % Overlay data points
        if kvargs.ShowDataPoints && ~isempty(scatterKeys)
            nSG = length(scatterKeys);
            jw = 0.15;
            off = linspace(-jw, jw, max(nSG, 1));
            for si = 1:nSG
                sd = scatterData.(matlab.lang.makeValidName(scatterKeys{si}));
                pts = strsplit(scatterKeys{si}, ':');
                sStim = pts{1}; sGrp = pts{2};
                sIdx = find(strcmp(thisStimSet, sStim), 1);
                sMrk = 'o'; mOpts = {'o', '^', 's', 'd'};
                if ~isempty(sIdx); sMrk = mOpts{mod(sIdx-1, numel(mOpts))+1}; end
                sCol = colorA;
                if strcmpi(strtrim(sGrp), strtrim(char(groupBStrain)))
                    sCol = colorB;
                end
                for bi = 1:length(sd.xNumeric)
                    xc = sd.xNumeric(bi);
                    vals = sd.animalMeansByBin{bi};
                    if isnan(xc) || isempty(vals); continue; end
                    jit = off(si) + jw*(2*rand(numel(vals),1)-1);
                    scatter(a, xc+jit, vals(:), 18, 'Marker', sMrk, ...
                        'MarkerFaceColor', sCol, 'MarkerEdgeColor', 'none', ...
                        'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
                end
            end
        end

        if ~isempty(orderedXLabels)
            xticks(a, 1:numel(orderedXLabels));
            xticklabels(a, orderedXLabels);
            xtickangle(a, 35);
            xlim(a, [0.5, numel(orderedXLabels)+0.5]);
        end
        if ~isempty(lineHandles)
            lgd = legend(a, lineHandles, lineLabels, 'Location', 'best', 'Interpreter', 'none');
            lgd.AutoUpdate = 'off';
        end
        if ~isempty(slopeLineHandles)
            lgdSlope = legend(aSlope, slopeLineHandles, slopeLineLabels, 'Location', 'best', 'Interpreter', 'none');
            lgdSlope.AutoUpdate = 'off';
        end
        yline(a, 0, ':k', 'LineWidth', 0.5, 'HandleVisibility', 'off');
        yline(aSlope, 0, ':k', 'LineWidth', 0.5, 'HandleVisibility', 'off');
        hold(a, 'off');
        hold(aSlope, 'off');
        title(a, sprintf('[%s]\n%s vs %s', strjoin(thisStimSet, ' / '), ...
            char(groupAStrain), char(groupBStrain)), 'Interpreter', 'none');
        title(aSlope, sprintf('[%s] Slope Over Time\n%s vs %s', strjoin(thisStimSet, ' / '), ...
            char(groupAStrain), char(groupBStrain)), 'Interpreter', 'none');
        xlabel(a, 'Bouts (% of session)');
        xlabel(aSlope, 'Mean Trial Time within Bin (s)');
        ylabel(a, strrep(ylabelStr, '\n', newline));
        ylabel(aSlope, 'Slope of Progression vs Time (\Deltaprogression/\Deltatime)');
        grid(a, 'on');
        grid(aSlope, 'on');
    end

    % Harmonize y-limits for progression axes
    if ~isempty(kvargs.YLim)
        if ~isempty(progressionAxes); ylim(progressionAxes, kvargs.YLim); end
    elseif kvargs.SameYLim
        if ~isempty(progressionAxes)
            ylm = NaN(numel(progressionAxes), 2);
            for ai = 1:numel(progressionAxes)
                yl = ylim(progressionAxes(ai));
                if all(isfinite(yl)); ylm(ai,:) = yl; end
            end
            gmn = min(ylm(:,1), [], 'omitnan');
            gmx = max(ylm(:,2), [], 'omitnan');
            if isfinite(gmn) && isfinite(gmx) && gmx > gmn
                ylim(progressionAxes, [gmn, gmx]);
            end
        end
    end

    % Harmonize y-limits for slope axes (only when SameYLim=true)
    if kvargs.SameYLim && ~isempty(slopeAxes)
        ylm = NaN(numel(slopeAxes), 2);
        for ai = 1:numel(slopeAxes)
            yl = ylim(slopeAxes(ai));
            if all(isfinite(yl)); ylm(ai,:) = yl; end
        end
        gmn = min(ylm(:,1), [], 'omitnan');
        gmx = max(ylm(:,2), [], 'omitnan');
        if isfinite(gmn) && isfinite(gmx) && gmx > gmn
            ylim(slopeAxes, [gmn, gmx]);
        end
    end

    %% Assemble export table
    if expRowIdx < nRowsEstimate
        keep = 1:expRowIdx;
        expMouseId = expMouseId(keep);
        expGene = expGene(keep);
        expCageCode = expCageCode(keep);
        expGeneId = expGeneId(keep);
        expSex = expSex(keep);
        expGenotype = expGenotype(keep);
        expLitter = expLitter(keep);
        expToeId = expToeId(keep);
        expDob = expDob(keep);
        expAge = expAge(keep);
        expStimProtocol = expStimProtocol(keep);
        expStimulusName = expStimulusName(keep);
        expStimsetIdx = expStimsetIdx(keep);
        expGroup = expGroup(keep);
        expBinLabels = expBinLabels(keep);
        expBinValues = expBinValues(keep);
    end

    tbl = table();
    tbl.('Mouse_ID') = expMouseId;
    tbl.('Gene') = expGene;
    tbl.('Cage #') = expCageCode;
    tbl.('Gene_ID') = expGeneId;
    tbl.('Sex$') = expSex;
    tbl.('Genotype$') = expGenotype;
    tbl.('Litter') = expLitter;
    tbl.('Toe_ID') = expToeId;
    tbl.('DOB') = expDob;
    tbl.('Age') = expAge;
    tbl.('Stimulus Protocol') = expStimProtocol;
    tbl.('Stimulus Name') = expStimulusName;
    tbl.('StimsetIdx') = expStimsetIdx;
    tbl.('Group') = expGroup;

    % Determine the maximum number of bins across all rows for column naming
    maxBins = 0;
    for ri = 1:numel(expBinValues)
        if ~isempty(expBinValues{ri})
            maxBins = max(maxBins, numel(expBinValues{ri}));
        end
    end

    for bi = 1:maxBins
        colVals = NaN(expRowIdx, 1);
        for ri = 1:expRowIdx
            v = expBinValues{ri};
            if ~isempty(v) && bi <= numel(v)
                colVals(ri) = v(bi);
            end
        end
        label = '';
        for ri = 1:expRowIdx
            lbls = expBinLabels{ri};
            if ~isempty(lbls) && bi <= numel(lbls)
                label = lbls{bi};
                break;
            end
        end
        tbl.(sprintf('TimeBin_%d__%s', bi, label)) = colVals;
    end
end