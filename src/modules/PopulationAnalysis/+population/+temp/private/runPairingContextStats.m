function stats = runPairingContextStats(progressionStats, mergedTable, metricType, kvargs)
    %%RUNPAIRINGCONTEXTSTATS Analyze Normal-conditioned progression by pairing context
    %
    % Tests whether the Normal stimulus differs when paired with other stimulus A vs B,
    % within each strain and across strains.

    arguments
        progressionStats (1,1) struct
        mergedTable struct {mustBeNonempty}
        metricType (1,1) string {mustBeMember(metricType, ["state", "distance"])}

        kvargs.TimeBinMode (1,1) string {mustBeMember(kvargs.TimeBinMode, ["numeric", "categorical"])} = "numeric"
        kvargs.IncludeMovementCovariate (1,1) logical = true
        kvargs.RandomSlope (1,1) logical = false
        kvargs.Verbose (1,1) logical = true
    end

    if ~isfield(progressionStats, 'longTable') || ~istable(progressionStats.longTable)
        error('runPairingContextStats:missingLongTable', 'progressionStats.longTable is required.');
    end

    longTbl = progressionStats.longTable;
    if isempty(longTbl)
        stats = emptyPairingStats(metricType);
        return;
    end

    normalStimLabel = string(mergedTable(1).stimuliSorted{1});
    pairContexts = strings(numel(mergedTable), 1);
    for i = 1:numel(mergedTable)
        pairContexts(i) = string(mergedTable(i).stimuliSorted{2});
    end

    pairTbl = longTbl(longTbl.Stimulus == normalStimLabel, :);
    if isempty(pairTbl)
        error('runPairingContextStats:noNormalRows', 'No Normal rows found for pairing-context analysis.');
    end

    pairTbl.PairingContext = categorical(pairContexts(pairTbl.StimsetIdx));
    pairTbl.PairingContext = reordercats(pairTbl.PairingContext, categories(pairTbl.PairingContext));

    [withinStrainSummary, withinStrainDetails] = fitWithinStrainModels(pairTbl, metricType, kvargs.TimeBinMode, kvargs.IncludeMovementCovariate, kvargs.RandomSlope);
    [crossStrainSummary, crossStrainDetails] = fitCrossStrainModel(pairTbl, metricType, kvargs.TimeBinMode, kvargs.IncludeMovementCovariate, kvargs.RandomSlope);
    [slopeTable, slopeWithinSummary, slopeCrossSummary, slopeWithinDetails, slopeCrossDetails] = fitPairingSlopeModels(pairTbl, metricType, kvargs.IncludeMovementCovariate);

    stats = struct();
    stats.metricType = metricType;
    stats.longTable = pairTbl;
    stats.withinStrainSummary = withinStrainSummary;
    stats.crossStrainSummary = crossStrainSummary;
    stats.withinStrainDetails = withinStrainDetails;
    stats.crossStrainDetails = crossStrainDetails;
    stats.slopeTable = slopeTable;
    stats.slopeWithinSummary = slopeWithinSummary;
    stats.slopeCrossSummary = slopeCrossSummary;
    stats.slopeWithinDetails = slopeWithinDetails;
    stats.slopeCrossDetails = slopeCrossDetails;
    stats.pairingSummary = vertcat(withinStrainSummary, crossStrainSummary, slopeWithinSummary, slopeCrossSummary);

    if kvargs.Verbose
        fprintf('\n========== %s pairing-context stats ==========' , upper(char(metricType)));

        fprintf('\nWithin-strain trajectory formulas:\n');
        for di = 1:numel(withinStrainDetails)
            fprintf('  %s: %s\n', withinStrainDetails(di).Scope, string(withinStrainDetails(di).Formula));
        end
        fprintf('\nCross-strain trajectory formula:\n');
        fprintf('  %s: %s\n', crossStrainDetails.Scope, string(crossStrainDetails.Formula));

        fprintf('\nWithin-strain slope formulas:\n');
        for di = 1:numel(slopeWithinDetails)
            fprintf('  %s: %s\n', slopeWithinDetails(di).Scope, string(slopeWithinDetails(di).Formula));
        end
        fprintf('\nCross-strain slope formula:\n');
        fprintf('  %s: %s\n', slopeCrossDetails.Scope, string(slopeCrossDetails.Formula));

        fprintf('\nWithin-strain pairing model terms:\n');
        disp(withinStrainSummary);
        fprintf('\nCross-strain pairing model terms:\n');
        disp(crossStrainSummary);
        fprintf('\nSlope model terms:\n');
        disp(vertcat(slopeWithinSummary, slopeCrossSummary));
    end
end

function stats = emptyPairingStats(metricType)
    stats = struct(...
        'metricType', metricType, ...
        'longTable', table(), ...
        'withinStrainSummary', table(), ...
        'crossStrainSummary', table(), ...
        'withinStrainDetails', struct(), ...
        'crossStrainDetails', struct(), ...
        'slopeTable', table(), ...
        'slopeWithinSummary', table(), ...
        'slopeCrossSummary', table(), ...
        'slopeWithinDetails', struct(), ...
        'slopeCrossDetails', struct(), ...
        'pairingSummary', table());
