function protocolLabels = validateProtocolTables(standardizedTables)
    %VALIDATEPROTOCOLTABLES Validate a 2-table standardizedTables protocol pair.
    %
    %   protocolLabels = cohort.internal.validateProtocolTables(standardizedTables)
    %
    %   Validates that:
    %       1) exactly 2 standardizedTables elements are provided;
    %       2) each table has a non-empty centerpointData with a 'Stimulus name'
    %          column containing at least one 'NONE | Pre-Stimulus' row AND at
    %          least one non-NONE stimulus row;
    %       3) the subject key sets (strain|genotype|sex|cagecode|id built from
    %          animalMetadata values, in column order) are identical across the
    %          two tables;
    %       4) no subject key is duplicated within a table.
    %
    %   Any violation throws a hard error naming the offending subjects/tables.
    %
    %   Returns protocolLabels = {T1.stimfileName, T2.stimfileName}. The ORDER
    %   is semantic: table 1's pre-stimulus block is the exploration/
    %   habituation window; table 2's pre-stimulus block is the baseline.

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
    end

    if numel(standardizedTables) ~= 2
        error('cohort:internal:validateProtocolTables:WrongTableCount', ...
            'Expected exactly 2 standardizedTables (2 stim protocols), got %d. Table order is semantic: (1) exploration protocol, (2) baseline protocol.', ...
            numel(standardizedTables));
    end

    for i = 1:2
        stdTable = standardizedTables(i);
        cp = stdTable.centerpointData;

        if isempty(cp) || ~ismember('Stimulus name', cp.Properties.VariableNames)
            error('cohort:internal:validateProtocolTables:MissingStimulusName', ...
                'standardizedTables(%d).centerpointData is empty or lacks a ''Stimulus name'' column.', i);
        end

        stimNames = strtrim(string(cp{:, 'Stimulus name'}));
        nPreStim = sum(strcmpi(stimNames, "NONE | Pre-Stimulus"));
        nStim = sum(~startsWith(stimNames, "NONE") & strlength(stimNames) > 0);

        if nPreStim < 1
            error('cohort:internal:validateProtocolTables:MissingPreStimulus', ...
                'standardizedTables(%d) (''%s'') has no ''NONE | Pre-Stimulus'' rows. Both tables must include the pre-stimulus period.', ...
                i, stdTable.stimfileName);
        end
        if nStim < 1
            error('cohort:internal:validateProtocolTables:MissingStimulus', ...
                'standardizedTables(%d) (''%s'') has no active stimulus rows.', ...
                i, stdTable.stimfileName);
        end
    end

    keys1 = subjectKeys(standardizedTables(1));
    keys2 = subjectKeys(standardizedTables(2));

    allKeys = {keys1, keys2};
    for i = 1:2
        thisKeys = allKeys{i};
        [uKeys, ~, iu] = unique(thisKeys, 'stable');
        counts = accumarray(iu, 1);
        duplicated = uKeys(counts > 1);
        if ~isempty(duplicated)
            error('cohort:internal:validateProtocolTables:DuplicateSubject', ...
                'standardizedTables(%d) contains duplicated subject key(s): %s', ...
                i, strjoin(duplicated(1:min(end, 5)), ', '));
        end
    end

    missingIn2 = setdiff(keys1, keys2, 'stable');
    missingIn1 = setdiff(keys2, keys1, 'stable');
    if ~isempty(missingIn2) || ~isempty(missingIn1)
        msg = 'Subject key sets differ between the two protocol tables.';
        if ~isempty(missingIn2)
            msg = sprintf('%s In table 1 only (missing from table 2): %s.', msg, ...
                strjoin(missingIn2(1:min(end, 5)), ', '));
        end
        if ~isempty(missingIn1)
            msg = sprintf('%s In table 2 only (missing from table 1): %s.', msg, ...
                strjoin(missingIn1(1:min(end, 5)), ', '));
        end
        error('cohort:internal:validateProtocolTables:SubjectSetMismatch', '%s', msg);
    end

    protocolLabels = { ...
        displayLabelOf(standardizedTables(1).stimfileName, 1), ...
        displayLabelOf(standardizedTables(2).stimfileName, 2)};
end


function label = displayLabelOf(stimfileName, tableIdx)
    % Display label for a table's stimfileName. Tables joined with
    % population.temp.joinStdTableByStim carry the original protocol
    % variations in a cell; those are shown as 'a.flac + b.flac'.
    variants = cohort.internal.stimfileNameVariants(stimfileName, 'stimfileName');
    if isempty(variants)
        error('cohort:internal:validateProtocolTables:EmptyStimfileName', ...
            'standardizedTables(%d).stimfileName is empty; protocol labels must be non-empty text.', tableIdx);
    end
    if isscalar(variants)
        label = variants(1);
    else
        label = strjoin(variants, ' + ');
    end
end


function keysOut = subjectKeys(stdTable)
    animalMetadata = stdTable.animalMetadata;
    mdList = animalMetadata.values();
    if ~isstruct(mdList)
        mdList = struct([]);
    end
    n = numel(mdList);
    keysOut = strings(n, 1);
    for k = 1:n
        md = mdList(k);
        strain = cohort.internal.textScalar(getMetaField(md, 'strain'), 'strain');
        geno = cohort.internal.textScalar(getMetaField(md, 'genotype'), 'genotype');
        sex = cohort.internal.textScalar(getMetaField(md, 'sex'), 'sex');
        % Canonicalize genotype/sex (strain-aware, silent) so variant drift
        % (KO vs Hom, m vs Male) cannot split keys across protocol tables.
        [geno, sex] = outlier.internal.canonicalKeyTokens(geno, sex, strain);
        parts = [ ...
            strain
            geno
            sex
            cohort.internal.textScalar(getMetaField(md, 'cagecode'), 'cagecode')
            cohort.internal.textScalar(getMetaField(md, 'id'), 'id')];
        keysOut(k) = strjoin(parts, "|");
    end
end


function v = getMetaField(md, fieldName)
    if isfield(md, fieldName)
        v = md.(fieldName);
    else
        v = '';
    end
end
