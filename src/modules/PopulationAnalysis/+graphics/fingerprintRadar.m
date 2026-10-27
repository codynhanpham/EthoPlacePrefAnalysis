function fig = fingerprintRadar(fp, kvargs)
    %%FINGERPRINTRADAR Radar charts of cohort fingerprint z profiles.
    %
    %   fig = graphics.fingerprintRadar(fp)
    %
    %   One polar axes per eligible sex-specific cohort (up to MaxCohorts, in
    %   strain/genotype/sex order). Axes are the whitelisted metric contexts in
    %   tier order with a fixed rotation (exploration first, then baseline,
    %   then stimulus tiers); radial value is the cohort robust z clamped to
    %   +/-ClampZ for display. Axis order strongly affects the visual
    %   impression; interpret shapes comparatively, not absolutely.
    %
    %   See also: cohort.fingerprint

    arguments
        fp struct
        kvargs.MaxCohorts (1,1) double {mustBePositive, mustBeInteger} = 12
        kvargs.ClampZ (1,1) double {mustBePositive, mustBeFinite} = 3
    end

    zMatrix = fp.zMatrix;
    rowLabels = fp.rowLabels;
    colLabels = fp.colLabels;

    if isempty(zMatrix)
        fig = [];
        return;
    end

    nCohortsAll = height(rowLabels);
    [~, rowOrder] = sortrows([string(rowLabels.Strain), string(rowLabels.Genotype), string(rowLabels.Sex)]);
    nCohorts = min(kvargs.MaxCohorts, nCohortsAll);

    colOrder = graphics.fingerprintContextOrder(fp);

    Z = zMatrix(rowOrder(1:nCohorts), colOrder);
    Z = min(max(Z, -kvargs.ClampZ), kvargs.ClampZ);
    rowMeta = rowLabels(rowOrder(1:nCohorts), :);
    colMeta = colLabels(colOrder, :);
    nContexts = height(colMeta);

    nCols = ceil(sqrt(nCohorts * 1.4));
    nRows = ceil(nCohorts / nCols);

    fig = figure('Name', 'Cohort Fingerprint Radar', 'Color', 'w', ...
        'Position', [140, 140, min(1800, 360 * nCols), min(1100, 380 * nRows)]);
    tiledlayout(fig, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');

    theta = linspace(0, 2*pi, nContexts + 1);

    for r = 1:nCohorts
        nexttile;
        vals = [Z(r, :), Z(r, 1)];
        polarplot(theta, vals, '-', 'LineWidth', 1.4, 'Color', lines(1));

        pax = gca;
        thetadeg = rad2deg(theta);
        thetadeg(thetadeg == 360) = 0;
        pax.ThetaTick = thetadeg(1:end-1);
        pax.ThetaTickLabel = shortContextLabels(colMeta);
        pax.RLim = [-kvargs.ClampZ, kvargs.ClampZ];
        pax.RTick = [-kvargs.ClampZ, 0, kvargs.ClampZ];
        pax.FontSize = 6;

        title(pax, char(string(rowMeta.Strain(r)) + " | " + string(rowMeta.Genotype(r)) + " | " + string(rowMeta.Sex(r))), 'FontSize', 8);
    end
end


function labels = shortContextLabels(colMeta)
    n = height(colMeta);
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = char(string(colMeta.Tier(i)) + ":" + string(colMeta.Metric(i)));
    end
end
