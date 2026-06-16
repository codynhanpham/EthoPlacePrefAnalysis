function [stimPeriodTable, keepMask] = filterStimulusPeriodRows(stimPeriodTable)
%FILTERSTIMULUSPERIODROWS Keep only rows within stimulus period (exclude pre/post window rows).
%   [stimPeriodTable, keepMask] = graphics.filterStimulusPeriodRows(stimPeriodTable)
%
%   This helper removes rows labeled as:
%       - "NONE | Pre-Stimulus"
%       - "NONE | Post-Stimulus"
%   from standardized centerpointData tables that may include pre/post windows.

    keepMask = true(height(stimPeriodTable), 1);
    if isempty(stimPeriodTable) || ~ismember('Stimulus name', stimPeriodTable.Properties.VariableNames)
        return;
    end

    stimNames = string(stimPeriodTable{:, 'Stimulus name'});
    stimNames = strtrim(stimNames);
    isPre = strcmpi(stimNames, "NONE | Pre-Stimulus");
    isPost = strcmpi(stimNames, "NONE | Post-Stimulus");

    keepMask = ~(isPre | isPost);
    stimPeriodTable = stimPeriodTable(keepMask, :);
end
