function [headers, datatable, units] = loadEthovisionXlsx(filePath, kvargs)
    %LOADETHOVISIONXLSX Load data from an EthoVision exported Excel (.xlsx) file
    %   This function reads an Ethovision Excel file and returns the header
    %   and data table as separate outputs.
    %
    %   Inputs:
    %       filePath - The path to the Excel file
    %
    %   Name-Value Pair Arguments:
    %       - 'ExpectedNumVariables': The number of data columns in the table to expect. Default max is 50, with empty columns removed.
    %
    %
    %   Outputs:
    %       headers    - The headers of the data table, as a string-string dictionary
    %       datatable - The data table after header
    %       units      - The units of the data columns, as a string-string dictionary with keys == datatable column headers
    
    arguments
        filePath {mustBeFile}
        kvargs.ExpectedNumVariables {mustBeNumeric} = 50
    end
    
    % Read the entire header section, this should be < 50 lines most of the time
    header_info = readcell(filePath, 'Range', sprintf('A1:B%d', 50));
    
    % Find the number of header lines from first row
    if ~startsWith(header_info{1,1}, 'Number of header lines')
        error('Unknown EthoVision file format: first cell should start with "Number of header lines:"');
    end
    
    num_header_lines = str2double(header_info{1, 2});
    if isnan(num_header_lines)
        error('Unknown EthoVision file format: number of header lines is not a valid number');
    end
    num_header_lines = num_header_lines - 3;
    
    % Extract actual headers from the loaded block
    header_data = header_info(1:num_header_lines, 1:2);
    headers = dictionary(string(header_data(:,1)), string(header_data(:,2)));
    
    % Skip parsing units and/or datatable if user does not request them
    try
        isTilde = detectOutputSuppression(nargout);
    catch
        isTilde = false(1, nargout); % if cannot detect, assume everything is NOT suppressed
    end

    if isequal(isTilde, [false, true, true])
        datatable = table(); units = configureDictionary("string", "string");
        return;
    end
    
    % Read table headers and units
    header_unit_data = readcell(filePath, 'Range', [num_header_lines + 2, 1, num_header_lines + 3, kvargs.ExpectedNumVariables], 'TextType', 'char');
    
    % Extract table headers and units
    table_headers = header_unit_data(1, :);
    table_headers = table_headers(~cellfun(@anymissing, table_headers));
    numVars = numel(table_headers);
    
    unit_row = header_unit_data(2, 1:numVars);
    units = dictionary(string(table_headers), string(unit_row));
    
    if isequal(isTilde, [false, true, false])
        datatable = table();
        return;
    end

    % Read data table, keeping the original variable names
    datatable = readtable( ...
        filePath, 'DataRange', num_header_lines + 4, ...
        'ReadVariableNames', false ...
    );
    datatable.Properties.VariableNames = string(table_headers);
    datatable = rmmissing(datatable, MinNumMissing=width(datatable));
end