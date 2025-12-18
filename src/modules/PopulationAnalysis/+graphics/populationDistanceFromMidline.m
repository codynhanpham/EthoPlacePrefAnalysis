function f = populationDistanceFromMidline(standardizedTables, kvargs)
    %%POPULATIONDISTANCEFROMMIDLINE Plots the average distance from midline over time for each stimulus set in standardizedTables
    %
    %   Inputs:
    %       standardizedTables - struct array of standardized tables, generated via population.stats.populationPositionByStim()
    %
    %   Name-Value Pair Arguments:
    %       'MainApp' - handle to the main PlacePrefDataGUI_main app (for additional configs + syncing)
    %
    %   Outputs:
    %       f - handle to the generated figure
    %
    %   See also: population.stats.populationPositionByStim

    arguments
        standardizedTables (1,:) struct
        kvargs.MainApp {mustBeAOrEmpty(kvargs.MainApp, 'PlacePrefDataGUI_main')} = [];
    end



    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), 2/1);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Distance from midline"), 'Position', figPos);
    t = tiledlayout(f, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    stimsets = {standardizedTables.stimfileName};

    for i = 1:length(stimsets)
        stimPeriodTable = standardizedTables(i).centerpointData;
        trialTime = stimPeriodTable{:, 'Trial time'};
        distFromMidline_cm = mean(stimPeriodTable.("Distance from Midline"), 2, 'omitnan'); % average across animals
        stdDist = std(stimPeriodTable.("Distance from Midline"), 0, 2, 'omitnan'); % std across animals

        curve1 = distFromMidline_cm + stdDist;
        curve2 = distFromMidline_cm - stdDist;
        x2 = [trialTime', fliplr(trialTime')];
        inBetween = [curve1', fliplr(curve2')];


        a = nexttile(t);
        l = plot(a, trialTime, distFromMidline_cm, 'k-');
        plotXLim = a.XLim; plotYLim = a.YLim; % Save this for later: the default limits should fit the data nicely in plot
        maxY = max(abs(plotYLim));
        plotYLim = [-maxY, maxY]; % Symmetric y-limits
        plotYLim = plotYLim * 1.05; % Add 5% padding Y
        plotXLim = [plotXLim(1), plotXLim(2) + diff(plotXLim) * 0.16]; % Add 16% padding X end for stim labels
        % If the first stim starts at time > 5% of diff(plotXLim), no need to pad the start, otherwise pad start too
        firstStimTime = trialTime(1);
        if firstStimTime <= plotXLim(1) + diff(plotXLim) * 0.05
            padamount = (plotXLim(1) + diff(plotXLim) * 0.05) - firstStimTime;
            plotXLim(1) = plotXLim(1) - padamount;
        end

        hold(a, 'on');
        line(a, [min(0, plotXLim(1)), max(max(trialTime), plotXLim(2))], [0,0], 'Color', [0.5,0.5,0.5], 'LineStyle', ':', 'LineWidth', 1);
        fill(x2, inBetween, [0.5, 0.5, 0.5], 'FaceAlpha', 0.2, 'EdgeColor', 'none');

        % Plot the left/right color patched regions: rectangle from xlim(1) to xlim(2), y=0 to ylim(2) in red (right), and y=0 to ylim(1) in blue (left)
        patch(a, [plotXLim(1), plotXLim(1), plotXLim(2), plotXLim(2)], [0, plotYLim(2), plotYLim(2), 0], [1,0,0], 'FaceAlpha', 0.04, 'EdgeColor', 'none');
        patch(a, [plotXLim(1), plotXLim(1), plotXLim(2), plotXLim(2)], [plotYLim(1), 0, 0, plotYLim(1)], [0,0,1], 'FaceAlpha', 0.04, 'EdgeColor', 'none');


        % Add the stimuli as shaded regions behind the line plot, color of [0.5 0.5 0.5] if it contains {'Intro', 'Outro', 'ISI'}, else color based on speaker position as in "Stim Speaker Corrected" (contains 'Left' -> blue, 'Right' -> red)
        stims = stimPeriodTable{:,'Stimulus name'};
        ustims = unique(stims(~cellfun(@anymissing, stims)));
        for j = 1:length(ustims)
            stimName = ustims{j};
            stimIdx = find(strcmp(stims, stimName));
            if isempty(stimIdx)
                continue;
            end
            
            % Find the start and end blocks of consecutive frames for this stim
            stimBlocks = NaN(0,2); % each row is [startIdx, endIdx]
            blockStart = stimIdx(1);
            for k = 2:length(stimIdx)
                if stimIdx(k) ~= stimIdx(k-1) + 1
                    % Not consecutive, end the previous block
                    blockEnd = stimIdx(k-1)+1;
                    stimBlocks = [stimBlocks; blockStart, blockEnd]; %#ok<AGROW>
                    blockStart = stimIdx(k);
                end
            end
            % Add the last block
            stimBlocks = [stimBlocks; blockStart, stimIdx(end)]; %#ok<AGROW>

            if contains(stimName, {'Intro', 'Outro', 'ISI'})
                stimColor = [0.5, 0.5, 0.5];
            else
                if startsWith(stimName, '[Ch1] ')
                    stimName = extractAfter(stimName, '[Ch1] ');
                elseif startsWith(stimName, '[Ch2] ')
                    stimName = extractAfter(stimName, '[Ch2] ');
                end

                containcheck = contains(standardizedTables(i).stimuliSorted, stimName, 'IgnoreCase', true);
                index = find(containcheck, 1);
                switch index
                    case 1
                        stimColor = [0, 0, 1]; % blue
                    case 2
                        stimColor = [1, 0, 0]; % red
                    otherwise
                        stimColor = [0.5, 0.5, 0.5]; % gray for non-stims (Intro/Outro/ISI)
                end
            end

            % Plot each block as a shaded region
            for k = 1:size(stimBlocks,1)
                blockStartIdx = stimBlocks(k,1);
                blockEndIdx = stimBlocks(k,2);
                xStart = trialTime(blockStartIdx);
                xEnd = trialTime(blockEndIdx);
                patchX = [xStart, xEnd, xEnd, xStart];
                patchY = [plotYLim(1), plotYLim(1), plotYLim(2), plotYLim(2)];
                patch(a, patchX, patchY, stimColor, 'FaceAlpha', 0.1, 'EdgeColor', 'none');
            end
        end

        % Bring line plot to front
        uistack(l, 'top');

        % Add text at the end of x-axis indicating the stims
        % We know that when making the bar, left speaker stim is first
        textPaddingX = 0.02 * diff(plotXLim);
        textPaddingY = 0.05 * diff(plotYLim);
        text(a, plotXLim(2) - textPaddingX, plotYLim(1) + textPaddingY, standardizedTables(i).stimuliSorted(1), 'Color', 'b', 'FontWeight', 'bold', 'FontSize', 9, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Clipping', 'on');
        text(a, plotXLim(2) - textPaddingX, plotYLim(2) - textPaddingY, standardizedTables(i).stimuliSorted(2), 'Color', 'r', 'FontWeight', 'bold', 'FontSize', 9, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Clipping', 'on');
        
        title(a, 'Distance from Midline Over Time');
        xlabel(a, 'Time (s)');
        ylabel(a, 'Distance from Midline (cm)');

        % allow interactive zooming and panning
        enableDefaultInteractivity(a);
        axtoolbar(a, {'export', 'pan', 'zoomin', 'zoomout', 'restoreview'});

        a.XLim = plotXLim; a.YLim = plotYLim; % Restore original limits
        hold(a, 'off');


    end
end