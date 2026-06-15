function [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = initCommonColumns(nRowsEstimate)
    mouseIdCol = repmat({''}, nRowsEstimate, 1);
    geneCol = repmat({''}, nRowsEstimate, 1);
    cageCodeCol = repmat({''}, nRowsEstimate, 1);
    geneIdCol = repmat({''}, nRowsEstimate, 1);
    sexCol = repmat({''}, nRowsEstimate, 1);
    genotypeCol = repmat({''}, nRowsEstimate, 1);
    litterCol = repmat({''}, nRowsEstimate, 1);
    toeIdCol = repmat({''}, nRowsEstimate, 1);
    dobCol = repmat({''}, nRowsEstimate, 1);
    ageCol = nan(nRowsEstimate, 1);
    stimProtocolCol = repmat({''}, nRowsEstimate, 1);
end
