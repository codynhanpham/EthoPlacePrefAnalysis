function key = animalSubjectKey(md)
    %ANIMALSUBJECTKEY Composite subject key from one animalMetadata struct.
    %
    %   key = outlier.internal.animalSubjectKey(md)
    %
    %   Builds the same composite subject key as
    %   outlier.internal.subjectKeysFromTable does from cohort.metrics output
    %   tables, but directly from an animalMetadata struct (using the same
    %   field mapping as cohort.metrics.utils.fillCommonColumns:
    %   id->Mouse_ID, strain->Gene, cagecode->Cage #, parsed id->Gene_ID /
    %   Litter / Toe_ID, sex->Sex$, genotype->Genotype$).
    %
    %   Used by outlier.excludeBaselineSubjects to map detected outlier
    %   subjects back to animalMetadata entries for exclusion.
    %
    %   Input:
    %       md - struct from a standardizedTables animalMetadata dictionary
    %
    %   Output:
    %       key - char scalar composite subject key

    id = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'id', ''));
    strain = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'strain', ''));
    cage = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'cagecode', ''));
    sex = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'sex', ''));
    geno = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'genotype', ''));

    [geneId, litterId, mouseNumber] = cohort.metrics.utils.parseMouseId(id, strain);

    parts = {id, strain, cage, geneId, sex, geno, litterId, mouseNumber};
    key = strjoin(cellfun(@valueToKeyChar, parts, 'UniformOutput', false), '|');
end

function out = valueToKeyChar(value)
    if isempty(value) || (isscalar(value) && ismissing(value)) || (ischar(value) && strlength(value) == 0) || (isstring(value) && strlength(value) == 0)
        out = '<EMPTY>';
    else
        out = char(string(value));
    end
end
