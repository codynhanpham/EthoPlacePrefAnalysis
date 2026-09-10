function componentsLongTbl = progressionComponents(longTbl, kvargs)
	%%PROGRESSIONCOMPONENTS Per-subject progression scoring components (tidy long output)
	%
	%   componentsLongTbl = cohort.metrics.progressionComponents(longTbl)
	%   componentsLongTbl = cohort.metrics.progressionComponents(longTbl, ExpectedDirection=ed)
	%
	%   Given the tidy long progression table produced by
	%   population.temp.private.normalizeProgressionInput (one row per
	%   subject x protocol x stim x bin, with columns SubjectKey, StimsetIdx,
	%   StimulusProtocol, Stimulus, Group, BinIdx, BinLabel, Progression),
	%   computes per (subject, protocol, stim) progression scoring components.
	%
	%   This is the scoring loop extracted from population.temp.rankSubjectProgression
	%   so that it can be reused (e.g., by similarity-to-baseline ranking).
	%
	%   Inputs:
	%       longTbl - tidy long table with columns:
	%           SubjectKey, StimsetIdx, StimulusProtocol, Stimulus, Group,
	%           BinIdx, BinLabel, Progression
	%
	%   Name-Value Pair Arguments:
	%       ExpectedDirection - optional struct array, one element per Stimulus Protocol:
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
	%
	%   Outputs:
	%       componentsLongTbl : tidy long table, one row per (subject, protocol, stim):
	%           SubjectKey, StimsetIdx, StimulusProtocol, Stimulus, Group, ExpectedDir,
	%           DeltaEndStart, TheilSenSlope, KendallTau, ProgressEfficiency, NValidBins
	%
	%   Component definitions (computed on direction-adjusted values
	%   v = ExpectedDir(protocol, stim) * Progression over valid (non-NaN) bins.
	%   Positions use the ACTUAL BinIdx values, so NaN gaps are not collapsed,
	%   e.g. valid bins [1 2 3 5] are treated as spanning bins 1..5):
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
	%   See also: population.temp.rankSubjectProgression

	arguments
		longTbl table {mustBeNonempty}
		kvargs.ExpectedDirection struct = []
	end

	requiredVars = {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', 'Stimulus', ...
		'Group', 'BinIdx', 'Progression'};
	missingVars = requiredVars(~ismember(requiredVars, longTbl.Properties.VariableNames));
	if ~isempty(missingVars)
		error('cohort:metrics:progressionComponents:missingColumns', ...
			'longTbl is missing required columns: %s', strjoin(missingVars, ', '));
	end

	% Resolve expected directions per (protocol, stim)
	dirLookup = resolveExpectedDirections(kvargs.ExpectedDirection, longTbl);

	%% Per (subject, protocol, stim) scoring
	subjKeys   = string(longTbl.SubjectKey);
	protocols  = string(longTbl.StimulusProtocol);
	stims      = string(longTbl.Stimulus);
	pairKey    = strcat(subjKeys, "||", protocols, "||", stims);
	[uniquePairs, ~] = unique(pairKey, 'stable');

	nPairs = numel(uniquePairs);
	scoreSubj   = strings(nPairs, 1);
	scoreStimsetIdx = zeros(nPairs, 1);
	scoreProto  = strings(nPairs, 1);
	scoreStim   = strings(nPairs, 1);
	scoreGroup  = strings(nPairs, 1);
	scoreDir    = zeros(nPairs, 1);
	scoreDeltaES = nan(nPairs, 1);   % last valid value - first valid value
	scoreTS      = nan(nPairs, 1);   % Theil-Sen slope vs actual BinIdx
	scoreTau     = nan(nPairs, 1);   % Kendall tau of v vs actual BinIdx
	scoreEff     = nan(nPairs, 1);   % net-to-gross progress efficiency
	scoreNValid  = zeros(nPairs, 1);

	for pi = 1:nPairs
		rows = longTbl(pairKey == uniquePairs(pi), :);
		rows = sortrows(rows, 'BinIdx');

		subj = string(rows.SubjectKey(1));
		proto = string(rows.StimulusProtocol(1));
		stim = string(rows.Stimulus(1));
		expectedDir = dirLookup(sprintf('%s|%s', char(proto), char(stim)));

		v = expectedDir .* rows.Progression;
		valid = isfinite(v);
		vv = v(valid);
		xx = double(rows.BinIdx(valid));   % actual bin positions (NaN gaps preserved)

		scoreSubj(pi) = subj;
		scoreStimsetIdx(pi) = rows.StimsetIdx(1);
		scoreProto(pi) = proto;
		scoreStim(pi) = stim;
		scoreGroup(pi) = rows.Group(1);
		scoreDir(pi) = expectedDir;

		scoreNValid(pi) = numel(vv);
		if numel(vv) < 2
			continue;
		end

		% Net change (>= 2 valid bins)
		scoreDeltaES(pi) = vv(end) - vv(1);

		% Theil-Sen slope: median of all pairwise slopes vs actual bin index
		[I, J] = find(triu(true(numel(vv), numel(vv)), 1));
		dx = xx(J) - xx(I);
		keep = dx ~= 0;
		if any(keep)
			scoreTS(pi) = median((vv(J(keep)) - vv(I(keep))) ./ dx(keep));
		end

		% Kendall tau of values vs actual bin index (0 if either variable is constant)
		if std(vv) > 0 && std(xx) > 0
			scoreTau(pi) = corr(vv(:), xx(:), 'Type', 'Kendall');
		else
			scoreTau(pi) = 0;
		end

		% Progress efficiency: net-to-gross ratio; 0 when the path length is 0
		pathLen = sum(abs(diff(vv)));
		if pathLen > 0
			scoreEff(pi) = (vv(end) - vv(1)) / pathLen;
		else
			scoreEff(pi) = 0;
		end
	end

	componentsLongTbl = table(scoreSubj, scoreStimsetIdx, scoreProto, scoreStim, ...
		scoreGroup, scoreDir, scoreDeltaES, scoreTS, scoreTau, scoreEff, scoreNValid, ...
		'VariableNames', {'SubjectKey', 'StimsetIdx', 'StimulusProtocol', 'Stimulus', ...
		'Group', 'ExpectedDir', 'DeltaEndStart', 'TheilSenSlope', 'KendallTau', ...
		'ProgressEfficiency', 'NValidBins'});
