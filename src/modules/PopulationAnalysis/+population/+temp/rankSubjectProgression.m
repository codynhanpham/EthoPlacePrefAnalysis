function [rankedTbl, componentsLongTbl] = rankSubjectProgression(src, kvargs)
    %%RANKSUBJECTPROGRESSION Rank subjects by progression direction & consistency over time
    %
    %   [rankedTbl, componentsLongTbl] = rankSubjectProgression(src)
    %   [rankedTbl, componentsLongTbl] = rankSubjectProgression(..., Name=Value)
    %
    %   Given either the exported tbl of plotProgressionInTab (TimeBin_N__{x-y%} columns)
    %   or a merged standardizedTables struct (joinStdTableByStim output), computes
    %   per-subject progression scores and ranks subjects by progression magnitude/direction
    %   and consistency of progression over time.
    %
    %   A unique subject is defined by the common headers:
    %       Mouse_ID, Gene, Cage #, Gene_ID, Sex$, Genotype$, Litter, Toe_ID
    %   Each subject is scored per (Stimulus Protocol, Stimulus) pair and combined across
    %   pairs into a per-subject summary + composite rank.
    %
    %   Inputs:
    %       src : exported table from plotProgressionInTab (needs TimeBin_N__ columns and the
    %             common metadata columns), OR a mergedTable struct from joinStdTableByStim.
    %
    %   Name-Value Pair Arguments:
    %       MetricType        : "state" | "distance" - required only for mergedTable input.
    %       BinWidth          : bins of bouts per progression bin (default 1).
    %       MeanWindowFrames  : smoothing window frames at bout start/end (default 15).
    %                           Only used for mergedTable input (tbl is already binned).
    %       ExpectedDirection : optional struct array, one element per Stimulus Protocol:
    %                               .stimfileName                  {mustBeText}
    %                               .sortedExpectedProgressionDir  vector of 1/-1, same length
    %                                                              as that protocol's
    %                                                              order-stable-unique
    %                                                              Stimulus Name sequence
    %                                                              (== stimuliSorted).
    %                           k-th direction applies to k-th stimulus of that protocol.
    %                           Protocols not listed default to +1 (plot convention).
    %                           The scores are computed on
    %                           ExpectedDir(protocol, stim) * Progression.
    %       SortBy            : column name to sort the output by, descending
    %                           (default "CompositeScore"). Can be any per-stim score column
    %                           (e.g. "DeltaEndStart__VBS Normal") or a summary column.
    %       Verbose           : print summary (default true).
    %
    %   Per (subject, protocol, stim) scoring components, computed on direction-adjusted
    %   values v = ExpectedDir(protocol, stim) * Progression over valid (non-NaN) bins.
    %   Positions use the ACTUAL BinIdx values, so NaN gaps are not collapsed
    %   (e.g. valid bins [1 2 3 5] are treated as spanning bins 1..5):
    %       DeltaEndStart      : last valid value - first valid value (>= 2 valid bins)
    %       TheilSenSlope      : median of all pairwise slopes (vj - vi) / (xj - xi)
    %                            against actual bin index x (>= 2 valid bins); robust
    %                            trend magnitude per bin
    %       KendallTau         : Kendall tau of v vs actual bin index (>= 2 valid bins);
    %                            nonparametric monotonic-trend consistency in [-1, 1]
    %       ProgressEfficiency : net-to-gross ratio (vv(end) - vv(1)) / sum(abs(diff(vv))),
    %                            defined 0 when the path length is 0 (>= 2 valid bins);
    %                            1 = perfectly monotonic, ~0 = noisy random walk
    %
    %   Outputs:
    %       rankedTbl : one row per subject, sorted by kvargs.SortBy (descending). Columns:
    %           - SubjectKey and the 8 common headers (Mouse_ID ... Toe_ID)
    %           - Per (protocol, stim) breakdown columns:
    %               DeltaEndStart__{stim}, TheilSenSlope__{stim}, KendallTau__{stim},
    %               ProgressEfficiency__{stim}, NValidBins__{stim}
    %               (stim label is "{stim} @{protocol}" when multiple protocols exist)
    %           - Combined summary: MeanDeltaEndStart, MeanTheilSenSlope,
    %               MeanKendallTau, MeanProgressEfficiency, NPairs
    %           - CompositeScore: PC1 projection of the z-scored 4 summary axes
    %               (missing z imputed to 0; loadings sign-aligned so positive PC1
    %               = better progression), plus PC1VarianceExplained (fraction of
    %               total summary variance carried by PC1)
    %           - Ranks (1 = best; ties -> average): Rank_Composite,
    %               Rank_MeanDeltaEndStart, Rank_MeanTheilSenSlope,
    %               Rank_MeanKendallTau, Rank_MeanProgressEfficiency
    %           - Group (strain) for downstream coloring
    %       componentsLongTbl : tidy long table, one row per (subject, protocol, stim):
    %           SubjectKey, StimulusProtocol, Stimulus, Group, ExpectedDir,
    %           DeltaEndStart, TheilSenSlope, KendallTau, ProgressEfficiency, NValidBins

    arguments
        src {mustBeNonempty}
        kvargs.MetricType (1,1) string {mustBeMember(kvargs.MetricType, ["state", "distance"])} = "distance"
        kvargs.BinWidth (1,1) {mustBePositive, mustBeInteger} = 1
        kvargs.MeanWindowFrames (1,1) {mustBePositive, mustBeInteger} = 15
        kvargs.ExpectedDirection struct = []
        kvargs.SortBy (1,1) string {mustBeTextScalar(kvargs.SortBy)} = "CompositeScore"
        kvargs.Verbose (1,1) logical = true
    end

    %% Normalize input to tidy long form
    [longTbl, ~] = normalizeProgressionInput(src, kvargs.MetricType, ...
        'BinWidth', kvargs.BinWidth, 'MeanWindowFrames', kvargs.MeanWindowFrames);

    %% Per (subject, protocol, stim) scoring (delegated to cohort.metrics)
    componentsLongTbl = cohort.metrics.progressionComponents(longTbl, ...
        'ExpectedDirection', kvargs.ExpectedDirection);

    %% Combined per-subject summary
    subjKeys = string(longTbl.SubjectKey);
    subjList = unique(componentsLongTbl.SubjectKey, 'stable');

    % Common metadata per subject (first occurrence)
    nSubj = numel(subjList);
    meta = struct('Mouse_ID', cell(nSubj,1), 'Gene', cell(nSubj,1), 'CageNo', cell(nSubj,1), ...
        'Gene_ID', cell(nSubj,1), 'SexDollar', cell(nSubj,1), 'GenotypeDollar', cell(nSubj,1), ...
        'Litter', cell(nSubj,1), 'Toe_ID', cell(nSubj,1), 'Group', cell(nSubj,1));

    % Extract common headers from longTbl first rows per subject
    for si = 1:nSubj
        rows = longTbl(subjKeys == subjList(si), :);
        meta(si) = extractSubjectMeta(rows, src);
    end

    %% Per (protocol, stim) breakdown columns
    [breakdownNames, breakdownValues] = buildBreakdownColumns(componentsLongTbl);

    %% Composite score (PC1 of z-scored summary axes)
    summaryDeltaES = nan(nSubj, 1);
    summaryTS      = nan(nSubj, 1);
    summaryTau     = nan(nSubj, 1);
    summaryEff     = nan(nSubj, 1);
    nPairsPerSubject = zeros(nSubj, 1);

    for si = 1:nSubj
        rows = componentsLongTbl(componentsLongTbl.SubjectKey == subjList(si), :);
        summaryDeltaES(si) = mean(rows.DeltaEndStart, 'omitnan');
        summaryTS(si)      = mean(rows.TheilSenSlope, 'omitnan');
        summaryTau(si)     = mean(rows.KendallTau, 'omitnan');
        summaryEff(si)     = mean(rows.ProgressEfficiency, 'omitnan');
        nPairsPerSubject(si) = height(rows);
    end

    zMat = [zScore(summaryDeltaES), zScore(summaryTS), zScore(summaryTau), zScore(summaryEff)];
    zMat(~isfinite(zMat)) = 0;   % impute missing z-scores to the (standardized) mean

    % PC1 via SVD of the z-scored summary matrix
    [~, S, V] = svd(zMat, 'econ');
    totalVar = sum(diag(S).^2);
    pc1Loadings = V(:, 1);
    if totalVar > 0
        pc1VarExplained = S(1, 1)^2 / totalVar;
    else
        pc1VarExplained = 0;
        pc1Loadings = [1; 0; 0; 0];
    end

    % Sign-align PC1 so positive = better progression (anchor on the net-change
    % axis; fall back to the trend-consistency axis if net change has ~0 loading).
    anchor = pc1Loadings(1);
    if abs(anchor) < eps
        anchor = pc1Loadings(3);
    end
    if anchor < 0
        pc1Loadings = -pc1Loadings;
    end

    compositeScore = zMat * pc1Loadings;

    rankComposite = tiedrank(-compositeScore); % 1 = highest composite
    rankDeltaES = tiedrank(-summaryDeltaES);
    rankTS      = tiedrank(-summaryTS);
    rankTau     = tiedrank(-summaryTau);
    rankEff     = tiedrank(-summaryEff);

    %% Assemble ranked table
    rankedTbl = table();
    rankedTbl.('SubjectKey') = subjList;
    rankedTbl.('Mouse_ID')   = arrayfun(@(m) string(m.Mouse_ID), meta);
    rankedTbl.('Gene')       = arrayfun(@(m) string(m.Gene), meta);
    rankedTbl.('Cage #')     = arrayfun(@(m) string(m.CageNo), meta);
    rankedTbl.('Gene_ID')    = arrayfun(@(m) string(m.Gene_ID), meta);
    rankedTbl.('Sex$')       = arrayfun(@(m) string(m.SexDollar), meta);
    rankedTbl.('Genotype$')  = arrayfun(@(m) string(m.GenotypeDollar), meta);
    rankedTbl.('Litter')     = arrayfun(@(m) string(m.Litter), meta);
    rankedTbl.('Toe_ID')     = arrayfun(@(m) string(m.Toe_ID), meta);
    rankedTbl.('Group')      = arrayfun(@(m) string(m.Group), meta);

    rankedTbl = [rankedTbl, array2table(breakdownValues, 'VariableNames', breakdownNames)];

    rankedTbl.('MeanDeltaEndStart') = summaryDeltaES;
    rankedTbl.('MeanTheilSenSlope') = summaryTS;
    rankedTbl.('MeanKendallTau') = summaryTau;
    rankedTbl.('MeanProgressEfficiency') = summaryEff;
    rankedTbl.('NPairs') = nPairsPerSubject;
    rankedTbl.('PC1VarianceExplained') = repmat(pc1VarExplained, nSubj, 1);
    rankedTbl.('CompositeScore') = compositeScore;

    rankedTbl.('Rank_Composite') = rankComposite;
    rankedTbl.('Rank_MeanDeltaEndStart') = rankDeltaES;
    rankedTbl.('Rank_MeanTheilSenSlope') = rankTS;
    rankedTbl.('Rank_MeanKendallTau') = rankTau;
    rankedTbl.('Rank_MeanProgressEfficiency') = rankEff;

    %% Sort
    sortCol = char(kvargs.SortBy);
    if ~ismember(sortCol, rankedTbl.Properties.VariableNames)
        error('rankSubjectProgression:badSortBy', ...
            'SortBy column ''%s'' not found. Available: %s', sortCol, ...
            strjoin(rankedTbl.Properties.VariableNames, ', '));
    end
    rankedTbl = sortrows(rankedTbl, sortCol, 'descend');

    if kvargs.Verbose
        fprintf('\n========== Subject progression ranking ==========\n');
        fprintf('Subjects: %d | Protocol-stim pairs per subject: %d (mean %.1f)\n', ...
            nSubj, size(breakdownNames, 1), mean(nPairsPerSubject));
        disp(headColumns(rankedTbl));
    end
