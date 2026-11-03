function r = levenshteinRatio(s1, s2)
    %LEVENSHTEINRATIO Similarity ratio of two strings from Levenshtein distance.
    %
    %   r = cohort.internal.levenshteinRatio(s1, s2)
    %
    %   r = 1 - editDistance / max(lengths), in [0, 1]. Identical strings
    %   return 1; two strings with no common characters approach 0. Standard
    %   two-row dynamic-programming Levenshtein distance.

    arguments
        s1 {mustBeTextScalar}
        s2 {mustBeTextScalar}
    end

    a = char(string(s1));
    b = char(string(s2));

    if isempty(a) && isempty(b)
        r = 1;
        return;
    end
    if isempty(a) || isempty(b)
        r = 0;
        return;
    end

    m = numel(a);
    n = numel(b);
    previous = 0:n;
    for i = 1:m
        current = zeros(1, n + 1);
        current(1) = i;
        for j = 1:n
            substitutionCost = ~(a(i) == b(j));
            current(j + 1) = min([ ...
                current(j) + 1, ...               % deletion
                previous(j + 1) + 1, ...          % insertion
                previous(j) + substitutionCost]); % substitution
        end
        previous = current;
    end

    r = 1 - previous(end) / max(m, n);
end
