function clustering()
    MODES=["IN-HOUSE", "WU-SMAC"];
    SELCTED_MODE = 1; % Change this to switch between datasets

    STDTABLES = [
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/012 TSC2/L3/012 TSC2 standardizedTables.mat",
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/014 SCN1A/L3/014 SCN1A standardizedTables.mat",
        % "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/WU-SMAC/WU-SMAC_L3_L4/016 FBN1/L3/016 FBN1 standardizedTables.mat",


        % "D:\JOBS\WashU_Neuroscience\Behavior\WU-SMAC\PlacePreference\POPULATION\In-House\C57\20260604_standardizedTable_MalesOnly.mat",
        "D:\JOBS\WashU_Neuroscience\Behavior\WU-SMAC\PlacePreference\POPULATION\In-House\Mecp2\20260602_standardizedTable_MalesKOOnly.mat",
        "D:\JOBS\WashU_Neuroscience\Behavior\WU-SMAC\PlacePreference\POPULATION\In-House\C57\20260604_standardizedTable_FemalesOnly.mat",
    ];

    % Parse the strain name as 2nd to last directory in the path, split space, get 2nd part (SCN1A, FBN1, etc.)
    strainNames = arrayfun(@(p) parseStrainNameFromPath(p, MODES(SELCTED_MODE)), STDTABLES, "UniformOutput", false);
    strainKeys = matlab.lang.makeValidName(strainNames); % Ensure valid variable names. For most gene names, this should be the same as the original name and this is just a safety measure.

    stdTables = struct();
    metricsSummaryTables = table();
    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', ...
        'fps', 'px2cm', 'centerpointData', 'bodyparts'};

    uSex = {}; % unique sex values, as formatted in metadata
    uStrain = {}; % unique strain values, as formatted in metadata
    uGenotype = {}; % unique genotype values, as formatted in metadata

    for i = 1:length(STDTABLES)
        stdTablePath = STDTABLES(i);
        strainKey = strainKeys{i};
        data = load(stdTablePath);
        % data is contained in a field named "standardizedTables", so we need to extract that
        if ~isfield(data, "standardizedTables")
            error("The loaded data from %s does not contain the expected field 'standardizedTables'.", stdTablePath);
        end
        data = data.standardizedTables;
        % Check if all required fields are present
        missingFields = setdiff(requiredFields, fieldnames(data));
        if ~isempty(missingFields)
            error("The following required fields are missing in the loaded data from %s: %s", stdTablePath, strjoin(missingFields, ", "));
        end
        stdTables.(strainKey) = data;

        for tableI = 1:length(data)
            % Check unique values for sex, strain, and genotype across all tables
            meta = data(tableI).animalMetadata.values();
            uSex = unique([uSex, {meta.sex}]);
            uStrain = unique([uStrain, {meta.strain}]);
            uGenotype = unique([uGenotype, {meta.genotype}]);
        end
        
        % summaryTable = cohort.summary(data, "StimuliSortedColumnNameDisplayOverride", {'SC', 'NS'});
        summaryTable = cohort.summary(data);
        % metricsSummaryTables.(strainKey) = summaryTable;
        metricsSummaryTables = [metricsSummaryTables; summaryTable]; %#ok<AGROW>
    end


    % For all metrics (columns other than the common headers), convert the actual metric values to z-scores within each stimulus across the entire population (i.e., across all tables). This ensures that the metrics are on the same scale for clustering, and also accounts for any differences in metric distributions across stimuli.

    % --- Z-score metric values within the population ---
    % Common header columns that are metadata, not metrics
    commonHeaders = {'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', ...
        'Litter', 'Toe_ID', 'DOB', 'Age', 'Stimulus Protocol'};
    metricCols = setdiff(metricsSummaryTables.Properties.VariableNames, commonHeaders, 'stable');
    % Exclude "Std" columns — they're derivatives of the raw metrics and
    % add redundant variance without additional signal for clustering
    metricCols = metricCols(~contains(metricCols, 'Std'));

    % Remove redundant/derived columns to reduce feature space noise:
    removeMask = false(size(metricCols));
    for i = 1:numel(metricCols)
        col = metricCols{i};
        % 1) Delta Last-First columns (linearly derived from First/Last)
        if contains(col, 'Last-First')
            removeMask(i) = true;
        end
        % 2) Overall per-stimulus metrics — keep only First/Last bout versions.
        %    Exceptions: "During Stimulus" / "During Active Stimulus" have no
        %    bout counterpart and are kept as single aggregates.
        if contains(col, 'During') && ~contains(col, 'First') && ~contains(col, 'Last') ...
                && ~contains(col, 'During Stimulus') && ~contains(col, 'During Active Stimulus')
            removeMask(i) = true;
        end
        % 3) Min/Max for speed and acceleration (keep Mean only)
        if (contains(col, 'Speed') || contains(col, 'Accel')) && ...
                (contains(col, 'Min') || contains(col, 'Max'))
            removeMask(i) = true;
        end
    end
    metricCols(removeMask) = [];

    fprintf('Using %d metric columns for clustering (removed %d redundant).\n', ...
        numel(metricCols), sum(removeMask));

    % Z-score metric columns within each Stimulus Protocol group (different
    % protocols may have different stimulus sets / column names, so we
    % normalize within protocol for safety)
    protoCol = string(metricsSummaryTables.('Stimulus Protocol'));
    uniqueProtocols = unique(protoCol);
    zScoredParts = cell(numel(uniqueProtocols), 1);
    for p = 1:numel(uniqueProtocols)
        protoMask = protoCol == uniqueProtocols(p);
        subTable = metricsSummaryTables(protoMask, :);

        for c = 1:numel(metricCols)
            col = metricCols{c};
            vals = subTable.(col);
            mu = mean(vals, 'omitnan');
            sigma = std(vals, 'omitnan');
            if sigma > 0
                subTable.(col) = (vals - mu) / sigma;
            else
                subTable.(col) = zeros(size(vals));
            end
        end
        zScoredParts{p} = subTable;
    end
    metricsZ = vertcat(zScoredParts{:});

    % --- Remove columns that are all zero-like (0, NaN, missing) ---
    % These are columns where every row is either 0, NaN, or missing —
    % typically metrics with zero variance across the population,
    % or that these metrics are not applicable for certain stim protocols
    zeroLikeMask = false(size(metricCols));
    for c = 1:numel(metricCols)
        col = metricCols{c};
        vals = metricsZ.(col);
        % A value is "zero-like" if it is 0, NaN, or missing
        zeroLikeMask(c) = all(vals == 0 | isnan(vals) | ismissing(vals));
    end
    if any(zeroLikeMask)
        fprintf('Removing %d zero-variance column(s): %s\n', ...
            sum(zeroLikeMask), strjoin(metricCols(zeroLikeMask), ', '));
        metricCols(zeroLikeMask) = [];
    end

    % --- Build the feature matrix for clustering ---
    X = metricsZ{:, metricCols};
    % Some animals may have NaN for certain metrics — fill with 0 (population mean after z-score)
    nanMask = any(isnan(X), 2);
    if any(nanMask)
        warning('population:temp:clustering:NaNInMetrics', ...
            '%d of %d rows have NaN metric values — filling with 0.', ...
            sum(nanMask), size(X, 1));
    end
    X = fillmissing(X, 'constant', 0);

    % --- Build factors for per-metric ANOVA ---
    sexFactor    = categorical(metricsZ.('Sex$'));
    genoFactor   = categorical(metricsZ.('Genotype$'));
    strainFactor = categorical(metricsZ.('Gene'));

    fprintf('\n========== Metric Ranking: ANOVA per factor ==========\n');
    fprintf('(Sex controlled for Strain + Genotype; Genotype controlled for Strain)\n');

    nMetrics = numel(metricCols);
    rankTables = cell(1, 3);

    % ---------- Sex (controlling for Strain + Genotype) ----------
    fprintf('\n--- Factor: Sex (covariates: Strain, Genotype) ---\n');
    Fvals = nan(nMetrics, 1);
    pvals = nan(nMetrics, 1);
    etaSq = nan(nMetrics, 1);

    for c = 1:nMetrics
        col = metricCols{c};
        vals = metricsZ.(col);
        validMask = isfinite(vals);
        if sum(validMask) < 6, continue; end

        % Three-way ANOVA: metric ~ Sex + Strain + Genotype
        [p_tbl, tbl] = anovan(vals(validMask), ...
            {sexFactor(validMask), strainFactor(validMask), genoFactor(validMask)}, ...
            'model', 'linear', 'varnames', {'Sex', 'Strain', 'Genotype'}, 'display', 'off');
        % Row 2 = Sex, Row 3 = Strain, Row 4 = Genotype, Row 5 = Error, Row 6 = Total
        Fvals(c) = tbl{2,6};        % F for Sex
        pvals(c) = p_tbl(1);        % p for Sex
        SSsex   = tbl{2,2};         % SS Sex
        SSerror = tbl{5,2};         % SS Error (row 5 now since Genotype is row 4)
        if SSsex + SSerror > 0
            etaSq(c) = SSsex / (SSsex + SSerror);
        end
    end

    rankTables{1} = buildRankTable(metricCols, Fvals, pvals, etaSq, nMetrics, 'Sex');

    % ---------- Genotype (controlling for Strain) ----------
    fprintf('\n--- Factor: Genotype (covariate: Strain) ---\n');
    Fvals = nan(nMetrics, 1);
    pvals = nan(nMetrics, 1);
    etaSq = nan(nMetrics, 1);

    for c = 1:nMetrics
        col = metricCols{c};
        vals = metricsZ.(col);
        validMask = isfinite(vals);
        if sum(validMask) < 6, continue; end

        % Two-way ANOVA: metric ~ Genotype + Strain
        [p_tbl, tbl] = anovan(vals(validMask), ...
            {genoFactor(validMask), strainFactor(validMask)}, ...
            'model', 'linear', 'varnames', {'Genotype', 'Strain'}, 'display', 'off');
        Fvals(c) = tbl{2,6};
        pvals(c) = p_tbl(1);
        SSgeno   = tbl{2,2};
        SSerror  = tbl{4,2};
        if SSgeno + SSerror > 0
            etaSq(c) = SSgeno / (SSgeno + SSerror);
        end
    end

    rankTables{2} = buildRankTable(metricCols, Fvals, pvals, etaSq, nMetrics, 'Genotype');

    % ---------- Strain (one-way, no covariate) ----------
    fprintf('\n--- Factor: Strain ---\n');
    Fvals = nan(nMetrics, 1);
    pvals = nan(nMetrics, 1);
    etaSq = nan(nMetrics, 1);

    for c = 1:nMetrics
        col = metricCols{c};
        vals = metricsZ.(col);
        validMask = isfinite(vals);
        if sum(validMask) < 6, continue; end

        [p, tbl] = anova1(vals(validMask), strainFactor(validMask), 'off');
        Fvals(c) = tbl{2,5};
        pvals(c) = p;
        SSstrain = tbl{2,2};
        SStotal  = tbl{4,2};
        if SStotal > 0
            etaSq(c) = SSstrain / SStotal;
        end
    end

    rankTables{3} = buildRankTable(metricCols, Fvals, pvals, etaSq, nMetrics, 'Strain');

    % =================================================================
    % Cross-factor comparison: top metrics for each factor side by side
    % =================================================================
    topN = min(15, nMetrics);
    figure('Name', 'Top Discriminating Metrics by Factor', 'NumberTitle', 'off');
    t = tiledlayout(1, 3);

    factorNames = {'Sex (adj. Strain+Genotype)', 'Genotype (adj. Strain)', 'Strain'};
    for f = 1:3
        nexttile;
        T = rankTables{f};
        topT = T(1:topN, :);
        % barh draws first row at top — largest eta^2 is already first
        barColors = repmat([0 0.4470 0.7410], topN, 1);
        rawSigMask = topT.p < 0.05;
        adjSigMask = topT.p_adj < 0.05;
        barColors(rawSigMask, :) = repmat([0.8500 0.3250 0.0980], sum(rawSigMask), 1);
        barColors(adjSigMask, :) = repmat([0.6350 0.0780 0.1840], sum(adjSigMask), 1);
        b = barh(topT.EtaSq_pct, 'FaceColor', 'flat');
        b.CData = barColors;
        set(gca, 'YTick', 1:topN, 'YTickLabel', topT.Metric);
        xlabel('\eta^2 (%)');
        title(sprintf('%s — Top %d Metrics', factorNames{f}, topN));

        hold on;
        legendHandles = [
            plot(nan, nan, 's', 'MarkerFaceColor', [0 0.4470 0.7410], 'MarkerEdgeColor', [0 0.4470 0.7410]);
            plot(nan, nan, 's', 'MarkerFaceColor', [0.8500 0.3250 0.0980], 'MarkerEdgeColor', [0.8500 0.3250 0.0980]);
            plot(nan, nan, 's', 'MarkerFaceColor', [0.6350 0.0780 0.1840], 'MarkerEdgeColor', [0.6350 0.0780 0.1840])
        ];
        hold off;
        legend(legendHandles, {'ns', 'p < 0.05', 'adj. p < 0.05'}, 'Location', 'northeast');
    end
    t.Title.String = 'Top Discriminating Metrics by Factor';

    % =================================================================
    % PCA + t-SNE for context (colored by biological groups)
    % =================================================================
    [G, ~, ~, ~] = findgroups(sexFactor, genoFactor, strainFactor);
    
    [~, scoreFull, ~, ~, explained] = pca(X);
    nPCs = find(cumsum(explained) >= 80, 1);
    X_red = scoreFull(:, 1:nPCs);
    fprintf('\nPCA: %d PCs capture %.1f%% variance (%d original columns)\n', ...
        nPCs, sum(explained(1:nPCs)), size(X,2));

    rng(42);
    perplexity = min(30, floor(size(X_red,1) / 4));
    if perplexity < 5, perplexity = 5; end
    Y = tsne(X_red, 'NumDimensions', 2, 'Standardize', false, ...
        'Perplexity', perplexity, 'Verbose', 1);

    figure('Name', 'Context: PCA & t-SNE by Group', 'NumberTitle', 'off');
    tiledlayout(1, 2);

    nexttile;
    gscatter(scoreFull(:,1), scoreFull(:,2), G, lines(max(G)), '.', 12);
    xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
    ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
    title('PCA — Colored by Sex × Genotype × Strain');
    legend('Location', 'best');

    nexttile;
    gscatter(Y(:,1), Y(:,2), G, lines(max(G)), '.', 12);
    xlabel('t-SNE 1'); ylabel('t-SNE 2');
    title(sprintf('t-SNE (perplexity=%d)', perplexity));
    legend('Location', 'best');

    % =================================================================
    % Export to base workspace
    % =================================================================
    assignin("base", "stdTables", stdTables);
    assignin("base", "metricsSummaryTables", metricsSummaryTables);
    assignin("base", "metricsZ", metricsZ);
    assignin("base", "rankTable_Sex", rankTables{1});
    assignin("base", "rankTable_Genotype", rankTables{2});
    assignin("base", "rankTable_Strain", rankTables{3});
    assignin("base", "metricCols", metricCols);
    assignin("base", "PCAscores", scoreFull);
    assignin("base", "PCAexplained", explained);

    fprintf('\nDone. Ranking tables exported: rankTable_Sex, rankTable_Genotype, rankTable_Strain\n');

