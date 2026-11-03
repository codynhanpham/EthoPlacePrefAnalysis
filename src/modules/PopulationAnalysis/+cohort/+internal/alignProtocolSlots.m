function [alignedGroups, report] = alignProtocolSlots(groups)
    %ALIGNPROTOCOLSLOTS Align the 2 protocol slots of every strain group by stimfileName similarity.
    %
    %   [alignedGroups, report] = cohort.internal.alignProtocolSlots(groups)
    %
    %   groups is the cell array produced by cohort.internal.adaptPipelineInput
    %   (each element a struct with .tables, a 1x2 standardizedTables pair, and
    %   .strainLabel). Slot semantics (table 1 = exploration protocol, table 2
    %   = baseline protocol) are defined by input ORDER, which is only valid
    %   across strains when every group lists the same protocol family in the
    %   same slot. This function canonicalizes each table's stimfileName
    %   (cohort.internal.protocolKey over all joined variations from
    %   cohort.internal.stimfileNameVariants), anchors on the first group, and
    %   reorders any group whose tables match the anchors better when swapped.
    %
    %   report is a table with one row per group: StrainGroup, Slot1, Slot2
    %   (display names), Swapped, Slot1Similarity, Slot2Similarity. A warning
    %   is emitted when a group's best per-slot similarity falls below 0.75
    %   (possible cross-strain protocol mismatch).
    %
    %   See also: cohort.internal.protocolKey, cohort.internal.stimfileNameVariants,
    %       cohort.internal.levenshteinRatio

    arguments
        groups cell {mustBeNonempty}
    end

    alignedGroups = groups;
    nGroups = numel(groups);

    slotKeys = cell(nGroups, 2);
    slotDisplay = strings(nGroups, 2);
    groupLabels = strings(nGroups, 1);
    for g = 1:nGroups
        thisPair = alignedGroups{g}.tables;
        if numel(thisPair) ~= 2
            error('cohort:internal:alignProtocolSlots:WrongTableCount', ...
                'Group %d (%s) must contain exactly 2 standardizedTables.', ...
                g, cohort.internal.textScalar(alignedGroups{g}.strainLabel, 'strainLabel'));
        end
        groupLabels(g) = cohort.internal.textScalar(alignedGroups{g}.strainLabel, 'strainLabel');
        for slot = 1:2
            variants = cohort.internal.stimfileNameVariants(thisPair(slot).stimfileName, 'stimfileName');
            if isempty(variants)
                error('cohort:internal:alignProtocolSlots:EmptyStimfileName', ...
                    'Group %d (%s) table %d has an empty stimfileName.', g, groupLabels(g), slot);
            end
            slotKeys{g, slot} = arrayfun(@cohort.internal.protocolKey, variants);
            slotDisplay(g, slot) = variants(1);
        end
    end

    swapped = false(nGroups, 1);
    swapped(1) = false;
    sim1 = ones(nGroups, 1);
    sim2 = ones(nGroups, 1);

    anchor1 = slotKeys{1, 1};
    anchor2 = slotKeys{1, 2};
    for g = 2:nGroups
        identityScore = setSimilarity(slotKeys{g, 1}, anchor1) + setSimilarity(slotKeys{g, 2}, anchor2);
        swapScore = setSimilarity(slotKeys{g, 1}, anchor2) + setSimilarity(slotKeys{g, 2}, anchor1);

        if swapScore > identityScore
            alignedGroups{g}.tables = alignedGroups{g}.tables([2, 1]);
            swapped(g) = true;
            sim1(g) = setSimilarity(slotKeys{g, 2}, anchor1);
            sim2(g) = setSimilarity(slotKeys{g, 1}, anchor2);
        else
            sim1(g) = setSimilarity(slotKeys{g, 1}, anchor1);
            sim2(g) = setSimilarity(slotKeys{g, 2}, anchor2);
        end

        if min(sim1(g), sim2(g)) < 0.75
            warning('cohort:internal:alignProtocolSlots:LowSimilarity', ...
                ['Group %d (%s): protocol similarity to the first strain group is low ' ...
                '(slot 1: %.2f, slot 2: %.2f). The protocol pairing across strains may be wrong.'], ...
                g, groupLabels(g), sim1(g), sim2(g));
        end
    end

    report = table(groupLabels, slotDisplay(:, 1), slotDisplay(:, 2), swapped, sim1, sim2, ...
        'VariableNames', {'StrainGroup', 'Slot1', 'Slot2', 'Swapped', 'Slot1Similarity', 'Slot2Similarity'});
end


function r = setSimilarity(keysA, keysB)
    % Best pairwise similarity between two sets of protocol keys (joined
    % variations match when ANY of their variations match).
    r = 0;
    for i = 1:numel(keysA)
        for j = 1:numel(keysB)
            r = max(r, cohort.internal.levenshteinRatio(keysA(i), keysB(j)));
        end
    end
end
