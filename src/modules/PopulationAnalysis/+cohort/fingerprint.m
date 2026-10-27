function out = fingerprint(perAnimalLong, kvargs)
    %%FINGERPRINT Cohort-level aggregation and robust z fingerprint of long per-animal metrics.
    %
    %   out = cohort.fingerprint(perAnimalLong)
    %
    %   Inputs:
    %       perAnimalLong - long per-animal table from cohort.longify (requires
    %           columns: SubjectKey, Gene, Genotype$, Sex$, Tier, Protocol,
    %           Stimulus, Metric, Value).
    %
    %   Name-Value Pair Arguments:
    %       - 'Whitelist': struct with fields Include/Exclude (substring cell
    %         arrays). Default: cohort.internal.defaultWhitelist().
    %       - 'ReferenceGenotype': genotype label serving as the reference
    %         cohort within each strain. Default 'WT'. Matched against data
    %         case-insensitively after trimming.
    %       - 'ReferenceGenotypeByStrain': per-strain reference genotype
    %         override for strains that do not ship the default reference.
    %         Accepts a cell of {strain, genotype, ...} pairs, a struct with
    %         strain-named fields, or a dictionary(string,string). Default {}.
    %       - 'MinCohortN': minimum cohort AND reference n for stats eligibility. Default 4.
    %       - 'NBoot': bootstrap resamples for cohort median CI. Default 2000.
    %       - 'IncludePooledSex': add flagged pooled-sex genotype rows per strain. Default true.
    %       - 'Seed': RNG seed for reproducible bootstrap. Default 1.
    %
    %   Outputs (struct):
    %       cohortTable  - long descriptive table (Strain x Genotype x Sex x Tier x
    %                       Protocol x Stimulus x Metric) with NAnimals, NValid, Median,
    %                       MAD, Q25, Q75, bootstrap 95% CI (CiLo/CiHi), Z, statsEligible,
    %                       Reason, PooledSex. Native units for descriptives; Z is dimensionless.
    %       zMatrix      - eligible sex-specific cohorts (rows) x metric contexts (cols) of Z.
    %       rowLabels    - table(Strain, Genotype, Sex) aligned with zMatrix rows.
    %       colLabels    - table(Tier, Protocol, Stimulus, Metric, Context) aligned with zMatrix cols.
    %       perAnimalZ   - per-animal z table (SubjectKey + metadata + one column per context).
    %       referenceMap - table(Strain, ReferenceGenotype) actually used.
    %
    %   z definition: z = (value - median(refAnimals)) / (1.4826*MAD(refAnimals)),
    %   where refAnimals are the same-strain, same-sex reference-genotype values
    %   for that exact metric context. NaN with a reason when the cohort or the
    %   reference falls below MinCohortN, or when the reference MAD is 0.
    %
    %   See also: cohort.longify, cohort.internal.defaultWhitelist, cohort.fingerprintStats

    arguments
        perAnimalLong table {mustBeNonempty}
        kvargs.Whitelist struct = struct()
        kvargs.ReferenceGenotype {mustBeTextScalar} = 'WT'
        kvargs.ReferenceGenotypeByStrain {} = {}
        kvargs.MinCohortN (1,1) double {mustBePositive, mustBeInteger} = 4
        kvargs.NBoot (1,1) double {mustBePositive, mustBeInteger} = 2000
        kvargs.IncludePooledSex (1,1) logical = true
        kvargs.Seed (1,1) double {mustBeNonnegative, mustBeInteger} = 1
    end

    requiredColumns = {'SubjectKey', 'Gene', 'Genotype$', 'Sex$', 'Litter', 'Cage #', 'Age', ...
        'Tier', 'Protocol', 'Stimulus', 'Metric', 'Value'};
    missing = setdiff(requiredColumns, perAnimalLong.Properties.VariableNames, 'stable');
    if ~isempty(missing)
        error('cohort:fingerprint:MissingColumns', ...
            'perAnimalLong is missing required columns: %s', strjoin(missing, ', '));
    end

    if isempty(fieldnames(kvargs.Whitelist))
        whitelist = cohort.internal.defaultWhitelist();
    else
        whitelist = kvargs.Whitelist;
    end

    refByStrain = normalizeRefByStrain(kvargs.ReferenceGenotypeByStrain);
    defaultRefGenotype = string(kvargs.ReferenceGenotype);
    minN = kvargs.MinCohortN;

    rng(kvargs.Seed, 'twister');

    strain = string(perAnimalLong.Gene);
    genotype = string(perAnimalLong.('Genotype$'));
    genoNorm = lower(strtrim(genotype));
    sex = string(perAnimalLong.('Sex$'));
    tier = string(perAnimalLong.Tier);
    protocol = string(perAnimalLong.Protocol);
    stimulus = string(perAnimalLong.Stimulus);
    metric = string(perAnimalLong.Metric);
    values = double(perAnimalLong.Value);
    subjectKey = string(perAnimalLong.SubjectKey);

    contextKey = tier + "|" + protocol + "|" + stimulus + "|" + metric;
    keepRows = whitelistMask(metric, whitelist) & isfinite(values);

    %% Integer id mapping (single pass; no linear scans per element)
    % Subjects over the full table, restricted to subjects with kept rows.
    [subjectListAll, subjectFirstRows, subjIdOfRow] = unique(subjectKey);
    isKeptSubject = accumarray(subjIdOfRow(keepRows), 1, [numel(subjectListAll), 1]) > 0;
    subjectList = subjectListAll(isKeptSubject);
    keptSubjectPos = zeros(numel(subjectListAll), 1);
    keptSubjectPos(isKeptSubject) = 1:nnz(isKeptSubject);
    subjectRowIdx = subjectFirstRows(isKeptSubject);
    nSubjects = numel(subjectList);

    % Contexts over the full table, restricted to contexts with kept rows.
    [ctxListAll, ~, ctxIdOfRow] = unique(contextKey);
    isKeptCtx = accumarray(ctxIdOfRow(keepRows), 1, [numel(ctxListAll), 1]) > 0;
    contextsList = ctxListAll(isKeptCtx);
    ctxKeptPos = zeros(numel(ctxListAll), 1);
    ctxKeptPos(isKeptCtx) = 1:nnz(isKeptCtx);
    nContexts = numel(contextsList);

    % Context components (tier/protocol/stimulus/metric per context).
    [ctxStable, ctxFirstRows] = unique(contextKey, 'stable');
    [~, ord] = sort(ctxStable);
    ctxTierComp = tier(ctxFirstRows(ord));
    ctxProtocolComp = protocol(ctxFirstRows(ord));
    ctxStimulusComp = stimulus(ctxFirstRows(ord));
    ctxMetricComp = metric(ctxFirstRows(ord));
    contextsTable = table(ctxTierComp(isKeptCtx), ctxProtocolComp(isKeptCtx), ...
        ctxStimulusComp(isKeptCtx), ctxMetricComp(isKeptCtx), contextsList, ...
        'VariableNames', {'Tier', 'Protocol', 'Stimulus', 'Metric', 'Context'});

    perAnimalMeta = perAnimalLong(subjectRowIdx, ...
        {'SubjectKey', 'Gene', 'Genotype$', 'Sex$', 'Litter', 'Cage #', 'Age'});

    %% Reference statistics per (strain, sex, context)
    strainsList = unique(strain(keepRows));
    sexesList = unique(sex(keepRows));
    [~, strainIdx] = ismember(strain, strainsList);
    [~, sexIdx] = ismember(sex, sexesList);
    [genoNormList, ~, genoNormIdx] = unique(genoNorm);

    referenceMap = table(strainsList, arrayfun(@(s) referenceGenotypeFor(s, refByStrain, defaultRefGenotype), strainsList), ...
        'VariableNames', {'Strain', 'ReferenceGenotype'});

    nStrains = numel(strainsList);
    nSexes = numel(sexesList);
    refMedian = nan(nStrains, nSexes, nContexts);
    refScale = nan(nStrains, nSexes, nContexts);
    refCount = nan(nStrains, nSexes, nContexts);
    for sti = 1:nStrains
        refGenoN = normGeno(referenceGenotypeFor(strainsList(sti), refByStrain, defaultRefGenotype));
        rg = find(genoNormList == refGenoN, 1);
        for sei = 1:nSexes
            isRef = keepRows & strainIdx == sti & sexIdx == sei & genoNormIdx == rg;
            g = ctxKeptPos(ctxIdOfRow(isRef));
            v = values(isRef);
            ok = g > 0 & isfinite(v);
            gOk = g(ok);
            vOk = v(ok);
            if isempty(gOk)
                refCount(sti, sei, :) = 0;
                continue;
            end

            refCount(sti, sei, :) = accumarray(gOk, 1, [nContexts, 1]);
            [gc, gid] = findgroups(gOk);
            medRow = nan(nContexts, 1);
            madRow = nan(nContexts, 1);
            medRow(gid) = splitapply(@(x) median(x, 'omitnan'), vOk, gc);
            madRow(gid) = splitapply(@(x) mad(x, 1), vOk, gc);
            refMedian(sti, sei, :) = medRow;
            scl = 1.4826 * madRow;
            scl(~(isfinite(scl) & scl > 0)) = NaN;
            refScale(sti, sei, :) = scl;
        end
    end

    %% Per-animal z
    % subject x context value matrix (one value per subject per context)
    valueMatrix = nan(nSubjects, nContexts);
    kr = find(keepRows);
    valueMatrix(keptSubjectPos(subjIdOfRow(kr)) + (ctxKeptPos(ctxIdOfRow(kr)) - 1) * nSubjects) = values(kr);

    zAll = nan(nSubjects, nContexts);
    subjStrainIdx = strainIdx(subjectRowIdx);
    subjSexIdx = sexIdx(subjectRowIdx);
    for s = 1:nSubjects
        sti = subjStrainIdx(s);
        sei = subjSexIdx(s);
        if sti == 0 || sei == 0
            continue;
        end
        cnt = reshape(refCount(sti, sei, :), 1, []);
        scl = reshape(refScale(sti, sei, :), 1, []);
        med = reshape(refMedian(sti, sei, :), 1, []);
        ok = cnt >= minN & isfinite(scl);
        vals = valueMatrix(s, :);
        zAll(s, ok) = (vals(ok) - med(ok)) ./ scl(ok);
    end

    colNamesZ = makeContextColumnNames(contextsTable);
    zTable = array2table(zAll, 'VariableNames', colNamesZ);
    perAnimalZ = [perAnimalMeta, zTable];

    %% Cohort table
    cohortTable = buildCohortTable(genotype, genoNormIdx, genoNormList, sex, ...
        tier, protocol, stimulus, metric, values, subjectKey, keepRows, ...
        strainIdx, sexIdx, ctxKeptPos(ctxIdOfRow), ...
        refByStrain, defaultRefGenotype, minN, kvargs.NBoot, kvargs.IncludePooledSex, ...
        strainsList, sexesList, refMedian, refScale, refCount);

    %% zMatrix over eligible sex-specific cohorts
    eligible = cohortTable.statsEligible & ~cohortTable.PooledSex;
    eligibleTable = cohortTable(eligible, :);

    ctStrain = string(eligibleTable.Strain);
    ctGeno = string(eligibleTable.Genotype);
    ctSex = string(eligibleTable.Sex);
    ctCtx = string(eligibleTable.Tier) + "|" + string(eligibleTable.Protocol) + ...
        "|" + string(eligibleTable.Stimulus) + "|" + string(eligibleTable.Metric);

    cohortKeys = unique([ctStrain, ctGeno, ctSex], 'rows', 'stable');
    [~, whichCohort] = ismember([ctStrain, ctGeno, ctSex], cohortKeys, 'rows');
    [~, whichCtx] = ismember(ctCtx, contextsList);

    zMatrix = nan(size(cohortKeys, 1), nContexts);
    for r = 1:height(eligibleTable)
        if whichCohort(r) == 0 || whichCtx(r) == 0
            continue;
        end
        zMatrix(whichCohort(r), whichCtx(r)) = eligibleTable.Z(r);
    end

    rowLabels = table(cohortKeys(:, 1), cohortKeys(:, 2), cohortKeys(:, 3), ...
        'VariableNames', {'Strain', 'Genotype', 'Sex'});

    out = struct();
    out.cohortTable = cohortTable;
    out.zMatrix = zMatrix;
    out.rowLabels = rowLabels;
    out.colLabels = contextsTable;
    out.perAnimalZ = perAnimalZ;
    out.referenceMap = referenceMap;
