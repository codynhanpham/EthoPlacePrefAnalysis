function nameOut = periodColumnName(nameIn, stimLabels)
    %PERIODCOLUMNNAME Map a stimulus-period metric column name to its pre-stimulus counterpart.
    %
    %   nameOut = cohort.internal.periodColumnName(nameIn, stimLabels)
    %
    %   Stimulus-period metric columns embed the period they were computed
    %   over. This helper rewrites that phrase so a stimulus-period column can
    %   be paired with its pre-stimulus counterpart (for delta contrasts).
    %
    %   Rewriting rules, applied in order:
    %       1) Bout-derived columns (' Bout' or 'Last-First' in the name) have
    %          no pre-stimulus counterpart -> ''.
    %       2) 'During Post-Stimulus' columns have no pre-stimulus counterpart -> ''.
    %       3) Already-pre-stimulus names are returned unchanged.
    %       4) 'During Active Stimulus' -> 'During Pre-Stimulus'.
    %       5) 'During Stimulus' -> 'During Pre-Stimulus'.
    %       6) 'During <stimLabel>' -> 'During Pre-Stimulus' (longest labels
    %          first; the label must be followed by a space, '(', or end).
    %       7) If no rule applies -> ''.
    %
    %   Note that multiple stimulus-specific columns can map to the same
    %   aggregate pre-stimulus name (e.g., 'Speed Mean During A' and
    %   'Speed Mean During B' both map to 'Speed Mean During Pre-Stimulus');
    %   callers that need distinct pairs should treat the mapped name as a key
    %   into the pre-stimulus table rather than as a unique identifier.

    arguments
        nameIn {mustBeTextScalar}
        stimLabels {validator.mustBeTextOrEmpty} = {}
    end

    s = char(string(nameIn));

    if contains(s, ' Bout') || contains(s, 'Last-First')
        nameOut = '';
        return;
    end

    if contains(s, 'During Post-Stimulus')
        nameOut = '';
        return;
    end

    if contains(s, 'During Pre-Stimulus')
        nameOut = s;
        return;
    end

    if contains(s, 'During Active Stimulus')
        nameOut = strrep(s, 'During Active Stimulus', 'During Pre-Stimulus');
        return;
    end

    if contains(s, 'During Stimulus')
        nameOut = strrep(s, 'During Stimulus', 'During Pre-Stimulus');
        return;
    end

    labels = string(stimLabels);
    [label, kind] = cohort.internal.stimContextInColumn(s, stimLabels);
    if strlength(label) > 0 && kind == "period"
        nameOut = strrep(s, 'During ' + label, 'During Pre-Stimulus');
        return;
    end

    nameOut = '';
end