end

%% ------------------------------------------------------------------
function [names, values] = buildBreakdownColumns(componentsLongTbl)
    % Per (protocol, stim) breakdown columns, one column per component.
    % Column name: {Component}__{stim} when single protocol, else {Component}__{stim} @{protocol}
    pairs = unique(table(componentsLongTbl.StimulusProtocol, componentsLongTbl.Stimulus, ...
        'VariableNames', {'P', 'S'}), 'stable');
    nPairs = height(pairs);
    nSubj = numel(unique(componentsLongTbl.SubjectKey, 'stable'));
    nProtocols = numel(unique(componentsLongTbl.StimulusProtocol));

    components = {'DeltaEndStart', 'TheilSenSlope', 'KendallTau', ...
        'ProgressEfficiency', 'NValidBins'};
    nComp = numel(components);

    names = {};
    values = nan(nSubj, nPairs * nComp);
    colIdx = 0;
    subjectList = unique(componentsLongTbl.SubjectKey, 'stable');

    for pi = 1:nPairs
        p = pairs.P(pi);
        s = pairs.S(pi);
        if nProtocols > 1
            stimTag = sprintf('%s @%s', s, p);
        else
            stimTag = char(s);
        end
        rows = componentsLongTbl(componentsLongTbl.StimulusProtocol == p & componentsLongTbl.Stimulus == s, :);

        for ci = 1:nComp
            colIdx = colIdx + 1;
            names{colIdx} = sprintf('%s__%s', components{ci}, stimTag);
            for si = 1:nSubj
                m = strcmp(rows.SubjectKey, subjectList{si});
                if any(m)
                    values(si, colIdx) = rows.(components{ci})(find(m, 1));
                end
            end
        end
    end
