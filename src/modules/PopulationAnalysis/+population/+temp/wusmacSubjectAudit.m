function audit = wusmacSubjectAudit(standardizedTablePaths)
    %WUSMACSUBJECTAUDIT Dump extracted subject metadata and cohort-drop diagnostics.
    %
    %   audit = wusmacSubjectAudit()                   % default WU-SMAC L3/L4 files
    %   audit = wusmacSubjectAudit({paths...})         % explicit files
    %
    %   Companion diagnostic for wusmacFingerprintPipeline: loads the same
    %   per-strain standardizedTables files and reports, WITHOUT running the
    %   expensive statistics (no permutations, no figures):
    %       1. protocol slot alignment (which table landed in slot 1/2 per strain);
    %       2. every extracted subject (strain|genotype|sex|cagecode|id) per
    %          strain and protocol slot, from animalMetadata AND from the
    %          metric-table common columns, side by side to catch parser drift;
    %       3. cohort composition counts (strain x genotype x sex);
    %       4. per-animal z completeness: how many subjects per cohort are
    %          complete-case across metric contexts (what Mahalanobis uses),
    %          plus the contexts responsible for the most NaNs;
    %       5. cohortTable ineligibility reason counts.
    %
    %   Use this to confirm that "n >= 6 per sex x genotype" survives all the
    %   way into the fingerprint, and to see which metric contexts knock
    %   subjects out of the complete-case Mahalanobis set.
    %
    %   The audit struct is also assigned to 'wusmacSubjectAudit' in the base
    %   workspace.
    %
    %   See also: population.temp.wusmacFingerprintPipeline, cohort.fingerprintPipeline

    arguments
        standardizedTablePaths cell = defaultPaths()
    end

    %% Load pairs (same conventions as wusmacFingerprintPipeline)
    fprintf('Loading %d per-strain standardizedTables files...\n', numel(standardizedTablePaths));
    strainPairs = cell(numel(standardizedTablePaths), 1);
    for i = 1:numel(standardizedTablePaths)
        thisPath = char(standardizedTablePaths{i});
        if ~isfile(thisPath)
            error('population:temp:wusmacSubjectAudit:MissingInput', ...
                'Input file not found: %s', thisPath);
        end
        loaded = load(thisPath);
        strainPairs{i} = extractStandardizedTables(loaded, thisPath);
    end

    %% Input adaptation + protocol alignment
    groups = cohort.internal.adaptPipelineInput(strainPairs);
    alignment = [];
    if numel(groups) > 1
        [groups, alignment] = cohort.internal.alignProtocolSlots(groups);
    end
    if ~isempty(alignment)
        fprintf('\n=== Protocol slot alignment ===\n');
        disp(alignment);
    end

    %% Subject dump from animalMetadata (per group, per slot)
    subjectRows = table();
    for g = 1:numel(groups)
        [protocolLabels, perSlotVariants] = validateWithVariants(groups{g}.tables);
        fprintf('Group %d: %s | slot 1 = %s | slot 2 = %s\n', g, groups{g}.strainLabel, ...
            strjoin(perSlotVariants{1}, ' + '), strjoin(perSlotVariants{2}, ' + '));

        for slot = 1:2
            stdTable = groups{g}.tables(slot);
            mdList = stdTable.animalMetadata.values();
            if ~isstruct(mdList)
                mdList = struct([]);
            end
            keysOrder = keys(stdTable.animalMetadata);
            n = numel(mdList);
            rows = table();
            rows.StrainGroup = repmat(string(groups{g}.strainLabel), n, 1);
            rows.ProtocolSlot = repmat(string(slot), n, 1);
            rows.ColumnOrder = string(1:n)';
            rows.Key = strings(n, 1);
            rows.Strain = strings(n, 1);
            rows.Genotype = strings(n, 1);
            rows.Sex = strings(n, 1);
            rows.Cage = strings(n, 1);
            rows.Id = strings(n, 1);
            for k = 1:n
                md = mdList(k);
                rows.Key(k) = string(keysOrder{k});
                rows.Strain(k) = metaText(md, 'strain');
                rows.Genotype(k) = metaText(md, 'genotype');
                rows.Sex(k) = metaText(md, 'sex');
                rows.Cage(k) = metaText(md, 'cagecode');
                rows.Id(k) = metaText(md, 'id');
            end
            if isempty(subjectRows)
                subjectRows = rows;
            else
                subjectRows = vertcat(subjectRows, rows);
            end
        end
    end

    fprintf('\n=== Cohort composition from animalMetadata (Strain x Genotype x Sex) ===\n');
    metaCounts = groupsummary(subjectRows, {'Strain', 'Genotype', 'Sex'});
    disp(metaCounts);

    %% Run the cheap pipeline pieces (summary x periods, longify, fingerprint)
    fprintf('Extracting metrics and fingerprint (no permutations)...\n');
    longParts = cell(numel(groups), 1);
    for g = 1:numel(groups)
        stdPair = groups{g}.tables;
        protocolLabels = cohort.internal.validateProtocolTables(stdPair);
        stimLabels = cohort.metrics.utils.getOutputStimNames(stdPair, {});

        wideStim = cohort.summary(stdPair, Period='stimulus');
        widePre = cohort.summary(stdPair, Period='pre-stimulus');
        longParts{g} = cohort.longify(wideStim, widePre, ...
            ProtocolLabels=protocolLabels, StimLabels=stimLabels);
    end
    perAnimalLong = vertcat(longParts{:});

    fprintf('\n=== Cohort composition from metric tables (Gene x Genotype$ x Sex$) ===\n');
    metricCounts = groupsummary(perAnimalLong(perAnimalLong.Tier == 'stim_all', :), ...
        {'Gene', 'Genotype$', 'Sex$'}, @(x) numel(unique(x)));
    metricCounts = renameVar(metricCounts, 'fun1_SubjectKey', 'NSubjects');
    disp(metricCounts);

    %% Fingerprint + completeness audit
    fp = cohort.fingerprint(perAnimalLong, MinCohortN=4, NBoot=100);

    metaCols = {'SubjectKey', 'Gene', 'Genotype$', 'Sex$'};
    zCols = setdiff(fp.perAnimalZ.Properties.VariableNames, ...
        [metaCols, {'Litter', 'Cage #', 'Age'}], 'stable');
    Z = double(fp.perAnimalZ{:, zCols});
    geneCol = string(fp.perAnimalZ.Gene);
    genoCol = string(fp.perAnimalZ.('Genotype$'));
    sexCol = string(fp.perAnimalZ.('Sex$'));

    fprintf('\n=== Per-cohort z completeness (complete-case n is what Mahalanobis uses) ===\n');
    completeness = table();
    triples = unique([geneCol(:), genoCol(:), sexCol(:)], 'rows', 'stable');
    for k = 1:size(triples, 1)
        sel = geneCol == triples(k, 1) & genoCol == triples(k, 2) & sexCol == triples(k, 3);
        nSubjects = nnz(sel);
        nComplete = sum(all(isfinite(Z(sel, :)), 2));
        finitePerSubject = sum(isfinite(Z(sel, :)), 2);
        rowTable = table(triples(k, 1), triples(k, 2), triples(k, 3), nSubjects, ...
            numel(zCols), nComplete, min(finitePerSubject), median(finitePerSubject), ...
            'VariableNames', {'Strain', 'Genotype', 'Sex', 'NSubjects', 'NContexts', ...
            'NCompleteCase', 'MinFiniteContexts', 'MedianFiniteContexts'});
        completeness = [completeness; rowTable]; %#ok<AGROW>
    end
    disp(completeness);

    fprintf('=== Contexts with the most NaN subjects (top 10) ===\n');
    nanCounts = sum(~isfinite(Z), 1);
    [sortedNan, order] = sort(nanCounts, 'descend');
    ctxTable = table(string(zCols(order(1:min(10, numel(order))))), ...
        sortedNan(1:min(10, numel(order))), height(fp.perAnimalZ) - sortedNan(1:min(10, numel(order))), ...
        'VariableNames', {'Context', 'NNaNSubjects', 'NFiniteSubjects'});
    disp(ctxTable);

    fprintf('=== Cohort ineligibility reasons (sex-specific rows) ===\n');
    ineligible = fp.cohortTable(~fp.cohortTable.statsEligible & ~fp.cohortTable.PooledSex, :);
    if isempty(ineligible.Reason)
        fprintf('none\n');
    else
        reasonCounts = groupsummary(ineligible, 'Reason');
        disp(reasonCounts);
    end

    audit = struct();
    audit.subjects = subjectRows;
    audit.metaCounts = metaCounts;
    audit.metricCounts = metricCounts;
    audit.perAnimalLong = perAnimalLong;
    audit.fingerprint = fp;
    audit.completeness = completeness;
    audit.contextNanCounts = ctxTable;
    audit.protocolAlignment = alignment;

    assignin('base', 'wusmacSubjectAudit', audit);
    fprintf('\nAudit complete. Inspect via ''wusmacSubjectAudit'' in the base workspace.\n');
