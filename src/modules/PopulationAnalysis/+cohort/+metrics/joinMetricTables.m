function tJoined = joinMetricTables(metricTables, kvargs)
	%%JOINMETRICTABLES Join cohort metric tables by shared common-header keys.
	%
	% tJoined = cohort.metrics.joinMetricTables(metricTables)
	% tJoined = cohort.metrics.joinMetricTables(metricTables, CommonHeaders=headers)
	%
	% Inputs:
	%   metricTables  - Either:
	%       1) a table
	%       2) a cell array of tables
	%
	% Name-Value Pair Arguments:
	%   CommonHeaders - Common key columns used to match rows across metric tables.
	%                   Defaults to the shared metadata columns emitted by cohort metrics.
	%
	% Example:
	%   tDist = cohort.metrics.distanceTravel(standardizedTables);
	%   tSpeed = cohort.metrics.speed(standardizedTables);
	%   tAccel = cohort.metrics.acceleration(standardizedTables);
	%   tAll = cohort.metrics.joinMetricTables({tDist, tSpeed, tAccel});
	%
	% Behavior:
	%   - Each table must contain all CommonHeaders.
	%   - Within each table, CommonHeaders must uniquely identify rows.
	%   - Across tables, the key set must match exactly.
	%   - If any unique entry cannot be matched by CommonHeaders, an error is thrown.

	arguments
		metricTables
		kvargs.CommonHeaders {validator.mustBeTextOrEmpty} = {
			'Mouse_ID', 'Gene', 'Cage #', 'Gene_ID', 'Sex$', 'Genotype$', ...
			'Litter', 'Toe_ID', 'DOB', 'Age', 'Stimulus Protocol'
		}
	end

	tables = normalizeMetricTables(metricTables);
	if isempty(tables)
		tJoined = table();
		return;
	end
	if isscalar(tables)
		tJoined = tables{1};
		return;
	end

	commonHeaders = normalizeHeaderNames(kvargs.CommonHeaders);
	if isempty(commonHeaders)
		error('cohort:metrics:joinMetricTables:EmptyCommonHeaders', ...
			'CommonHeaders cannot be empty.');
	end

	for i = 1:numel(tables)
		validateRequiredHeaders(tables{i}, commonHeaders, i);
	end

	tJoined = tables{1};
	baseKeys = rowKeys(tJoined, commonHeaders);
	assertUniqueKeys(baseKeys, 1);

	for i = 2:numel(tables)
		ti = tables{i};
		keysI = rowKeys(ti, commonHeaders);
		assertUniqueKeys(keysI, i);
		assertSameKeySet(baseKeys, keysI, i);

		overlapNonKeys = intersect( ...
			setdiff(ti.Properties.VariableNames, commonHeaders, 'stable'), ...
			setdiff(tJoined.Properties.VariableNames, commonHeaders, 'stable'), ...
			'stable');
		if ~isempty(overlapNonKeys)
			error('cohort:metrics:joinMetricTables:OverlappingMetricColumns', ...
				'Cannot join table %d due to overlapping non-key columns: %s', ...
				i, strjoin(overlapNonKeys, ', '));
		end

		% Align ti rows to the base key order and append only non-key metric columns.
		[isMatched, loc] = ismember(baseKeys, keysI);
		if ~all(isMatched)
			error('cohort:metrics:joinMetricTables:UnmatchedRows', ...
				'Table %d key alignment failed unexpectedly after key-set validation.', i);
		end

		nonKeyVars = setdiff(ti.Properties.VariableNames, commonHeaders, 'stable');
		tiAligned = ti(loc, nonKeyVars);
		tJoined = [tJoined, tiAligned]; %#ok<AGROW>
	end
end


function tables = normalizeMetricTables(metricTables)
	if istable(metricTables)
		tables = {metricTables};
		return;
	end

	if ~iscell(metricTables)
		error('cohort:metrics:joinMetricTables:InvalidInputType', ...
			'metricTables must be a table or a cell array of tables.');
	end

	tables = metricTables(:);
	for i = 1:numel(tables)
		if ~istable(tables{i})
			error('cohort:metrics:joinMetricTables:InvalidCellEntry', ...
				'metricTables{%d} is not a table.', i);
		end
	end
