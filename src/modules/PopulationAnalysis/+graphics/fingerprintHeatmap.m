function fig = fingerprintHeatmap(fp, statsTable)
    %%FINGERPRINTHEATMAP Cohort fingerprint heatmap of robust z with FDR annotation.
    %
    %   fig = graphics.fingerprintHeatmap(fp, statsTable)
    %
    %   Rows are eligible sex-specific cohorts (strain x genotype x sex,
    %   ordered by strain then genotype then sex). Columns are whitelisted
    %   metric contexts in graphics.fingerprintContextOrder, grouped by tier
    %   [exploration | baseline | P1/P2 stim tiers | delta]. Cells are robust
    %   z on a diverging colormap; cells whose permutation test does not
    %   survive BH-FDR q <= 0.05 (or have no test) are overlaid with gray dots
    %   drawn in a single scatter.
    %
    %   See also: cohort.fingerprint, cohort.fingerprintStats,
    %       graphics.fingerprintContextOrder

    arguments
        fp struct
        statsTable table = table()
    end

    zMatrix = fp.zMatrix;
    rowLabels = fp.rowLabels;
    colLabels = fp.colLabels;

    colOrder = graphics.fingerprintContextOrder(fp);
    [~, rowOrder] = sortrows([string(rowLabels.Strain), string(rowLabels.Genotype), string(rowLabels.Sex)]);

    % Rows = cohorts, columns = contexts (no transpose: imagesc draws rows on Y).
    Z = zMatrix(rowOrder, colOrder);
    rowMeta = rowLabels(rowOrder, :);
    colMeta = colLabels(colOrder, :);

    nCohorts = height(rowMeta);
    nContexts = height(colMeta);

    fig = figure('Name', 'Cohort Fingerprint', 'Color', 'w', 'Position', [100, 100, max(900, 22*nContexts), max(500, 26*nCohorts)]);
    ax = axes(fig);
    hold(ax, 'on');

    zClim = 3;
    imagesc(ax, Z);

    half = 128;
    blue = [0.02, 0.19, 0.42];
    white = [1, 1, 1];
    red = [0.65, 0.08, 0.14];
    cmap = [blue + (white - blue) .* linspace(0, 1, half)'; white + (red - white) .* linspace(0, 1, half)'];
    colormap(ax, cmap);
    clim(ax, [-zClim, zClim]);
    colorbar(ax);
    cb = ax.Colorbar;
    cb.Label.String = 'Robust z vs same-strain same-sex reference';

    % Overlay non-significant / untested cells with gray dots (single scatter).
    if ~isempty(statsTable)
        qByCell = lookupQBatch(statsTable, rowMeta, colMeta);
        notSig = isnan(qByCell) | qByCell > 0.05;
        [dotX, dotY] = find(notSig');
        if ~isempty(dotX)
            scatter(ax, dotX, dotY, 10, [0.45, 0.45, 0.45], 'filled', ...
                'HandleVisibility', 'off');
        end
    end

    set(ax, 'YDir', 'reverse', 'XAxisLocation', 'top', 'XTick', 1:nContexts, 'YTick', 1:nCohorts);
    xticklabels(ax, string(colMeta.Metric));
    xtickangle(ax, 45);
    cohortLabels = string(rowMeta.Strain) + " | " + string(rowMeta.Genotype) + " | " + string(rowMeta.Sex);
    yticklabels(ax, cohortLabels);
    ax.FontSize = 8;

    % Separators between tier groups and strain groups.
    tierOrder = ["exploration", "baseline", "stim_all", "per-stim", "delta"];
    tierVec = categorical(string(colMeta.Tier), tierOrder, 'Ordinal', true);
    tierChange = find(diff(double(tierVec)) ~= 0) + 0.5;
    for i = 1:numel(tierChange)
        xline(ax, tierChange(i), 'Color', 'k', 'LineWidth', 0.75);
    end
    strainVec = string(rowMeta.Strain);
    strainChange = find(strainVec(2:end) ~= strainVec(1:end-1)) + 0.5;
    for i = 1:numel(strainChange)
        yline(ax, strainChange(i), 'Color', 'k', 'LineWidth', 1.5);
    end

    axis(ax, 'tight');
    title(ax, 'Cohort behavioral fingerprint (gray dot = q > 0.05 or untested)');
end


function qByCell = lookupQBatch(statsTable, rowMeta, colMeta)
    % Vectorized q lookup: build one key per cohort x context and resolve
    % against a dictionary of statsTable keys.
    nCohorts = height(rowMeta);
    nContexts = height(colMeta);

    ctxKeys = string(colMeta.Tier) + "|" + string(colMeta.Protocol) + "|" + ...
        string(colMeta.Stimulus) + "|" + string(colMeta.Metric);
    cohortKeys = string(rowMeta.Strain) + "|" + string(rowMeta.Genotype) + "|" + string(rowMeta.Sex);

    qByCell = nan(nCohorts, nContexts);

    if isempty(statsTable)
        return;
    end

    stKeys = string(statsTable.Strain) + "|" + string(statsTable.Genotype) + "|" + ...
        string(statsTable.Sex) + "|" + string(statsTable.Tier) + "|" + ...
        string(statsTable.Protocol) + "|" + string(statsTable.Stimulus) + "|" + string(statsTable.Metric);
    qLookup = dictionary(stKeys, double(statsTable.QFDR));

    for r = 1:nCohorts
        keys = cohortKeys(r) + "|" + ctxKeys;
        tf = isKey(qLookup, keys);
        vals = nan(size(keys));
        vals(tf) = qLookup(keys(tf));
        qByCell(r, :) = vals;
    end
end
