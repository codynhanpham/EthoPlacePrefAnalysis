function [featWide, meta] = pivotEntries(entries, refTable, commonHeaders)
    %PIVOTENTRIES Pivot (subjKey, featName, value) entries into a wide table.
    %
    %   [featWide, meta] = outlier.internal.pivotEntries(entries, refTable, commonHeaders)
    %
    %   Aggregates the tidy (subject key, feature name, value) entry list into
    %   a wide per-subject feature table (mean, omitting NaN, across all
    %   entries for the same subject/feature). Subject metadata is filled from
    %   the first matching row of a cohort.metrics reference table.
    %
    %   Inputs:
    %       entries       - [n x 3] cell array {subjKey, featName, value}
    %       refTable      - cohort.metrics output table containing the common
    %                       header columns (used for subject metadata)
    %       commonHeaders - cellstr of common header column names in canonical order
    %
    %   Outputs:
    %       featWide - table with columns: SubjectKey + one column per feature
    %       meta     - table with columns: SubjectKey, Mouse_ID, Gene, Cage #,
    %                  Gene_ID, Sex$, Genotype$, Litter, Toe_ID, Group
    %                  (Group = strain/Gene column, matching plot convention)

    subjKeys = unique(entries(:, 1), 'stable');
    featNames = unique(entries(:, 2), 'stable');

    % Subject metadata from the first matching refTable row.
    refKeys = outlier.internal.subjectKeysFromTable(refTable, commonHeaders);
    n = numel(subjKeys);
    meta = table();
    meta.('SubjectKey') = subjKeys;
    meta.('Mouse_ID') = strings(n, 1);
    meta.('Gene') = strings(n, 1);
    meta.('Cage #') = strings(n, 1);
    meta.('Gene_ID') = strings(n, 1);
    meta.('Sex$') = strings(n, 1);
    meta.('Genotype$') = strings(n, 1);
    meta.('Litter') = strings(n, 1);
    meta.('Toe_ID') = strings(n, 1);
    meta.('Group') = strings(n, 1);
    for si = 1:n
        hit = find(strcmp(refKeys, subjKeys{si}), 1);
        if isempty(hit)
            continue;
        end
        for h = 1:numel(commonHeaders)
            meta.(commonHeaders{h})(si) = string(refTable.(commonHeaders{h})(hit));
        end
        % Group = strain (Gene column), matching plotProgressionInTab convention.
        meta.('Group')(si) = string(refTable.('Gene')(hit));
    end

    featWide = table(subjKeys, 'VariableNames', {'SubjectKey'});
    for f = 1:numel(featNames)
        vals = nan(n, 1);
        for si = 1:n
            m = strcmp(entries(:, 1), subjKeys{si}) & strcmp(entries(:, 2), featNames{f});
            if any(m)
                vals(si) = mean(cell2mat(entries(m, 3)), 'omitnan');
            end
        end
        featWide.(featNames{f}) = vals;
    end
end
