function fig = plotSimilarityToBaseline(baselineStdTables, testStdTables, kvargs)
%%PLOTSIMILARITYTOBASELINE Visualize test-subject similarity against baseline.
%
%   fig = population.temp.plotSimilarityToBaseline(baselineStdTables, testStdTables)
%   fig = population.temp.plotSimilarityToBaseline(..., Name=Value)
%
%   The ranking is computed internally so every tab uses the same feature
%   construction and scoring result. Baseline subjects are rendered as an
%   aggregate reference: a robust center, an empirical envelope, and quiet
%   distribution context. Test subjects are the foreground of every view.

    arguments
        baselineStdTables struct {sdTable.mustBeStandardizedTable}
        testStdTables struct {sdTable.mustBeStandardizedTable}
        kvargs.ProgressionMetricType (1,1) string {mustBeMember(kvargs.ProgressionMetricType, ["state", "distance"])} = "state"
        kvargs.BinWidth (1,1) double {mustBePositive, mustBeInteger} = 6
        kvargs.MeanWindowFrames (1,1) double {mustBePositive, mustBeInteger} = 30
        kvargs.StimulusIncludesTrailingISI (1,1) logical = true
        kvargs.LocomotionCovariateColumn (1,1) string {mustBeTextScalar} = "Speed Mean During Stimulus (cm/s)"
        kvargs.AdjustmentLabel (1,1) string {mustBeTextScalar} = ""
        kvargs.WTEnvelopePct (1,2) double {mustBeInRange(kvargs.WTEnvelopePct, 0, 100), mustBeEnvelopeSorted(kvargs.WTEnvelopePct)} = [5 95]
        kvargs.MinShrinkageLambda (1,1) double {mustBeNonnegative, mustBeLessThanOrEqual(kvargs.MinShrinkageLambda, 1)} = 0.1
        kvargs.OutlierMethod (1,1) string {mustBeMember(kvargs.OutlierMethod, ["none", "multivariate", "mixedquality", "baselinelocomotion"])} = "baselinelocomotion"
        kvargs.OutlierThresholdK (1,1) double {mustBePositive} = 3.5
        kvargs.MinValidBins (1,1) double {mustBePositive, mustBeInteger} = 2
        kvargs.MinPreStimDistanceCm (1,1) double {mustBeReal} = NaN
        kvargs.MinMeanSpeedCmS (1,1) double {mustBeNonnegative} = 0.1
        kvargs.FilePrefix (1,1) string {mustBeTextScalar} = "similarity"
        kvargs.RunStamp (1,1) string {mustBeTextScalar} = ""
        kvargs.PlotTypes (1,:) string {mustBeMember(kvargs.PlotTypes, ["rank", "heatmap", "pca", "profiles", "trajectory"])} = ["rank", "heatmap", "pca", "profiles", "trajectory"]
        kvargs.TopKFeatures (1,1) double {mustBePositive, mustBeInteger} = 8
        kvargs.LOOBandPct (1,1) double {mustBeInRange(kvargs.LOOBandPct, 50, 100)} = 95
        kvargs.D2RankLayer (1,1) string {mustBeMember(kvargs.D2RankLayer, ["adjusted", "raw"])} = "adjusted"
        kvargs.OutputDir (1,1) string {mustBeTextScalar} = ""
        kvargs.ExportPlots (1,1) logical = false
        kvargs.FigureName (1,1) string {mustBeTextScalar} = "Similarity to baseline"
        kvargs.Verbose (1,1) logical = true
    end

    rankArgs = kvargs;
    rankArgs = rmfield(rankArgs, {'PlotTypes', 'TopKFeatures', 'LOOBandPct', 'D2RankLayer', ...
        'OutputDir', 'ExportPlots', 'FigureName'});
    rankArgsCell = namedargs2cell(rankArgs);
    [rankedTbl, componentsLongTbl, info, baselineData] = ...
        population.temp.rankSubjectSimilarityToBaseline(baselineStdTables, ...
        testStdTables, rankArgsCell{:});
    plotKvargs = kvargs;
    plotKvargs.StandardizedTables = baselineStdTables;

    tabOrder = ["rank", "heatmap", "pca", "profiles", "trajectory"];
    selected = tabOrder(ismember(tabOrder, kvargs.PlotTypes));
    tabTitles = strings(1, numel(selected));
    titleMap = containers.Map({'rank', 'heatmap', 'pca', 'profiles', 'trajectory'}, ...
        {'D2 Rank', 'Z Heatmap', 'PCA Map', 'Z Profiles', 'Trajectory RMSE'});
    for i = 1:numel(selected)
        tabTitles(i) = titleMap(char(selected(i)));
    end
    if isempty(selected)
        error('plotSimilarityToBaseline:noPlots', 'PlotTypes must contain at least one supported plot.');
    end

    [screenSize, videoAspect] = deal(get(0, 'ScreenSize'), 16 / 10);
    [figW, figH] = ui.dynamicFigureSize(videoAspect, 0);
    figPos = [(screenSize(3) - figW) / 2, (screenSize(4) - figH) / 2, figW, figH];
    figProps = struct('Name', kvargs.FigureName, 'Position', figPos, 'NumberTitle', 'off');
    tabProps = repmat(struct('Title', ""), 1, numel(tabTitles));
    for i = 1:numel(tabTitles)
        tabProps(i).Title = tabTitles(i);
    end
    [fig, tabGroup, tabs] = ui.tabbedFigure(figProps, struct(), tabProps);

    renderArgs = {rankedTbl, componentsLongTbl, info, baselineData, plotKvargs};
    for i = 1:numel(selected)
        switch selected(i)
            case "rank"
                renderRankTab(tabs{i}, renderArgs{:});
            case "heatmap"
                renderHeatmapTab(tabs{i}, renderArgs{:});
            case "pca"
                renderPcaTab(tabs{i}, renderArgs{:});
            case "profiles"
                renderProfileTab(tabs{i}, renderArgs{:});
            case "trajectory"
                renderTrajectoryTab(tabs{i}, renderArgs{:});
        end
    end

    if kvargs.ExportPlots || strlength(kvargs.OutputDir) > 0
        outputDir = char(kvargs.OutputDir);
        if isempty(outputDir)
            outputDir = pwd;
        elseif ~exist(outputDir, 'dir')
            mkdir(outputDir);
        end
        stamp = strtrim(sprintf('%s %s', kvargs.FilePrefix, kvargs.RunStamp));
        stamp = regexprep(stamp, '\s+', '_');
        for i = 1:numel(selected)
            tabGroup.SelectedTab = tabs{i};
            drawnow;
            path = fullfile(outputDir, sprintf('%s_%s.png', stamp, selected(i)));
            exportgraphics(fig, path, 'Resolution', 180);
        end
    end

    if kvargs.Verbose
        fprintf('Rendered similarity visualization with %d tab(s): %s\n', ...
            numel(selected), strjoin(selected, ', '));
    end
