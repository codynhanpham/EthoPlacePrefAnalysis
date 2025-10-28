function writeEthovisionXlsx(filePath, headers, datatable, units, kvargs)
    %%WRITEETHOVISIONXLSX Write an EthoVision-compatible XLSX file
    %   Given headers, data table, and units, write an EthoVision-compatible XLSX file.
    %   Please be extremely cautious: you may overwrite important data if the filePath already exists.
    %
    %   Inputs:
    %       filePath - The path to save the EthoVision XLSX file
    %       headers - A dictionary of header key-value pairs
    %       datatable - A table containing the data
    %       units - A dictionary of units for each column in the datatable
    %
    %   Name-Value Pair Arguments:
    %       'Overwrite' - (optional) If true, overwrite the existing file. Default is false, which will error if the file already exists.
    %
    %   See also: io.ethovision.loadEthovisionXlsx, io.ethovision.narena

    arguments
        filePath {validator.mustBeValidFilepath}
        headers {mustBeA(headers, 'dictionary')}
        datatable {mustBeA(datatable, 'table')}
        units {mustBeA(units, 'dictionary')}

        kvargs.Overwrite (1,1) logical = false
    end

    if isfile(filePath) && ~kvargs.Overwrite
        error('File "%s" already exists. To overwrite, set the ''Overwrite'' name-value pair argument to true.', filePath);
    end


    % Prepare header section
    headerKeys = keys(headers);
    headerValues = values(headers);
    headerString = [headerKeys(:), headerValues(:)];

    sheetname = sprintf('Track-%s-%s', headers("Arena name"), headers("Subject name"));

    % Prepare table headers and units
    tableHeaders = keys(units);
    tableUnits = values(units);
    tableHeaders = [tableHeaders(:), tableUnits(:)]';
    tableHeaders = [strings(1, size(tableHeaders,2)); tableHeaders]; % Add an empty row before headers for EthoVision format

    % Write the header first
    writematrix(headerString, filePath, 'Sheet', sheetname, 'WriteMode', 'overwrite');
    % Write the table headers + units
    writematrix(tableHeaders, filePath, 'Sheet', sheetname, 'WriteMode', 'append');
    % Write the data table
    writetable(datatable, filePath, 'Sheet', sheetname, 'WriteMode', 'append');
end