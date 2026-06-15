function [mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol] = fillCommonColumns(mouseIdCol, geneCol, cageCodeCol, geneIdCol, sexCol, genotypeCol, litterCol, toeIdCol, dobCol, ageCol, stimProtocolCol, rowIdx, md, stimfileName)
    thisMouseId = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'id', ''));
    thisStrain = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'strain', ''));
    thisCageCode = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'cagecode', ''));
    thisSex = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'sex', ''));
    thisGenotype = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'genotype', ''));
    thisDob = cohort.metrics.utils.textToChar(cohort.metrics.utils.getFieldOr(md, 'dob', ''));
    thisAge = cohort.metrics.utils.numericOrNaN(cohort.metrics.utils.getFieldOr(md, 'age', NaN));

    [geneId, litterId, mouseNumber] = cohort.metrics.utils.parseMouseId(thisMouseId, thisStrain);

    mouseIdCol{rowIdx} = thisMouseId;
    geneCol{rowIdx} = thisStrain;
    cageCodeCol{rowIdx} = thisCageCode;
    geneIdCol{rowIdx} = geneId;
    sexCol{rowIdx} = thisSex;
    genotypeCol{rowIdx} = thisGenotype;
    litterCol{rowIdx} = litterId;
    toeIdCol{rowIdx} = mouseNumber;
    dobCol{rowIdx} = thisDob;
    ageCol(rowIdx) = thisAge;
    stimProtocolCol{rowIdx} = cohort.metrics.utils.textToChar(stimfileName);
end