end

function renderRankTab(parent, rankedTbl, ~, info, ~, kvargs)
    ax = axes(parent);
    hold(ax, 'on');
    n = height(rankedTbl);
    [subjectOrder, ~] = sortRowsByD2(rankedTbl, kvargs.D2RankLayer);
    x = 1:n;
    adjustmentLabel = getAdjustmentLabel(info, kvargs);
    loo = finiteValues(info.LOO_D2);
    [bandLo, bandHi] = referenceBand(loo, kvargs.LOOBandPct);
    if isfinite(bandLo) && isfinite(bandHi)
        patch(ax, [0.5, n + 0.5, n + 0.5, 0.5], [bandLo, bandLo, bandHi, bandHi], ...
            [0.82, 0.86, 0.90], 'FaceAlpha', 0.55, 'EdgeColor', 'none', ...
            'DisplayName', sprintf('Baseline LOO %g%% envelope', kvargs.LOOBandPct));
        yline(ax, median(loo), '--', 'Color', [0.25, 0.30, 0.35], ...
            'DisplayName', 'Baseline LOO median');
    end
    if ~isempty(loo)
        scatter(ax, repmat(0.72, size(loo)), loo, 18, [0.45, 0.48, 0.52], ...
            'Marker', 'x', 'LineWidth', 1, 'DisplayName', 'Baseline LOO scores');
    end

    looAdj = finiteValues(info.LOO_D2_Adj);
    [bandLoAdj, bandHiAdj] = referenceBand(looAdj, kvargs.LOOBandPct);
    if isfinite(bandLoAdj) && isfinite(bandHiAdj)
        patch(ax, [0.5, n + 0.5, n + 0.5, 0.5], ...
            [bandLoAdj, bandLoAdj, bandHiAdj, bandHiAdj], ...
            [0.98, 0.84, 0.73], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
            'DisplayName', sprintf('%s baseline LOO %g%% envelope', adjustmentLabel, kvargs.LOOBandPct));
        yline(ax, median(looAdj), ':', 'Color', [0.75, 0.30, 0.08], ...
            'DisplayName', sprintf('%s baseline LOO median', adjustmentLabel));
    end
    if ~isempty(looAdj)
        scatter(ax, repmat(0.92, size(looAdj)), looAdj, 18, [0.85, 0.30, 0.12], ...
            'Marker', '+', 'LineWidth', 1, ...
            'DisplayName', sprintf('%s baseline LOO scores', adjustmentLabel));
    end

    if kvargs.D2RankLayer == "adjusted"
        primaryD2 = columnOrNan(rankedTbl, 'MahalanobisD2_Adj');
        primaryP = columnOrNan(rankedTbl, 'EmpiricalP_Adj');
        secondaryD2 = columnOrNan(rankedTbl, 'MahalanobisD2');
        primaryLabel = adjustmentLabel + " D^2";
        secondaryLabel = "Raw D^2";
    else
        primaryD2 = columnOrNan(rankedTbl, 'MahalanobisD2');
        primaryP = columnOrNan(rankedTbl, 'EmpiricalP');
        secondaryD2 = columnOrNan(rankedTbl, 'MahalanobisD2_Adj');
        primaryLabel = "Raw D^2";
        secondaryLabel = adjustmentLabel + " D^2";
    end
    primaryD2 = primaryD2(subjectOrder);
    primaryP = primaryP(subjectOrder);
    secondaryD2 = secondaryD2(subjectOrder);
    finite = isfinite(primaryD2);
    if any(finite)
        scatter(ax, x(finite), primaryD2(finite), 70, primaryP(finite), 'filled', ...
            'MarkerEdgeColor', [0.10, 0.12, 0.16], 'LineWidth', 0.7, ...
            'DisplayName', sprintf('Test subject %s', primaryLabel));
    end
    finiteSecondary = isfinite(secondaryD2);
    if any(finiteSecondary)
        scatter(ax, x(finiteSecondary), secondaryD2(finiteSecondary), 86, 'o', ...
            'MarkerEdgeColor', [0.45, 0.48, 0.52], 'LineWidth', 1.4, ...
            'DisplayName', sprintf('Test subject %s', secondaryLabel));
    end

    labels = subjectLabels(rankedTbl);
    labels = labels(subjectOrder);
    set(ax, 'XLim', [0.5, max(n + 0.5, 1.5)], 'XTick', x, 'XTickLabel', labels);
    xtickangle(ax, 35);
    ylabel(ax, 'Mahalanobis D^2');
    xlabel(ax, sprintf('Test subjects, ordered by %s D^2', kvargs.D2RankLayer));
    title(ax, sprintf('Similarity rank relative to the aggregate baseline; ordered by %s D^2', ...
        kvargs.D2RankLayer));
        colormap(ax, parula(256));
    cb = colorbar(ax);
    cb.Label.String = sprintf('%s empirical P', primaryLabel);
    legend(ax, 'Location', 'eastoutside');
    grid(ax, 'on');
    hold(ax, 'off');
