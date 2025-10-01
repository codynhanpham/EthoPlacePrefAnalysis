function groupedTable = groupby(metadataTable, groupVars, kvargs)
    %%GROUPBY Groups a metadata table by specified variables and counts occurrences.
    %   All variables in groupVars must be categorical or string arrays.
    %   Remaining variables within a group are converted to cell arrays.
    %
    %   Inputs:
    %       metadataTable - A table containing metadata.
    %       groupVars - A cell array of variable names to group by.
    %
    %   Name-Value Pair Arguments:
    %       'IncludeEmptyGroups' - Logical indicating whether to include groups with zero counts. Default is false.
    %
    %   Outputs:
    %       groupedTable - A table grouped by the specified variables with counts (`GroupCount`) and cell/numeric arrays of the remaining variables.

    arguments
        metadataTable table
        groupVars {mustBeText}

        kvargs.IncludeEmptyGroups (1,1) logical = false
    end

    groupVars = cellstr(groupVars); % Normalize the input for consistency
    tableVars = metadataTable.Properties.VariableNames;

    % All variables to be grouped by must exist in the table
    missing = setdiff(groupVars, tableVars);
    if ~isempty(missing)
        error('The following grouping variables are missing from the table: %s', strjoin(missing, ', '));
    end

    % Remaining variables to be converted to cell arrays
    remainVars = setdiff(tableVars, groupVars);

    % Group the table by the specified variables
    if kvargs.IncludeEmptyGroups
        groupedTable = groupWithEmptyGroups(metadataTable, groupVars, remainVars);
    else
        groupedTable = groupWithoutEmptyGroups(metadataTable, groupVars, remainVars);
    end
end


function groupedTable = groupWithoutEmptyGroups(metadataTable, groupVars, remainVars)
    %GROUPWITHOUTEMPTYGROUPS Group table excluding empty groups
    [groupIdx, groupLabels] = findgroups(metadataTable(:, groupVars));
    
    % Create the result table starting with the unique group combinations
    groupedTable = groupLabels;
    
    groupCounts = splitapply(@numel, groupIdx, groupIdx);
    groupedTable.GroupCount = groupCounts;
    
    % For each remaining variable, collect values into cell arrays
    for i = 1:length(remainVars)
        varName = remainVars{i};
        varData = metadataTable.(varName);
        cellArrays = splitapply(@(x) {x}, varData, groupIdx);
        groupedTable.(varName) = cellArrays;
    end
end

function groupedTable = groupWithEmptyGroups(metadataTable, groupVars, remainVars)
    %GROUPWITHEMPTYGROUPS Group table including empty groups using groupsummary
    % Use groupsummary to get all group combinations including empty ones
    groupedTable = groupsummary(metadataTable, groupVars, 'IncludeEmptyGroups', true);
    
    
    % If no remaining variables, we're done
    if isempty(remainVars)
        return;
    end
    
    % Get non-empty groups data using the same approach as groupWithoutEmptyGroups
    nonEmptyGrouped = groupWithoutEmptyGroups(metadataTable, groupVars, remainVars);
    % groupsummary creates a GroupCount variable automatically!
    nonEmptyGrouped.GroupCount = [];
    
    groupedTable = outerjoin(groupedTable, nonEmptyGrouped, ...
        'Keys', groupVars, ...
        'MergeKeys', true, ...
        'Type', 'left');
end