end

%% ------------------------------------------------------------------
function meta = extractSubjectMeta(rows, src) %#ok<INUSD>
    % Extract the common metadata for one subject from its longTbl rows.
    % SubjectKey encodes: Mouse_ID | Gene | Cage # | Gene_ID | Sex$ | Genotype$ | Litter | Toe_ID
    meta = struct();
    sk = char(rows.SubjectKey(1));
    % Never collapse delimiters: empty key fields must keep their positions.
    parts = strsplit(sk, '|', 'CollapseDelimiters', false);
    parts(strcmp(parts, '<EMPTY>')) = {''};
    while numel(parts) < 8
        parts{end+1} = ''; %#ok<AGROW>
    end
    meta.Mouse_ID = parts{1};
    meta.Gene = parts{2};
    meta.CageNo = parts{3};
    meta.Gene_ID = parts{4};
    meta.SexDollar = parts{5};
    meta.GenotypeDollar = parts{6};
    meta.Litter = parts{7};
    meta.Toe_ID = parts{8};
    % Group: first-seen group among this subject's rows
    uGroups = unique(string(rows.Group), 'stable');
    meta.Group = char(uGroups(1));
end

%% ------------------------------------------------------------------
function z = zScore(x)
    z = nan(size(x));
    finite = isfinite(x);
    if nnz(finite) < 2
        return;
    end
    sd = std(x(finite), 0, 'omitnan');
    if sd == 0
        z(finite) = 0;
    else
        z(finite) = (x(finite) - mean(x(finite), 'omitnan')) ./ sd;
    end
end

function out = headColumns(T)
    keepCols = {'Mouse_ID', 'Group', 'MeanDeltaEndStart', 'MeanTheilSenSlope', ...
        'MeanKendallTau', 'MeanProgressEfficiency', 'CompositeScore', 'Rank_Composite'};
    keepCols = keepCols(ismember(keepCols, T.Properties.VariableNames));
    out = T(:, keepCols);
end