end

%% ------------------------------------------------------------------
function dirLookup = resolveExpectedDirections(expectedDirection, longTbl)
	% Build a containers.Map keyed "protocol|stim" -> +/-1 (default +1).
	dirLookup = containers.Map('KeyType', 'char', 'ValueType', 'double');

	protocols = unique(string(longTbl.StimulusProtocol), 'stable');
	protosub = longTbl;
	for p = 1:numel(protocols)
		proto = protocols(p);
		sub = protosub(protosub.StimulusProtocol == proto, :);
		stimIdxs = unique(sub.StimsetIdx, 'stable');
		if isempty(stimIdxs)
			error('cohort:metrics:progressionComponents:missingProtocol', ...
				'No rows found for Stimulus Protocol ''%s''.', char(proto));
		end
		if numel(stimIdxs) ~= 1
			error('cohort:metrics:progressionComponents:ambiguousProtocol', ...
				['Stimulus Protocol ''%s'' maps to multiple StimsetIdx values (%s). ' ...
				'ExpectedDirection requires one stimulus order per protocol.'], ...
				char(proto), mat2str(stimIdxs(:)'));
		end
		stimsThisProto = unique(sub.Stimulus, 'stable');
		for k = 1:numel(stimsThisProto)
			dirLookup(sprintf('%s|%s', char(proto), char(stimsThisProto(k)))) = 1;
		end
	end

	if isempty(expectedDirection)
		return;
	end

	for ei = 1:numel(expectedDirection)
		ed = expectedDirection(ei);
		if ~isfield(ed, 'stimfileName') || ~isfield(ed, 'sortedExpectedProgressionDir')
			error('cohort:metrics:progressionComponents:invalidExpectedDirection', ...
				'Each ExpectedDirection element must have stimfileName and sortedExpectedProgressionDir fields.');
		end
		proto = string(ed.stimfileName);
		if ~isscalar(proto) || ~(ischar(ed.stimfileName) || isstring(ed.stimfileName))
			error('cohort:metrics:progressionComponents:invalidExpectedDirection', ...
				'ExpectedDirection.stimfileName must be a text scalar.');
		end
		hit = false;
		canonicalProto = "";
		for p = 1:numel(protocols)
			aliases = unique(string(longTbl.StimulusProtocol), 'stable');
			if any(aliases == proto) || protocols(p) == proto
				hit = true;
				canonicalProto = protocols(p);
				break;
			end
		end
		if ~hit
			error('cohort:metrics:progressionComponents:unknownProtocol', ...
				['ExpectedDirection.stimfileName ''%s'' does not match any Stimulus Protocol. ' ...
				'Available: %s'], char(proto), strjoin(cellstr(protocols), ', '));
		end

		sub = longTbl(longTbl.StimulusProtocol == canonicalProto, :);
		stimsThisProto = unique(sub.Stimulus, 'stable');

		dirs = ed.sortedExpectedProgressionDir;
		if ~isnumeric(dirs) || ~isvector(dirs)
			error('cohort:metrics:progressionComponents:invalidExpectedDirection', ...
				'sortedExpectedProgressionDir for protocol ''%s'' must be a numeric vector.', char(proto));
		end
		dirs = dirs(:)';
		if numel(dirs) ~= numel(stimsThisProto)
			error('cohort:metrics:progressionComponents:directionLengthMismatch', ...
				['ExpectedDirection for protocol ''%s'': sortedExpectedProgressionDir has %d ' ...
				'elements but the protocol has %d stimuli: %s'], char(proto), ...
				numel(dirs), numel(stimsThisProto), strjoin(cellstr(stimsThisProto), ', '));
		end
		if ~all(dirs == 1 | dirs == -1)
			error('cohort:metrics:progressionComponents:badDirectionValue', ...
				'sortedExpectedProgressionDir values must be 1 or -1 (protocol ''%s'').', char(proto));
		end

		for k = 1:numel(stimsThisProto)
			dirLookup(sprintf('%s|%s', char(canonicalProto), char(stimsThisProto(k)))) = dirs(k);
		end
	end
end
