function [header, datatable, units, stimulusFrameRange, animalMetadata, stimuli] = alignTrackingToStim(sleapFile, stimuliDir, kvargs)
	%ALIGNTRACKINGTOSTIM Align dense SLEAP pose data to stimulus chapters.
	arguments
		sleapFile {mustBeFile}
		stimuliDir {mustBeFolder}
		kvargs.Config (1,1) struct = struct()
		kvargs.ArenaName {validator.mustBeTextScalarOrEmpty} = ''
		kvargs.Interpolation {mustBeMember(kvargs.Interpolation, ...
			{'none', 'linear', 'nearest', 'spline', 'makima', 'pchip', 'cubic'}), ...
			mustBeTextScalar} = 'pchip'
		kvargs.ReferencePointOutlierThresholdFactor (1,1) double {mustBePositive, mustBeFinite} = 3
		kvargs.StimulusProtocol {mustBeTextScalar} = ''
		kvargs.StimStartFrame {mustBePositiveIntOrEmpty} = []
		kvargs.SpeakerFlipped {mustBeNumericLogicalOrEmpty} = []
		kvargs.MasterMetadataTable {validator.mustBeFileTableOrEmpty} = ''
	end

	SCRIPT_VERSION = '1.0.0';

	[header, slpTable, units] = io.sleap.loadTrackingSlp(sleapFile, ...
		Interpolation=kvargs.Interpolation);
	mediafile = string(header("Video file"));
	if strlength(mediafile) == 0 || ~isfile(mediafile)
		error('io:sleap:alignTrackingToStim:MissingMediaFile', ...
			'The source media file referenced by the SLEAP file could not be found: %s', mediafile);
	end

	if strlength(string(kvargs.ArenaName)) > 0 && ...
			~strcmp(string(kvargs.ArenaName), string(header("Arena name")))
		error('io:sleap:alignTrackingToStim:ArenaMismatch', ...
			'Requested arena "%s" does not match the SLEAP arena "%s".', ...
			kvargs.ArenaName, header("Arena name"));
	end

	[trialTimes, fps] = localReadMediaTimestamps(mediafile, height(slpTable));
	[nodeNames, outputNodeNames, xValues, yValues] = localExtractNodeCoordinates(slpTable, header);
	[~, metadataRow] = localResolveMetadata(kvargs.MasterMetadataTable, header);

	stimulusProtocol = string(kvargs.StimulusProtocol);
	if strlength(stimulusProtocol) == 0 && ~isempty(metadataRow)
		stimulusProtocol = string(metadataRow.('STIMULUS_PROTOCOL'));
	end
	if strlength(stimulusProtocol) == 0
		error('io:sleap:alignTrackingToStim:MissingStimulusProtocol', ...
			'StimulusProtocol must be specified directly or through MasterMetadataTable.');
	end
	stimFile = localFindStimulusFile(stimuliDir, stimulusProtocol);

	refJsonPath = localReferenceJsonPath(mediafile);
	refJsonExists = isfile(refJsonPath);
	refJsonHash = '';
	if refJsonExists
		refJsonHash = DataHash(refJsonPath, 'SHA-256', 'file');
	end

	[stimStartFrame, speakerFlipped] = localResolveStimulusOptions( ...
		kvargs, metadataRow, refJsonPath, trialTimes, fps);
	metadata = io.stimuli.extractMetadata(stimFile, "Config", kvargs.Config);
	requiredFields = {'chapters', 'duration'};
	if ~isstruct(metadata) || ~all(isfield(metadata, requiredFields))
		missing = setdiff(requiredFields, fieldnames(metadata));
		error('io:sleap:alignTrackingToStim:InvalidStimulusMetadata', ...
			'Stimulus metadata is missing required fields: %s.', strjoin(missing, ', '));
	end
	if isempty(metadata.chapters)
		error('io:sleap:alignTrackingToStim:MissingChapters', ...
			'No chapter markers were found in stimulus metadata.');
	end

	[filedir, filename] = fileparts(char(sleapFile));
	composite = [ ...
		char(DataHash(sleapFile, 'SHA-256', 'file')), ...
		char(DataHash(mediafile, 'SHA-256', 'file')), ...
		char(DataHash(kvargs.Config, 'SHA-256')), ...
		char(DataHash(metadataRow, 'SHA-256')), ...
		char(DataHash(stimFile, 'SHA-256', 'file')), ...
		char(DataHash({kvargs.StimulusProtocol, kvargs.StimStartFrame, kvargs.SpeakerFlipped, ...
			kvargs.Interpolation, kvargs.ReferencePointOutlierThresholdFactor}, 'SHA-256')), ...
		char(refJsonPath), char(string(refJsonExists)), char(refJsonHash), SCRIPT_VERSION];
	compositeHash = DataHash(composite, 'SHA-256');
	alignedFile = io.cache.alignedCacheFilePath(filedir, filename, "SLEAP", compositeHash);
	localCleanupAlignedCaches(filedir, filename, "SLEAP", alignedFile);
	if isfile(alignedFile)
		[cached, loaded] = io.cache.loadAlignedCache(alignedFile, ...
			["header", "datatable", "units", "stimulusFrameRange", "animalMetadata", "stimuli"]);
		if loaded
			header = cached.header;
			datatable = cached.datatable;
			units = cached.units;
			stimulusFrameRange = cached.stimulusFrameRange;
			animalMetadata = cached.animalMetadata;
			stimuli = cached.stimuli;
			return;
		end
	end

	[referencePosition, referenceSource] = localReferencePosition( ...
		xValues, yValues, nodeNames, slpTable, kvargs.Config, ...
		kvargs.ReferencePointOutlierThresholdFactor);
	[videoWidth, videoHeight] = localVideoSize(mediafile);
	videoSize = [videoWidth, videoHeight];
	[refMode, referenceX, referenceY] = localReferenceGeometry( ...
		refJsonPath, kvargs.Config, string(header("Arena name")), ...
		videoSize);
	[referencePositionForSide, referenceXForSide, referenceYForSide] = ...
		localApplyCameraFlips(referencePosition, referenceX, referenceY, ...
		videoSize, kvargs.Config);
	animalSide = localClassifySides(referencePositionForSide, referenceXForSide, ...
		referenceYForSide, refMode);

	numRows = height(slpTable);
	datatable = slpTable;
	datatable.('Trial time') = trialTimes;
	rawVariableNames = string(datatable.Properties.VariableNames);
	for nodeIdx = 1:numel(nodeNames)
		datatable.Properties.VariableNames{strcmp(rawVariableNames, ...
			nodeNames(nodeIdx) + " |> x")} = char("X " + outputNodeNames(nodeIdx));
		datatable.Properties.VariableNames{strcmp(rawVariableNames, ...
			nodeNames(nodeIdx) + " |> y")} = char("Y " + outputNodeNames(nodeIdx));
		rawVariableNames = string(datatable.Properties.VariableNames);
	end
	datatable.('X center') = referencePosition(:, 1);
	datatable.('Y center') = referencePosition(:, 2);

	chapterOriginal = strings(numRows, 1);
	chapterOriginal(:) = "NONE | Pre-Stimulus";
	speakerChannelsFlipped = repmat(speakerFlipped, numRows, 1);
	stimSpeakerCorrected = strings(numRows, 1);
	animalSameZoneAsStim = zeros(numRows, 1);
	animalMatchedStim = strings(numRows, 1);
	matchedSpeakerPosition = strings(numRows, 1);

	timeAtStimStart = trialTimes(stimStartFrame);
	stimEndTime = timeAtStimStart + double(metadata.duration);
	stimEndFrame = find(trialTimes >= stimEndTime, 1, 'first');
	if isempty(stimEndFrame)
		stimEndFrame = numRows + 1;
	end
	if stimEndFrame <= numRows
		chapterOriginal(stimEndFrame:end) = "NONE | Post-Stimulus";
	end

	if stimStartFrame < stimEndFrame
		stimIndices = stimStartFrame:(stimEndFrame - 1);
		relativeTimestamps = trialTimes(stimIndices) - timeAtStimStart;
		chapters = metadata.chapters;
		chapterTimestamps = [chapters.timestamp];
		chapterIndices = discretize(relativeTimestamps, [-inf, chapterTimestamps, inf]);
		chapterIndices = max(1, chapterIndices - 1);
		chapterIndices = min(chapterIndices, numel(chapters));
		chapterTitles = string({chapters.title});
		assignedTitles = chapterTitles(chapterIndices(:));
		chapterOriginal(stimIndices) = assignedTitles;

		[stimSpeakerCorrectedLocal, sameZoneLocal, matchedStimLocal, matchedSpeakerLocal] = ...
			localAssignStimulusSides(assignedTitles, animalSide(stimIndices), speakerFlipped);
		stimSpeakerCorrected(stimIndices) = stimSpeakerCorrectedLocal;
		animalSameZoneAsStim(stimIndices) = sameZoneLocal;
		animalMatchedStim(stimIndices) = matchedStimLocal;
		matchedSpeakerPosition(stimIndices) = matchedSpeakerLocal;
	end

	datatable = addvars(datatable, cellstr(chapterOriginal), speakerChannelsFlipped, ...
		stimSpeakerCorrected, animalSameZoneAsStim, animalMatchedStim, matchedSpeakerPosition, ...
		'NewVariableNames', {'Chapter Original', 'Speaker Channels Flipped', ...
		'Stim Speaker Corrected', 'Animal Is Same Zone As Stim', ...
		'Animal Matched Stim Name', 'Matched Speaker Position'});

	header("Tracking provider") = "SLEAP";
	header("Alignment coordinates") = "image-pixels";
	header("SLEAP reference mode") = string(refMode);
	header("SLEAP reference source") = string(jsonencode(cellstr(referenceSource)));
	header("SLEAP reference bodypart") = string(localReferenceBodypartConfig(kvargs.Config));
	header("SLEAP reference bodypart fallback") = "outlier-filtered non-tail centroid";
	header("SLEAP alignment script version") = SCRIPT_VERSION;
	header("SLEAP interpolation") = string(kvargs.Interpolation);

	for variableName = string(datatable.Properties.VariableNames)
		units(variableName) = "";
	end
	units("Trial time") = "s";
	units("X center") = "px";
	units("Y center") = "px";
	for nodeName = outputNodeNames'
		units("X " + nodeName) = "px";
		units("Y " + nodeName) = "px";
	end

	animalMetadata = localAnimalMetadata(metadataRow);
	stimulusFrameRange = [stimStartFrame, stimEndFrame - 1];
	if isfield(metadata, 'thumbnail')
		metadata = rmfield(metadata, 'thumbnail');
	end
	stimuli = metadata;
	cacheData = struct('header', header, 'datatable', datatable, 'units', units, ...
		'metadataRow', metadataRow, 'stimulusFrameRange', stimulusFrameRange, ...
		'animalMetadata', animalMetadata, 'stimuli', stimuli, ...
		'sleapFileHash', DataHash(sleapFile, 'SHA-256', 'file'), ...
		'stimFileHash', DataHash(stimFile, 'SHA-256', 'file'), ...
		'ALIGNMENT_SCRIPT_VERSION', SCRIPT_VERSION);
	io.cache.saveAlignedCache(alignedFile, cacheData);