end


function headers = normalizeHeaderNames(headersIn)
	if isempty(headersIn)
		headers = {};
		return;
	end

	headers = cellstr(string(headersIn));
	headers = headers(:)';
	headers = unique(headers, 'stable');
end


function validateRequiredHeaders(t, commonHeaders, tableIdx)
	missing = setdiff(commonHeaders, t.Properties.VariableNames, 'stable');
	if ~isempty(missing)
		error('cohort:metrics:joinMetricTables:MissingCommonHeader', ...
			'Table %d is missing required CommonHeaders: %s', ...
			tableIdx, strjoin(missing, ', '));
	end
end


function assertUniqueKeys(keys, tableIdx)
	[u, ~, ic] = unique(keys, 'stable');
	counts = accumarray(ic, 1);
	dupMask = counts > 1;
	if any(dupMask)
		dupKeys = u(dupMask);
		preview = cellstr(dupKeys(1:min(end, 3)));
		error('cohort:metrics:joinMetricTables:NonUniqueKey', ...
			'Table %d has non-unique CommonHeaders key rows. Example duplicate key(s): %s', ...
			tableIdx, strjoin(preview, ' | '));
	end
end


function assertSameKeySet(baseKeys, keysI, tableIdx)
	missingInI = setdiff(baseKeys, keysI, 'stable');
	extraInI = setdiff(keysI, baseKeys, 'stable');

	if ~isempty(missingInI) || ~isempty(extraInI)
		msg = sprintf('Table %d cannot be joined by CommonHeaders because key sets do not match exactly.', tableIdx);
		if ~isempty(missingInI)
			missPreview = strjoin(cellstr(missingInI(1:min(end, 3))), ' | ');
			msg = sprintf('%s Missing in table %d (examples): %s.', msg, tableIdx, missPreview);
		end
		if ~isempty(extraInI)
			extraPreview = strjoin(cellstr(extraInI(1:min(end, 3))), ' | ');
			msg = sprintf('%s Extra in table %d (examples): %s.', msg, tableIdx, extraPreview);
		end
		error('cohort:metrics:joinMetricTables:UnmatchedRows', '%s', msg);
	end
end


function keys = rowKeys(t, commonHeaders)
	n = height(t);
	keys = strings(n, 1);

	for r = 1:n
		parts = strings(1, numel(commonHeaders));
		for c = 1:numel(commonHeaders)
			header = commonHeaders{c};
			v = t{r, header};
			parts(c) = scalarToStableString(v);
		end
		keys(r) = strjoin(parts, "||");
	end
end


function s = scalarToStableString(v)
	if iscell(v)
		if isempty(v)
			s = "<empty>";
			return;
		end
		s = scalarToStableString(v{1});
		return;
	end

	if ischar(v)
		s = string(v);
		return;
	end

	if isstring(v)
		if isempty(v)
			s = "<empty>";
		else
			s = v(1);
		end
		return;
	end

	if iscategorical(v)
		s = string(v);
		return;
	end

	if isdatetime(v)
		s = string(v, 'yyyy-MM-dd''T''HH:mm:ss.SSSSSSZZZZZ');
		return;
	end

	if isduration(v)
		s = string(v);
		return;
	end

	if isnumeric(v) || islogical(v)
		if isempty(v)
			s = "<empty>";
			return;
		end
		if isnan(v)
			s = "NaN";
			return;
		end
		if isinf(v)
			if v > 0
				s = "Inf";
			else
				s = "-Inf";
			end
			return;
		end
		s = string(compose('%.17g', double(v(1))));
		return;
	end

	try
		s = string(v);
		if isempty(s)
			s = "<empty>";
		else
			s = s(1);
		end
	catch
		s = "<unprintable>";
	end
end
