function standardizedTables = subsetByMetadata(standardizedTables, metadataFilters)
    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        metadataFilters.Sex {validator.mustBeTextOrEmpty} = {} % default to no filter
        metadataFilters.Strain {validator.mustBeTextOrEmpty} = {} % default to no filter
        metadataFilters.Genotype {validator.mustBeTextOrEmpty} = {} % default to no filter
    end

    % Get the uSex, uStrain, and uGenotype values from the standardizedTables struct to validate the filters
    % Genotype/sex matching is case-insensitive; genotype tokens are canonicalized
    % (strain-aware, per genotypes.info.yml) on BOTH the filter values and the
    % metadata values so variant drift (KO vs Hom vs Hem) cannot split groups.
    uSex = {};
    uStrain = {};
    uGenotype = {};
    for i = 1:length(standardizedTables)
        meta = standardizedTables(i).animalMetadata.values();
        uSex = unique([uSex, cellstr(string({meta.sex}))]);
        uStrain = unique([uStrain, cellstr(string({meta.strain}))]);
        uGenotype = unique([uGenotype, cellstr(string({meta.genotype}))]);
    end

    % Validate the filters against the unique values in the standardizedTables struct
    % If non-empty, the filter value must be one of the unique values in the standardizedTables struct
    % If empty, set the filter to the full list of unique values (i.e., no filtering on that field)
    function filter = validateFilter(filter, fieldName, validValues)
        filter = cellstr(string(filter));
        validValues = cellstr(string(validValues));
        filter = filter(~cellfun('isempty', filter));
        validValues = validValues(~cellfun('isempty', validValues));
        if ~isempty(filter)
            % Case-insensitive match against the valid values
            err = filter(~ismember(lower(filter), lower(validValues)));
            if ~isempty(err)
                error('Invalid %s filter value(s): %s \nValid values are: %s', fieldName, strjoin(err, ", "), strjoin(validValues, ", "));
            end
        else
            filter = validValues;
        end
    end
    metadataFilters.Sex = validateFilter(metadataFilters.Sex, "Sex", uSex);
    metadataFilters.Strain = validateFilter(metadataFilters.Strain, "Strain", uStrain);
    metadataFilters.Genotype = validateFilter(metadataFilters.Genotype, "Genotype", uGenotype);

    % Canonicalize the filter values themselves so a user-supplied variant
    % token (e.g. Sex='F', Genotype='KO' for a Mecp2 male) matches the
    % canonicalized metadata values. Sex filters map to Male/Female; genotype
    % filters are resolved per strain when a strain filter is also given.
    rules = io.metadata.loadGenotypeInfo();
    metadataFilters.Sex = cellfun(@(s) io.metadata.canonicalSex(s), metadataFilters.Sex, 'UniformOutput', false);
    if ~isempty(metadataFilters.Strain) && ~isempty(metadataFilters.Genotype)
        canonicalGenoFilters = cell(size(metadataFilters.Genotype));
        for gi = 1:numel(metadataFilters.Genotype)
            canonicalGenoFilters{gi} = metadataFilters.Genotype{gi};
            for si = 1:numel(metadataFilters.Strain)
                idx = find(strcmpi({rules.byStrain.strain}, metadataFilters.Strain{si}), 1);
                if ~isempty(idx)
                    canonicalGenoFilters{gi} = io.metadata.canonicalGenotype( ...
                        metadataFilters.Genotype{gi}, metadataFilters.Strain{si}, '', rules);
                    break;
                end
            end
        end
        metadataFilters.Genotype = canonicalGenoFilters;
    end

    % For each of the tables in the standardizedTables struct, filter the columns of multi-column variables based on the specified metadata filters
    for tableIndex = 1:length(standardizedTables)
        metadata = standardizedTables(tableIndex).animalMetadata.values();
        n = length(metadata); % number of columns in the multi-column variables for this table
        % Canonicalize per-animal genotype (strain-aware) and sex before matching
        metaGeno = strings(n, 1);
        metaSex = strings(n, 1);
        metaStrain = strings(n, 1);
        rules = io.metadata.loadGenotypeInfo();
        for mi = 1:n
            md = metadata(mi);
            metaStrain(mi) = string(cohort.metrics.utils.getFieldOr(md, 'strain', ''));
            metaGeno(mi) = string(cohort.metrics.utils.getFieldOr(md, 'genotype', ''));
            metaSex(mi) = string(cohort.metrics.utils.getFieldOr(md, 'sex', ''));
            if strlength(strtrim(metaGeno(mi))) > 0 && strlength(strtrim(metaStrain(mi))) > 0
                metaGeno(mi) = string(io.metadata.canonicalGenotype(metaGeno(mi), metaStrain(mi), metaSex(mi), rules));
            end
            if strlength(strtrim(metaSex(mi))) > 0
                metaSex(mi) = string(io.metadata.canonicalSex(metaSex(mi)));
            end
        end
        % Strain per animal, forced to n x 1 column (string({metadata.strain})
        % yields a 1 x n row, which would broadcast the & into an n x n mask)
        metaStrainAll = strings(n, 1);
        for mi = 1:n
            metaStrainAll(mi) = metaStrain(mi);
        end
        idxMask = ismember(lower(metaSex), lower(string(metadataFilters.Sex))) & ...
                ismember(lower(metaStrainAll), lower(string(metadataFilters.Strain))) & ...
                ismember(lower(metaGeno), lower(string(metadataFilters.Genotype)));
        
        % Multi-column variables that matches n can be subsetted by the idxMask values. Other variables (e.g., scalar variables or otherwise unmatched) should be left unchanged
        vars = standardizedTables(tableIndex).centerpointData.Properties.VariableNames;
        for varI = 1:length(vars)
            varName = vars{varI};
            varData = standardizedTables(tableIndex).centerpointData.(varName);
            sizeVar = size(varData, 2);
            if sizeVar == n
                standardizedTables(tableIndex).centerpointData.(varName) = varData(:, idxMask);
            end
        end

        % Keep body-part columns aligned with the same metadata ordering.
        bodypartTable = standardizedTables(tableIndex).bodyparts;
        if ~isempty(bodypartTable)
            vars = bodypartTable.Properties.VariableNames;
            for varI = 1:length(vars)
                varName = vars{varI};
                varData = bodypartTable.(varName);
                if size(varData, 2) == n
                    bodypartTable.(varName) = varData(:, idxMask);
                end
            end
            standardizedTables(tableIndex).bodyparts = bodypartTable;
        end

        % Finally subset animalMetadata itself to only include the entries that match the filters
        keys = standardizedTables(tableIndex).animalMetadata.keys();
        standardizedTables(tableIndex).animalMetadata = remove(standardizedTables(tableIndex).animalMetadata, keys(~idxMask));
    end
end