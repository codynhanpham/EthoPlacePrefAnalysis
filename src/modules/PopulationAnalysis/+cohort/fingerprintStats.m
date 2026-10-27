function out = fingerprintStats(perAnimalLong, fp, kvargs)
    %%FINGERPRINTSTATS Cross-cohort inference for a cohort fingerprint.
    %
    %   out = cohort.fingerprintStats(perAnimalLong, fp)
    %
    %   Inputs:
    %       perAnimalLong - long per-animal table from cohort.longify (same one
    %                       passed to cohort.fingerprint).
    %       fp            - struct output of cohort.fingerprint (cohortTable and
    %                       perAnimalZ are used).
    %
    %   Name-Value Pair Arguments:
    %       - 'NPerm': permutation resamples. Default 10000.
    %       - 'Seed': RNG seed. Default 2.
    %       - 'MinCohortN': minimum n on both sides for a test. Default 4.
    %
    %   Outputs (struct):
    %       statsTable - one row per eligible (Strain x Genotype x Sex x metric
    %           context): Z (from fp), CliffDelta, PPerm (two-sided
    %           label-swap permutation within strain x sex), QFDR (BH-FDR
    %           across metric contexts within each comparison).
    %       mahalTable - one row per non-reference cohort: shrunk-covariance
    %           Mahalanobis D^2 of the cohort's per-animal z profiles against
    %           the same-strain same-sex reference animals (reuses
    %           outlier.internal.mahalanobisScores / fitShrunkInverse).
    %
    %   See also: cohort.fingerprint, outlier.internal.mahalanobisScores

    arguments
        perAnimalLong table {mustBeNonempty}
        fp struct
        kvargs.NPerm (1,1) double {mustBePositive, mustBeInteger} = 10000
        kvargs.Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 2
        kvargs.MinCohortN (1,1) double {mustBePositive, mustBeInteger} = 4
    end

    rng(kvargs.Seed, 'twister');

    %% Precompute row group indices ONCE (integer ids, no in-loop string work)
    strainS = string(perAnimalLong.Gene);
    genoNormS = lower(strtrim(string(perAnimalLong.('Genotype$'))));
    sexS = string(perAnimalLong.('Sex$'));
    subjectKey = string(perAnimalLong.SubjectKey);
    values = double(perAnimalLong.Value);
    ctxS = string(perAnimalLong.Tier) + "|" + string(perAnimalLong.Protocol) + ...
        "|" + string(perAnimalLong.Stimulus) + "|" + string(perAnimalLong.Metric);
    finiteVals = isfinite(values);

    [strainId, strainNames] = integerIds(strainS);
    [genoId, genoNames] = integerIds(genoNormS);
    [sexId, sexNames] = integerIds(sexS);
    [ctxId, ctxNames] = integerIds(ctxS);

    cohortTable = fp.cohortTable;
    referenceMap = fp.referenceMap;

    eligible = cohortTable.statsEligible & ~cohortTable.PooledSex;
    eligibleTable = cohortTable(eligible, :);

    ctStrain = string(eligibleTable.Strain);
    ctGeno = string(eligibleTable.Genotype);
    ctSex = string(eligibleTable.Sex);
    ctCtx = string(eligibleTable.Tier) + "|" + string(eligibleTable.Protocol) + ...
        "|" + string(eligibleTable.Stimulus) + "|" + string(eligibleTable.Metric);

    statsRows = {};
    comparisons = unique([ctStrain, ctGeno, ctSex], 'rows', 'stable');

    for c = 1:size(comparisons, 1)
        strainI = comparisons(c, 1);
        genoI = comparisons(c, 2);
        sexI = comparisons(c, 3);

        refGeno = referenceGenotypeFromMap(referenceMap, strainI);
        refGenoN = lower(strtrim(refGeno));

        sti = find(strainNames == strainI, 1);
        sxi = find(sexNames == sexI, 1);
        gi = find(genoNames == genoNormOf(genoI), 1);
        rg = find(genoNames == refGenoN, 1);

        cohortRows = find(ctStrain == strainI & ctGeno == genoI & ctSex == sexI);

        for r = 1:numel(cohortRows)
            rowIdx = cohortRows(r);
            ci = find(ctxNames == ctCtx(rowIdx), 1);

            inCohort = strainId == sti & genoId == gi & sexId == sxi & ctxId == ci & finiteVals;
            inRef = strainId == sti & genoId == rg & sexId == sxi & ctxId == ci & finiteVals;

            cohortVals = values(inCohort);
            refVals = values(inRef);

            nC = numel(unique(subjectKey(inCohort)));
            nR = numel(unique(subjectKey(inRef)));

            [delta, pVal] = cliffsDeltaPerm(cohortVals, refVals, kvargs.NPerm);

            statsRows{end+1} = table(strainI, genoI, sexI, ...
                string(eligibleTable.Tier(rowIdx)), string(eligibleTable.Protocol(rowIdx)), ...
                string(eligibleTable.Stimulus(rowIdx)), string(eligibleTable.Metric(rowIdx)), ...
                nC, nR, eligibleTable.Z(rowIdx), delta, pVal, NaN, ...
                'VariableNames', {'Strain', 'Genotype', 'Sex', 'Tier', 'Protocol', 'Stimulus', ...
                'Metric', 'NCohort', 'NRef', 'Z', 'CliffDelta', 'PPerm', 'QFDR'}); %#ok<AGROW>
        end
    end

    if isempty(statsRows)
        statsTable = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
            strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
            zeros(0,1), zeros(0,1), ...
            'VariableNames', {'Strain', 'Genotype', 'Sex', 'Tier', 'Protocol', 'Stimulus', ...
            'Metric', 'NCohort', 'NRef', 'Z', 'CliffDelta', 'PPerm', 'QFDR'});
    else
        statsTable = vertcat(statsRows{:});
        % BH-FDR across metric contexts within each (Strain, Genotype, Sex) comparison.
        groupKey = string(statsTable.Strain) + "|" + string(statsTable.Genotype) + "|" + string(statsTable.Sex);
        for gkey = unique(groupKey(:))'
            sel = groupKey == gkey;
            p = statsTable.PPerm(sel);
            statsTable.QFDR(sel) = bhFdr(p);
        end
    end

    mahalTable = mahalanobisByCohort(fp, referenceMap, kvargs.MinCohortN);

    out = struct();
    out.statsTable = statsTable;
    out.mahalTable = mahalTable;