end


function paths = defaultPaths()
    paths = {
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/012 TSC2/L3/012_TSC2_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/014 SCN1A/L3/014_SCN1A_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/016 FBN1/L3/016_FBN1_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/020 CACNA1A/L3/020_CACNA1A_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/021 ZBTB10/L3/021_ZBTB10_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/023 GRIN2A/L3/023_GRIN2A_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/024 PTEN/L3/024_PTEN_standardizedTables.mat", ...
        "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/026 KDM5B/L3/026_KDM5B_standardizedTables.mat" ...
    };
end


function stdTables = extractStandardizedTables(loaded, sourcePath)
    varNames = fieldnames(loaded);
    if ismember('standardizedTables', varNames)
        stdTables = loaded.standardizedTables;
    elseif numel(varNames) == 1
        stdTables = loaded.(varNames{1});
    else
        error('population:temp:wusmacSubjectAudit:AmbiguousMatVariable', ...
            ['%s contains %d variables and none is named ''standardizedTables''.'], ...
            sourcePath, numel(varNames));
    end
    if ~isstruct(stdTables)
        error('population:temp:wusmacSubjectAudit:NotAStruct', ...
            '%s: expected a struct array, got %s.', sourcePath, class(stdTables));
    end
end


function [protocolLabels, perSlotVariants] = validateWithVariants(stdPair)
    protocolLabels = cohort.internal.validateProtocolTables(stdPair);
    perSlotVariants = cell(1, 2);
    for slot = 1:2
        variants = cohort.internal.stimfileNameVariants(stdPair(slot).stimfileName, 'stimfileName');
        if isempty(variants)
            variants = string(protocolLabels{slot});
        end
        perSlotVariants{slot} = variants;
    end
end


function s = metaText(md, fieldName)
    if isstruct(md) && isfield(md, fieldName)
        s = cohort.internal.textScalar(md.(fieldName), fieldName);
    else
        s = "";
    end
end


function t = renameVar(t, from, toName)
    names = t.Properties.VariableNames;
    idx = find(strcmp(names, from), 1);
    if ~isempty(idx)
        names{idx} = toName;
        t.Properties.VariableNames = names;
    end
end
