function [fam, pattern] = metricFamily(metricName, kvargs)
    %METRICFAMILY Metric-family categorical label for fingerprint metric names.
    %
    %   fam = cohort.internal.metricFamily(metricName)
    %
    %   Maps metric column names (as produced by the cohort metrics functions)
    %   to the curated metric families defined alongside the Include patterns
    %   in cohort.internal.defaultWhitelist. A name matches a family when it
    %   contains that pattern's Include substring (case-insensitive) and no
    %   Exclude substring; the FIRST matching pattern in whitelist order
    %   wins, so order-specific patterns (e.g. 'Inactive Total Mean') take
    %   precedence over generic ones (e.g. 'Last-First'). Names matching no
    %   Include pattern, or any Exclude pattern, map to "Other".
    %
    %   [fam, pattern] = cohort.internal.metricFamily(metricName) also returns
    %   the matched Include substring itself ("" for "Other"), which figure
    %   helpers use to abbreviate per-metric tick labels.
    %
    %   fam = cohort.internal.metricFamily(metricName, Whitelist=wl) uses a
    %   custom whitelist struct with Include and Family fields.
    %
    %   metricName may be a string array, char row vector, or cellstr; fam is
    %   a categorical of the same number of elements.
    %
    %   See also: cohort.internal.defaultWhitelist, graphics.fingerprintContextOrder

    arguments
        metricName {mustBeNonempty}
        kvargs.Whitelist struct = struct()
    end

    if ischar(metricName)
        names = string(metricName);
    else
        names = string(metricName(:));
    end
    names = names(:);

    if isempty(fieldnames(kvargs.Whitelist))
        whitelist = cohort.internal.defaultWhitelist();
    else
        whitelist = kvargs.Whitelist;
    end

    if isfield(whitelist, 'Family')
        nFamily = numel(whitelist.Family);
    else
        nFamily = 0;
    end
    if nFamily ~= numel(whitelist.Include)
        error('cohort:internal:metricFamily:BadWhitelist', ...
            'Whitelist must carry one Family label per Include pattern (Include: %d, Family: %d).', ...
            numel(whitelist.Include), nFamily);
    end

    include = string(whitelist.Include);
    familyOf = string(whitelist.Family);
    if isfield(whitelist, 'Exclude')
        exclude = string(whitelist.Exclude);
    else
        exclude = strings(0, 1);
    end

    excluded = false(size(names));
    for i = 1:numel(exclude)
        excluded = excluded | contains(names, exclude(i), 'IgnoreCase', true);
    end

    fam = repmat("Other", size(names));
    pattern = repmat("", size(names));
    % Walk patterns in reverse so the first (most specific) match wins.
    for i = numel(include):-1:1
        hit = ~excluded & contains(names, include(i), 'IgnoreCase', true);
        fam(hit) = familyOf(i);
        pattern(hit) = include(i);
    end

    fam = categorical(fam);
end
