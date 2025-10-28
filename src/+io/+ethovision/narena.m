function [n, names] = narena(ethovisionXlsx)
    %NARENA Get the number of arenas in an EthoVision XLSX file
    %
    %   Inputs:
    %       ethovisionXlsx - The path to the Excel file
    %
    %   Outputs:
    %       n - The number of arenas found in the Excel file
    %       names - A cell array of arena names found in the Excel file
    arguments
        ethovisionXlsx {mustBeFile}
    end

    % Read the sheet names from the Excel file
    sheets = sheetnames(ethovisionXlsx);

    % The arena sheets start with "Track-" and has the following format:
    % Track-<ArenaName>-<Subject ID>
    arenaSheets = sheets(startsWith(sheets, 'Track-'));
    
    % Extract between the first and last hyphen to get the arena names
    % Index of first and last hyphen
    hyphensI = strfind(arenaSheets, '-');
    if isscalar(arenaSheets)
        arenaSheets = char(arenaSheets);
        first = hyphensI(1);
        last = hyphensI(end);
        names = {arenaSheets(first+1:last-1)};
        n = 1;
        return;
    else
        first = cellfun(@(x) x(1), hyphensI);
        last = cellfun(@(x) x(end), hyphensI);
    end
    arenaNames = cellfun(@(s, f, l) s(f+1:l-1), arenaSheets, num2cell(first), num2cell(last), 'UniformOutput', false);
    arenaNames = unique(arenaNames, 'stable');
    n = numel(arenaNames);
    names = arenaNames;
end