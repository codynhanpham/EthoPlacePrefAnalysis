function t = summary(standardizedTables, kvargs)


    arguments
        standardizedTables struct {sdTable.mustBeStandardizedTable}

        kvargs.MetricsToInclude cell = {} % cell array of metric function handles or names, e.g. {@cohort.metrics.midlineCrossingFreq, @cohort.metrics.rateOfStay} or {'midlineCrossingFreq', 'rateOfStay'}, default to all available metrics

        kvargs.StimulusIncludesTrailingISI (1,1) logical = true % whether the immediately following ISI after a stimulus should be included in the stimulus period
        kvargs.StimuliSortedColumnNameDisplayOverride {sdTable.mustBeStimuliSortedDisplayOverride(standardizedTables, kvargs.StimuliSortedColumnNameDisplayOverride)} = {}

        % Metric-Specific Parameters:
        kvargs.InactiveThresholds (1,1) struct = struct()
        kvargs.ActiveThresholds (1,1) struct = struct()
    end

	if isempty(standardizedTables)
		t = table();
		return;
	end

    metricFcns = resolveMetricFunctions(kvargs.MetricsToInclude);
    if isempty(metricFcns)
        t = table();
        return;
    end

    metricTables = cell(1, numel(metricFcns));
    for i = 1:numel(metricFcns)
        thisMetricFcn = metricFcns{i};
        thisMetricName = func2str(thisMetricFcn);
        try
            metricKvargs = commonMetricArguments(kvargs);
            metricKvargs = metricSpecificArguments(thisMetricName, kvargs, metricKvargs);
            metricKvargs = namedargs2cell(metricKvargs);
            metricTables{i} = thisMetricFcn(standardizedTables, metricKvargs{:});
        catch ME
            error('cohort:summary:MetricExecutionFailed', ...
                'Failed to execute metric "%s". Original error: %s', ...
                thisMetricName, ME.message);
        end

        if ~istable(metricTables{i})
            error('cohort:summary:InvalidMetricOutput', ...
                'Metric "%s" must return a table.', thisMetricName);
        end
    end

    t = cohort.metrics.joinMetricTables(metricTables);
end


function metricFcns = resolveMetricFunctions(metricsToInclude)
    if isempty(metricsToInclude)
        metricFcns = defaultMetricFunctions();
        return;
    end

    if ~iscell(metricsToInclude)
        error('cohort:summary:InvalidMetricsToInclude', ...
            'MetricsToInclude must be a cell array of metric names or function handles.');
    end

    metricFcns = cell(1, numel(metricsToInclude));
    for i = 1:numel(metricsToInclude)
        item = metricsToInclude{i};
        if isa(item, 'function_handle')
            metricFcns{i} = item;
            continue;
        end

        if ~(ischar(item) || (isstring(item) && isscalar(item)))
            error('cohort:summary:InvalidMetricSpecifier', ...
                'MetricsToInclude{%d} must be a function handle or text scalar.', i);
        end

        metricName = char(strtrim(string(item)));
        if isempty(metricName)
            error('cohort:summary:InvalidMetricSpecifier', ...
                'MetricsToInclude{%d} cannot be empty text.', i);
        end

        if startsWith(metricName, '@')
            metricName = metricName(2:end);
        end

        if ~contains(metricName, '.')
            metricName = ['cohort.metrics.' metricName];
        end

        if exist(metricName, 'file') ~= 2
            error('cohort:summary:MetricNotFound', ...
                'MetricsToInclude{%d} could not be resolved: %s', i, metricName);
        end

        metricFcns{i} = str2func(metricName);
    end
end


function metricFcns = defaultMetricFunctions()
    metricFcns = {
        @cohort.metrics.distanceTravel
        @cohort.metrics.preferenceIndex
        @cohort.metrics.speed
        @cohort.metrics.acceleration
        @cohort.metrics.inactivity
        @cohort.metrics.midlineCrossingFreq
        @cohort.metrics.rateofstay
    };
end


function metricKvargs = commonMetricArguments(kvargs)
    metricKvargs = struct();
    metricKvargs.StimulusIncludesTrailingISI = kvargs.StimulusIncludesTrailingISI;
    metricKvargs.StimuliSortedColumnNameDisplayOverride = kvargs.StimuliSortedColumnNameDisplayOverride;
end


function metricKvargs = metricSpecificArguments(metricName, kvargs, metricKvargs)
    metricKey = canonicalMetricKey(metricName);
    specMap = metricSpecificArgumentSpecs();

    if ~isfield(specMap, metricKey)
        return;
    end

    fieldNames = specMap.(metricKey);
    for i = 1:numel(fieldNames)
        fieldName = fieldNames{i};
        metricKvargs.(fieldName) = kvargs.(fieldName);
    end
end


function metricKey = canonicalMetricKey(metricName)
    metricKey = lower(char(string(metricName)));
    lastDot = find(metricKey == '.', 1, 'last');
    if ~isempty(lastDot)
        metricKey = metricKey(lastDot + 1:end);
    end
end


function specMap = metricSpecificArgumentSpecs()
    specMap = struct();
    specMap.inactivity = {'InactiveThresholds', 'ActiveThresholds'};
end