end

function [trialTimes, fps] = localReadMediaTimestamps(mediafile, expectedRows)
	[pts, timebase] = ffprobe.pts(char(mediafile));
	trialTimes = double(pts(:)) * double(timebase);
	if numel(trialTimes) ~= expectedRows
		error('io:sleap:alignTrackingToStim:TimestampCountMismatch', ...
			'ffprobe returned %d timestamps for %d SLEAP rows.', numel(trialTimes), expectedRows);
	end
	if any(~isfinite(trialTimes)) || (numel(trialTimes) > 1 && any(diff(trialTimes) <= 0))
		error('io:sleap:alignTrackingToStim:InvalidTimestamps', ...
			'The source media timestamps must be finite and strictly increasing.');
	end
	if numel(trialTimes) > 1
		fps = 1 / mean(diff(trialTimes), 'omitnan');
	else
		fps = NaN;
	end
end

function [nodeNames, outputNodeNames, xValues, yValues] = localExtractNodeCoordinates(data, header)
	dataHeader = jsondecode(char(header("SLEAP data header jsonencode")));
	nodeNames = string(dataHeader.bodyparts(:));
	outputNodeNames = nodeNames;
	centerMask = strcmpi(outputNodeNames, "center");
	if any(centerMask)
		if any(strcmpi(outputNodeNames, "center-pred") & ~centerMask)
			error('io:sleap:alignTrackingToStim:CenterNodeNameCollision', ...
				'SLEAP contains both "center" and "center-pred" nodes; rename one before alignment.');
		end
		outputNodeNames(centerMask) = "center-pred";
	end
	xValues = NaN(height(data), numel(nodeNames));
	yValues = NaN(height(data), numel(nodeNames));
	for nodeIdx = 1:numel(nodeNames)
		xVariable = char(nodeNames(nodeIdx) + " |> x");
		yVariable = char(nodeNames(nodeIdx) + " |> y");
		if ~ismember(xVariable, data.Properties.VariableNames) || ...
				~ismember(yVariable, data.Properties.VariableNames)
			error('io:sleap:alignTrackingToStim:MissingNodeCoordinates', ...
				'SLEAP data is missing coordinates for node "%s".', nodeNames(nodeIdx));
		end
		xValues(:, nodeIdx) = data{:, xVariable};
		yValues(:, nodeIdx) = data{:, yVariable};
	end