end


function T = buildRankTable(metricCols, Fvals, pvals, etaSq, nMetrics, ~)
    pAdj = min(pvals * nMetrics, 1);
    T = table(metricCols(:), Fvals, pvals, etaSq, ...
        pAdj, 'VariableNames', {'Metric', 'F', 'p', 'EtaSq_pct', 'p_adj'});
    T.EtaSq_pct = T.EtaSq_pct * 100;  % as percentage
    T = sortrows(T, 'EtaSq_pct', 'descend');

    nSig = sum(T.p < 0.05);
    nSigBonf = sum(T.p_adj < 0.05);
    fprintf('  Significant (p<0.05):      %d / %d\n', nSig, nMetrics);
    fprintf('  Significant (Bonferroni):  %d / %d\n', nSigBonf, nMetrics);
    fprintf('  Top 10 metrics:\n');
    for i = 1:min(10, height(T))
        fprintf('    %2d. %-60s  F=%.2f  p=%.4g  p_adj=%.4g  eta^2=%.1f%%\n', ...
            i, T.Metric{i}, T.F(i), T.p(i), T.p_adj(i), T.EtaSq_pct(i));
    end
end


function strainname = parseStrainNameFromPath(path, mode)
    parts = utils.path.canonicalPathParts(path);
    if length(parts) < 2
        error("Path does not have enough parts to extract strain name: %s", path);
    end
    parts = cellstr(parts);

    switch mode
        case "IN-HOUSE"
            strainPart = parts{end}; % Get the last part
            % For in house, just use the full folder name here
            strainname = char(string(strainPart));
        case "WU-SMAC"
            strainPart = parts{end-1}; % Get the 2nd to last part
            strainParts = split(strainPart, " ");
            if length(strainParts) < 2
                error("Strain part does not have enough parts to extract strain name: %s", strainPart);
            end
            strainname = strainParts{2}; % Get the 2nd part (e.g., SCN1A, FBN1)
            return;
        otherwise
            error("Unknown mode: %s", mode);
    end
