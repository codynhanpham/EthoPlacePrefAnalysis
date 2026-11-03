function fig = fingerprintDotPlots(fp, kvargs)
    %%FINGERPRINTDOTPLOTS Per-metric dot panels of per-animal fingerprint z values.
    %
    %   fig = graphics.fingerprintDotPlots(fp)
    %
    %   One panel per metric context (up to MaxPanels, in
    %   graphics.fingerprintContextOrder): per-animal z values as jittered
    %   points (color = genotype, marker = sex) grouped by strain, with the
    %   matching sex-specific cohort median z and bootstrap 95% CI in the
    %   same z units (cohortTable Z/ZCiLo/ZCiHi) drawn next to each sex's
    %   point cloud. Only sex-specific cohorts are shown.
    %
    %   See also: cohort.fingerprint, graphics.fingerprintContextOrder

    arguments
        fp struct
        kvargs.MaxPanels (1,1) double {mustBePositive, mustBeInteger} = 24
    end

    perAnimalZ = fp.perAnimalZ;
    cohortTable = fp.cohortTable;
    colLabels = fp.colLabels;

    metaCols = {'SubjectKey', 'Gene', 'Genotype$', 'Sex$', 'Litter', 'Cage #', 'Age'};
    zCols = setdiff(perAnimalZ.Properties.VariableNames, metaCols, 'stable');
    if isempty(zCols) || isempty(cohortTable)
        fig = [];
        return;
    end

    ctxOrder = graphics.fingerprintContextOrder(fp);
    zColsOrdered = zCols(ctxOrder);
    nPanels = min(kvargs.MaxPanels, numel(zColsOrdered));

    tilesX = ceil(sqrt(nPanels));
    tilesY = ceil(nPanels / tilesX);
    fig = figure('Name', 'Fingerprint Dot Panels', 'Color', 'w', ...
        'Position', [120, 120, min(1600, 420 * tilesX), min(1000, 320 * tilesY)]);
    tiledlayout(fig, tilesY, tilesX, 'TileSpacing', 'compact', 'Padding', 'compact');

    genotype = categorical(string(perAnimalZ.('Genotype$')));
    sex = categorical(string(perAnimalZ.('Sex$')));
    strain = string(perAnimalZ.Gene);
    genotypes = categories(genotype);
    sexes = categories(sex);
    cmap = lines(numel(genotypes));
    sexMarkers = containers.Map( ...
        {'F', 'M', 'Female', 'Male', 'female', 'male'}, ...
        {'o', 's', 'o', 's', 'o', 's'});
    strainsList = unique(strain);

    cohortSexSpecific = cohortTable(~cohortTable.PooledSex, :);

    for p = 1:nPanels
        zCol = zColsOrdered{p};
        ctxIdx = find(strcmp(zCols, zCol), 1, 'first');
        tierI = string(colLabels.Tier(ctxIdx));
        protocolI = string(colLabels.Protocol(ctxIdx));
        stimulusI = string(colLabels.Stimulus(ctxIdx));
        metricI = string(colLabels.Metric(ctxIdx));

        vals = double(perAnimalZ.(zCol));
        valid = isfinite(vals);

        ax = nexttile;
        hold(ax, 'on');

        tickCenters = [];
        tickLabels = strings(0, 1);
        offset = 0;
        for s = 1:numel(strainsList)
            for gi = 1:numel(genotypes)
                groupSel = valid & strain == strainsList(s) & genotype == genotypes{gi};
                present = false(1, numel(sexes));
                for si = 1:numel(sexes)
                    present(si) = any(groupSel & sex == sexes{si});
                end
                sexesHere = sexes(present);
                if isempty(sexesHere)
                    continue;
                end

                nSexes = numel(sexesHere);
                center = offset + 1;
                for si = 1:nSexes
                    sx = sexesHere{si};
                    sel = groupSel & sex == sx;
                    sexCenter = center + (si - (nSexes + 1) / 2) * 0.4;

                    marker = 'o';
                    if isKey(sexMarkers, char(sx))
                        marker = sexMarkers(char(sx));
                    end
                    jitterPos = sexCenter + (rand(nnz(sel), 1) - 0.5) * 0.4;
                    scatter(ax, jitterPos, vals(sel), 24, cmap(gi, :), marker, ...
                        'filled', 'MarkerFaceAlpha', 0.7, 'HandleVisibility', 'off');

                    % Matching sex-specific cohort median z + bootstrap CI in
                    % z units (ZCiLo/ZCiHi), matching the per-animal z dots.
                    rowSel = string(cohortSexSpecific.Strain) == strainsList(s) & ...
                        string(cohortSexSpecific.Genotype) == genotypes{gi} & ...
                        string(cohortSexSpecific.Sex) == string(sx) & ...
                        string(cohortSexSpecific.Tier) == tierI & ...
                        string(cohortSexSpecific.Protocol) == protocolI & ...
                        string(cohortSexSpecific.Stimulus) == stimulusI & ...
                        string(cohortSexSpecific.Metric) == metricI;
                    idx = find(rowSel, 1, 'first');
                    if ~isempty(idx)
                        zVal = cohortSexSpecific.Z(idx);
                        zCiLo = cohortSexSpecific.ZCiLo(idx);
                        zCiHi = cohortSexSpecific.ZCiHi(idx);
                        if all(isfinite([zVal, zCiLo, zCiHi]))
                            errorbar(ax, sexCenter + 0.5, zVal, ...
                                zVal - zCiLo, zCiHi - zVal, ...
                                'k-', 'LineWidth', 1, 'HandleVisibility', 'off');
                            plot(ax, sexCenter + 0.5, zVal, 'k_', ...
                                'LineWidth', 2, 'HandleVisibility', 'off');
                        end
                    end
                end

                tickCenters(end+1, 1) = center; %#ok<AGROW>
                tickLabels(end+1, 1) = strainsList(s) + newline + genotypes{gi}; %#ok<AGROW>
                offset = offset + 2;
            end
        end

        set(ax, 'XTick', tickCenters, 'XTickLabel', tickLabels, 'FontSize', 7);
        xtickangle(ax, 30);
        yline(ax, 0, '--', 'Color', [0.6, 0.6, 0.6], 'HandleVisibility', 'off');
        ylabel(ax, 'z');
        title(ax, sprintf('%s | P%s | %s', tierI, protocolI, metricI), 'FontSize', 7, 'Interpreter', 'none');
        grid(ax, 'on');
    end
end
