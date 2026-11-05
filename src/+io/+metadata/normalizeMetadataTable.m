function masterMetadata = normalizeMetadataTable(masterMetadata, rules)
    %%NORMALIZEMETADATATABLE Canonicalize ANIMAL_GENOTYPE / ANIMAL_SEX columns of a master metadata table
    %   masterMetadata = io.metadata.normalizeMetadataTable(masterMetadata)
    %   masterMetadata = io.metadata.normalizeMetadataTable(masterMetadata, rules)
    %
    %   Applies the genotypes.info.yml normalization rules (see io.metadata.loadGenotypeInfo)
    %   row-by-row using each row's strain (and sex) context:
    %       * ANIMAL_GENOTYPE is replaced by its canonical label (variant tokens such as
    %         'KO' for Mecp2 males become 'Hem'; declared combo labels keep their file-written case).
    %       * ANIMAL_SEX is canonicalized via io.metadata.canonicalSex ('m' -> 'Male', ...).
    %       * Strains not defined in the rules are left untouched (case-insensitive identity
    %         grouping is handled by downstream consumers).
    %       * A genotype outside the declared combos/variants of a DEFINED strain (for that
    %         sex, when available) is kept as-is and triggers a warning once per unique
    %         strain|sex|genotype combination per MATLAB session, suggesting to double-check
    %         the metadata or update genotypes.info.yml.
    %
    %   Inputs:
    %       masterMetadata - Table with at least ANIMAL_STRAIN and ANIMAL_GENOTYPE columns
    %                        (ANIMAL_SEX optional; canonicalized too when present).
    %       rules          - (optional) Rules struct from io.metadata.loadGenotypeInfo.
    %
    %   Outputs:
    %       masterMetadata - Same table with normalized ANIMAL_GENOTYPE / ANIMAL_SEX values.
    %                        Column storage class (cellstr/string) is preserved.
    %
    %   See also: io.metadata.loadGenotypeInfo, io.metadata.canonicalGenotype, io.metadata.canonicalSex

    arguments
        masterMetadata table
        rules (1, 1) struct = io.metadata.loadGenotypeInfo()
    end

    persistent WarnedKeys
    if isempty(WarnedKeys)
        WarnedKeys = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end

    requiredCols = {'ANIMAL_STRAIN', 'ANIMAL_GENOTYPE'};
    missingCols = setdiff(requiredCols, masterMetadata.Properties.VariableNames);
    if ~isempty(missingCols)
        error('io:metadata:normalizeMetadataTable:MissingColumns', ...
            'masterMetadata is missing required columns: %s', strjoin(missingCols, ', '));
    end
    hasSex = ismember('ANIMAL_SEX', masterMetadata.Properties.VariableNames);

    genotypes = textColumnToString(masterMetadata.ANIMAL_GENOTYPE);
    strains = textColumnToString(masterMetadata.ANIMAL_STRAIN);
    if hasSex
        sexes = textColumnToString(masterMetadata.ANIMAL_SEX);
    else
        sexes = repmat("", height(masterMetadata), 1);
    end

    for i = 1:height(masterMetadata)
        sexToken = sexes(i);
        [canonical, status] = io.metadata.canonicalGenotype(genotypes(i), strains(i), sexToken, rules);
        genotypes(i) = string(canonical);
        if strcmp(status, 'unknown')
            warnKey = lower(sprintf('%s|%s|%s', strtrim(strains(i)), strtrim(sexToken), strtrim(genotypes(i))));
            if ~isKey(WarnedKeys, warnKey)
                WarnedKeys(warnKey) = true;
                warning('io:metadata:normalizeMetadataTable:UnknownGenotype', ...
                    ['Genotype "%s" (strain "%s", sex "%s") is not a declared combo or variant in the genotype info rules. ' ...
                    'Keeping the token as-is. Double-check the metadata or update genotypes.info.yml.'], ...
                    strtrim(genotypes(i)), strtrim(strains(i)), strtrim(sexToken));
            end
        end
        if hasSex
            sexes(i) = string(io.metadata.canonicalSex(sexToken));
        end
    end

    masterMetadata.ANIMAL_GENOTYPE = restoreColumnClass(genotypes, masterMetadata.ANIMAL_GENOTYPE);
    if hasSex
        masterMetadata.ANIMAL_SEX = restoreColumnClass(sexes, masterMetadata.ANIMAL_SEX);
    end
end


function col = textColumnToString(col)
    if iscategorical(col)
        col = string(col);
    elseif iscellstr(col) || iscell(col)
        col = string(col);
    elseif ischar(col)
        col = string(col);
    elseif ~isstring(col)
        col = string(col);
    end
    col = reshape(col, [], 1);
end


function col = restoreColumnClass(values, template)
    if iscategorical(template)
        col = categorical(cellstr(values));
    elseif iscell(template)
        col = cellstr(values);
    elseif isstring(template)
        col = values;
    elseif ischar(template)
        col = char(values);
    else
        col = values;
    end
end