end


function g = normGeno(x)
    g = lower(strtrim(string(x)));
end


function mask = whitelistMask(metric, whitelist)
    metric = string(metric);
    include = string(whitelist.Include);
    exclude = string(whitelist.Exclude);

    mask = false(size(metric));
    for i = 1:numel(include)
        mask = mask | contains(metric, include(i), 'IgnoreCase', true);
    end
    for i = 1:numel(exclude)
        mask = mask & ~contains(metric, exclude(i), 'IgnoreCase', true);
    end
end


function refByStrain = normalizeRefByStrain(inputValue)
    refByStrain = dictionary(string, string);

    if isempty(inputValue)
        return;
    end

    if isa(inputValue, 'dictionary')
        keysIn = string(keys(inputValue));
        valsIn = string(values(inputValue));
        for i = 1:numel(keysIn)
            refByStrain(keysIn(i)) = valsIn(i);
        end
        return;
    end

    if isstruct(inputValue)
        fields = fieldnames(inputValue);
        for i = 1:numel(fields)
            refByStrain(string(fields{i})) = string(inputValue.(fields{i}));
        end
        return;
    end

    if iscell(inputValue)
        if numel(inputValue) == 2 && ~iscell(inputValue{1})
            refByStrain(string(inputValue{1})) = string(inputValue{2});
            return;
        end
        if mod(numel(inputValue), 2) ~= 0
            error('cohort:fingerprint:InvalidReferenceByStrain', ...
                'ReferenceGenotypeByStrain cell input must contain {strain, genotype} pairs (even number of elements).');
        end
        for i = 1:2:numel(inputValue)
            refByStrain(string(inputValue{i})) = string(inputValue{i+1});
        end
        return;
    end

    error('cohort:fingerprint:InvalidReferenceByStrain', ...
        'Unsupported ReferenceGenotypeByStrain input type: %s', class(inputValue));
