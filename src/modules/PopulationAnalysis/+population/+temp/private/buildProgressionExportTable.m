function analysisTbl = buildProgressionExportTable(stats)
    %%BUILDPROGRESSIONEXPORTTABLE Build combined TSV export rows for progression analysis.
    %
    % analysisTbl = buildProgressionExportTable(stats)

    arguments
        stats (1,1) struct
    end

    analysisTbl = emptyAnalysisExportTable();

    if isfield(stats, 'state') && isstruct(stats.state)
        analysisTbl = [analysisTbl; addProgressionExportRows(stats.state, "STATE progression stats", "STATE")]; %#ok<AGROW>
    end
    if isfield(stats, 'distance') && isstruct(stats.distance)
        analysisTbl = [analysisTbl; addProgressionExportRows(stats.distance, "DISTANCE progression stats", "DISTANCE")]; %#ok<AGROW>
    end

    if isfield(stats, 'pairing') && isstruct(stats.pairing)
        if isfield(stats.pairing, 'state') && isstruct(stats.pairing.state)
            analysisTbl = [analysisTbl; addPairingExportRows(stats.pairing.state, "STATE pairing-context stats", "state")]; %#ok<AGROW>
        end
        if isfield(stats.pairing, 'distance') && isstruct(stats.pairing.distance)
            analysisTbl = [analysisTbl; addPairingExportRows(stats.pairing.distance, "DISTANCE pairing-context stats", "distance")]; %#ok<AGROW>
        end
    end

    if isfield(stats, 'summary') && istable(stats.summary) && ~isempty(stats.summary)
        analysisTbl = [analysisTbl; addSummaryExportRows(stats.summary, "Progression statistics summary")]; %#ok<AGROW>
    end
end

function rows = addProgressionExportRows(progressStats, description, metricLabel)
    rows = emptyAnalysisExportTable();

    if isfield(progressStats, 'trajectoryDetails') && ~isempty(progressStats.trajectoryDetails)
        rows = [rows; addFormulaRows(progressStats.trajectoryDetails, progressStats, description, metricLabel, "LME-Trajectory", false)]; %#ok<AGROW>
    end
    if isfield(progressStats, 'trajectorySummary') && istable(progressStats.trajectorySummary) && ~isempty(progressStats.trajectorySummary)
        rows = [rows; addModelTermRows(progressStats.trajectorySummary, description, "model_term")]; %#ok<AGROW>
    end
    if isfield(progressStats, 'slopeDetails') && ~isempty(progressStats.slopeDetails)
        rows = [rows; addFormulaRows(progressStats.slopeDetails, progressStats, description, metricLabel, "LME-Slope", false)]; %#ok<AGROW>
    end
    if isfield(progressStats, 'slopeSummary') && istable(progressStats.slopeSummary) && ~isempty(progressStats.slopeSummary)
        rows = [rows; addModelTermRows(progressStats.slopeSummary, description, "model_term")]; %#ok<AGROW>
    end

    if isempty(rows)
        rows = emptyAnalysisExportTable();
    end
end

function rows = addPairingExportRows(pairStats, description, metricLabel)
    rows = emptyAnalysisExportTable();

    if isfield(pairStats, 'withinStrainDetails') && ~isempty(pairStats.withinStrainDetails)
        rows = [rows; addFormulaRows(pairStats.withinStrainDetails, pairStats, description, metricLabel, "", true)]; %#ok<AGROW>
    end
    if isfield(pairStats, 'withinStrainSummary') && istable(pairStats.withinStrainSummary) && ~isempty(pairStats.withinStrainSummary)
        rows = [rows; addModelTermRows(pairStats.withinStrainSummary, description, "model_term")]; %#ok<AGROW>
    end
    if isfield(pairStats, 'crossStrainDetails') && ~isempty(pairStats.crossStrainDetails)
        rows = [rows; addFormulaRows(pairStats.crossStrainDetails, pairStats, description, metricLabel, "", true)]; %#ok<AGROW>
    end
    if isfield(pairStats, 'crossStrainSummary') && istable(pairStats.crossStrainSummary) && ~isempty(pairStats.crossStrainSummary)
        rows = [rows; addModelTermRows(pairStats.crossStrainSummary, description, "model_term")]; %#ok<AGROW>
    end
    if isfield(pairStats, 'slopeWithinDetails') && ~isempty(pairStats.slopeWithinDetails)
        rows = [rows; addFormulaRows(pairStats.slopeWithinDetails, pairStats, description, metricLabel, "Slope", true)]; %#ok<AGROW>
    end
    if isfield(pairStats, 'slopeWithinSummary') && istable(pairStats.slopeWithinSummary) && ~isempty(pairStats.slopeWithinSummary)
        rows = [rows; addModelTermRows(pairStats.slopeWithinSummary, description, "model_term")]; %#ok<AGROW>
    end
    if isfield(pairStats, 'slopeCrossDetails') && ~isempty(pairStats.slopeCrossDetails)
        rows = [rows; addFormulaRows(pairStats.slopeCrossDetails, pairStats, description, metricLabel, "Slope", true)]; %#ok<AGROW>
    end
    if isfield(pairStats, 'slopeCrossSummary') && istable(pairStats.slopeCrossSummary) && ~isempty(pairStats.slopeCrossSummary)
        rows = [rows; addModelTermRows(pairStats.slopeCrossSummary, description, "model_term")]; %#ok<AGROW>
    end

    if isempty(rows)
        rows = emptyAnalysisExportTable();
    end