end

function [summaryTbl, details] = fitWithinStrainModels(pairTbl, metricType, timeBinMode, includeMovementCov, randomSlope)
    summaryTbl = table();
    details = struct('Scope', {}, 'Formula', {}, 'Model', {}, 'Converged', {});
    strainLevels = unique(pairTbl.Strain, 'stable');

    for i = 1:numel(strainLevels)
        strainLevel = strainLevels(i);
        sub = pairTbl(pairTbl.Strain == strainLevel, :);
        [rows, detail] = fitPairingModel(sub, metricType, timeBinMode, includeMovementCov, randomSlope, sprintf('Within-%s', string(strainLevel)), false);
        summaryTbl = [summaryTbl; rows]; %#ok<AGROW>
        details(end+1) = detail; %#ok<AGROW>
    end
end

function [summaryTbl, detail] = fitCrossStrainModel(pairTbl, metricType, timeBinMode, includeMovementCov, randomSlope)
    [summaryTbl, detail] = fitPairingModel(pairTbl, metricType, timeBinMode, includeMovementCov, randomSlope, 'Cross-Strain', true);
end

function [summaryRows, detail] = fitPairingModel(sub, metricType, timeBinMode, includeMovementCov, randomSlope, scopeLabel, includeStrain)
    detail = struct('Scope', scopeLabel, 'Formula', "", 'Model', [], 'Converged', false);
    summaryRows = table();

    if isempty(sub)
        return;
    end

    sub = sub(isfinite(sub.Progression) & isfinite(sub.BinMeanTime), :);
    if height(sub) < 6
        return;
    end

    sub.Animal = categorical(sub.Animal);
    sub.Strain = categorical(sub.Strain);
    sub.PairingContext = categorical(sub.PairingContext);

    if timeBinMode == "numeric"
        sub.TimeBin = double(sub.BinIdx);
    else
        sub.TimeBin = categorical(sub.BinIdx);
    end

    fixedParts = {'PairingContext * TimeBin'};
    if includeStrain && numel(categories(sub.Strain)) > 1
        fixedParts = {'Strain * PairingContext * TimeBin'};
    end

    useMovement = false;
    if includeMovementCov && ismember('MovementCovariate', sub.Properties.VariableNames)
        v = sub.MovementCovariate;
        finiteMask = isfinite(v);
        if any(finiteMask)
            vFill = v;
            vFill(~finiteMask) = mean(v(finiteMask), 'omitnan');
            if std(vFill, 0, 'omitnan') > 0
                sub.MovementCovariateZ = (vFill - mean(vFill, 'omitnan')) ./ std(vFill, 0, 'omitnan');
                useMovement = true;
            end
        end
    end
    if useMovement
        fixedParts{end+1} = 'MovementCovariateZ'; %#ok<AGROW>
    end

    randomPart = '(1 | Animal)';
    if randomSlope && timeBinMode == "numeric"
        randomPart = '(1 + TimeBin | Animal)';
    end

    formula = sprintf('Progression ~ %s + %s', strjoin(fixedParts, ' + '), randomPart);
    lme = [];
    converged = false;
    usedFormula = formula;
    try
        lme = fitlme(sub, formula, 'FitMethod', 'REML');
        converged = true;
    catch
        if randomSlope
            usedFormula = sprintf('Progression ~ %s + (1 | Animal)', strjoin(fixedParts, ' + '));
            try
                lme = fitlme(sub, usedFormula, 'FitMethod', 'REML');
                converged = true;
            catch
                converged = false;
            end
        end
    end

    detail.Formula = usedFormula;
    detail.Model = lme;
    detail.Converged = converged;

    if ~converged || isempty(lme)
        return;
    end

    summaryRows = collectModelTermSummary(lme, metricType, scopeLabel, sub.StimsetLabel(1), scopeLabel);
end

function summaryTbl = collectModelTermSummary(lme, metricType, scopeLabel, stimsetLabel, analysisLabel)
    coef = lme.Coefficients;
    ci = coefCI(lme);
    termNames = string(coef.Name);

    keep = false(size(termNames));
    for i = 1:numel(termNames)
        tn = termNames(i);
        keep(i) = contains(tn, 'PairingContext_') || contains(tn, 'PairingContext:TimeBin') || contains(tn, 'TimeBin:PairingContext') || contains(tn, 'Strain_');
    end

    rows = table();
    for i = find(keep)'
        rows = [rows; table( ...
            string(metricType), string(scopeLabel), string(stimsetLabel), string(analysisLabel), string(termNames(i)), ...
            coef.Estimate(i), ci(i,1), ci(i,2), coef.pValue(i), ...
            'VariableNames', {'Metric','Scope','StimsetLabel','Analysis','Term','Estimate','CILow','CIHigh','pValue'})]; %#ok<AGROW>
    end
    summaryTbl = rows;