end

function renderHeatmapTab(parent, rankedTbl, componentsLongTbl, info, baselineData, kvargs)
    [zTest, featureNames] = testZMatrix(rankedTbl, componentsLongTbl, info);
    displayFeatureNames = simplifyFeatureLabels(featureNames, kvargs.StandardizedTables);
    [order, ~] = sortRowsByD2(rankedTbl, kvargs.D2RankLayer);
    zTest = zTest(order, :);
    labels = subjectLabels(rankedTbl);
    labels = labels(order);
    zPlot = [zeros(1, size(zTest, 2)); zTest];

    layout = tiledlayout(parent, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(layout, 1);
    imagesc(ax, max(min(zPlot, 3), -3));
    axis(ax, 'tight');
    set(ax, 'YTick', 1:size(zPlot, 1), 'YTickLabel', ["Baseline median"; labels]);
    set(ax, 'XTick', 1:numel(featureNames), 'XTickLabel', displayFeatureNames);
    ax.XAxis.TickLabelInterpreter = 'none';
    ax.YAxis.TickLabelInterpreter = 'none';
    xtickangle(ax, 35);
    ylabel(ax, 'Subjects');
    title(ax, sprintf('Feature deviations from baseline; test rows are ranked by %s D^2', ...
        kvargs.D2RankLayer));
    clim(ax, [-3, 3]);
        colormap(ax, robustZMap(256));
    cb = colorbar(ax);
    cb.Label.String = 'Robust z';
    box(ax, 'on');

    axSpread = nexttile(layout, 2);
    baseZ = baselineData.ZMatrix;
    qLow = nan(1, numel(featureNames));
    qHigh = qLow;
    med = qLow;
    for j = 1:numel(featureNames)
        values = finiteValues(baseZ(:, j));
        if ~isempty(values)
            qLow(j) = finiteQuantile(values, 0.05);
            qHigh(j) = finiteQuantile(values, 0.95);
            med(j) = median(values);
        end
    end
    hold(axSpread, 'on');
    valid = isfinite(qLow) & isfinite(qHigh);
    if any(valid)
        patch(axSpread, [find(valid), fliplr(find(valid))], ...
            [qLow(valid), fliplr(qHigh(valid))], [0.72, 0.76, 0.80], ...
            'FaceAlpha', 0.7, 'EdgeColor', 'none', 'DisplayName', 'Baseline 5-95%');
        plot(axSpread, find(valid), med(valid), 'k-', 'LineWidth', 1.2, ...
            'DisplayName', 'Baseline median');
    end
    yline(axSpread, 0, '--', 'Color', [0.35, 0.35, 0.35]);
    set(axSpread, 'XLim', [0.5, max(numel(featureNames) + 0.5, 1.5)], ...
        'XTick', 1:numel(featureNames), 'XTickLabel', displayFeatureNames);
    axSpread.XAxis.TickLabelInterpreter = 'none';
    axSpread.YAxis.TickLabelInterpreter = 'none';
    xtickangle(axSpread, 35);
    ylabel(axSpread, 'Baseline robust z');
    xlabel(axSpread, 'Feature');
    title(axSpread, 'Baseline feature spread used as the reference');
    legend(axSpread, 'Location', 'eastoutside');
    grid(axSpread, 'on');
    hold(axSpread, 'off');
end

function renderPcaTab(parent, rankedTbl, componentsLongTbl, info, baselineData, kvargs)
    [zTest, featureNames] = testZMatrix(rankedTbl, componentsLongTbl, info);
    baseZ = baselineData.ZMatrix;
    nBase = size(baseZ, 1);
    combined = [baseZ; zTest];
    fillValues = nanmedianMatrix(combined);
    for j = 1:size(combined, 2)
        missing = ~isfinite(combined(:, j));
        combined(missing, j) = fillValues(j);
    end
    combined = combined - mean(combined, 1);
    [~, ~, v] = svd(combined, 'econ');
    if size(v, 2) < 2
        text(parent, 0.5, 0.5, 'At least two non-degenerate feature dimensions are required for PCA.', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end
    scores = combined * v(:, 1:2);
    baseScores = scores(1:nBase, :);
    [testOrder, ~] = sortRowsByD2(rankedTbl, kvargs.D2RankLayer);
    testScores = scores(nBase + testOrder, :);

    ax = axes(parent);
    hold(ax, 'on');
    validBase = all(isfinite(baseScores), 2);
    scatter(ax, baseScores(validBase, 1), baseScores(validBase, 2), 28, ...
        [0.65, 0.68, 0.72], 'filled', 'MarkerFaceAlpha', 0.55, ...
        'DisplayName', 'Baseline subjects');
    if nnz(validBase) >= 3
        ellipse = covarianceEllipse(baseScores(validBase, :), 0.90);
        patch(ax, ellipse(:, 1), ellipse(:, 2), [0.72, 0.76, 0.81], ...
            'FaceAlpha', 0.25, 'EdgeColor', [0.40, 0.44, 0.50], ...
            'DisplayName', 'Baseline 90% envelope');
    end
    baseCenter = mean(baseScores(validBase, :), 1, 'omitnan');
    plot(ax, baseCenter(1), baseCenter(2), 'p', 'MarkerSize', 14, ...
        'MarkerFaceColor', [0.12, 0.15, 0.20], 'MarkerEdgeColor', 'w', ...
        'DisplayName', 'Baseline centroid');

    d2 = primaryD2Values(rankedTbl, kvargs.D2RankLayer);
    d2 = d2(testOrder);
    outside = columnOrNan(rankedTbl, 'NOutsideWT');
    outside = outside(testOrder);
    finiteTest = all(isfinite(testScores), 2);
    sizeData = 70 + 18 * max(outside, 0);
    sizeData(~isfinite(sizeData)) = 70;
    scatter(ax, testScores(finiteTest, 1), testScores(finiteTest, 2), ...
        sizeData(finiteTest), d2(finiteTest), 'filled', ...
        'MarkerEdgeColor', [0.08, 0.10, 0.12], 'LineWidth', 0.8, ...
        'DisplayName', 'Test subjects');
    labels = subjectLabels(rankedTbl);
    labels = labels(testOrder);
    for i = find(finiteTest(:))'
        text(ax, testScores(i, 1), testScores(i, 2), ['  ', labels(i)], ...
            'FontSize', 8, 'Interpreter', 'none', 'Clipping', 'on');
    end
    xlabel(ax, sprintf('PC1 (%.1f%%)', explainedVariance(combined, v, 1)));
    ylabel(ax, sprintf('PC2 (%.1f%%)', explainedVariance(combined, v, 2)));
    title(ax, sprintf('Combined baseline/test PCA (%d features)', numel(featureNames)));
    subtitle(ax, 'Baseline is gray context; test subjects are colored and labeled by ID');
    colormap(ax, parula(256));
    cb = colorbar(ax);
    cb.Label.String = 'Mahalanobis D^2';
    legend(ax, 'Location', 'best');
    grid(ax, 'on');
    hold(ax, 'off');
end

function renderProfileTab(parent, rankedTbl, componentsLongTbl, info, baselineData, kvargs)
    [zTest, featureNames] = testZMatrix(rankedTbl, componentsLongTbl, info);
    displayFeatureNames = simplifyFeatureLabels(featureNames, kvargs.StandardizedTables);
    [order, ~] = sortRowsByD2(rankedTbl, kvargs.D2RankLayer);
    zTest = zTest(order, :);
    labels = subjectLabels(rankedTbl);
    labels = labels(order);
    baseZ = baselineData.ZMatrix;
    n = size(zTest, 1);
    nCols = min(4, max(1, n));
    nRows = ceil(n / nCols);
    layout = tiledlayout(parent, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:n
        ax = nexttile(layout);
        values = zTest(i, :);
        [~, featureOrder] = sort(abs(values), 'descend', 'MissingPlacement', 'last');
        featureOrder = featureOrder(1:min(kvargs.TopKFeatures, numel(featureOrder)));
        hold(ax, 'on');
        for k = 1:numel(featureOrder)
            j = featureOrder(k);
            baseValues = finiteValues(baseZ(:, j));
            if ~isempty(baseValues)
                low = finiteQuantile(baseValues, 0.05);
                high = finiteQuantile(baseValues, 0.95);
                patch(ax, [k - 0.42, k + 0.42, k + 0.42, k - 0.42], ...
                    [low, low, high, high], [0.75, 0.78, 0.82], ...
                    'FaceAlpha', 0.65, 'EdgeColor', [0.55, 0.58, 0.63], ...
                    'LineWidth', 0.5);
            end
        end
        bar(ax, 1:numel(featureOrder), values(featureOrder), 0.62, ...
            'FaceColor', [0.10, 0.43, 0.62], 'EdgeColor', [0.05, 0.12, 0.18]);
        yline(ax, 0, 'k-');
        yline(ax, 2, ':', 'Color', [0.45, 0.20, 0.10]);
        yline(ax, -2, ':', 'Color', [0.45, 0.20, 0.10]);
        set(ax, 'XTick', 1:numel(featureOrder), ...
            'XTickLabel', displayFeatureNames(featureOrder));
        ax.XAxis.TickLabelInterpreter = 'none';
        ax.YAxis.TickLabelInterpreter = 'none';
        xtickangle(ax, 35);
        title(ax, labels(i), 'Interpreter', 'none');
        ylabel(ax, 'Robust z');
        grid(ax, 'on');
        hold(ax, 'off');
    end
    title(layout, 'Largest subject deviations with baseline 5-95% bands');
end

function renderTrajectoryTab(parent, rankedTbl, ~, info, baselineData, kvargs)
    adjustmentLabel = getAdjustmentLabel(info, kvargs);
    trajNames = normalizeNames(baselineData.TrajectoryFeatureNames);
    trajNames = trajNames(ismember(trajNames, rankedTbl.Properties.VariableNames));
    if isempty(trajNames)
        text(parent, 0.5, 0.5, 'No trajectory features are available.', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end
    [order, ~] = sortRowsByD2(rankedTbl, kvargs.D2RankLayer);
    labels = subjectLabels(rankedTbl);
    labels = labels(order);
    n = numel(trajNames);
    nCols = min(3, max(1, n));
    nRows = ceil(n / nCols);
    layout = tiledlayout(parent, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');
    baseRef = baselineTrajectoryReference(baselineData.progressionLongTable);
    baseRefAdj = baselineTrajectoryReference(baselineData.progressionLongTableAdj);
    for j = 1:n
        ax = nexttile(layout);
        rawName = trajNames(j);
        adjName = strrep(rawName, 'TrajRMSE__', 'TrajRMSE_Adj__');
        raw = rankedTbl.(rawName);
        raw = raw(order);
        adj = columnOrNan(rankedTbl, adjName);
        adj = adj(order);
        hold(ax, 'on');
        ref = trajectoryReferenceColumn(baseRef, rawName);
        ref = finiteValues(ref);
        if ~isempty(ref)
            low = finiteQuantile(ref, 0.05);
            high = finiteQuantile(ref, 0.95);
            patch(ax, [0.5, numel(raw) + 0.5, numel(raw) + 0.5, 0.5], ...
                [low, low, high, high], [0.76, 0.79, 0.83], 'FaceAlpha', 0.8, ...
                'EdgeColor', 'none', 'DisplayName', 'Baseline reference');
            yline(ax, median(ref), '--', 'Color', [0.22, 0.25, 0.30], ...
                'DisplayName', 'Baseline median');
        end
        refAdj = trajectoryReferenceColumn(baseRefAdj, rawName);
        refAdj = finiteValues(refAdj);
        if ~isempty(refAdj)
            lowAdj = finiteQuantile(refAdj, 0.05);
            highAdj = finiteQuantile(refAdj, 0.95);
            patch(ax, [0.5, numel(raw) + 0.5, numel(raw) + 0.5, 0.5], ...
                [lowAdj, lowAdj, highAdj, highAdj], [0.98, 0.84, 0.73], ...
                'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
                'DisplayName', sprintf('%s baseline reference', adjustmentLabel));
            yline(ax, median(refAdj), ':', 'Color', [0.75, 0.30, 0.08], ...
                'DisplayName', sprintf('%s baseline median', adjustmentLabel));
        end
        bar(ax, 1:numel(raw), raw, 0.62, 'FaceColor', [0.10, 0.43, 0.62], ...
            'DisplayName', 'Test raw');
        if any(isfinite(adj))
            plot(ax, 1:numel(adj), adj, 'o-', 'Color', [0.85, 0.30, 0.12], ...
                'LineWidth', 1.2, 'MarkerFaceColor', [0.98, 0.88, 0.78], ...
                'DisplayName', sprintf('Test %s', adjustmentLabel));
        end
        set(ax, 'XTick', 1:numel(labels), 'XTickLabel', labels);
        ax.XAxis.TickLabelInterpreter = 'none';
        ax.YAxis.TickLabelInterpreter = 'none';
        xtickangle(ax, 35);
        title(ax, simplifyFeatureLabels(strrep(rawName, 'TrajRMSE__', ''), ...
            kvargs.StandardizedTables), 'Interpreter', 'none');
        ylabel(ax, 'RMSE');
        grid(ax, 'on');
        if j == 1
            legend(ax, 'Location', 'best');
        end
        hold(ax, 'off');
    end
    title(layout, 'Trajectory deviation from the aggregate baseline');
end

function [z, featureNames] = testZMatrix(rankedTbl, componentsLongTbl, info)
    featureNames = normalizeNames(info.FeatureNames);
    if isempty(featureNames)
        featureNames = unique(string(componentsLongTbl.Feature), 'stable');
    end
    z = nan(height(rankedTbl), numel(featureNames));
    subjectKeys = string(rankedTbl.SubjectKey);
    componentKeys = string(componentsLongTbl.SubjectKey);
    componentFeatures = string(componentsLongTbl.Feature);
    for i = 1:height(rankedTbl)
        for j = 1:numel(featureNames)
            hit = componentKeys == subjectKeys(i) & componentFeatures == featureNames(j);
            if any(hit)
                z(i, j) = componentsLongTbl.Z(find(hit, 1, 'first'));
            end
        end
    end
end

function [order, rankValues] = sortRowsByD2(tbl, rankLayer)
    rankValues = primaryD2Values(tbl, rankLayer);
    rankValues(~isfinite(rankValues)) = inf;
    [~, order] = sort(rankValues, 'ascend');
end

function d2 = primaryD2Values(tbl, rankLayer)
    if rankLayer == "adjusted"
        d2 = columnOrNan(tbl, 'MahalanobisD2_Adj');
    else
        d2 = columnOrNan(tbl, 'MahalanobisD2');
    end
end

function labels = subjectLabels(tbl)
    if ismember('Mouse_ID', tbl.Properties.VariableNames)
        labels = string(tbl.Mouse_ID);
    else
        labels = string(tbl.SubjectKey);
    end
    if ismember('Cage #', tbl.Properties.VariableNames)
        cageLabels = string(tbl.('Cage #'));
        hasCage = ~(ismissing(cageLabels) | strlength(strtrim(cageLabels)) == 0);
        labels(hasCage) = strtrim(cageLabels(hasCage) + " " + labels(hasCage));
    end
    missing = ismissing(labels) | strlength(labels) == 0;
    labels(missing) = "subject_" + string(find(missing));
end

function values = columnOrNan(tbl, name)
    if ismember(name, tbl.Properties.VariableNames)
        values = double(tbl.(name));
        values = values(:);
    else
        values = nan(height(tbl), 1);
    end
end

function values = finiteValues(values)
    values = values(isfinite(values));
end

function [low, high] = referenceBand(values, widthPct)
    values = finiteValues(values);
    if isempty(values)
        low = NaN;
        high = NaN;
        return;
    end
    tail = (100 - widthPct) / 200;
    low = finiteQuantile(values, tail);
    high = finiteQuantile(values, 1 - tail);
end

function value = finiteQuantile(values, q)
    values = sort(finiteValues(values));
    if isempty(values)
        value = NaN;
        return;
    end
    if numel(values) == 1
        value = values(1);
        return;
    end
    position = 1 + (numel(values) - 1) * min(max(q, 0), 1);
    lower = floor(position);
    upper = ceil(position);
    if lower == upper
        value = values(lower);
    else
        value = values(lower) + (position - lower) * (values(upper) - values(lower));
    end
end

function names = normalizeNames(names)
    if iscell(names)
        if numel(names) == 1 && iscell(names{1})
            names = names{1};
        end
        names = string(names);
    else
        names = string(names);
    end
    names = names(:)';
end

function displayNames = simplifyFeatureLabels(featureNames, standardizedTables)
    displayNames = string(featureNames);
    for tableIndex = 1:numel(standardizedTables)
        protocol = string(standardizedTables(tableIndex).stimfileName);
        stimuli = string(standardizedTables(tableIndex).stimuliSorted);
        if strlength(protocol) == 0 || isempty(stimuli)
            continue;
        end
        stimulusLabel = "[" + join(stimuli, "|") + "]";
        displayNames = replace(displayNames, protocol, stimulusLabel);
    end
end

function values = nanmedianMatrix(matrix)
    values = nan(1, size(matrix, 2));
    for j = 1:size(matrix, 2)
        column = finiteValues(matrix(:, j));
        if ~isempty(column)
            values(j) = median(column);
        else
            values(j) = 0;
        end
    end
end

function percent = explainedVariance(centered, vectors, component)
    total = sum(centered(:) .^ 2);
    if total == 0
        percent = 0;
    else
        componentScores = centered * vectors(:, component);
        percent = 100 * sum(componentScores .^ 2) / total;
    end
end

function map = robustZMap(n)
    % Diverging robust-z map: blue negative, #D6D6D6 at zero, red positive.
    blue = [0.12, 0.32, 0.78];
    zero = [214, 214, 214] / 255;
    red = [0.80, 0.12, 0.10];
    map = interp1([-1, 0, 1], [blue; zero; red], linspace(-1, 1, n)');
    if mod(n, 2) == 0
        center = n / 2;
        map(center:center + 1, :) = repmat(zero, 2, 1);
    else
        map((n + 1) / 2, :) = zero;
    end
end

function points = covarianceEllipse(values, coverage)
    center = mean(values, 1, 'omitnan');
    complete = values(all(isfinite(values), 2), :);
    if size(complete, 1) >= 2
        covariance = cov(complete, 1);
    else
        covariance = eye(2);
    end
    if any(~isfinite(covariance(:)))
        covariance = eye(2);
    end
    [vectors, eigenValues] = eig((covariance + covariance') / 2);
    eigenValues = max(diag(eigenValues), 0);
    radius = sqrt(-2 * log(1 - coverage));
    theta = linspace(0, 2 * pi, 160)';
    points = [cos(theta), sin(theta)] * diag(sqrt(eigenValues) * radius) * vectors' + center;
end

function baseRef = baselineTrajectoryReference(longTbl)
    keys = unique(string(longTbl.SubjectKey), 'stable');
    pairs = unique(longTbl(:, {'StimulusProtocol', 'Stimulus'}), 'stable');
    multiProto = height(unique(pairs(:, 'StimulusProtocol'))) > 1;
    baseRef = struct();
    baseRef.SubjectKey = keys;
    baseRef.Names = trajectoryNames(pairs, multiProto);
    baseRef.Values = nan(numel(keys), height(pairs));
    for i = 1:numel(keys)
        for j = 1:height(pairs)
            protocol = string(pairs.StimulusProtocol(j));
            stimulus = string(pairs.Stimulus(j));
            isPair = string(longTbl.StimulusProtocol) == protocol & string(longTbl.Stimulus) == stimulus;
            isSubject = string(longTbl.SubjectKey) == keys(i);
            subjectRows = longTbl(isPair & isSubject, :);
            referenceRows = longTbl(isPair & ~isSubject, :);
            if isempty(subjectRows) || isempty(referenceRows)
                continue;
            end
            grid = unique(referenceRows.BinIdx)';
            referenceMean = nan(size(grid));
            subjectValues = nan(size(grid));
            for g = 1:numel(grid)
                referenceMean(g) = mean(referenceRows.Progression(referenceRows.BinIdx == grid(g)), 'omitnan');
                hit = subjectRows.BinIdx == grid(g);
                if any(hit)
                    subjectValues(g) = subjectRows.Progression(find(hit, 1, 'first'));
                end
            end
            delta = subjectValues - referenceMean;
            delta = delta(isfinite(delta));
            if ~isempty(delta)
                baseRef.Values(i, j) = sqrt(mean(delta .^ 2));
            end
        end
    end
end

function values = trajectoryReferenceColumn(baseRef, name)
    hit = find(baseRef.Names == string(name), 1, 'first');
    if isempty(hit)
        values = nan(0, 1);
    else
        values = baseRef.Values(:, hit);
    end
end

function names = trajectoryNames(pairs, multiProto)
    names = strings(1, height(pairs));
    for j = 1:height(pairs)
        tag = string(pairs.Stimulus(j));
        if multiProto
            tag = tag + " @" + string(pairs.StimulusProtocol(j));
        end
        names(j) = "TrajRMSE__" + tag;
    end
end

function label = getAdjustmentLabel(info, kvargs)
    label = "Adjusted";
    if isstruct(info) && isfield(info, 'Adjustment') && ...
            isfield(info.Adjustment, 'Label') && strlength(string(info.Adjustment.Label)) > 0
        label = string(info.Adjustment.Label);
    elseif isstruct(kvargs) && isfield(kvargs, 'AdjustmentLabel') && ...
            strlength(string(kvargs.AdjustmentLabel)) > 0
        label = string(kvargs.AdjustmentLabel);
    end
end

function mustBeEnvelopeSorted(value)
    if value(1) > value(2)
        error('plotSimilarityToBaseline:badEnvelopePct', ...
            'WTEnvelopePct must be [lo hi] with lo <= hi.');
    end
end