end

function [masterMetadata, metadataRow] = localResolveMetadata(masterMetadataTable, header)
	masterMetadata = table();
	metadataRow = table();
	if istable(masterMetadataTable)
		[valid, missingHeaders] = io.metadata.isMasterMetadataTable(masterMetadataTable);
		if ~valid
			error('io:sleap:alignTrackingToStim:InvalidMasterMetadata', ...
				'MasterMetadataTable is missing headers: %s.', strjoin(missingHeaders, ', '));
		end
		masterMetadata = masterMetadataTable;
	elseif ~isempty(masterMetadataTable)
		masterMetadata = io.metadata.loadMasterMetadata(masterMetadataTable);
	end
	if isempty(masterMetadata)
		return;
	end

	trialParts = split(string(header("Trial name")), ' ');
	trialNumber = str2double(strtrim(trialParts(end)));
	trialMask = masterMetadata.ETHOVISION_TRIAL == trialNumber & ...
		masterMetadata.ETHOVISION_FILE == string(header("Experiment")) & ...
		masterMetadata.ETHOVISION_ARENA == string(header("Arena name"));
	rowIdx = find(trialMask, 1);
	if isempty(rowIdx)
		error('io:sleap:alignTrackingToStim:MetadataRowNotFound', ...
			'No master metadata row matched SLEAP trial %s, experiment %s, arena %s.', ...
			header("Trial name"), header("Experiment"), header("Arena name"));
	end
	metadataRow = masterMetadata(rowIdx, :);
