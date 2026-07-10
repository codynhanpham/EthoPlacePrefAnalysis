function plotProgressionFromSummaryProgressionTable()
    %%PLOTPROGRESSIONFROMSUMMARYPROGRESSIONTABLE Plot a progression over time from a summary progression table CSV.
    % This is mainly a re-plot/QC/downstream consumer of plotProgressionInTab.m output table
    % The goal is to replicate the same progression plots as in plotProgressionInTab.m, exactly as it was binned and windowed by plotProgressionInTab.m

    CSV = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/In-House/Mecp2/Male Mecp2 KO vs. C57 WT/outputs/mecp2_pilot_stats_20260625_110826/distance_progression_table.csv";

    SHOW_DATA_POINTS = false;
    BIN_WIDTH = 6;
    MEAN_WINDOW_FRAMES = 30;
    METRIC_TYPE = "distance"; % "state" or "distance"
    Y_LIM = [-0.4, 0.4];
    SAME_Y_LIM = true;

    %% Read CSV
    T = readtable(CSV, 'TextType', 'string');

    %% Identify TimeBin columns and parse their labels
    varNames = T.Properties.VariableNames;
    binColMask = startsWith(varNames, 'TimeBin_');
    binColNames = varNames(binColMask);
    nBins = numel(binColNames);

    binLabels = cell(nBins, 1);
    binNumericX = (1:nBins)';
    for bi = 1:nBins
        % Column name format: TimeBin_{i}__{perc_range%}
        parts = split(binColNames{bi}, '__');
        if numel(parts) >= 2
            binLabels{bi} = char(parts{2});
        else
            binLabels{bi} = sprintf('Bin %d', bi);
        end
    end

    %% Metric-dependent ylabel
    switch METRIC_TYPE
        case "state"
            ylabelStr = sprintf('State Progression Score \n(Positive = moved toward active stimulus; \nNegative = moved away)');
        case "distance"
            ylabelStr = sprintf('Distance-from-Midline Progression \n(Positive = moved toward active stimulus; \nNegative = moved away)');
    end

    %% Determine stimsets, stimuli, and groups
    stimsetIdxs = unique(T.StimsetIdx, 'stable')';
    nstimsets = numel(stimsetIdxs);

    % Collect all unique groups across the table to assign colors.
    % Group column holds the strain name (set by plotProgressionInTab).
    allGroups = unique(T.Group, 'stable')';
    nGroups = numel(allGroups);
    groupColors = cell(nGroups, 1);
    for gi = 1:nGroups
        groupColors{gi} = graphics.strainColorMap(char(allGroups(gi)));
    end

    % Line styles: first stimulus = solid, others cycle through dashed/dotted
    NORMAL_LINE_STYLE = '-';
    OTHER_LINE_STYLE = {'-.', '--', ':'};

    %% Create figure + tiledlayout (one tile per stimset, single row)
    f = figure('Name', sprintf('Progression from %s', METRIC_TYPE), ...
        'Position', [100, 100, 900, 500]);
    ncols = min(nstimsets, 2);
    nrows = ceil(nstimsets / ncols);
    tlo = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');

    allAxes = gobjects(0);

    for si = 1:nstimsets
        stimsetIdx = stimsetIdxs(si);
        sub = T(T.StimsetIdx == stimsetIdx, :);

        % Unique stimuli in this stimset (preserve order of first appearance)
        stimNames = unique(sub.StimulusName, 'stable')';
        nStims = numel(stimNames);

        % Groups present in this stimset
        stimsetGroups = unique(sub.Group, 'stable')';
        nStimsetGroups = numel(stimsetGroups);

        % Strain names for title
        if nStimsetGroups >= 2
            titleStr = sprintf('[%s]\n%s vs %s', strjoin(stimNames, ' / '), ...
                char(stimsetGroups{1}), char(stimsetGroups{2}));
        else
            titleStr = sprintf('[%s]\n%s', strjoin(stimNames, ' / '), ...
                char(stimsetGroups{1}));
        end

        a = nexttile(tlo, si);
        hold(a, 'on');
        allAxes(end+1) = a; %#ok<AGROW>

        knownOtherStimLineStyles = configureDictionary('char', 'char');
        lineHandles = [];
        lineLabels = {};
        scatterKeys = {};
        scatterData = struct();

        for gi = 1:nStimsetGroups
            grpName = char(stimsetGroups{gi});
            grpColor = graphics.strainColorMap(grpName);

            grpRows = sub(sub.Group == stimsetGroups{gi}, :);

            for stimIdx = 1:nStims
                stimName = char(stimNames{stimIdx});
                stimRows = grpRows(grpRows.StimulusName == stimNames{stimIdx}, :);
                nAnimals = height(stimRows);

                if nAnimals == 0
                    continue;
                end

                % Extract per-animal bin values: nAnimals x nBins
                binMatrix = NaN(nAnimals, nBins);
                for bi = 1:nBins
                    if ismember(binColNames{bi}, stimRows.Properties.VariableNames)
                        binMatrix(:, bi) = stimRows.(binColNames{bi});
                    end
                end

                % Per-bin mean, SEM, n across animals
                meanByBin = NaN(nBins, 1);
                semByBin = NaN(nBins, 1);
                nByBin = zeros(nBins, 1);
                animalMeansByBin = cell(nBins, 1);

                for bi = 1:nBins
                    col = binMatrix(:, bi);
                    vv = col(isfinite(col));
                    animalMeansByBin{bi} = vv;
                    nByBin(bi) = numel(vv);
                    if ~isempty(vv)
                        meanByBin(bi) = mean(vv, 'omitnan');
                        semByBin(bi) = std(vv, 0, 'omitnan') / sqrt(numel(vv));
                    end
                end

                % Store scatter data
                ck = sprintf('%s:%s', stimName, grpName);
                scatterKeys{end+1} = ck; %#ok<AGROW>
                scatterData.(matlab.lang.makeValidName(ck)) = struct(...
                    'xNumeric', binNumericX, 'animalMeansByBin', {animalMeansByBin});

                validPlotMask = isfinite(meanByBin);
                if ~any(validPlotMask)
                    continue;
                end

                xV = binNumericX(validPlotMask);
                yV = meanByBin(validPlotMask);
                sV = semByBin(validPlotMask);
                sV(isnan(sV)) = 0;

                % SEM shaded fill
                fill(a, [xV; flipud(xV)], [yV+sV; flipud(yV-sV)], ...
                    grpColor, 'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                % Line style: first stim = solid, others cycle
                if stimIdx == 1
                    ls = NORMAL_LINE_STYLE;
                else
                    if isKey(knownOtherStimLineStyles, stimName)
                        ls = knownOtherStimLineStyles(stimName);
                    else
                        idx = length(knownOtherStimLineStyles.keys()) + 1;
                        ls = OTHER_LINE_STYLE{mod(idx-1, length(OTHER_LINE_STYLE))+1};
                        knownOtherStimLineStyles(stimName) = ls;
                    end
                end

                lh = plot(a, xV, yV, 'Color', grpColor, 'LineStyle', ls, ...
                    'LineWidth', 2, 'Marker', 'o', 'MarkerFaceColor', grpColor, ...
                    'DisplayName', sprintf('%s - %s', stimName, grpName));
                lineHandles = [lineHandles; lh]; %#ok<AGROW>
                lineLabels{end+1} = sprintf('%s - %s (n=%d)', stimName, grpName, max(nByBin)); %#ok<AGROW>
            end
        end

        % Overlay individual data points
        if SHOW_DATA_POINTS && ~isempty(scatterKeys)
            nSG = numel(scatterKeys);
            jw = 0.15;
            off = linspace(-jw, jw, max(nSG, 1));
            for ski = 1:nSG
                sd = scatterData.(matlab.lang.makeValidName(scatterKeys{ski}));
                pts = strsplit(scatterKeys{ski}, ':');
                sStim = pts{1};
                sGrp = pts{2};
                sIdx = find(strcmp(stimNames, sStim), 1);
                sMrk = 'o';
                mOpts = {'o', '^', 's', 'd'};
                if ~isempty(sIdx)
                    sMrk = mOpts{mod(sIdx-1, numel(mOpts))+1};
                end
                sCol = groupColors{find(strcmp(allGroups, sGrp), 1)};
                for bi = 1:numel(sd.xNumeric)
                    xc = sd.xNumeric(bi);
                    vals = sd.animalMeansByBin{bi};
                    if isnan(xc) || isempty(vals)
                        continue;
                    end
                    jit = off(ski) + jw*(2*rand(numel(vals),1)-1);
                    scatter(a, xc+jit, vals(:), 18, 'Marker', sMrk, ...
                        'MarkerFaceColor', sCol, 'MarkerEdgeColor', 'none', ...
                        'MarkerFaceAlpha', 0.35, 'HandleVisibility', 'off');
                end
            end
        end

        % X ticks from bin labels
        xticks(a, 1:numel(binLabels));
        xticklabels(a, binLabels);
        xtickangle(a, 35);
        xlim(a, [0.5, numel(binLabels)+0.5]);

        if ~isempty(lineHandles)
            lgd = legend(a, lineHandles, lineLabels, 'Location', 'best', 'Interpreter', 'none');
            lgd.AutoUpdate = 'off';
        end

        yline(a, 0, ':k', 'LineWidth', 0.5, 'HandleVisibility', 'off');
        hold(a, 'off');
        title(a, titleStr, 'Interpreter', 'none');
        xlabel(a, 'Bouts (% of session)');
        ylabel(a, ylabelStr);
        set(a, 'TickLabelInterpreter', 'none');
        grid(a, 'on');
    end

    %% Harmonize y-limits
    if ~isempty(Y_LIM)
        if ~isempty(allAxes)
            ylim(allAxes, Y_LIM);
        end
    elseif SAME_Y_LIM && ~isempty(allAxes)
        ylm = NaN(numel(allAxes), 2);
        for ai = 1:numel(allAxes)
            yl = ylim(allAxes(ai));
            if all(isfinite(yl))
                ylm(ai, :) = yl;
            end
        end
        gmn = min(ylm(:,1), [], 'omitnan');
        gmx = max(ylm(:,2), [], 'omitnan');
        if isfinite(gmn) && isfinite(gmx) && gmx > gmn
            ylim(allAxes, [gmn, gmx]);
        end
    end

    fprintf('Plot generated from: %s\n', CSV);
    fprintf('  Metric: %s | BinWidth: %d | MeanWindowFrames: %d | ShowDataPoints: %d\n', ...
        METRIC_TYPE, BIN_WIDTH, MEAN_WINDOW_FRAMES, SHOW_DATA_POINTS);
    fprintf('  Note: BIN_WIDTH and MEAN_WINDOW_FRAMES are informational only (binning already applied in the CSV).\n');
    fprintf('  Note: Slope-over-time subplot is omitted (trial time data is not in the CSV).\n');
end