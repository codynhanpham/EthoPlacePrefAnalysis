function [fig, data] = fingerprintRadar(fp, kvargs)
    %%FINGERPRINTRADAR Per-strain genotype/sex effect radar charts of fingerprint z.
    %
    %   fig = graphics.fingerprintRadar(fp)
    %   [fig, data] = graphics.fingerprintRadar(fp, ...)
    %
    %   One radar per strain (all strains are rendered; no cohort cap). Spokes
    %   are metric families (cohort.internal.metricFamily over the
    %   whitelisted contexts) in canonical order, or with SpokeLevel =
    %   "context" every metric context gets its own spoke (high-resolution
    %   variant; see graphics.fingerprintRadarEverything, which forces this
    %   together with the minimal look). Lines per strain, all in
    %   robust-z units of the strain's same-sex WT reference:
    %     - Genotype effect (solid): one line per non-reference genotype
    %       (HOM #7391a7, HET #c6ac76, others gray), the sex-averaged cohort
    %       z vs WT, i.e. mean over sexes of (median_geno,sex - median_WT,sex)
    %       / robust scale of the same-sex WT.
    %     - Sex effect (solid #bb8875): WT Female minus Male median
    %       difference, scaled by the mean of the two sex-specific WT robust
    %       scales (baseline sexual dimorphism).
    %     - Genotype x sex interaction (dashed): per genotype, the
    %       difference-in-differences z_geno,F - z_geno,M, drawn as a closed
    %       dashed curve tinted toward that genotype's color (purple mixed
    %       with the genotype line color); markers highlight the family
    %       spokes where |interaction| >= InteractionThreshold, so
    %       sex-independent effects stay visually quiet.
    %
    %   Solid lines are smoothed with a periodic cubic spline (Curve Fitting
    %   Toolbox) or periodic-augmented PCHIP fallback, for aesthetics only;
    %   raw markers stay at the spoke positions (families without data are
    %   drawn at the 0 ring). Values are clamped to +/-ClampZ for display.
    %   Radial tick text is suppressed (it collided with the top spoke
    %   label); the dark solid ring marks 0, the reference level, and
    %   the outer ring is the display clamp. The second output returns the
    %   unclamped line values as a long table (Strain, Family, Effect,
    %   Kind, Unit, Value).
    %
    %   Named options:
    %       ClampZ                 display clamp in robust-z units, default 3
    %                              (used when RadialUnit = "z")
    %       ClampDelta             display clamp in Cliff's-delta units,
    %                              default 1 (used when RadialUnit =
    %                              "cliffsDelta")
    %       RadialUnit             "z" (default) or "cliffsDelta". In delta
    %                              mode the radial values are Cliff's delta
    %                              (rank-based dominance vs the same-sex WT,
    %                              bounded +/-1) instead of robust z: genotype
    %                              and interaction effects come from
    %                              StatsTable, the sex effect is computed
    %                              from PerAnimalLong (WT Female vs Male
    %                              animals). Falls back to "z" with a
    %                              warning when StatsTable is empty.
    %       StatsTable             cohort.fingerprintStats output (required
    %                              for RadialUnit = "cliffsDelta")
    %       PerAnimalLong          long per-animal table (required for the
    %                              sex-effect line in delta mode)
    %       InteractionThreshold   min |DiD| to show interaction, default NaN
    %                              = auto: 1 in z units, 0.25 in delta units
    %       Smooth                 spline smoothing on/off, default true
    %       PointsPerSpoke         curve samples per spoke, default 24
    %       ShowMarkers            draw spoke markers, default false
    %       ShowGrid               rings and spokes grid, default true; when
    %                              false the grid, spoke labels, and tick
    %                              text are all hidden and only a black +
    %                              at the center marks the plot origin
    %       SpokeLevel             "family" (default) groups contexts by
    %                              metric family; "context" gives every
    %                              metric context its own spoke (high
    %                              resolution; forces the minimal no-grid,
    %                              no-marker, no-label look)
    %
    %   See also: cohort.fingerprint, cohort.internal.metricFamily, spider_plot

    arguments
        fp struct
        kvargs.ClampZ (1,1) double {mustBePositive, mustBeFinite} = 3
        kvargs.ClampDelta (1,1) double {mustBePositive, mustBeFinite} = 1
        kvargs.RadialUnit (1,1) string = "z"
        kvargs.StatsTable table = table()
        kvargs.PerAnimalLong table = table()
        kvargs.InteractionThreshold (1,1) double = NaN % NaN = auto per unit
        kvargs.Smooth (1,1) logical = true
        kvargs.PointsPerSpoke (1,1) double {mustBePositive, mustBeInteger} = 24
        kvargs.ShowMarkers (1,1) logical = false
        kvargs.ShowGrid (1,1) logical = true
        kvargs.SpokeLevel (1,1) string = "family"
    end

    if ~ismember(kvargs.SpokeLevel, ["family", "context"])
        error('graphics:fingerprintRadar:InvalidSpokeLevel', ...
            'SpokeLevel must be "family" or "context", got %s', string(kvargs.SpokeLevel));
    end
    contextLevel = kvargs.SpokeLevel == "context";

    if ~ismember(kvargs.RadialUnit, ["z", "cliffsDelta"])
        error('graphics:fingerprintRadar:InvalidRadialUnit', ...
            'RadialUnit must be "z" or "cliffsDelta", got %s', string(kvargs.RadialUnit));
    end

    %% Resolve radial unit, display clamp and interaction threshold
    useDelta = kvargs.RadialUnit == "cliffsDelta";
    if useDelta && height(kvargs.StatsTable) == 0
        warning('graphics:fingerprintRadar:MissingStatsTable', ...
            ['RadialUnit = "cliffsDelta" requires StatsTable; falling back to ' ...
            'robust-z effects. Pass the cohort.fingerprintStats output as StatsTable.']);
        useDelta = false;
    end
    if useDelta
        clamp = kvargs.ClampDelta;
    else
        clamp = kvargs.ClampZ;
    end
    intThreshold = kvargs.InteractionThreshold;
    if isnan(intThreshold)
        if useDelta
            intThreshold = 0.25;
        else
            intThreshold = 1;
        end
    end
    if intThreshold < 0
        error('graphics:fingerprintRadar:InvalidInteractionThreshold', ...
            'InteractionThreshold must be NaN (auto) or non-negative, got %g', intThreshold);
    end
    unitUsed = "z";
    if useDelta
        unitUsed = "cliffsDelta";
    end

    % Context-level spokes are a pure visualization mode: always minimal.
    showGrid = kvargs.ShowGrid;
    showMarkers = kvargs.ShowMarkers;
    if contextLevel
        showGrid = false;
        showMarkers = false;
    end

    zMatrix = fp.zMatrix;
    rowLabels = fp.rowLabels;
    colLabels = fp.colLabels;

    data = emptyData();

    if isempty(zMatrix) || isempty(colLabels)
        fig = [];
        return;
    end

    %% Spoke groups in canonical order: metric families, or every metric
    %  context individually (SpokeLevel = "context", high-resolution variant).
    colOrder = graphics.fingerprintContextOrder(fp);
    nCtx = numel(colOrder);
    if contextLevel
        ctxGroupId = compose("ctx%05d", 1:nCtx); % per-context group id
        groupId = ctxGroupId;                    % one group per context
        groupLabel = string(colLabels.Metric(colOrder));
    else
        ctxGroupId = string(cohort.internal.metricFamily(string(colLabels.Metric(colOrder))));
        groupId = unique(ctxGroupId, 'stable');
        groupLabel = groupId;
    end
    nFam = numel(groupId);
    famMask = false(nFam, nCtx);
    for f = 1:nFam
        famMask(f, :) = ctxGroupId == groupId(f);
    end

    %% zMatrix row lookup by strain|geno|sex
    rowKey = string(rowLabels.Strain) + "|" + string(rowLabels.Genotype) + "|" + string(rowLabels.Sex);
    zRowOf = dictionary(rowKey, (1:height(rowLabels))');

    %% Reference genotype per strain; WT median/MAD lookup from cohortTable
    refGenoOf = dictionary(string, string);
    if isfield(fp, 'referenceMap') && ~isempty(fp.referenceMap)
        refGenoOf = dictionary(string(fp.referenceMap.Strain), lower(strtrim(string(fp.referenceMap.ReferenceGenotype))));
    end

    cohortTable = fp.cohortTable;
    ctKey = string(cohortTable.Strain) + "|" + lower(strtrim(string(cohortTable.Genotype))) + "|" + ...
        string(cohortTable.Sex) + "|" + string(cohortTable.Tier) + "|" + string(cohortTable.Protocol) + ...
        "|" + string(cohortTable.Stimulus) + "|" + string(cohortTable.Metric);
    ctRowOf = dictionary(ctKey, (1:height(cohortTable))');

    ctxKeyByCol = strings(1, numel(colOrder));
    for c = 1:numel(colOrder)
        ci = colOrder(c);
        ctxKeyByCol(c) = string(colLabels.Tier(ci)) + "|" + string(colLabels.Protocol(ci)) + ...
            "|" + string(colLabels.Stimulus(ci)) + "|" + string(colLabels.Metric(ci));
    end

    %% Cliff's-delta lookups (RadialUnit = "cliffsDelta")
    deltaRowOf = dictionary(string, 0);
    palKey = strings(0, 1);
    palStrain = strings(0, 1);
    palGeno = strings(0, 1);
    palSex = strings(0, 1);
    palValue = zeros(0, 1);
    if useDelta
        stTab = kvargs.StatsTable;
        stKey = string(stTab.Strain) + "|" + lower(strtrim(string(stTab.Genotype))) + "|" + ...
            string(stTab.Sex) + "|" + string(stTab.Tier) + "|" + string(stTab.Protocol) + ...
            "|" + string(stTab.Stimulus) + "|" + string(stTab.Metric);
        deltaRowOf = dictionary(stKey, double(stTab.CliffDelta));

        % Per-animal prefilters for the sex-effect delta (WT Female vs Male).
        pal = kvargs.PerAnimalLong;
        palKey = string(pal.Tier) + "|" + string(pal.Protocol) + "|" + ...
            string(pal.Stimulus) + "|" + string(pal.Metric);
        palStrain = string(pal.Gene);
        palGeno = lower(strtrim(string(pal.('Genotype$'))));
        palSex = string(pal.('Sex$'));
        palValue = double(pal.Value);
    end

    strains = unique(string(rowLabels.Strain));
    nStrains = numel(strains);

    % Sex labels as they actually appear in the data ("F"/"Female",
    % "M"/"Male", ...); hardcoded literals would miss every lookup.
    [sexLabelF, sexLabelM] = resolveSexLabels(string(rowLabels.Sex));

    %% Colors
    sexColor = [187, 136, 117] / 255;               % F/M     #bb8875
    interactionColor = [150, 119, 175] / 255;       % DiD base #9677af
    otherColors = [0.55, 0.55, 0.55; 0.35, 0.35, 0.35; 0.25, 0.25, 0.25];
    interactionMarkers = {'o', 's', '^', 'v'};

    %% Compute the line set per strain
    linesByStrain = cell(nStrains, 1);
    for s = 1:nStrains
        strainI = strains(s);
        refGenoN = "wt";
        if isKey(refGenoOf, strainI)
            refGenoN = refGenoOf(strainI);
        end

        genoList = unique(string(rowLabels.Genotype(rowLabels.Strain == strainI)));
        genoList = genoList(lower(strtrim(genoList)) ~= refGenoN);
        % HOM first, then HET, then any other non-reference genotypes.
        isHom = lower(genoList) == "hom";
        isHet = lower(genoList) == "het";
        orderKey = isHom * 0 + isHet * 1 + (~isHom & ~isHet) * 2;
        [~, genoRank] = sort(orderKey);
        genoList = genoList(genoRank);

        lines = struct('Name', {}, 'Kind', {}, 'Color', {}, 'Marker', {}, 'Values', {}, 'ShowWhere', {});
        for g = 1:numel(genoList)
            genoI = genoList(g);
            ctxF = nan(1, numel(colOrder));
            ctxM = nan(1, numel(colOrder));
            if useDelta
                % Cliff's delta vs same-sex WT, one statsTable row per context.
                if strlength(sexLabelF) > 0
                    for c = 1:numel(colOrder)
                        k = strainI + "|" + lower(genoI) + "|" + sexLabelF + "|" + ctxKeyByCol(c);
                        if isKey(deltaRowOf, k)
                            ctxF(c) = deltaRowOf(k);
                        end
                    end
                end
                if strlength(sexLabelM) > 0
                    for c = 1:numel(colOrder)
                        k = strainI + "|" + lower(genoI) + "|" + sexLabelM + "|" + ctxKeyByCol(c);
                        if isKey(deltaRowOf, k)
                            ctxM(c) = deltaRowOf(k);
                        end
                    end
                end
            else
                if strlength(sexLabelF) > 0 && isKey(zRowOf, strainI + "|" + genoI + "|" + sexLabelF)
                    ctxF = zMatrix(zRowOf(strainI + "|" + genoI + "|" + sexLabelF), :);
                end
                if strlength(sexLabelM) > 0 && isKey(zRowOf, strainI + "|" + genoI + "|" + sexLabelM)
                    ctxM = zMatrix(zRowOf(strainI + "|" + genoI + "|" + sexLabelM), :);
                end
            end

            genoVals = familyMean(mean([ctxF; ctxM], 1, 'omitnan'), famMask); % sex-averaged genotype effect
            intVals = familyMean(ctxF - ctxM, famMask);                       % difference-in-differences

            gColor = otherColors(mod(g - 1, size(otherColors, 1)) + 1, :);
            genoBase = genoBaseColor(genoI);
            if ~isempty(genoBase)
                gColor = genoBase;
            end
            gMarker = interactionMarkers{mod(g - 1, numel(interactionMarkers)) + 1};

            lines(end+1) = struct('Name', genoI + "/" + upper(refGenoN), 'Kind', "genotype", ...
                'Color', gColor, 'Marker', 'o', 'Values', genoVals, 'ShowWhere', true(1, nFam)); %#ok<AGROW>
            lines(end+1) = struct('Name', genoI + " x sex", 'Kind', "interaction", ...
                'Color', 0.5 * interactionColor + 0.5 * gColor, 'Marker', gMarker, ...
                'Values', intVals, ...
                'ShowWhere', abs(intVals) >= intThreshold); %#ok<AGROW>
        end

        % Sex effect: reference-genotype Female vs Male. In z mode a median
        % difference scaled by the mean WT robust scale (cohortTable); in
        % delta mode an animal-level Cliff's delta (PerAnimalLong).
        sexCtx = nan(1, numel(colOrder));
        if useDelta
            if strlength(sexLabelF) > 0 && strlength(sexLabelM) > 0
                selF = palStrain == strainI & palGeno == refGenoN & palSex == sexLabelF;
                selM = palStrain == strainI & palGeno == refGenoN & palSex == sexLabelM;
                for c = 1:numel(colOrder)
                    vF = palValue(palKey == ctxKeyByCol(c) & selF);
                    vM = palValue(palKey == ctxKeyByCol(c) & selM);
                    vF = vF(isfinite(vF));
                    vM = vM(isfinite(vM));
                    if ~isempty(vF) && ~isempty(vM)
                        sexCtx(c) = cohort.internal.cliffsDelta(vF, vM);
                    end
                end
            end
        elseif strlength(sexLabelF) > 0 && strlength(sexLabelM) > 0
            for c = 1:numel(colOrder)
                keyF = strainI + "|" + refGenoN + "|" + sexLabelF + "|" + ctxKeyByCol(c);
                keyM = strainI + "|" + refGenoN + "|" + sexLabelM + "|" + ctxKeyByCol(c);
                if isKey(ctRowOf, keyF) && isKey(ctRowOf, keyM)
                    rowF = ctRowOf(keyF);
                    rowM = ctRowOf(keyM);
                    scaleF = 1.4826 * double(cohortTable.MAD(rowF));
                    scaleM = 1.4826 * double(cohortTable.MAD(rowM));
                    scale = mean([scaleF, scaleM]);
                    medF = double(cohortTable.Median(rowF));
                    medM = double(cohortTable.Median(rowM));
                    if isfinite(scale) && scale > 0 && isfinite(medF) && isfinite(medM)
                        sexCtx(c) = (medF - medM) / scale;
                    end
                end
            end
        end
        lines(end+1) = struct('Name', upper(refGenoN) + " " + sexLabelF + "/" + sexLabelM, 'Kind', "sex", ...
            'Color', sexColor, 'Marker', 'd', 'Values', familyMean(sexCtx, famMask), ...
            'ShowWhere', true(1, nFam)); %#ok<AGROW>

        linesByStrain{s} = lines;
    end

    %% Render: one tile per strain
    nColsFig = ceil(sqrt(nStrains * 1.4));
    nRowsFig = ceil(nStrains / nColsFig);
    fig = figure('Name', 'Cohort Fingerprint Radar (genotype / sex effects)', 'Color', 'w', ...
        'Position', [140, 140, min(2100, 460 * nColsFig), min(1300, 440 * nRowsFig)]);
    tl = tiledlayout(fig, nRowsFig, nColsFig, 'TileSpacing', 'loose', 'Padding', 'loose'); %#ok<NASGU> % legend attaches to this layout; loose spacing keeps adjacent radars' spoke labels apart

    proxyHandles = gobjects(0);
    proxyLabels = {};
    proxySeen = dictionary(string, true);
    proxySource = zeros(0, 2); % [strainIdx, lineIdx] per distinct proxy
    axFirst = [];
    thetaSpokes = mod(pi/2 - (0:nFam-1) * 2*pi/nFam, 2*pi);

    for s = 1:nStrains
        strainI = strains(s);
        refGenoN = "wt";
        if isKey(refGenoOf, strainI)
            refGenoN = refGenoOf(strainI);
        end
        lines = linesByStrain{s};

        ax = nexttile;
        if isempty(axFirst)
            axFirst = ax;
        end
        hold(ax, 'on');

        % Drive spider_plot for webs, spoke labels and the zero ring; hide
        % its own data polygon (we overdraw smooth curves in its mapping).
        plotValues = zeros(numel(lines), nFam);
        for l = 1:numel(lines)
            v = lines(l).Values;
            v(~isfinite(v)) = 0;
            plotValues(l, :) = min(max(v, -clamp), clamp);
        end
        if showGrid
            axesLabels = cellstr(groupId(:));
        else
            axesLabels = repmat({""}, nFam, 1); % minimal look: no spoke labels
        end
        spider_plot(plotValues, ...
            'AxesHandle', ax, ...
            'BackgroundColor', 'none', ...
            'PlotVisible', 'off', ...
            'AxesLabels', axesLabels, ...
            'AxesLimits', repmat([-clamp; clamp], 1, nFam), ...
            'AxesInterval', 1, ...
            'AxesPrecision', 1, ...
            'AxesDisplay', 'none', ...  % tick text collided with the top spoke label
            'AxesWeb', onOff(showGrid), ...
            'AxesRadial', onOff(showGrid), ...
            'AxesWebType', 'web', ...
            'LabelFontSize', 8, ...
            'AxesFontSize', 7, ...
            'AxesLabelsEdge', 'none', ...
            'AxesLabelsRotate', 'off', ...
            'AxesZoom', 0.62); % shrink the circle within its tile so spoke labels stay clear of neighbors

        if showGrid
            % Reference-level ring at z = 0 (spider_plot's AxesZero requires
            % its tick-label mode, so draw it in the same spoke mapping).
            thetaRing = linspace(0, 2*pi, 181);
            [xz, yz] = pol2cart(thetaRing, scaleRho(0, clamp) * ones(size(thetaRing)));
            plot(ax, xz, yz, '-', 'Color', [0.25, 0.25, 0.25], 'LineWidth', 1.1, ...
                'HandleVisibility', 'off');
        end

        for l = 1:numel(lines)
            v = lines(l).Values;
            show = lines(l).ShowWhere & isfinite(v);
            if ~any(show)
                continue;
            end
            vDisp = min(max(v, -clamp), clamp);

            % Closed dashed curve for the interaction too; markers flag the
            % spokes above the threshold.
            rho = scaleRho(vDisp, clamp);
            rho(~isfinite(v)) = scaleRho(0, clamp); % families without data at the 0 ring
            [xFine, yFine] = smoothClosedCurve(rho, kvargs.PointsPerSpoke, kvargs.Smooth);
            if lines(l).Kind == "interaction"
                plot(ax, xFine, yFine, '--', 'Color', lines(l).Color, ...
                    'LineWidth', 1.2, 'HandleVisibility', 'off');
            else
                plot(ax, xFine, yFine, '-', 'Color', lines(l).Color, ...
                    'LineWidth', 1.5, 'HandleVisibility', 'off');
            end

            if showMarkers
                [xMk, yMk] = pol2cart(thetaSpokes(show), scaleRho(vDisp(show), clamp));
                scatter(ax, xMk, yMk, 28, lines(l).Color, lines(l).Marker, 'filled', ...
                    'MarkerEdgeColor', 'w', 'HandleVisibility', 'off');
            end

            proxyKey = lines(l).Kind + "|" + lines(l).Marker + "|" + ...
                sprintf('%.3f%.3f%.3f', lines(l).Color);
            if ~isKey(proxySeen, proxyKey)
                proxySeen(proxyKey) = true;
                proxySource(end+1, :) = [s, l]; %#ok<AGROW>
            end
        end

        if ~showGrid
            % Grid-less look: only a black + marks the plot center.
            arm = 0.06;
            plot(ax, [-arm, arm], [0, 0], '-', 'Color', 'k', 'LineWidth', 1.2, ...
                'HandleVisibility', 'off');
            plot(ax, [0, 0], [-arm, arm], '-', 'Color', 'k', 'LineWidth', 1.2, ...
                'HandleVisibility', 'off');
        end

        title(ax, char(strainI + "  (ref " + upper(refGenoN) + ")"), 'FontSize', 9, 'Interpreter', 'none');
    end

    % Legend proxies in reading order: genotype effects, sex effect, then
    % interactions.
    proxyOrder = ["genotype", "sex", "interaction"];
    proxyHandles = gobjects(0);
    proxyLabels = {};
    for k = 1:numel(proxyOrder)
        for m = 1:size(proxySource, 1)
            lines = linesByStrain{proxySource(m, 1)};
            l = proxySource(m, 2);
            if lines(l).Kind ~= proxyOrder(k)
                continue;
            end
            if lines(l).Kind == "interaction"
                hProxy = plot(axFirst, NaN, NaN, '--', 'Color', lines(l).Color, 'LineWidth', 1.2);
            else
                hProxy = plot(axFirst, NaN, NaN, '-', 'Color', lines(l).Color, 'LineWidth', 1.5);
            end
            hProxy.Marker = lines(l).Marker;
            if ~showMarkers
                hProxy.Marker = 'none';
            end
            hProxy.MarkerFaceColor = lines(l).Color;
            hProxy.MarkerSize = 6;
            proxyHandles(end+1) = hProxy; %#ok<AGROW>
            proxyLabels{end+1} = char(lines(l).Name); %#ok<AGROW>
        end
    end

    if ~isempty(proxyHandles)
        lgd = legend(proxyHandles, proxyLabels, 'FontSize', 8, 'NumColumns', min(4, numel(proxyHandles)));
        lgd.Layout.Tile = 'south';
    end

    %% Long-format output of unclamped values
    parts = cell(nStrains, 1);
    for s = 1:nStrains
        parts{s} = emptyData();
        lines = linesByStrain{s};
        for l = 1:numel(lines)
            n = numel(lines(l).Values);
            parts{s} = [parts{s}; table(repmat(strains(s), n, 1), groupLabel(:), ...
                repmat(lines(l).Name, n, 1), repmat(lines(l).Kind, n, 1), ...
                repmat(unitUsed, n, 1), lines(l).Values(:), ...
                'VariableNames', {'Strain', 'Family', 'Effect', 'Kind', 'Unit', 'Value'})]; %#ok<AGROW>
        end
    end
    data = vertcat(parts{:});
end


function tOut = emptyData()
    tOut = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
        'VariableNames', {'Strain', 'Family', 'Effect', 'Kind', 'Unit', 'Value'});
end


function c = genoBaseColor(genoName)
    % Genotype line colors: HOM #7391a7, HET #c6ac76; empty for others
    % (they fall back to the gray sequence).
    switch lower(strtrim(string(genoName)))
        case "hom"
            c = [113, 145, 167] / 255;
        case "het"
            c = [198, 172, 118] / 255;
        otherwise
            c = [];
    end
end


function [fLabel, mLabel] = resolveSexLabels(sexValues)
    % Female/male labels exactly as they appear in the data ("F"/"Female",
    % "M"/"Male", ...). Female patterns are tested first: "female" contains
    % "male" as a substring. Unrecognized labels are ignored.
    u = unique(string(sexValues));
    fLabel = "";
    mLabel = "";
    for i = 1:numel(u)
        s = lower(strtrim(u(i)));
        if strlength(s) == 0
            continue;
        end
        isF = s == "f" || startsWith(s, "f") || contains(s, "female");
        isM = ~isF && (s == "m" || startsWith(s, "m") || contains(s, "male"));
        if isF && strlength(fLabel) == 0
            fLabel = u(i);
        elseif isM && strlength(mLabel) == 0
            mLabel = u(i);
        end
    end
end


function vals = familyMean(ctxVals, famMask)
    % Mean of per-context values within each family (omitnan; families with
    % no finite contexts give NaN).
    nFam = size(famMask, 1);
    vals = nan(1, nFam);
    for f = 1:nFam
        vals(f) = mean(ctxVals(famMask(f, :)), 'omitnan');
    end
end


function rho = scaleRho(r, clampZ)
    % Replicate spider_plot's spoke scaling for uniform AxesLimits
    % [-clampZ, clampZ] with AxesInterval 1 and default AxesOffset 1.
    rhoOffset = 1/2;
    rho = ((r + clampZ) / (2*clampZ)) * (1 - rhoOffset) + rhoOffset;
end


function s = onOff(tf)
    if tf
        s = 'on';
    else
        s = 'off';
    end
end


function [xFine, yFine] = smoothClosedCurve(rho, pointsPerSpoke, doSmooth)
    % Closed (periodic) smooth curve through the spoke rho values. Periodic
    % cubic spline (csape) when the Curve Fitting Toolbox is available,
    % periodic-augmented PCHIP otherwise. Spokes are laid out clockwise from
    % the top (spider_plot default); smoothing operates on the unwrapped arc
    % position so the curve closes smoothly.
    n = numel(rho);
    uSpoke = (0:n-1) * 2*pi/n;

    if n < 3 || ~doSmooth
        uFine = [uSpoke, 2*pi];
        rhoFine = [rho, rho(1)];
    else
        uFine = linspace(0, 2*pi, n * pointsPerSpoke);
        % csape's 'periodic' treats the first/last knot as the period
        % boundary, so append the closing knot (same value as spoke 1) to
        % interpolate the last sector correctly.
        uAug = [uSpoke, 2*pi];
        vAug = [rho, rho(1)];
        if exist('csape', 'file')
            pp = csape(uAug, vAug, 'periodic');
            rhoFine = fnval(pp, uFine);
        else
            rhoFine = interp1(uAug, vAug, uFine, 'pchip');
        end
        rhoFine = min(max(rhoFine, 0), 1);
    end

    thetaFine = mod(pi/2 - uFine, 2*pi);
    [xFine, yFine] = pol2cart(thetaFine, rhoFine);
end