end


function g = genoNormOf(x)
    g = lower(strtrim(string(x)));
end


function [ids, names] = integerIds(s)
    [names, ~, ids] = unique(s);
    ids = double(ids(:));
    names = names(:);
end


function refGeno = referenceGenotypeFromMap(referenceMap, strainValue)
    refGeno = "";
    strainCol = string(referenceMap.Strain);
    idx = find(strainCol == string(strainValue), 1);
    if ~isempty(idx)
        refGeno = string(referenceMap.ReferenceGenotype(idx));
    end
end


function [delta, pVal] = cliffsDeltaPerm(cohortVals, refVals, nPerm)
    % Two-sided label-swap permutation test for Cliff's delta. All
    % permutations are evaluated vectorized: because sign(x - x') is
    % antisymmetric, within-group terms cancel and delta(G) equals the sum of
    % per-element net wins r = sum(S, 2) over G's members, divided by n1*n2.
    delta = NaN;
    pVal = NaN;
    if isempty(cohortVals) || isempty(refVals)
        return;
    end

    n1 = numel(cohortVals);
    n2 = numel(refVals);
    pooled = [cohortVals(:); refVals(:)];
    S = sign(pooled - pooled');
    r = sum(S, 2);

    delta = sum(r(1:n1)) / (n1 * n2);
    if ~isfinite(delta)
        return;
    end

    n = n1 + n2;
    [~, permOrder] = sort(rand(n, nPerm), 1); % each column is one permutation
    g1 = permOrder(1:n1, :);                  % group-1 member rows per permutation

    d = zeros(1, nPerm);
    chunk = max(1, floor(2e6 / n));           % bound indicator-matrix memory
    for startIdx = 1:chunk:nPerm
        sel = startIdx:min(startIdx + chunk - 1, nPerm);
        M = false(n, numel(sel));
        linIdx = g1(:, sel) + (0:numel(sel) - 1) * n; % column-major indices
        M(linIdx(:)) = true;
        d(sel) = (r' * double(M)) / (n1 * n2);
    end

    pVal = (1 + sum(abs(d) >= abs(delta))) / (1 + nPerm);
end


function q = bhFdr(p)
    %BHFDN Benjamini-Hochberg FDR q-values with monotonicity enforcement.
    %   q(i) = min over j >= i of (p(j) * m / j), computed as a backward
    %   cumulative minimum over p-sorted ranks. qSorted is a COLUMN vector,
    %   so the reversal must use flipud (fliplr is a no-op on columns).
    p = p(:);
    q = nan(size(p));
    valid = isfinite(p);
    if ~any(valid)
        return;
    end

    pv = p(valid);
    [pvSorted, order] = sort(pv, 'ascend');
    m = numel(pv);
    qSorted = pvSorted .* m ./ (1:m)';
    qSorted = flipud(cummin(flipud(qSorted)));
    qSorted = min(qSorted, 1);
    qValid = nan(size(pv));
    qValid(order) = qSorted;
    q(valid) = qValid;
end


function mahalTable = mahalanobisByCohort(fp, referenceMap, minCohortN)
    perAnimalZ = fp.perAnimalZ;
    if isempty(perAnimalZ) || width(perAnimalZ) <= 7
        mahalTable = emptyMahalTable();
        return;
    end

    metaCols = {'SubjectKey', 'Gene', 'Genotype$', 'Sex$', 'Litter', 'Cage #', 'Age'};
    zCols = setdiff(perAnimalZ.Properties.VariableNames, ...
        [metaCols, {'Litter', 'Cage #', 'Age'}], 'stable');
    if isempty(zCols)
        mahalTable = emptyMahalTable();
        return;
    end

    Z = double(perAnimalZ{:, zCols});
    strain = string(perAnimalZ.Gene);
    genotypeRaw = string(perAnimalZ.('Genotype$'));
    genotype = lower(strtrim(genotypeRaw));
    sex = string(perAnimalZ.('Sex$'));

    triples = [strain(:), genotype(:), sex(:)];
    uniqueTriples = unique(triples, 'rows', 'stable');

    rows = {};
    for k = 1:height(uniqueTriples)
        strainI = uniqueTriples(k, 1);
        genoI = uniqueTriples(k, 2);
        sexI = uniqueTriples(k, 3);
        genoIRaw = genotypeRaw(find(genotype == genoI, 1));
        if isempty(genoIRaw)
            genoIRaw = genoI;
        end

        refGenoN = genoNormOf(referenceGenotypeFromMap(referenceMap, strainI));
        refGenoRaw = genotypeRaw(find(genotype == refGenoN, 1));
        if isempty(refGenoRaw)
            refGenoRaw = refGenoN;
        end
        if strcmp(genoI, refGenoN)
            continue;
        end

        cohortSel = strain == strainI & genotype == genoI & sex == sexI;
        refSel = strain == strainI & genotype == refGenoN & sex == sexI;

        % Complete-case rows on the features observed for the cohort
        cohortRows = find(cohortSel);
        refRows = find(refSel);
        if isempty(cohortRows) || isempty(refRows)
            continue;
        end

        % Features finite for at least one cohort and one ref animal
        featOk = any(isfinite(Z(cohortRows, :)), 1) & any(isfinite(Z(refRows, :)), 1);
        if nnz(featOk) < 2
            continue;
        end

        Xref = Z(refRows, featOk);
        Xtarget = Z(cohortRows, featOk);

        completeTarget = all(isfinite(Xtarget), 2);
        nUsable = sum(completeTarget);
        if nUsable < minCohortN
            rows{end+1} = table(strainI, genoIRaw, sexI, refGenoRaw, nUsable, size(Xtarget, 2), ...
                NaN, NaN, NaN, 'cohortBelowN', ...
                'VariableNames', {'Strain', 'Genotype', 'Sex', 'ReferenceGenotype', 'NAnimals', ...
                'NFeatures', 'MeanD2', 'MedianD2', 'MeanLambda', 'Reason'}); %#ok<AGROW>
            continue;
        end

        [d2, lambdaUsed] = outlier.internal.mahalanobisScores(Xref, Xtarget, 0.1);
        d2Valid = d2(isfinite(d2));

        if isempty(d2Valid)
            reason = 'noFit';
            meanD2 = NaN; medianD2 = NaN; meanLambda = NaN;
        else
            reason = "";
            meanD2 = mean(d2Valid);
            medianD2 = median(d2Valid);
            meanLambda = mean(lambdaUsed(isfinite(d2)), 'omitnan');
        end

        rows{end+1} = table(strainI, genoIRaw, sexI, refGenoRaw, nUsable, size(Xtarget, 2), ...
            meanD2, medianD2, meanLambda, reason, ...
            'VariableNames', {'Strain', 'Genotype', 'Sex', 'ReferenceGenotype', 'NAnimals', ...
            'NFeatures', 'MeanD2', 'MedianD2', 'MeanLambda', 'Reason'}); %#ok<AGROW>
    end

    if isempty(rows)
        mahalTable = emptyMahalTable();
    else
        mahalTable = vertcat(rows{:});
    end
end


function tOut = emptyMahalTable()
    tOut = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'Strain', 'Genotype', 'Sex', 'ReferenceGenotype', 'NAnimals', ...
        'NFeatures', 'MeanD2', 'MedianD2', 'MeanLambda', 'Reason'});
end
