function summary = summarizeProgressionStats(statsStruct)
    %%SUMMARIZEPROGRESSIONSTATS Build compact cross-metric summary table and print readout.
    %
    % summary = summarizeProgressionStats(statsStruct)
    %
    % Input:
    %   statsStruct : struct with fields such as stats.state / stats.distance,
    %                 where each field is output of runProgressionStats.

    arguments
        statsStruct (1,1) struct
    end

    metricFields = fieldnames(statsStruct);
    allRows = table();

    for fi = 1:numel(metricFields)
        fname = metricFields{fi};
        s = statsStruct.(fname);
        if ~isstruct(s)
            continue;
        end

        parts = {};
        if isfield(s, 'trajectorySummary') && istable(s.trajectorySummary) && ~isempty(s.trajectorySummary)
            parts{end+1} = s.trajectorySummary; %#ok<AGROW>
        end
        if isfield(s, 'slopeSummary') && istable(s.slopeSummary) && ~isempty(s.slopeSummary)
            parts{end+1} = s.slopeSummary; %#ok<AGROW>
        end
        if isempty(parts)
            continue;
        end

        metricRows = vertcat(parts{:});
        allRows = [allRows; metricRows]; %#ok<AGROW>
    end

    if isempty(allRows)
        summary = table();
        fprintf('\n========== Progression statistics summary ==========' );
        fprintf('\nNo model terms available for summary.\n');
        return;
    end

    % Derived columns for compact readout
    effectSize = allRows.Estimate;
    ciWidth = allRows.CIHigh - allRows.CILow;
    absEffect = abs(effectSize);
    sigFlag = allRows.pValue < 0.05;

    summary = table(allRows.Metric, allRows.StimsetIdx, allRows.StimsetLabel, allRows.Analysis, allRows.Term, ...
        effectSize, allRows.CILow, allRows.CIHigh, ciWidth, absEffect, allRows.pValue, sigFlag, ...
        'VariableNames', {'Metric','StimsetIdx','StimsetLabel','Analysis','Term', ...
        'EffectSize','CILow','CIHigh','CIWidth','AbsEffect','pValue','Significant'});

    % Sort for readability: stimset, metric, analysis, then strongest effects first.
    summary = sortrows(summary, {'StimsetIdx','Metric','Analysis','AbsEffect'}, {'ascend','ascend','ascend','descend'});

    fprintf('\n========== Progression statistics summary ==========' );
    fprintf('\nTotal terms: %d | Significant (p<0.05): %d\n', height(summary), nnz(summary.Significant));

    for stimsetIdx = unique(summary.StimsetIdx(:))'
        sub = summary(summary.StimsetIdx == stimsetIdx, :);
        if isempty(sub)
            continue;
        end
        fprintf('\n[Stimset %d: %s]\n', stimsetIdx, string(sub.StimsetLabel(1)));

        keyTerms = sub(contains(sub.Term, 'Strain_') | contains(sub.Term, 'TimeBin:Strain_') | contains(sub.Term, 'Strain_:TimeBin'), :);
        if isempty(keyTerms)
            keyTerms = sub;
        end

        nShow = min(8, height(keyTerms));
        disp(keyTerms(1:nShow, {'Metric','Analysis','Term','EffectSize','CILow','CIHigh','pValue','Significant'}));
    end
end