end


function index = mustBeTableSelector(standardizedTables, tableSelector)
    %%MUSTBETABLESELECTOR Validate that the input is a valid table selector for the given standardizedTables
    % 
    % A valid table selector can be either:
    %   - A numeric index corresponding to the table's position in the standardizedTables struct
    %   - A text scalar matching a single 'stimfileName' entry in the standardizedTables struct
    % The function returns the numeric index of the selected table for use in further processing.

    stimtableLength = length(standardizedTables);
    if isnumeric(tableSelector)
        % Validate numeric index
        if ~isscalar(tableSelector) || tableSelector < 1 || tableSelector > stimtableLength
            error('Numeric table selector must be a scalar integer between 1 and %d.', stimtableLength);
        end
        index = tableSelector; % Use the numeric index directly
    elseif isstring(tableSelector) || ischar(tableSelector) || iscellstr(tableSelector)
        % Validate text scalar, allow cellstr of single element for flexibility
        if iscellstr(tableSelector) %#ok<ISCLSTR>
            if length(tableSelector) ~= 1
                error('Text table selector must be a single text scalar or a cell array of one text scalar.');
            end
            tableSelector = tableSelector{1}; % Extract the string from the cell array
        end
        if ~ischar(tableSelector) && ~isstring(tableSelector)
            error('Text table selector must be a text scalar.');
        end
        tableSelector = string(tableSelector); % Convert to string for comparison
        stimfileNames = string({standardizedTables.stimfileName});
        if ~any(stimfileNames == tableSelector)
            error('No table found with stimfileName "%s".', tableSelector);
        end
        index = find(stimfileNames == tableSelector, 1); % Get the index of the matching table
    else
        error('Table selector must be either a numeric index or a text scalar.');
    end
