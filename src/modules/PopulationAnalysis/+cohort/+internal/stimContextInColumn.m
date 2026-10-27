function [label, kind] = stimContextInColumn(name, stimLabels)
    %STIMCONTEXTINCOLUMN Detect a stimulus label embedded in a metric column name.
    %
    %   [label, kind] = cohort.internal.stimContextInColumn(name, stimLabels)
    %
    %   Single source of truth for how stimulus-specific metric columns are
    %   recognized (used by cohort.longify for tier tagging and by
    %   cohort.internal.periodColumnName for delta pairing). Returns the
    %   matched stimulus label (longest labels checked first) and where it
    %   occurs:
    %       kind = "period"   - the label occupies the period phrase slot,
    %                           e.g. 'Speed Mean During A (cm/s)'
    %       kind = "embedded" - the label occurs in a fixed embedded slot:
    %                           'on <L> Side' (rate of stay) or
    %                           'Into <L>' (midline crossings)
    %       kind = ""         - no stimulus context (aggregate column)
    %
    %   Token boundaries require a non-word character (or string edge) on both
    %   sides of the matched label.

    arguments
        name {mustBeTextScalar}
        stimLabels {} = {}
    end

    s = char(string(name));
    labels = string(stimLabels);
    labels = labels(strlength(strtrim(labels)) > 0);
    if ~isempty(labels)
        [~, order] = sort(strlength(labels), 'descend');
        labels = labels(order);
    end
    label = "";
    kind = "";

    % Rule 1: label in the period-phrase slot.
    for i = 1:numel(labels)
        if boundedToken(s, 'During ' + labels(i))
            label = labels(i);
            kind = "period";
            return;
        end
    end

    % Rule 2: embedded 'on <L> Side'.
    for i = 1:numel(labels)
        if contains(s, 'on ' + labels(i) + ' Side', 'IgnoreCase', false)
            label = labels(i);
            kind = "embedded";
            return;
        end
    end

    % Rule 3: embedded 'Into <L>'.
    for i = 1:numel(labels)
        if contains(s, 'Into ' + labels(i) + ' ', 'IgnoreCase', false) || ...
                endsWith(s, 'Into ' + labels(i), 'IgnoreCase', false)
            label = labels(i);
            kind = "embedded";
            return;
        end
    end
end


function tf = boundedToken(s, tok)
    tokChar = char(tok);
    occurrences = strfind(s, tokChar);
    if isempty(occurrences)
        tf = false;
        return;
    end

    n = numel(s);
    for k = 1:numel(occurrences)
        before = occurrences(k) - 1;
        after = occurrences(k) + numel(tokChar);
        okBefore = before == 0 || ~isWordChar(s(before));
        okAfter = after > n || ~isWordChar(s(after));
        if okBefore && okAfter
            tf = true;
            return;
        end
    end

    tf = false;
end


function tf = isWordChar(c)
    tf = isletter(c) || (c >= '0' && c <= '9') || c == '_';
end