end

function stimFile = localFindStimulusFile(stimuliDir, stimulusProtocol)
	pattern = sprintf('%s/**/%s', string(stimuliDir), stimulusProtocol);
	files = dir(pattern);
	if isempty(files)
		error('io:sleap:alignTrackingToStim:StimulusFileNotFound', ...
			'No stimulus file found matching pattern %s.', pattern);
	end
	stimFile = fullfile(files(1).folder, files(1).name);
end

function [stimStartFrame, speakerFlipped] = localResolveStimulusOptions(kvargs, metadataRow, refJsonPath, trialTimes, fps)
	stimStartFrame = kvargs.StimStartFrame;
	speakerFlipped = kvargs.SpeakerFlipped;
	if isempty(metadataRow)
		if isempty(stimStartFrame) || isempty(speakerFlipped)
			error('io:sleap:alignTrackingToStim:MissingTrialOptions', ...
				'StimStartFrame and SpeakerFlipped must be provided when MasterMetadataTable is empty.');
		end
	else
		if isempty(stimStartFrame)
			stimStartFrame = localNumericMetadataValue(metadataRow, 'STIM_START_FRAME');
			if isempty(stimStartFrame) || isnan(stimStartFrame)
				stimStartFrame = localReadTriggerStartFrame(refJsonPath);
			end
			if isempty(stimStartFrame) || isnan(stimStartFrame)
				habitdur = localNumericMetadataValue(metadataRow, 'HABITUATION_DURATION_SEC');
				if isempty(habitdur) || isnan(habitdur)
					habitdur = 0;
				end
				stimStartFrame = habitdur * fps + 1;
			end
		end
		if isempty(speakerFlipped)
			speakerFlipped = localLogicalValue(metadataRow.('SPEAKER_FLIPPED'));
		end
	end
	if isempty(stimStartFrame) || ~isfinite(stimStartFrame) || stimStartFrame < 1
		stimStartFrame = 1;
	end
	stimStartFrame = round(double(stimStartFrame));
	speakerFlipped = logical(speakerFlipped(1));
	if stimStartFrame > numel(trialTimes)
		error('io:sleap:alignTrackingToStim:StimulusStartOutOfRange', ...
			'StimStartFrame %d exceeds the %d SLEAP frames.', stimStartFrame, numel(trialTimes));
	end
