function standardizedTables = subsetByStimBlock(standardizedTables, period)
    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        period {mustBeMember(period, {'stimulus', 'pre-stimulus', 'post-stimulus'})} = 'stimulus'
    end

    for tableIndex = 1:length(standardizedTables)
        stimPeriodTable = standardizedTables(tableIndex).centerpointData;
        if isempty(stimPeriodTable) || ~ismember('Stimulus name', stimPeriodTable.Properties.VariableNames)
            continue;
        end

        stimNames = string(stimPeriodTable{:, 'Stimulus name'});
        stimNames = strtrim(stimNames);

        switch period
            case 'stimulus'
                keepMask = ~(strcmpi(stimNames, "NONE | Pre-Stimulus") | strcmpi(stimNames, "NONE | Post-Stimulus"));
            case 'pre-stimulus'
                keepMask = strcmpi(stimNames, "NONE | Pre-Stimulus");
            case 'post-stimulus'
                keepMask = strcmpi(stimNames, "NONE | Post-Stimulus");
            otherwise
                error('Unexpected stim block period: %s', period);
        end

        standardizedTables(tableIndex).centerpointData = stimPeriodTable(keepMask, :);
    end

end