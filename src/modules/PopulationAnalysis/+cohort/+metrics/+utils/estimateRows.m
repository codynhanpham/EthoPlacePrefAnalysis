function nRowsEstimate = estimateRows(standardizedTables)
    nRowsEstimate = 0;
    for i = 1:length(standardizedTables)
        thisT = standardizedTables(i).centerpointData;
        nRowsEstimate = nRowsEstimate + size(thisT{:, 'X center'}, 2);
    end
end
