function [pcaStruct, fig] = fingerprintPca(fp)
    %%FINGERPRINTPCA PCA diagnostic of per-animal fingerprint z profiles.
    %
    %   [pcaStruct, fig] = graphics.fingerprintPca(fp)
    %
    %   Runs PCA on the complete-case per-animal z matrix (subjects x metric
    %   contexts) from cohort.fingerprint. Draws per-animal scores on PC1/PC2
    %   (color = genotype, marker = sex) with convex hulls per cohort
    %   (strain x genotype x sex).
    %
    %   Returns pcaStruct with fields: scores, coeff (loadings), explained,
    %   contextNames, cohortOfSubject, and the complete-case subject metadata.
    %
    %   See also: cohort.fingerprint

    arguments
        fp struct
    end

    pcaStruct = struct();
    fig = [];

    perAnimalZ = fp.perAnimalZ;
    metaCols = {'SubjectKey', 'Gene', 'Genotype$', 'Sex$', 'Litter', 'Cage #', 'Age'};
    zCols = setdiff(perAnimalZ.Properties.VariableNames, metaCols, 'stable');
    if isempty(zCols)
        return;
    end

    % Reorder context features to the canonical fingerprint ordering.
    if isfield(fp, 'colLabels') && height(fp.colLabels) == numel(zCols)
        ctxOrder = graphics.fingerprintContextOrder(fp);
        zCols = zCols(ctxOrder);
    end

    Zall = double(perAnimalZ{:, zCols});
    complete = all(isfinite(Zall), 2);
    if nnz(complete) < 4
        return;
    end

    Z = Zall(complete, :);
    meta = perAnimalZ(complete, :);

    [coeff, scores, explained] = pca(Z);

    genotype = categorical(string(meta.('Genotype$')));
    sex = categorical(string(meta.('Sex$')));
    strain = string(meta.Gene);
    cohortId = strain + " | " + string(genotype) + " | " + string(sex);

    fig = figure('Name', 'Fingerprint PCA', 'Color', 'w', 'Position', [150, 150, 760, 560]);
    ax = axes(fig);
    hold(ax, 'on');

    genotypes = categories(genotype);
    sexes = categories(sex);
    cmap = lines(numel(genotypes));
    sexMarkers = containers.Map( ...
        {'F', 'M', 'Female', 'Male', 'female', 'male'}, ...
        {'o', 's', 'o', 's', 'o', 's'});
    defaultMarker = 'o';

    for gi = 1:numel(genotypes)
        for si = 1:numel(sexes)
            sel = genotype == genotypes{gi} & sex == sexes{si};
            if ~any(sel)
                continue;
            end
            marker = defaultMarker;
            key = char(sexes{si});
            if isKey(sexMarkers, key)
                marker = sexMarkers(key);
            end
            scatter(ax, scores(sel, 1), scores(sel, 2), 36, cmap(gi, :), marker, ...
                'filled', 'MarkerFaceAlpha', 0.75, ...
                'DisplayName', genotypes{gi} + " " + sexes{si});
        end
    end

    % Convex hulls per cohort (>= 3 animals required).
    uniqueCohorts = unique(cohortId);
    for k = 1:numel(uniqueCohorts)
        sel = cohortId == uniqueCohorts(k);
        if nnz(sel) < 3
            continue;
        end
        xs = scores(sel, 1);
        ys = scores(sel, 2);
        kdt = convhull(xs, ys);
        plot(ax, xs(kdt), ys(kdt), '-', ...
            'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.75, 'HandleVisibility', 'off');
    end

    xlabel(ax, sprintf('PC1 (%.1f%%)', explained(1)));
    ylabel(ax, sprintf('PC2 (%.1f%%)', explained(2)));
    title(ax, 'Per-animal fingerprint z profiles (complete-case)');
    legend(ax, 'Location', 'bestoutside', 'FontSize', 8);
    grid(ax, 'on');

    pcaStruct.scores = scores;
    pcaStruct.coeff = coeff;
    pcaStruct.explained = explained;
    pcaStruct.contextNames = string(zCols);
    pcaStruct.subjectMeta = meta;
    pcaStruct.cohortOfSubject = cohortId;
end
