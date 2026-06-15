function metadata = ind2metadata(standardizedTables, tableSelector, columnIndices)
    %%IND2METADATA For a standardizedTable, extract the metadata for a given table and column index
    %
    %   metadata = ind2metadata(standardizedTable, tableSelector, columnIndices)
    %
    % Inputs:
    %   standardizedTable: a struct array containing standardized data tables, each with associated metadata (see mustBeStandardizedTable for required fields)
    %   tableSelector: (optional) a numeric index or text scalar to select which table in the standardizedTable to use for metadata extraction. Default: 1 (the first table)
    %   columnIndices: (optional) a vector of numeric indices specifying which columns of the animalMetadata to extract. Default: [] (all columns)
    %
    % Output:
    %   metadata: a struct array containing the selected metadata fields for the specified table and column indices
    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        tableSelector {mustBeTableSelector(standardizedTables, tableSelector)} = 1 % default to first table if not specified
        columnIndices {mustBeColumnIndices(standardizedTables, tableSelector, columnIndices)} = [] % default to all columns if not specified
    end

    tableIndex = mustBeTableSelector(standardizedTables, tableSelector);
    columnIndices = mustBeColumnIndices(standardizedTables, tableSelector, columnIndices);

    keynames = keys(standardizedTables(tableIndex).animalMetadata);
    querykeys = keynames(columnIndices);

    metadata = standardizedTables(tableIndex).animalMetadata(querykeys);
end


function index = mustBeTableSelector(standardizedTables, tableSelector)
    %%MUSTBETABLESELECTOR Validate that the input is a valid table selector for the given standardizedTables
    % 
    % A valid table selector can be either:
    %   - A numeric index corresponding to the table's position in the standardizedTables struct
    %   - A text scalar matching a single 'stimfileName' entry in the standardizedTables struct
    % The function returns the numeric index of the selected table for use in further processing.

    stimtableLength = length(standardizedTables);
    if isnumeric(tableSelector)
        % Validate numeric index
        if ~isscalar(tableSelector) || tableSelector < 1 || tableSelector > stimtableLength
            error('Numeric table selector must be a scalar integer between 1 and %d.', stimtableLength);
        end
        index = tableSelector; % Use the numeric index directly
    elseif isstring(tableSelector) || ischar(tableSelector) || iscellstr(tableSelector)
        % Validate text scalar, allow cellstr of single element for flexibility
        if iscellstr(tableSelector) %#ok<ISCLSTR>
            if length(tableSelector) ~= 1
                error('Text table selector must be a single text scalar or a cell array of one text scalar.');
            end
            tableSelector = tableSelector{1}; % Extract the string from the cell array
        end
        if ~ischar(tableSelector) && ~isstring(tableSelector)
            error('Text table selector must be a text scalar.');
        end
        tableSelector = string(tableSelector); % Convert to string for comparison
        stimfileNames = string({standardizedTables.stimfileName});
        if ~any(stimfileNames == tableSelector)
            error('No table found with stimfileName "%s".', tableSelector);
        end
        index = find(stimfileNames == tableSelector, 1); % Get the index of the matching table
    else
        error('Table selector must be either a numeric index or a text scalar.');
    end
end


function columnIndices = mustBeColumnIndices(standardizedTables, tableSelector, columnIndices)
    %%MUSTBECOLUMNINDICES Validate that the input is a valid set of column indices for the specified table in the standardizedTables
    % 
    % The function checks that the provided column indices are valid for the centerpointData table of the selected standardizedTables entry. If columnIndices is empty, it defaults to all columns.

    tableIndex = mustBeTableSelector(standardizedTables, tableSelector);

    % Columns in standardizedTables are either scalar (one dimension array) or a matrix (two dimension array), so we need to check both cases
    % All data columns in the table are the same shape, though, so we can just check the required column 'X center' to determine the number of columns available
    numColumns = size(standardizedTables(tableIndex).centerpointData.('X center'), 2);

    if isempty(columnIndices)
        columnIndices = 1:numColumns; % Default to all columns
    else
        if ~isnumeric(columnIndices) || any(columnIndices < 1) || any(columnIndices > numColumns) || any(mod(columnIndices, 1) ~= 0)
            error('Column indices must be a vector of positive integers between 1 and %d.', numColumns);
        end
    end
end