end



function mask = metadataFilters2standardizedTableIndices(standardizedTables, tableSelector, filters)
    %%METADATAFILTERS2STANDARDIZEDTABLEINDICES Convert metadata filters to table indices for a specified table in the standardizedTables struct
    % This function takes in the standardizedTables struct, a tableSelector function that selects which table to use from the standardizedTables struct, and a filters named value pair that specifies the metadata fields and values to filter on. It returns the boolean mask of column indices in the selected table that match the specified metadata filters.

    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}
        tableSelector {mustBeTableSelector(standardizedTables, tableSelector)} = 1 % default to first table if not specified
        filters.Sex {validator.mustBeTextOrEmpty} = {} % default to no filter
        filters.Strain {validator.mustBeTextOrEmpty} = {} % default to no filter
        filters.Genotype {validator.mustBeTextOrEmpty} = {} % default to no filter
    end

    % Get the uSex, uStrain, and uGenotype values from the standardizedTables struct to validate the filters
    uSex = {};
    uStrain = {};
    uGenotype = {};
    for i = 1:length(standardizedTables)
        meta = standardizedTables(i).animalMetadata.values();
        uSex = unique([uSex, {meta.sex}]);
        uStrain = unique([uStrain, {meta.strain}]);
        uGenotype = unique([uGenotype, {meta.genotype}]);
    end
    % Validate the filters against the unique values in the standardizedTables struct
    % If non-empty, the filter value must be one of the unique values in the standardizedTables struct
    % If empty, set the filter to the full list of unique values (i.e., no filtering on that field)
    function filter = validateFilter(filter, fieldName, validValues)
        filter = cellstr(string(filter));
        validValues = cellstr(string(validValues));
        filter = filter(~cellfun('isempty', filter));
        validValues = validValues(~cellfun('isempty', validValues));
        if ~isempty(filter)
            err = setdiff(filter, validValues);
            if ~isempty(err)
                error('Invalid %s filter value(s): %s \nValid values are: %s', fieldName, strjoin(err, ", "), strjoin(validValues, ", "));
            end
        else
            filter = validValues;
        end
    end
    filters.Sex = validateFilter(filters.Sex, "Sex", uSex);
    filters.Strain = validateFilter(filters.Strain, "Strain", uStrain);
    filters.Genotype = validateFilter(filters.Genotype, "Genotype", uGenotype);


    % Filter for appropriate metadata entries based on the specified filters
    % The column indices to return match the indices of the metadata entries
    tableIndex = mustBeTableSelector(standardizedTables, tableSelector);
    metadata = standardizedTables(tableIndex).animalMetadata.values();

    mask = ismember({metadata.sex}, filters.Sex) & ismember({metadata.strain}, filters.Strain) & ismember({metadata.genotype}, filters.Genotype);
end



function filterCombos = makeFilterCombos(uSex, uStrain, uGenotype)
    %MAKEFILTERCOMBOS Create all combinations of the unique sex, strain, and genotype values for filtering
    % Returns a struct array with fields: Sex, Strain, Genotype

    [S, St, G] = ndgrid(uSex, uStrain, uGenotype);
    filterCombos = struct('Sex', S(:), 'Strain', St(:), 'Genotype', G(:));
end