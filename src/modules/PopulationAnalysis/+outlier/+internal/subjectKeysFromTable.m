function keys = subjectKeysFromTable(T, commonHeaders)
    %SUBJECTKEYSFROMTABLE Composite per-subject keys from cohort metric tables.
    %
    %   keys = outlier.internal.subjectKeysFromTable(T, commonHeaders)
    %
    %   Builds one composite string key per row of a cohort.metrics output
    %   table by joining the given common-header columns with '|'. Must stay
    %   consistent with outlier.internal.animalSubjectKey, which builds the
    %   same composite from an animalMetadata struct.
    %
    %   Inputs:
    %       T             - table with the common header columns present
    %       commonHeaders - cellstr of column names, in canonical order:
    %                       {'Mouse_ID','Gene','Cage #','Gene_ID','Sex$', ...
    %                        'Genotype$','Litter','Toe_ID'}
    %
    %   Output:
    %       keys - [n x 1] cellstr of composite subject keys

    n = height(T);
    keys = repmat({''}, n, 1);

    % Pre-resolve the genotype/sex header positions (canonicalized below) so
    % keys stay consistent with outlier.internal.animalSubjectKey.
    genoHeader = find(strcmp(commonHeaders, 'Genotype$'), 1);
    sexHeader = find(strcmp(commonHeaders, 'Sex$'), 1);
    strainHeader = find(strcmp(commonHeaders, 'Gene'), 1);

    for r = 1:n
        parts = cell(1, numel(commonHeaders));
        for h = 1:numel(commonHeaders)
            parts{h} = valueToKeyChar(T.(commonHeaders{h})(r));
        end
        % Canonicalize genotype/sex tokens (strain-aware; silent) so variant
        % drift (KO vs Hom, m vs Male) cannot split keys.
        if ~isempty(genoHeader) && ~isempty(strainHeader)
            [parts{genoHeader}, parts{sexHeader}] = outlier.internal.canonicalKeyTokens( ...
                parts{genoHeader}, parts{sexHeader}, parts{strainHeader});
        end
        keys{r} = strjoin(parts, '|');
    end
end

function out = valueToKeyChar(value)
    if isempty(value) || (isscalar(value) && ismissing(value)) || (ischar(value) && strlength(value) == 0) || (isstring(value) && strlength(value) == 0)
        out = '<EMPTY>';
    else
        out = char(string(value));
    end
end