end


function refGeno = referenceGenotypeFor(strainValue, refByStrain, defaultGenotype)
    key = string(strainValue);
    if isKey(refByStrain, key)
        refGeno = refByStrain(key);
    else
        refGeno = defaultGenotype;
    end
end


function cohortTable = buildCohortTable(genotype, genoNormIdx, genoNormList, sex, ...
    tier, protocol, stimulus, metric, values, subjectKey, keepRows, ...
    strainIdx, sexIdx, ctxIdx, ...
    refByStrain, defaultRefGenotype, minN, nBoot, includePooledSex, ...
    strainsList, sexesList, refMedian, refScale, refCount)

    % All inputs restricted to kept rows once, then integer-id grouping.
    genotype = genotype(keepRows);
    genoNormIdx = genoNormIdx(keepRows);
    sex = sex(keepRows);
    sexIdx = sexIdx(keepRows);
    tier = tier(keepRows);
    protocol = protocol(keepRows);
    stimulus = stimulus(keepRows);
    metric = metric(keepRows);
    values = values(keepRows);
    subjectKey = subjectKey(keepRows);
    strainIdx = strainIdx(keepRows);
    ctxIdx = ctxIdx(keepRows);

    % Genotype identity is the NORMALIZED id; the display label is the first
    % original-case genotype string observed for that normalized id.
    genoLabelById = strings(numel(genoNormList), 1);
    for gi = 1:numel(genoNormList)
        firstRow = find(genoNormIdx == gi, 1, 'first');
        if ~isempty(firstRow)
            genoLabelById(gi) = genotype(firstRow);
        else
            genoLabelById(gi) = genoNormList(gi);
        end
    end

    triples = [strainIdx(:), genoNormIdx(:), sexIdx(:)];
    uniqueTriples = unique(triples, 'rows', 'stable');
    pairs = [strainIdx(:), genoNormIdx(:)];
    uniquePairs = unique(pairs, 'rows', 'stable');

    rowList = {};
    for pass = 1:2
        if pass == 2 && ~includePooledSex
            break;
        end

        if pass == 1
            nCohortDefs = size(uniqueTriples, 1);
        else
            nCohortDefs = size(uniquePairs, 1);
        end

        for k = 1:nCohortDefs
            if pass == 1
                sti = uniqueTriples(k, 1);
                gIdx = uniqueTriples(k, 2);
                sxi = uniqueTriples(k, 3);
                inCohort = strainIdx == sti & genoNormIdx == gIdx & sexIdx == sxi;
                pooledFlag = false;
                sexIn = unique(sex(inCohort), 'stable');
                if isempty(sexIn)
                    continue;
                end
            else
                sti = uniquePairs(k, 1);
                gIdx = uniquePairs(k, 2);
                inCohort = strainIdx == sti & genoNormIdx == gIdx;
                pooledFlag = true;
                sexIn = "ALL";
            end

            strainsIn = strainsList(sti);
            genoIn = genoLabelById(gIdx);

            rowsHere = find(inCohort);
            g = ctxIdx(rowsHere);
            ug = unique(g);
            for u = 1:numel(ug)
                sel = g == ug(u);
                rowsCtx = rowsHere(sel);
                vals = values(rowsCtx);
                nAnimals = numel(unique(subjectKey(rowsCtx)));

                [medVal, madVal, q25Val, q75Val, ciLo, ciHi] = cohortStats(vals, nBoot);

                zVal = NaN;
                reason = "";
                if pooledFlag
                    reason = "pooledSex";
                else
                    sei = find(sexesList == sexIn, 1);
                    refGenoN = normGeno(referenceGenotypeFor(strainsIn, refByStrain, defaultRefGenotype));
                    nRef = refCount(sti, sei, ug(u));

                    if nAnimals < minN || nRef < minN
                        reason = ineligibleReason(nAnimals, nRef, minN);
                    elseif genoNormList(gIdx) == refGenoN
                        % The reference cohort vs its own distribution: z of
                        % its median is 0 by construction.
                        zVal = 0;
                    elseif ~isfinite(refScale(sti, sei, ug(u)))
                        reason = "refDegenerate";
                    else
                        zVal = (medVal - refMedian(sti, sei, ug(u))) / refScale(sti, sei, ug(u));
                    end
                end

                firstIdx = rowsCtx(1);
                rowList{end+1} = table( ...
                    strainsIn, genoIn, sexIn, tier(firstIdx), protocol(firstIdx), ...
                    stimulus(firstIdx), metric(firstIdx), nAnimals, numel(vals), ...
                    medVal, madVal, q25Val, q75Val, ciLo, ciHi, zVal, ...
                    ~pooledFlag && isfinite(zVal), reason, pooledFlag, ...
                    'VariableNames', {'Strain', 'Genotype', 'Sex', 'Tier', 'Protocol', ...
                    'Stimulus', 'Metric', 'NAnimals', 'NValid', 'Median', 'MAD', 'Q25', 'Q75', ...
                    'CiLo', 'CiHi', 'Z', 'statsEligible', 'Reason', 'PooledSex'}); %#ok<AGROW>
            end
        end
    end

    if isempty(rowList)
        cohortTable = emptyCohortTable();
        return;
    end

    cohortTable = vertcat(rowList{:});