end

function value = localNumericMetadataValue(row, fieldName)
	value = [];
	if ~ismember(fieldName, row.Properties.VariableNames)
		return;
	end
	value = row.(fieldName);
	if ~isnumeric(value)
		value = str2double(string(value));
	end
	if ~isempty(value)
		value = double(value(1));
	end
end

function value = localLogicalValue(value)
	if iscell(value)
		value = value{1};
	end
	if islogical(value)
		value = value(1);
	elseif isnumeric(value)
		value = value(1) ~= 0;
	else
		value = ~isempty(regexpi(char(string(value)), '^(1|true|yes|y|t)$', 'once'));
	end
end

function refJsonPath = localReferenceJsonPath(mediafile)
	[mediaDir, mediaBaseName] = fileparts(char(mediafile));
	refJsonPath = fullfile(mediaDir, [mediaBaseName, '.ref.json']);
end

function [referencePosition, source] = localReferencePosition(xValues, yValues, nodeNames, ~, config, thresholdFactor)
	nRows = size(xValues, 1);
	referencePosition = NaN(nRows, 2);
	source = "";
	referenceNames = localReferenceBodypartNames(config);

	for rowIdx = 1:nRows
		selected = false;
		for nameIdx = 1:numel(referenceNames)
			nodeIdx = find(strcmp(nodeNames, referenceNames(nameIdx)), 1);
			if ~isempty(nodeIdx) && ...
					isfinite(xValues(rowIdx, nodeIdx)) && isfinite(yValues(rowIdx, nodeIdx))
				referencePosition(rowIdx, :) = [xValues(rowIdx, nodeIdx), yValues(rowIdx, nodeIdx)];
				selected = true;
				source(rowIdx, 1) = referenceNames(nameIdx);
				break;
			end
		end
		if selected
			continue;
		end

		valid = isfinite(xValues(rowIdx, :)) & ...
			isfinite(yValues(rowIdx, :)) & ~contains(nodeNames, "tail", 'IgnoreCase', true)';
		if ~any(valid)
			source(rowIdx, 1) = "missing";
			continue;
		end
		points = [xValues(rowIdx, valid)', yValues(rowIdx, valid)'];
		points = reshape(points, [], 2);
		center = median(points, 1);
		distances = hypot(points(:, 1) - center(1), points(:, 2) - center(2));
		if numel(distances) >= 3
			outlierMask = isoutlier(distances, 'median', 'ThresholdFactor', thresholdFactor);
			if any(~outlierMask)
				points = points(~outlierMask, :);
			end
		end
		referencePosition(rowIdx, :) = mean(points, 1, 'omitnan');
		source(rowIdx, 1) = "centroid";
	end
end

function names = localReferenceBodypartNames(config)
	names = string(localNestedConfig(config, {'tracking_providers', 'SLEAP', 'reference_body_part'}, ""));
	names = names(:);
	names = names(strlength(strtrim(names)) > 0);
end

function value = localReferenceBodypartConfig(config)
	names = localReferenceBodypartNames(config);
	value = strjoin(names, ', ');
end

function [mode, referenceX, referenceY] = localReferenceGeometry(refJsonPath, config, arenaName, videoSize)
	mode = lower(string(localNestedConfig(config, {'defaults', 'distance2refmode'}, 'line')));
	if ~ismember(mode, ["point", "line"])
		mode = "line";
	end
	width = videoSize(1);
	height = videoSize(2);
	arenaConfig = localArenaConfig(config, arenaName);
	offset = localNestedConfig(config, {'tracking_providers', 'SLEAP', 'default_midpoint_xoffset_px'}, 0);
	if isstruct(arenaConfig) && isfield(arenaConfig, 'midpoint_xoffset_px')
		offset = arenaConfig.midpoint_xoffset_px;
	end
	offset = double(offset(1));
	referenceX = [width / 2 + offset, width / 2 + offset];
	referenceY = [0, height];
	if mode == "point"
		referenceY = [height / 2, height / 2];
	end

	if ~isfile(refJsonPath)
		return;
	end
	try
		jsonData = jsondecode(fileread(refJsonPath));
		if mode == "point" && isfield(jsonData, 'midpoint')
			[x, y, valid] = localReferencePair(jsonData.midpoint, 1);
			if valid
				referenceX = [x, x];
				referenceY = [y, y];
			end
		elseif mode == "line" && isfield(jsonData, 'midline')
			[x, y, valid] = localReferencePair(jsonData.midline, 2);
			if valid
				referenceX = x;
				referenceY = y;
			end
		end
	catch
	end