end

function rows = addSummaryExportRows(summaryTbl, description)
    rows = emptyAnalysisExportTable();

    totalTerms = height(summaryTbl);
    sigTerms = nnz(summaryTbl.Significant);
    rows = [rows; makeExportRow(description, "summary_count", "", NaN, "", "", "", "Total terms", NaN, NaN, NaN, NaN, NaN, NaN, false, "", double(totalTerms), "")]; %#ok<AGROW>
    rows = [rows; makeExportRow(description, "summary_count", "", NaN, "", "", "", "Significant (p<0.05)", NaN, NaN, NaN, NaN, NaN, NaN, false, "", double(sigTerms), "")]; %#ok<AGROW>
    rows = [rows; addSummaryTermRows(summaryTbl, description)]; %#ok<AGROW>
end

function rows = addSummaryTermRows(summaryTbl, description)
    rows = emptyAnalysisExportTable();
    if isempty(summaryTbl)
        return;
    end

    for i = 1:height(summaryTbl)
        metric = string(summaryTbl.Metric(i));
        stimsetIdx = NaN;
        if ismember('StimsetIdx', summaryTbl.Properties.VariableNames)
            stimsetIdx = summaryTbl.StimsetIdx(i);
        end
        stimsetLabel = "";
        if ismember('StimsetLabel', summaryTbl.Properties.VariableNames)
            stimsetLabel = string(summaryTbl.StimsetLabel(i));
        end
        scope = "";
        if ismember('Scope', summaryTbl.Properties.VariableNames)
            scope = string(summaryTbl.Scope(i));
        end
        analysis = "";
        if ismember('Analysis', summaryTbl.Properties.VariableNames)
            analysis = string(summaryTbl.Analysis(i));
        end
        term = string(summaryTbl.Term(i));

        estimate = NaN;
        if ismember('Estimate', summaryTbl.Properties.VariableNames)
            estimate = summaryTbl.Estimate(i);
        elseif ismember('EffectSize', summaryTbl.Properties.VariableNames)
            estimate = summaryTbl.EffectSize(i);
        end

        ciLow = NaN;
        if ismember('CILow', summaryTbl.Properties.VariableNames)
            ciLow = summaryTbl.CILow(i);
        end
        ciHigh = NaN;
        if ismember('CIHigh', summaryTbl.Properties.VariableNames)
            ciHigh = summaryTbl.CIHigh(i);
        end
        pValue = NaN;
        if ismember('pValue', summaryTbl.Properties.VariableNames)
            pValue = summaryTbl.pValue(i);
        end
        significant = false;
        if ismember('Significant', summaryTbl.Properties.VariableNames)
            significant = logical(summaryTbl.Significant(i));
        elseif isfinite(pValue)
            significant = pValue < 0.05;
        end

        ciWidth = NaN;
        if ismember('CIWidth', summaryTbl.Properties.VariableNames)
            ciWidth = summaryTbl.CIWidth(i);
        elseif isfinite(ciLow) && isfinite(ciHigh)
            ciWidth = ciHigh - ciLow;
        end
        absEffect = abs(estimate);

        rows = [rows; makeExportRow(description, "summary_term", metric, stimsetIdx, stimsetLabel, scope, analysis, term, ...
            estimate, ciLow, ciHigh, ciWidth, absEffect, pValue, significant, "", NaN, "")]; %#ok<AGROW>
    end
end