end

function [slopeTable, slopeWithinSummary, slopeCrossSummary, slopeWithinDetails, slopeCrossDetails] = fitPairingSlopeModels(pairTbl, metricType, includeMovementCov)
    slopeWithinDetails = struct('Scope', {}, 'Formula', {}, 'Model', {}, 'Converged', {});
    slopeCrossDetails = struct('Scope', {}, 'Formula', {}, 'Model', {}, 'Converged', {});

    slopeRows = table();
    stimsetList = unique(pairTbl.StimsetIdx(:))';
    for stimsetIdx = stimsetList
        subStim = pairTbl(pairTbl.StimsetIdx == stimsetIdx, :);
        if isempty(subStim)
            continue;
        end

        animals = unique(subStim.Animal, 'stable');
        pairContexts = unique(subStim.PairingContext, 'stable');
        for ai = 1:numel(animals)
            for ci = 1:numel(pairContexts)
                q = subStim(subStim.Animal == animals(ai) & subStim.PairingContext == pairContexts(ci), :);
                if isempty(q)
                    continue;
                end
                q = sortrows(q, 'BinIdx');
                x = q.BinMeanTime;
                y = q.Progression;
                valid = isfinite(x) & isfinite(y);
                x = x(valid);
                y = y(valid);
                if numel(x) < 2 || numel(unique(x)) < 2
                    continue;
                end

                p = polyfit(x, y, 1);
                row = table(string(metricType), double(stimsetIdx), string(q.StimsetLabel(1)), string(q.Strain(1)), ...
                    string(q.PairingContext(1)), string(q.Animal(1)), p(1), numel(x), mean(x, 'omitnan'), ...
                    'VariableNames', {'Metric','StimsetIdx','StimsetLabel','Strain','PairingContext','Animal','Slope','NSupport','MeanTime'});
                slopeRows = [slopeRows; row]; %#ok<AGROW>
            end
        end
    end

    slopeTable = slopeRows;
    if isempty(slopeTable)
        slopeWithinSummary = table();
        slopeCrossSummary = table();
        return;
    end

    slopeWithinSummary = table();
    slopeCrossSummary = table();

    strainLevels = unique(slopeTable.Strain, 'stable');
    for i = 1:numel(strainLevels)
        strainLevel = strainLevels(i);
        sub = slopeTable(slopeTable.Strain == strainLevel, :);
        [rows, detail] = fitSlopeModel(sub, metricType, includeMovementCov, sprintf('Within-%s', string(strainLevel)), false);
        slopeWithinDetails(end+1) = detail; %#ok<AGROW>
        slopeWithinSummary = [slopeWithinSummary; rows]; %#ok<AGROW>
    end

    [slopeCrossSummary, detail] = fitSlopeModel(slopeTable, metricType, includeMovementCov, 'Cross-Strain', true);
    slopeCrossDetails(end+1) = detail; %#ok<AGROW>
end

function [summaryRows, detail] = fitSlopeModel(sub, metricType, includeMovementCov, scopeLabel, includeStrain)
    detail = struct('Scope', scopeLabel, 'Formula', "", 'Model', [], 'Converged', false);
    summaryRows = table();

    if isempty(sub) || height(sub) < 4
        return;
    end

    sub.Animal = categorical(sub.Animal);
    sub.Strain = categorical(sub.Strain);
    sub.PairingContext = categorical(sub.PairingContext);

    fixedParts = {'PairingContext'};
    if includeStrain && numel(categories(sub.Strain)) > 1
        fixedParts = {'Strain * PairingContext'};
    end

    useMovement = false;
    if includeMovementCov && ismember('MovementCovariate', sub.Properties.VariableNames)
        v = sub.MovementCovariate;
        finiteMask = isfinite(v);
        if any(finiteMask)
            vFill = v;
            vFill(~finiteMask) = mean(v(finiteMask), 'omitnan');
            if std(vFill, 0, 'omitnan') > 0
                sub.MovementCovariateZ = (vFill - mean(vFill, 'omitnan')) ./ std(vFill, 0, 'omitnan');
                useMovement = true;
            end
        end
    end
    if useMovement
        fixedParts{end+1} = 'MovementCovariateZ'; %#ok<AGROW>
    end

    formula = sprintf('Slope ~ %s + (1 | Animal)', strjoin(fixedParts, ' + '));
    lme = [];
    converged = false;
    try
        lme = fitlme(sub, formula, 'FitMethod', 'REML');
        converged = true;
    catch
        converged = false;
    end

    detail.Formula = formula;
    detail.Model = lme;
    detail.Converged = converged;

    if ~converged || isempty(lme)
        return;
    end

    summaryRows = collectModelTermSummary(lme, metricType, scopeLabel, sub.StimsetLabel(1), 'Slope');
end
