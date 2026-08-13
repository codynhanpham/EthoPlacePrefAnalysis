function standardizedTables = subsetByMetadata(standardizedTables, metadataFilters)
    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        metadataFilters.Sex {validator.mustBeTextOrEmpty} = {} % default to no filter
        metadataFilters.Strain {validator.mustBeTextOrEmpty} = {} % default to no filter
        metadataFilters.Genotype {validator.mustBeTextOrEmpty} = {} % default to no filter
    end

    % Get the uSex, uStrain, and uGenotype values from the standardizedTables struct to validate the filters
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
            err = setdiff(filter, validValues);
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

    % For each of the tables in the standardizedTables struct, filter the columns of multi-column variables based on the specified metadata filters
    for tableIndex = 1:length(standardizedTables)
        metadata = standardizedTables(tableIndex).animalMetadata.values();
        n = length(metadata); % number of columns in the multi-column variables for this table
        idxMask = ismember(cellstr(string({metadata.sex})), metadataFilters.Sex) & ...
                ismember(cellstr(string({metadata.strain})), metadataFilters.Strain) & ...
                ismember(cellstr(string({metadata.genotype})), metadataFilters.Genotype);
        
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