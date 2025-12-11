function [header, datatable, units] = loadDLCTrackingCSV(filePath, kvargs)
    %%LOADDLCTRACKINGCSV Load DeepLabCut tracking data from a CSV file
    %
    %   Inputs:
    %       filePath - Path to the DeepLabCut CSV file.
    %
    %   Name-Value Pair Arguments:
    %       MetadataTable - Table containing metadata information.
    %
    %   Outputs:
    %       header - Struct containing header information from the CSV file.
    %       datatable - Table containing the tracking data.
    %       units - Struct containing units information from the CSV file.

    arguments
        filePath {mustBeFile}
        
        kvargs.MetadataTable table = table(); %#ok<INUSA>
        kvargs.HeaderOnly (1,1) logical = false;
    end

    % Scan the first character of each line to determine header lines
    % The first line whose first character is "0" indicates the start of data
    % Read only the first character of each line for efficiency
    fid = fopen(filePath, 'r');
    lineIdx = 0;
    dataStartLine = 0;

    while ~feof(fid)
        line = fgetl(fid);
        lineIdx = lineIdx + 1;
        if startsWith(line, '0')
            dataStartLine = lineIdx - 1; % Header lines are before this line
            break;
        end
    end
    fclose(fid);
    if dataStartLine == 0
        error('io:dlc:loadDLCTrackingCSV:NoDataFound', 'No data lines found in the specified DLC CSV file.');
    end

    % Read header lines
    headerLines = cell(dataStartLine, 1);
    fid = fopen(filePath, 'r');
    for i = 1:dataStartLine
        headerLines{i} = fgetl(fid);
    end
    fclose(fid);
    
    dataheader = struct();
    colHeaders = cell(0,0);
    % Comma separated values, the first element is the key, get the unique values for each header line (stable) and save to struct
    for i = 1:dataStartLine
        parts = strsplit(headerLines{i}, ',');
        key = strtrim(parts{1});
        % unique values
        values = strtrim(parts(2:end));
        uvalues = unique(values, 'stable');
        if length(uvalues) > 1
            colHeaders(size(colHeaders, 1) + 1, 1:length(values)) = values;
        end
        dataheader.(key) = uvalues;
    end

    % Join the colHeaders into a single row of column headers with " |> "
    colHeaderStrs = cell(1, size(colHeaders, 2)+1);
    colHeaderStrs{1} = 'Frame';
    for j = 1:size(colHeaders, 2)
        colHeaderStrs{j+1} = strjoin(colHeaders(:,j), ' |> ');
    end


    [parent, thisCSVname, ~] = fileparts(filePath);
    thisCSVname = char(thisCSVname);
    % This csv file name can be split at the last "DLC_" occurrence to get the video file name
    dlcIdx = strfind(thisCSVname, 'DLC_');
    if isempty(dlcIdx)
        videoFileName = thisCSVname;
    else
        videoFileName = thisCSVname(1:dlcIdx(end)-1);
    end
    % look in the csv ../ folder to find the video file with matching name and known video extensions, grab the actual extension of the file
    videoExtensions = {'.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.3gp'};
    videoFilePath = "";
    for i = 1:length(videoExtensions)
        candidatePath = fullfile(fileparts(parent), strcat(videoFileName, videoExtensions{i}));
        if isfile(candidatePath)
            videoFilePath = candidatePath;
            break;
        end
    end

    trialName = videoFileName;
    arenaName = "Arena 1"; % default arena name to match Ethovision convention
    if contains(videoFileName, " @ ")
        parts = strsplit(videoFileName, " @ ");
        trialName = parts{1};
        arenaName = parts{2};
    end

    header = configureDictionary("string","string");
    header("Video file") = videoFilePath;
    header("Trial name") = trialName;
    header("Arena name") = arenaName;

    [~, experimentName] = fileparts(fileparts(fileparts(parent)));
    header("Experiment") = experimentName;

    dataheaderJson = jsonencode(dataheader);
    header("DLC data header jsonencode") = dataheaderJson;

    if kvargs.HeaderOnly
        datatable = table();
        units = configureDictionary("string","string");
        return;
    end


    % Read data table
    opts = detectImportOptions(filePath, 'NumHeaderLines', dataStartLine, 'Delimiter', ',', 'ReadVariableNames', false);
    datatable = readtable(filePath, opts);
    if width(datatable) ~= length(colHeaderStrs)
        error('io:dlc:loadDLCTrackingCSV:ColumnMismatch', 'Number of columns in data table does not match number of column headers parsed from header.');
    end
    datatable.Properties.VariableNames = colHeaderStrs;

    units = dictionary(string(colHeaderStrs), repmat("", size(colHeaderStrs)));
    pxCols = contains(colHeaderStrs, '|> x') | contains(colHeaderStrs, '|> y') | contains(colHeaderStrs, '|> z');
    for i = 1:length(colHeaderStrs)
        if pxCols(i)
            units(colHeaderStrs{i}) = "px";
        end
    end
end