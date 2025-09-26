function balancePolar(ax, metadataTable, groupVars)
    %%BALANCEPOLAR Generate a radar/spider plot to visualize balance of counts across categories.
    %
    %   balancePolar(ax, metadataTable, groupVars)
    %
    %   Inputs:
    %       ax - Axes handle where the polar plot will be drawn.
    %       metadataTable - Metadata table loaded with io.metadata.loadMasterMetadata
    %       groupVars - Cell array of variable names in metadataTable to group by.
    %
    %   See also: io.metadata.loadMasterMetadata

    arguments
        ax (1,1) matlab.graphics.axis.Axes
        metadataTable table
        groupVars {mustBeText}
    end

    [isValidTable, missingHeaders] = io.metadata.isMasterMetadataTable(metadataTable);
    if ~isValidTable
        error('The provided metadataTable is missing required headers: %s', strjoin(missingHeaders, ', '));
    end

    % Group the metadata by the specified variables
    groupedTable = population.metadata.groupby(metadataTable, groupVars, 'IncludeEmptyGroups', true);

    categories = cell(height(groupedTable), 1);
    for i = 1:height(groupedTable)
        categories{i} = char(strjoin(string(groupedTable{i, groupVars}), ' - '));
    end

    % Add a new column for the combined category labels Before GroupCount
    groupedTable = addvars(groupedTable, categories, 'Before', 'GroupCount', 'NewVariableNames', 'Category');
    groupedTable.Category = categorical(groupedTable.Category);

    
    groupCountMax = max(groupedTable.GroupCount);

    radarLimits = [zeros(1, height(groupedTable)); repmat(groupCountMax, 1, height(groupedTable))];
    axesLabels = cellstr(groupedTable.ANIMAL_STRAIN);
    [~,firstUniqueIdx] = unique(axesLabels, 'stable');
    % Not first unique, set to empty
    axesLabels(setdiff(1:height(groupedTable), firstUniqueIdx)) = {''};
    colors = cellfun(@(s) graphics.strainColorMap(char(s)), groupedTable.ANIMAL_STRAIN, "UniformOutput", false);
    colors = vertcat(colors{:});
    colors = reshape(colors, 1, size(colors,1), size(colors,2));

    s = spider_plot(groupedTable.GroupCount',...
        'AxesHandle', ax,...
        'BackgroundColor', 'none',...
        'AxesLimits', radarLimits,...
        'AxesWebType', 'web',...
        'AxesInterval', 5,...
        'AxesDisplay', 'one',...
        'AxesPrecision', 0,...
        'AxesLabelsOffset', 0.8,...
        'AxesFontSize', 11,...
        'LineWidth', 0.5,...
        'LineTransparency', 0.01,...
        'Color', [0.5 0.5 0.5],...
        'MarkerSize', 36,...
        'Marker', 'o',...
        'AxesLabels', axesLabels,...
        'AxesLabelsEdge', 'none',...
        'AxesLabelsRotate', 'off',...
        'AxesLabelsOffset', 0.1,...
        'AxesRadial', 'on',...
        'AxesRadialLineWidth', 0.5,...
        'AxesRadialLineStyle', ':',...
        'AxesWebLineWidth', 1,...
        'FillOption', 'interp',...
        'FillCData', colors,...
        'FillTransparency', 0.618,...
        'LabelFontSize', 14);

    ssTemplate = findobj(ax, 'Type', 'Scatter', 'Marker', 'o', 'SizeData', 36);
    % Copy the plot coords to be subset
    XData = ssTemplate.XData;
    YData = ssTemplate.YData;

    for i = 1:height(groupedTable)
        marker = 'x';
        lineWidth = 1.5;
        color = graphics.strainColorMap(char(groupedTable.ANIMAL_STRAIN(i)));
        hsl = utils.color.rgb2hsl(color);
        if strcmpi(char(groupedTable.ANIMAL_GENOTYPE(i)), 'WT') ...
        || strcmpi(char(groupedTable.ANIMAL_GENOTYPE(i)), 'Control')
            hsl(3) = 80;
        elseif strcmpi(char(groupedTable.ANIMAL_GENOTYPE(i)), 'Het')
            hsl(3) = 60;
        elseif strcmpi(char(groupedTable.ANIMAL_GENOTYPE(i)), 'KO')...
        || strcmpi(char(groupedTable.ANIMAL_GENOTYPE(i)), 'Hom')
            hsl(3) = 40;
        end
        color = utils.color.hsl2rgb(hsl);

        if strcmpi(char(groupedTable.ANIMAL_SEX(i)), 'Male') || strcmpi(char(groupedTable.ANIMAL_SEX(i)), 'M')
            marker = 'o';
            markerFace = color;
        elseif strcmpi(char(groupedTable.ANIMAL_SEX(i)), 'Female') || strcmpi(char(groupedTable.ANIMAL_SEX(i)), 'F')
            marker = 'o';
            markerFace = 'none';
            lineWidth = 2;
        end
        sc = copyobj(ssTemplate, ax);
        sc.XData = XData(i);
        sc.YData = YData(i);
        sc.Marker = marker;
        sc.LineWidth = lineWidth;
        sc.MarkerFaceColor = markerFace;
        sc.MarkerEdgeColor = color;

        dtRows = [dataTipTextRow('Group', string(groupedTable.Category(i))),...
            dataTipTextRow('GroupCount (N)', groupedTable.GroupCount(i))];
        sc.DataTipTemplate.DataTipRows(end+1:end+2) = dtRows;
    end
    delete(ssTemplate);
    
    % Dummy markers for legend
    legendLabels = {'Female', 'Male'};
    legenddummy{2} = scatter(ax, NaN, NaN, 55, 'o', 'MarkerFaceColor', 'none', 'MarkerEdgeColor', 'k', 'LineWidth', 1.5, 'Tag', 'FemaleLegend'); % Female
    legenddummy{1} = scatter(ax, NaN, NaN, 55, 'o', 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5, 'Tag', 'MaleLegend'); % Male

    genotypes = unique(groupedTable.ANIMAL_GENOTYPE, 'stable');
    for i = 1:length(genotypes)
        genotype = char(genotypes{i});
        color = 'k';
        hsl = utils.color.rgb2hsl(color);
        if strcmpi(char(genotype), 'WT') ...
        || strcmpi(char(genotype), 'Control')
            hsl(3) = 80;
        elseif strcmpi(char(genotype), 'Het')
            hsl(3) = 60;
        elseif strcmpi(char(genotype), 'KO')...
        || strcmpi(char(genotype), 'Hom')
            hsl(3) = 40;
        end
        color = utils.color.hsl2rgb(hsl);
        legenddummy{end+1} = scatter(ax, NaN, NaN, 55, 'o', 'MarkerFaceColor', color, 'MarkerEdgeColor', color, 'LineWidth', 0.5, 'Tag', [genotype 'Legend']); %#ok<AGROW>
        legendLabels{end+1} = genotype; %#ok<AGROW>
    end

    strains = unique(groupedTable.ANIMAL_STRAIN, 'stable');
    for i = 1:length(strains)
        strain = char(strains{i});
        color = graphics.strainColorMap(strain);
        legenddummy{end+1} = scatter(ax, NaN, NaN, 55, 'o', 'MarkerFaceColor', color, 'MarkerEdgeColor', color, 'LineWidth', 0.5, 'Tag', [strain 'Legend']); %#ok<AGROW>
        legendLabels{end+1} = strain; %#ok<AGROW>
    end

    legend(ax, [legenddummy{:}], legendLabels, 'Location', 'northeastoutside', 'FontSize', 11);


end