function fig = fingerprintHeatmap(fp, statsTable, kvargs)
    %%FINGERPRINTHEATMAP Cohort fingerprint heatmap of robust z with FDR annotation.
    %
    %   fig = graphics.fingerprintHeatmap(fp, statsTable)
    %   fig = graphics.fingerprintHeatmap(fp, statsTable, MaxContexts=60)
    %
    %   Rows are eligible sex-specific cohorts (strain x genotype x sex,
    %   ordered by strain then genotype then sex). Columns are whitelisted
    %   metric contexts in graphics.fingerprintContextOrder (tier ->
    %   protocol -> stimulus -> metric family -> metric), grouped visually:
    %   heavy separators between tier groups, light separators between
    %   metric families, and a family annotation band above the image with
    %   one family label (plus its units) per contiguous family block.
    %   Per-column tick labels are abbreviated metric names (period phrase
    %   and units stripped; the family label carries them). Cells are robust
    %   z on a diverging colormap; cells whose permutation test does not
    %   survive BH-FDR q <= 0.05 (or have no test) are overlaid with gray
    %   dots drawn in a single scatter. Contexts whose finite cells are
    %   >= 90%% pinned at |z| = 3 are reported to the console as possibly
    %   degenerate-scale (saturated) metrics.
    %
    %   MaxContexts caps the number of context columns, keeping the most
    %   significant ones first (smallest minimum q across cohorts; requires
    %   statsTable). Default inf keeps every context in one figure.
    %
    %   See also: cohort.fingerprint, cohort.fingerprintStats,
    %       graphics.fingerprintContextOrder, cohort.internal.metricFamily

    arguments
        fp struct
        statsTable table = table()
        kvargs.MaxContexts (1,1) double {mustBeNumeric} = inf
    end

    if kvargs.MaxContexts ~= round(kvargs.MaxContexts) || kvargs.MaxContexts < 1
        error('graphics:fingerprintHeatmap:InvalidMaxContexts', ...
            'MaxContexts must be a positive integer or inf.');
    end

    zMatrix = fp.zMatrix;
    rowLabels = fp.rowLabels;
    colLabels = fp.colLabels;

    colOrder = graphics.fingerprintContextOrder(fp);
    [~, rowOrder] = sortrows([string(rowLabels.Strain), string(rowLabels.Genotype), string(rowLabels.Sex)]);
    nContextsAll = numel(colOrder);

    % Optional cap: keep the most significant contexts, restore canonical order.
    if isfinite(kvargs.MaxContexts) && kvargs.MaxContexts < nContextsAll
        qByCellAll = lookupQBatch(statsTable, rowLabels(rowOrder, :), colLabels);
        qMinByCtx = min(qByCellAll, [], 1, 'omitnan');
        qMinByCtx(isnan(qMinByCtx)) = 1; % untested/NaN q rank last
        [~, rank] = sort(qMinByCtx(colOrder));
        colOrder = sort(colOrder(rank(1:kvargs.MaxContexts)));
    end

    % Rows = cohorts, columns = contexts (no transpose: imagesc draws rows on Y).
    Z = zMatrix(rowOrder, colOrder);
    rowMeta = rowLabels(rowOrder, :);
    colMeta = colLabels(colOrder, :);

    nCohorts = height(rowMeta);
    nContexts = height(colMeta);

    [famCol, famPattern] = cohort.internal.metricFamily(string(colMeta.Metric));
    famCol = string(famCol);

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
    xticklabels(ax, abbreviatedLabels(string(colMeta.Metric), famPattern, famCol));
    xtickangle(ax, 45);
    cohortLabels = string(rowMeta.Strain) + " | " + string(rowMeta.Genotype) + " | " + string(rowMeta.Sex);
    yticklabels(ax, cohortLabels);
    ax.FontSize = 8;

    %% Family annotation band above the image (inside the axes), family runs,
    % and tier/family separators.
    tierOrder = ["exploration", "baseline", "stim_all", "per-stim", "delta"];
    tierVec = categorical(string(colMeta.Tier), tierOrder, 'Ordinal', true);

    blockKey = string(tierVec) + "|" + string(colMeta.Protocol) + "|" + ...
        string(colMeta.Stimulus) + "|" + famCol;
    newBlock = [true; blockKey(2:end) ~= blockKey(1:end-1)];
    blockId = cumsum(newBlock);
    tierChangeX = find(diff(double(tierVec)) ~= 0) + 0.5;

    bandH = max(2, ceil(0.08 * nCohorts)); % annotation band height in row units
    for b = 1:max(blockId)
        cols = find(blockId == b);
        famLbl = famCol(cols(1));
        units = uniqueUnits(string(colMeta.Metric(cols)));
        if strlength(units) > 0
            famLbl = famLbl + " (" + units + ")";
        end
        text(ax, mean(cols), 0.5 - bandH * 0.45, famLbl, ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontSize', 8, 'Interpreter', 'none', 'HandleVisibility', 'off');
        if b < max(blockId)
            xSep = cols(end) + 0.5;
            if ~any(abs(tierChangeX - xSep) < 1e-9) % tier line already drawn there
                xline(ax, xSep, 'Color', [0.65, 0.65, 0.65], 'LineWidth', 0.5, ...
                    'HandleVisibility', 'off');
            end
        end
    end

    for i = 1:numel(tierChangeX)
        xline(ax, tierChangeX(i), 'Color', 'k', 'LineWidth', 0.75);
    end
    strainVec = string(rowMeta.Strain);
    strainChange = find(strainVec(2:end) ~= strainVec(1:end-1)) + 0.5;
    for i = 1:numel(strainChange)
        yline(ax, strainChange(i), 'Color', 'k', 'LineWidth', 1.5);
    end

    xlim(ax, [0.5, nContexts + 0.5]);
    ylim(ax, [0.5 - bandH, nCohorts + 0.5]);
    title(ax, 'Cohort behavioral fingerprint (gray dot = q > 0.05 or untested)');

    notes = strings(0, 1);
    if nContexts < nContextsAll
        notes(end+1, 1) = sprintf('%d of %d contexts (most significant first)', nContexts, nContextsAll); %#ok<AGROW>
    end

    % Flag near-fully saturated columns (possible degenerate reference scale)
    % among non-reference cohorts; reference rows sit at z ~ 0 by construction
    % and would dilute the fraction.
    isRefRow = false(nCohorts, 1);
    if isfield(fp, 'referenceMap') && ~isempty(fp.referenceMap)
        refDict = dictionary(string(fp.referenceMap.Strain), lower(strtrim(string(fp.referenceMap.ReferenceGenotype))));
        strainKeys = string(rowMeta.Strain);
        refGenoOfRow = refDict(strainKeys);
        isRefRow = lower(strtrim(string(rowMeta.Genotype))) == refGenoOfRow;
    end
    nFin = sum(isfinite(Z) & ~isRefRow, 1);
    nSat = sum(abs(Z) >= zClim - 1e-9 & ~isRefRow, 1);
    satFrac = nSat ./ max(nFin, 1);
    satSel = satFrac >= 0.9 & nFin > 0;
    if any(satSel)
        fprintf(['fingerprintHeatmap: %d of %d contexts are >= 90%% saturated at |z| = %g ' ...
            '(possible degenerate reference scale; distinguish from genuine effects):\n'], ...
            nnz(satSel), nContexts, zClim);
        satIdx = find(satSel);
        for i = 1:numel(satIdx)
            c = satIdx(i);
            fprintf('  %s | %s | %s (%d/%d rows at |z| >= %g)\n', ...
                string(colMeta.Tier(c)), string(colMeta.Stimulus(c)), ...
                string(colMeta.Metric(c)), nSat(c), nFin(c), zClim);
        end
        notes(end+1, 1) = sprintf('%d saturated context(s) at |z| = %g - see console', nnz(satSel), zClim); %#ok<AGROW>
    end
    if ~isempty(notes)
        subtitle(ax, strjoin(notes, ' | '), 'FontSize', 9, 'Interpreter', 'none');
    end
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


function labels = abbreviatedLabels(metrics, patterns, families)
    % Short per-column tick labels: strip the period phrase ("During ...",
    % "... Bouts") and the trailing units paren, then remove the family
    % include pattern / family label when contained. Labels that reduce to
    % the family itself are emptied (the family annotation row covers them).
    n = numel(metrics);
    labels = strings(n, 1);
    for i = 1:n
        lbl = strtrim(string(metrics(i)));
        lbl = strtrim(regexprep(lbl, '\s*\([^)]*\)\s*$', ''));
        lbl = strtrim(regexprep(lbl, '\s+During\s+.*$', ''));
        lbl = strtrim(regexprep(lbl, '\s+Across\s+Bouts\s*$', ''));

        pat = string(patterns(i));
        if strlength(pat) > 0
            lbl = strtrim(regexprep(lbl, regexEscape(pat), '', 'ignorecase'));
        end
        famLbl = string(families(i));
        if strlength(famLbl) > 0
            lbl = strtrim(regexprep(lbl, regexEscape(famLbl), '', 'ignorecase'));
        end
        if strlength(lbl) == 0 || strcmpi(lbl, famLbl)
            lbl = "";
        end
        labels(i) = lbl;
    end
end


function units = uniqueUnits(metrics)
    % Comma-joined distinct trailing "(units)" phrases of a family block.
    units = strings(0, 1);
    for i = 1:numel(metrics)
        tok = regexp(string(metrics(i)), '\(([^)]*)\)\s*$', 'tokens', 'once');
        if ~isempty(tok)
            units(end+1, 1) = string(tok{1}); %#ok<AGROW>
        end
    end
    units = unique(units, 'stable');
    units = strjoin(units, ', ');
end


function out = regexEscape(s)
    out = regexprep(string(s), '([$\.*+?^\(\)\[\]\{\}\|\\])', '\\$1');
end