function rows = addModelTermRows(summaryTbl, description, recordType)
    rows = emptyAnalysisExportTable();
    if isempty(summaryTbl)
        return;
    end

    for i = 1:height(summaryTbl)
        metric = string(summaryTbl.Metric(i));
        stimsetIdx = NaN;
        if ismember('StimsetIdx', summaryTbl.Properties.VariableNames)
            stimsetIdx = summaryTbl.StimsetIdx(i);
        end
        stimsetLabel = "";
        if ismember('StimsetLabel', summaryTbl.Properties.VariableNames)
            stimsetLabel = string(summaryTbl.StimsetLabel(i));
        end
        scope = "";
        if ismember('Scope', summaryTbl.Properties.VariableNames)
            scope = string(summaryTbl.Scope(i));
        end
        analysis = "";
        if ismember('Analysis', summaryTbl.Properties.VariableNames)
            analysis = string(summaryTbl.Analysis(i));
        end
        term = string(summaryTbl.Term(i));
        estimate = summaryTbl.Estimate(i);
        ciLow = summaryTbl.CILow(i);
        ciHigh = summaryTbl.CIHigh(i);
        pValue = summaryTbl.pValue(i);
        ciWidth = ciHigh - ciLow;
        absEffect = abs(estimate);

        rows = [rows; makeExportRow(description, recordType, metric, stimsetIdx, stimsetLabel, scope, analysis, term, ...
            estimate, ciLow, ciHigh, ciWidth, absEffect, pValue, pValue < 0.05, "", NaN, "")]; %#ok<AGROW>
    end
end

function rows = addFormulaRows(detailStructs, sourceStats, description, metricLabel, analysisLabel, isPairing)
    rows = emptyAnalysisExportTable();
    if isempty(detailStructs)
        return;
    end

    summaryLabel = "";
    if isfield(sourceStats, 'trajectorySummary') && istable(sourceStats.trajectorySummary) && ~isempty(sourceStats.trajectorySummary) && ismember('StimsetLabel', sourceStats.trajectorySummary.Properties.VariableNames)
        summaryLabel = string(sourceStats.trajectorySummary.StimsetLabel(1));
    elseif isfield(sourceStats, 'slopeSummary') && istable(sourceStats.slopeSummary) && ~isempty(sourceStats.slopeSummary) && ismember('StimsetLabel', sourceStats.slopeSummary.Properties.VariableNames)
        summaryLabel = string(sourceStats.slopeSummary.StimsetLabel(1));
    elseif isfield(sourceStats, 'withinStrainSummary') && istable(sourceStats.withinStrainSummary) && ~isempty(sourceStats.withinStrainSummary) && ismember('StimsetLabel', sourceStats.withinStrainSummary.Properties.VariableNames)
        summaryLabel = string(sourceStats.withinStrainSummary.StimsetLabel(1));
    elseif isfield(sourceStats, 'crossStrainSummary') && istable(sourceStats.crossStrainSummary) && ~isempty(sourceStats.crossStrainSummary) && ismember('StimsetLabel', sourceStats.crossStrainSummary.Properties.VariableNames)
        summaryLabel = string(sourceStats.crossStrainSummary.StimsetLabel(1));
    end

    for i = 1:numel(detailStructs)
        detail = detailStructs(i);
        stimsetIdx = NaN;
        if isfield(detail, 'StimsetIdx')
            stimsetIdx = detail.StimsetIdx;
        end

        if isPairing
            scope = "";
            if isfield(detail, 'Scope')
                scope = string(detail.Scope);
            end
            analysis = scope;
        else
            scope = "";
            if isfinite(stimsetIdx)
                scope = sprintf('Stimset %d', stimsetIdx);
            end
            analysis = analysisLabel;
        end

        notes = "";
        if isfield(detail, 'Converged')
            notes = string(sprintf('Converged=%d', logical(detail.Converged)));
        end

        rows = [rows; makeExportRow(description, "formula", metricLabel, stimsetIdx, summaryLabel, scope, analysis, "ModelFormula", ...
            NaN, NaN, NaN, NaN, NaN, NaN, false, string(detail.Formula), NaN, notes)]; %#ok<AGROW>
    end
end

function tbl = emptyAnalysisExportTable()
    tbl = table('Size', [0 18], ...
        'VariableTypes', {'string','string','string','double','string','string','string','string','double','double','double','double','double','double','logical','string','double','string'}, ...
        'VariableNames', {'Description','RecordType','Metric','StimsetIdx','StimsetLabel','Scope','Analysis','Term','Estimate','CILow','CIHigh','CIWidth','AbsEffect','pValue','Significant','Formula','Value','Notes'});
end

function row = makeExportRow(description, recordType, metric, stimsetIdx, stimsetLabel, scope, analysis, term, ...
    estimate, ciLow, ciHigh, ciWidth, absEffect, pValue, significant, formula, value, notes)

    row = table(string(description), string(recordType), string(metric), double(stimsetIdx), string(stimsetLabel), string(scope), string(analysis), string(term), ...
        double(estimate), double(ciLow), double(ciHigh), double(ciWidth), double(absEffect), double(pValue), logical(significant), string(formula), double(value), string(notes), ...
        'VariableNames', {'Description','RecordType','Metric','StimsetIdx','StimsetLabel','Scope','Analysis','Term','Estimate','CILow','CIHigh','CIWidth','AbsEffect','pValue','Significant','Formula','Value','Notes'});
end