end

function [x, y, valid] = localReferencePair(value, minimumCount)
	valid = false;
	x = [];
	y = [];
	if isstruct(value) && isfield(value, 'x') && isfield(value, 'y')
		x = double(value.x(:)');
		y = double(value.y(:)');
	elseif isnumeric(value) && size(value, 1) == 2 && size(value, 2) >= minimumCount
		x = double(value(1, :));
		y = double(value(2, :));
	else
		return;
	end
	valid = numel(x) >= minimumCount && numel(y) >= minimumCount && ...
		all(isfinite(x(1:minimumCount))) && all(isfinite(y(1:minimumCount)));
	x = x(1:min(2, numel(x)));
	y = y(1:min(2, numel(y)));
end

function [points, referenceX, referenceY] = localApplyCameraFlips(points, referenceX, referenceY, videoSize, config)
	xflip = localProviderFlip(config, 'xflip', false);
	yflip = localProviderFlip(config, 'yflip', false);
	width = videoSize(1);
	height = videoSize(2);
	if xflip
		points(:, 1) = width - points(:, 1);
		referenceX = width - referenceX;
	end
	if yflip
		points(:, 2) = height - points(:, 2);
		referenceY = height - referenceY;
	end
end

function side = localClassifySides(points, referenceX, referenceY, mode)
	side = strings(size(points, 1), 1);
	finitePoints = all(isfinite(points), 2);
	if mode == "point"
		delta = points(:, 1) - referenceX(1);
		side(finitePoints & delta < 0) = "Left";
		side(finitePoints & delta > 0) = "Right";
		return;
	end

	p1 = [referenceX(1), referenceY(1)];
	p2 = [referenceX(2), referenceY(2)];
	if p1(2) > p2(2) || (p1(2) == p2(2) && p1(1) > p2(1))
		[p1, p2] = deal(p2, p1);
	end
	direction = p2 - p1;
	signedLeft = -direction(2) .* (points(:, 1) - p1(1)) + ...
		direction(1) .* (points(:, 2) - p1(2));
	side(finitePoints & signedLeft > 0) = "Left";
	side(finitePoints & signedLeft < 0) = "Right";
end

function [speakerPosition, sameZone, matchedStim, matchedSpeaker] = localAssignStimulusSides(titles, animalSide, speakerFlipped)
	nRows = numel(titles);
	speakerPosition = strings(nRows, 1);
	sameZone = zeros(nRows, 1);
	matchedStim = strings(nRows, 1);
	matchedSpeaker = strings(nRows, 1);
	currentChannel = "";
	currentStimulus = "";
	for rowIdx = 1:nRows
		title = string(titles(rowIdx));
		if startsWith(title, "[Ch1]")
			currentChannel = "Ch1";
			currentStimulus = title;
		elseif startsWith(title, "[Ch2]")
			currentChannel = "Ch2";
			currentStimulus = title;
		elseif ~endsWith(title, "ISI")
			currentChannel = "";
			currentStimulus = "";
		end
		if currentChannel == ""
			continue;
		end
		if currentChannel == "Ch1"
			activeSpeaker = "Left";
			if speakerFlipped
				activeSpeaker = "Right";
			end
		else
			activeSpeaker = "Right";
			if speakerFlipped
				activeSpeaker = "Left";
			end
		end
		speakerPosition(rowIdx) = activeSpeaker + " Speaker";
		if animalSide(rowIdx) == activeSpeaker
			sameZone(rowIdx) = 1;
			matchedStim(rowIdx) = currentStimulus;
			matchedSpeaker(rowIdx) = speakerPosition(rowIdx);
		end
	end
end

function [width, height] = localVideoSize(mediafile)
	reader = VideoReader(char(mediafile));
	width = reader.Width;
	height = reader.Height;
end

function value = localNestedConfig(config, path, defaultValue)
	value = defaultValue;
	current = config;
	for idx = 1:numel(path)
		if iscell(current) && numel(current) == 1
			current = current{1};
		end
		if ~isstruct(current) || ~isfield(current, path{idx})
			return;
		end
		current = current.(path{idx});
	end
	if iscell(current) && numel(current) == 1
		current = current{1};
	end
	value = current;
end

function value = localProviderFlip(config, axisName, defaultValue)
	value = localNestedConfig(config, {'defaults', axisName}, defaultValue);
	providerValue = localNestedConfig(config, {'tracking_providers', 'SLEAP', axisName}, []);
	if ~isempty(providerValue)
		value = providerValue;
	end
	value = localLogicalValue(value);
end

function arenaConfig = localArenaConfig(config, arenaName)
	arenaConfig = struct();
	arenas = localNestedConfig(config, {'tracking_providers', 'SLEAP', 'arena'}, {});
	if isstruct(arenas)
		arenas = num2cell(arenas);
	end
	if ~iscell(arenas)
		return;
	end
	for idx = 1:numel(arenas)
		if isstruct(arenas{idx}) && isfield(arenas{idx}, 'name') && ...
				strcmp(string(arenas{idx}.name), arenaName)
			arenaConfig = arenas{idx};
			return;
		end
	end
end

function triggerStartFrame = localReadTriggerStartFrame(refJsonPath)
	triggerStartFrame = [];
	if ~isfile(refJsonPath)
		return;
	end
	try
		refData = jsondecode(fileread(refJsonPath));
		if ~isfield(refData, 'trigger_events') || isempty(refData.trigger_events)
			return;
		end
		events = refData.trigger_events;
		if isnumeric(events)
			triggerStartFrame = double(events(1));
		elseif iscell(events) && isnumeric(events{1}) && ~isempty(events{1})
			triggerStartFrame = double(events{1}(1));
		end
		if isempty(triggerStartFrame) || ~isfinite(triggerStartFrame) || triggerStartFrame < 1
			triggerStartFrame = [];
		else
			triggerStartFrame = round(triggerStartFrame);
		end
	catch
		triggerStartFrame = [];
	end
end

function metadata = localAnimalMetadata(metadataRow)
	metadata = struct('sex', '', 'genotype', '', 'strain', '', 'age', '', ...
		'dob', NaT, 'cagecode', '', 'id', '', 'source', '');
	if isempty(metadataRow)
		return;
	end
	metadata.sex = char(string(metadataRow.('ANIMAL_SEX')));
	metadata.genotype = char(string(metadataRow.('ANIMAL_GENOTYPE')));
	metadata.strain = char(string(metadataRow.('ANIMAL_STRAIN')));
	metadata.age = metadataRow.('ANIMAL_P_AGE');
	if ~isnumeric(metadata.age)
		metadata.age = str2double(string(metadata.age));
	end
	metadata.dob = metadataRow.('ANIMAL_DOB');
	metadata.cagecode = char(string(metadataRow.('CAGE_CODE')));
	metadata.id = char(string(metadataRow.('ANIMAL_ID')));
	if ismember('SOURCE_CODE', metadataRow.Properties.VariableNames)
		metadata.source = char(string(metadataRow.('SOURCE_CODE')));
	end
end

function localCleanupAlignedCaches(filedir, dataBaseName, trackingPlatform, canonicalFile)
	files = dir(fullfile(filedir, '*.mat'));
	for idx = 1:numel(files)
		candidate = fullfile(files(idx).folder, files(idx).name);
		if strcmpi(candidate, canonicalFile)
			continue;
		end
		info = io.cache.parseAlignedCacheFileName(files(idx).name, ...
			ExpectedDataBaseName=dataBaseName, ExpectedTrackingPlatform=trackingPlatform);
		if info.isAlignedCache && strcmp(info.dataBaseName, string(dataBaseName)) && ...
			(info.isLegacy || (info.isProviderLabeled && ...
			strcmpi(info.trackingPlatform, trackingPlatform)))
			warning('io:sleap:alignTrackingToStim:RemovingOldCache', ...
				'Removing old SLEAP aligned file "%s".', candidate);
			delete(candidate);
		end
	end
end

function mustBePositiveIntOrEmpty(value)
	if isempty(value)
		return;
	end
	mustBePositive(value);
	mustBeInteger(value);
end

function mustBeNumericLogicalOrEmpty(value)
	if isempty(value)
		return;
	end
	mustBeNumericOrLogical(value);
end