end


function reason = ineligibleReason(nCohort, nRef, minN)
    if nRef == 0 && nCohort < minN
        reason = "cohortBelowN+refMissing";
    elseif nRef == 0
        reason = "refMissing";
    elseif nCohort < minN && nRef < minN
        reason = "cohortBelowN+refBelowN";
    elseif nCohort < minN
        reason = "cohortBelowN";
    else
        reason = "refBelowN";
    end
end


function [medVal, madVal, q25Val, q75Val, ciLo, ciHi] = cohortStats(vals, nBoot)
    medVal = NaN; madVal = NaN; q25Val = NaN; q75Val = NaN; ciLo = NaN; ciHi = NaN;
    if isempty(vals)
        return;
    end

    medVal = median(vals, 'omitnan');
    madVal = mad(vals, 1);
    q25Val = prctile(vals, 25);
    q75Val = prctile(vals, 75);

    n = numel(vals);
    if n >= 2 && nBoot >= 1
        idx = randi(n, n, nBoot);
        bootMedians = median(vals(idx), 1, 'omitnan');
        ciLo = prctile(bootMedians, 2.5);
        ciHi = prctile(bootMedians, 97.5);
    else
        ciLo = medVal;
        ciHi = medVal;
    end
end


function tOut = emptyCohortTable()
    tOut = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        zeros(0,1), false(0,1), strings(0,1), false(0,1), ...
        'VariableNames', {'Strain', 'Genotype', 'Sex', 'Tier', 'Protocol', 'Stimulus', 'Metric', ...
        'NAnimals', 'NValid', 'Median', 'MAD', 'Q25', 'Q75', 'CiLo', 'CiHi', 'Z', ...
        'statsEligible', 'Reason', 'PooledSex'});
end


function colNames = makeContextColumnNames(contextsTable)
    n = height(contextsTable);
    raw = strings(n, 1);
    for i = 1:n
        raw(i) = "z__" + contextsTable.Tier(i) + "__P" + contextsTable.Protocol(i) + "__" + ...
            contextsTable.Stimulus(i) + "__" + contextsTable.Metric(i);
    end
    colNames = matlab.lang.makeValidName(replace(raw, " ", "_"));

    [uNames, ~, iu] = unique(colNames);
    counts = accumarray(iu, 1);
    for j = 1:numel(uNames)
        if counts(j) > 1
            sel = find(colNames == uNames(j));
            for k = 2:numel(sel)
                colNames(sel(k)) = colNames(sel(k)) + "_" + k;
            end
        end
    end
end
