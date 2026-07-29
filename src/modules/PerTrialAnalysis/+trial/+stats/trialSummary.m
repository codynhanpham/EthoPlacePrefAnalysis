function [summary, centerpointData] = trialSummary(trackingDataFile, stimuliDir, masterMetadataTable, kvargs)
    %%TRIALSUMMARY Align tracking data to stimulus events and summarize trial information
    %
    %   summary = trial.stats.trialSummary(ethovisionXlsx, stimuliDir, masterMetadataTable)
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTable - The master metadata table loaded from an Excel file with io.metadata.loadMasterMetadata
    %
    %   Name-Value Pair Arguments:
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml().
    %         IMPORTANT: Arena-grid speaker-flip behavior is read from:
    %         Config.arena_grid.invert_gradient_score_on_speaker_flip
    %         which must be one of {'x', 'y', 'both', 'none'} (default: 'x').
    %       - 'PreStimDurationSec': The duration in seconds to include before the first stimulus onset in the trial summary. Default is 480s (8 minutes) to cover typical pre-stimulus periods in place preference experiments. Set this to 0 to only include frames from the first stimulus onset onward. 'Trial time' for pre-stimulus frames will be negative, relative to time 0s at stimulus onset. If this is outside the range of the recording, missing timepoints data will be filled with NaNs.
    %       - 'PostStimDurationSec': The duration in seconds to include after the last stimulus offset in the trial summary. Default is 0s. 'Trial time' for post-stimulus frames will be positive, relative to time 0s at stimulus onset. If this is outside the range of the recording, missing timepoints data will be filled with NaNs.
    %
    %   Outputs:
    %       summary - A struct containing the analysis results:
    %           + animalMetadata - Metadata about the animal (age, sex, strain, genotype)
    %           + animalMatchedStim - Dictionary of stimulus names with # frame count where the animal was in the "active" stimulus zone
    %           + stimspeakerMatched - Left/Right speaker position of the matched stimulus frames (same as animalMatchedStim but with speaker position)
    %           + stimspeakerOriginal - Left/Right speaker position of the original stimulus, in frames, as designed in the stimulus file regardless of animal position
    %       centerpointData - A brief struct containing animal position over time:
    %           + fps - The framerate of the EthoVision recording in frames per second
    %           + data - A table with distance from midline values for each frame/timepoint during the stimulus period with 3 columns:
    %               * 'Trial time' - Time in seconds from the start of stimulus period (start at 0s), to get the absolute time relative to the start of trial, add 'stimulusStartTimeOffset'. If PreStimDurationSec > 0, this will include negative time values covering the pre-stimulus period; if PostStimDurationSec > 0, this will also include time values after the stimulus end covering the post-stimulus period.
    %               * 'X center' - The corrected (via config) X center position of the animal in cm 
    %               * 'Y center' - The corrected (via config) Y center position of the animal in cm
    %               * 'Stimulus name' - The name of the stimulus being played at that time. In addition, if PreStimDurationSec > 0, the pre-stimulus period will be labeled as 'NONE | Pre-Stimulus'; and/or if PostStimDurationSec > 0, the post-stimulus period will be labeled as 'NONE | Post-Stimulus'.
    %           + arenaGridScore - An array of size [height(data), 1] with the arena grid score (0-1) for each frame/timepoint during the stimulus period, calculated based on the center position and the arena grid defined for this trial in *.ref.arenagrid.mat. If the file for this trial doesn't exist or fail to load, this will be an empty array.
    %           + midline_x_px - The X coordinate of the arena midpoint (if scalar) or midline line (if 2-element vector) in pixels
    %           + midline_y_px - The Y coordinate of the arena midpoint (if scalar) or midline line (if 2-element vector) in pixels
    %           + px2cm - Conversion factor from pixels to centimeters (such that cm = px * px2cm)
    %           + stimulusStartTimeOffset - The time offset in seconds from the start of the trial to the start of the stimulus period
    %           + stimuliCorrected - A struct with fields: neg and pos, each containing a scalar string of the stimulus names played on that side, corrected by (flipped?) speaker position
    %               * left: stimulus name played on left side
    %               * right: stimulus name played on right side
    %           + speakerFlipped - Boolean indicating if the speaker positions were flipped for this trial
    %               Whether this trial had the left/right speaker positions flipped compared to the default configuration originally
    %           + stimuliMetadata - metadata of the stimuli used in this trial, including individual stimulus timestamps and durations
    %
    %
    %   See also: io.ethovision.alignEthovisionRawToStim, io.metadata.loadMasterMetadata, io.config.loadConfigYaml, io.stimuli.extractMetadata

    arguments
        trackingDataFile {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTable {validator.mustBeFileOrTable}

        kvargs.Config (1,1) struct = struct() % The full configuration struct loaded with io.config.loadConfigYaml()
        kvargs.TrackingProvider (1,1) {validator.mustBeTrackingProviderOrEmpty} = []
        kvargs.PreStimDurationSec (1,1) {mustBeNonnegative, mustBeFinite} = 480 % The duration in seconds to include before the first stimulus onset in the trial summary. Default is 480s (8 minutes) to cover typical pre-stimulus periods in place preference experiments. Set this to 0 to only include frames from the first stimulus onset onward. 'Trial time' for pre-stimulus frames will be negative, relative to time 0s at stimulus onset. If this is outside the range of the recording, missing timepoints data will be filled with NaNs.
        kvargs.PostStimDurationSec (1,1) {mustBeNonnegative, mustBeFinite} = 0 % The duration in seconds to include after the last stimulus offset in the trial summary. Default is 0s. 'Trial time' for post-stimulus frames will be positive, relative to time 0s at stimulus onset. If this is outside the range of the recording, missing timepoints data will be filled with NaNs.
    end

    if isempty(kvargs.TrackingProvider)
        error('trial:stats:trialSummary:MissingTrackingProvider', ...
            'TrackingProvider must be provided for trial alignment.');
    end
    [header, datatable, ~, stimulusFrameRange, animalMetadata, stimuli] = ...
        kvargs.TrackingProvider.alignTrackingToStim(trackingDataFile, stimuliDir, ...
        Options=struct('MasterMetadataTable', masterMetadataTable, 'Config', kvargs.Config));

    stimStartFrame = stimulusFrameRange(1);
    stimEndFrame = stimulusFrameRange(2);

    % Keep stimulus-only period for summary metrics (no pre/post contribution).
    stimPeriodTable = datatable(stimStartFrame:stimEndFrame, :);

    % Build centerpoint output window around stimulus period.
    % Time 0s must align to stimulus onset, with optional pre/post extension.
    allTrialTime = datatable{:, 'Trial time'};
    fpsFromData = mean(diff(allTrialTime), 'omitnan')^-1;
    if ~isfinite(fpsFromData) || fpsFromData <= 0
        warning('trial:stats:trialSummary:InvalidFPS', ...
            'Unable to infer valid FPS from trial time values. Falling back to 30 FPS for pre/post windowing.');
        fpsFromData = 30;
    end
    frameInterval = 1 / fpsFromData;

    preFrames = round(kvargs.PreStimDurationSec * fpsFromData);
    postFrames = round(kvargs.PostStimDurationSec * fpsFromData);

    windowStartFrame = stimStartFrame - preFrames;
    windowEndFrame = stimEndFrame + postFrames;

    nRowsTotal = size(datatable, 1);
    windowIndices = (windowStartFrame:windowEndFrame)';
    windowLength = numel(windowIndices);
    inRangeMask = windowIndices >= 1 & windowIndices <= nRowsTotal;
    inRangePositions = find(inRangeMask);
    inRangeRows = windowIndices(inRangeMask);

    stimulusStartAbsTime = datatable{stimStartFrame, 'Trial time'};
    % Relative time from stimulus onset for all desired rows, including padded rows.
    windowTrialTimeRel = (windowIndices - stimStartFrame) * frameInterval;
    if ~isempty(inRangeRows)
        windowTrialTimeRel(inRangePositions) = datatable{inRangeRows, 'Trial time'} - stimulusStartAbsTime;
    end

    windowXCenter = nan(windowLength, 1);
    windowYCenter = nan(windowLength, 1);
    windowStimulusName = strings(windowLength, 1);
    windowStimulusName(:) = missing;
    windowDistanceToPoint = [];
    if ismember("Distance to point", datatable.Properties.VariableNames)
        windowDistanceToPoint = nan(windowLength, 1);
    end

    if ~isempty(inRangeRows)
        windowXCenter(inRangePositions) = datatable{inRangeRows, 'X center'};
        windowYCenter(inRangePositions) = datatable{inRangeRows, 'Y center'};
        windowStimulusName(inRangePositions) = string(datatable{inRangeRows, 'Chapter Original'});
        if ~isempty(windowDistanceToPoint)
            windowDistanceToPoint(inRangePositions) = datatable{inRangeRows, 'Distance to point'};
        end
    end

    % Fill labels for padded rows and any empty labels.
    missingStimulusNameMask = ismissing(windowStimulusName) | strlength(strtrim(windowStimulusName)) == 0;
    windowStimulusName(missingStimulusNameMask & windowIndices < stimStartFrame) = "NONE | Pre-Stimulus";
    windowStimulusName(missingStimulusNameMask & windowIndices > stimEndFrame) = "NONE | Post-Stimulus";
    windowStimulusName(missingStimulusNameMask & windowIndices >= stimStartFrame & windowIndices <= stimEndFrame) = "NONE | Stimulus";

    allstims = stimPeriodTable{:,'Chapter Original'};
    allstims = unique(allstims(~cellfun(@anymissing, allstims)));
    allstims = allstims(~endsWith(allstims, 'ISI'));
    outrointro = {'Outro', 'Intro'};
    allstims = allstims(~startsWith(allstims, outrointro) & ~endsWith(allstims, outrointro));

    % Animal position is in the "active" speaker/stim zone
    animalMatchedStim = stimPeriodTable{:,'Animal Matched Stim Name'};
    animalMatchedStimFrameFreq = configureDictionary("string", "double");

    % Real data may contain no valid matched stim labels (animal is not ever in the stim zone); keep an empty typed dictionary.
    animalMatchedStimStr = string(animalMatchedStim);
    validMatchedStim = ~ismissing(animalMatchedStimStr) & strlength(strtrim(animalMatchedStimStr)) > 0;
    if any(validMatchedStim)
        cats = categories(categorical(animalMatchedStimStr(validMatchedStim)));
        animalMatchedStimCounts = countcats(categorical(animalMatchedStimStr(validMatchedStim)));
        animalMatchedStimFrameFreq = dictionary(string(cats), animalMatchedStimCounts);
    end
    missingStims = setdiff(allstims, keys(animalMatchedStimFrameFreq));
    for i = 1:length(missingStims)
        animalMatchedStimFrameFreq(missingStims{i}) = 0;
    end

    % Left/Right speaker position of the matched stimulus frames
    stimspeakerMatched = stimPeriodTable{:,'Matched Speaker Position'};
    stimspeakerMatchedFrameFreq = configureDictionary("string", "double");
    stimspeakerMatchedStr = string(stimspeakerMatched);
    validMatchedSpeaker = ~ismissing(stimspeakerMatchedStr) & strlength(strtrim(stimspeakerMatchedStr)) > 0;
    if any(validMatchedSpeaker)
        speakerCats = categories(categorical(stimspeakerMatchedStr(validMatchedSpeaker)));
        speakerCounts = countcats(categorical(stimspeakerMatchedStr(validMatchedSpeaker)));
        stimspeakerMatchedFrameFreq = dictionary(string(speakerCats), speakerCounts);
    end
    missingSpeakers = setdiff(["Left Speaker", "Right Speaker"], keys(stimspeakerMatchedFrameFreq));
    for i = 1:length(missingSpeakers)
        stimspeakerMatchedFrameFreq(missingSpeakers{i}) = 0;
    end

    % Count the frequency of stim speaker positions extended (available/original, no match by animal position)
    stimspeakerExtended = stimPeriodTable{:,'Stim Speaker Corrected'};
    stimspeakerOriginalFrameFreq = configureDictionary("string", "double");
    stimspeakerExtendedStr = string(stimspeakerExtended);
    validExtendedSpeaker = ~ismissing(stimspeakerExtendedStr) & strlength(strtrim(stimspeakerExtendedStr)) > 0;
    if any(validExtendedSpeaker)
        speakerCatsExtended = categories(categorical(stimspeakerExtendedStr(validExtendedSpeaker)));
        speakerCountsExtended = countcats(categorical(stimspeakerExtendedStr(validExtendedSpeaker)));
        stimspeakerOriginalFrameFreq = dictionary(string(speakerCatsExtended), speakerCountsExtended);
    end
    missingSpeakersExtended = setdiff(["Left Speaker", "Right Speaker"], keys(stimspeakerOriginalFrameFreq));
    for i = 1:length(missingSpeakersExtended)
        stimspeakerOriginalFrameFreq(missingSpeakersExtended{i}) = 0;
    end

    summary = struct(...
        'animalMetadata', animalMetadata, ...
        'animalMatchedStim', animalMatchedStimFrameFreq, ...
        'stimspeakerMatched', stimspeakerMatchedFrameFreq, ...
        'stimspeakerOriginal', stimspeakerOriginalFrameFreq ...
    );


    % For each key in animalMatchedStimFrameFreq, find the key in stimspeakerMatchedFrameFreq that has the same value, log the key with that value for normalization
    stim2speakerMap = configureDictionary("string", "string");
    stimKeys = keys(animalMatchedStimFrameFreq);
    for i = 1:length(stimKeys)
        stimKey = stimKeys{i};
        stimValue = animalMatchedStimFrameFreq(stimKey);
        speakerKey = "";
        speakerKeys = keys(stimspeakerMatchedFrameFreq);
        for j = 1:length(speakerKeys)
            if stimspeakerMatchedFrameFreq(speakerKeys{j}) == stimValue
                speakerKey = speakerKeys{j};
                break;
            end
        end
        if speakerKey ~= ""
            stim2speakerMap(stimKey) = speakerKey;
        end
    end

    [~, sortIdx] = sort(values(stim2speakerMap), 'ascend'); % We know that Left* will be sorted before Right*
    stimKeys = keys(stim2speakerMap);
    stimKeys = stimKeys(sortIdx); % Stim in left speaker first, then right speaker, 




    configs = kvargs.Config;
    fromConfigKey = {'tracking_providers', 'EthoVision', 'default_camera_imgwidth_fov_cm'};
    ImgWidthFOV_cm = 58.5; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        ImgWidthFOV_cm = getfield(configs, fromConfigKey{:});
        if iscell(ImgWidthFOV_cm)
            ImgWidthFOV_cm = cell2mat(ImgWidthFOV_cm);
        end
    end

    fromConfigKey = {'tracking_providers', 'EthoVision', 'default_camera_center_offset_px'};
    CenterOffset_px = [0,0]; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        CenterOffset_px = getfield(configs, fromConfigKey{:});
        CenterOffset_px = cell2mat(CenterOffset_px);
    end

    arenaName = header("Arena name");
    % Check for configs overrides for this arena
    arenaConfigPath = {'tracking_providers', 'EthoVision', 'arena'};
    if validator.nestedStructFieldExists(configs, arenaConfigPath)
        arenaConfigs = getfield(configs, arenaConfigPath{:});
        if iscell(arenaConfigs)
            namesinconfig = cellfun(@(x) x.name, arenaConfigs, 'UniformOutput', false);
        else
            namesinconfig = arenaConfigs.name;
        end
        namesinconfig = string(namesinconfig);
        if ismember(arenaName, namesinconfig)
            arenaIdx = find(strcmp(namesinconfig, arenaName), 1);
            if iscell(arenaConfigs)
                arenaConfig = arenaConfigs{arenaIdx};
            else
                arenaConfig = arenaConfigs(arenaIdx);
            end
            if isfield(arenaConfig, 'camera_imgwidth_fov_cm')
                ImgWidthFOV_cm = arenaConfig.camera_imgwidth_fov_cm;
            end
            if isfield(arenaConfig, 'camera_center_offset_px')
                CenterOffset_px = arenaConfig.camera_center_offset_px;
                CenterOffset_px = cell2mat(CenterOffset_px);
            end
        end
    end

    videoFilePath = kvargs.TrackingProvider.mediaPathFromTrackingData(trackingDataFile);
    if ~isfile(videoFilePath)
        error("Video file not found: %s.\nMake sure your folder structure is exactly how EthoVision exported it, with an 'Export Files' folder and a 'Media Files' folder.", videoFilePath);
    end

    v = VideoReader(videoFilePath);
    vidWidth = v.Width;
    vidHeight = v.Height;
    pixelsize = ImgWidthFOV_cm / vidWidth; % cm/pixel

    centerPos = [windowXCenter, windowYCenter];
    centerPos(:,1) = centerPos(:,1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
    centerPos(:,2) = centerPos(:,2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system, such that top-left is (0,0))
    centerPos(:,2) = vidHeight * pixelsize - centerPos(:,2);
    trialTime = windowTrialTimeRel;


    fromConfigKey = {'defaults', 'xflip'};
    xflip = false; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        xflip = getfield(configs, fromConfigKey{:});
        if ~islogical(xflip)
            try
                xflip = logical(xflip);
            catch ME
                xflip = false;
                warning('stats:trialSummary:xflip:InvalidValue', 'Invalid value for xflip in config, must be boolean. Using default false.\n%s', getReport(ME));
            end
        end
    end
    fromConfigKey = {'defaults', 'yflip'};
    yflip = false; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        yflip = getfield(configs, fromConfigKey{:});
        if ~islogical(yflip)
            try
                yflip = logical(yflip);
            catch ME
                yflip = false;
                warning('stats:trialSummary:yflip:InvalidValue', 'Invalid value for yflip in config, must be boolean. Using default false.\n%s', getReport(ME));
            end
        end
    end


    % MidlineX and midlineY, in px, top-left is (0,0), loaded from .ref.json
    % (legacy .midpoint.csv/.midline.csv are auto-migrated) depending on
    % config's defaults.distance2refmode.
    refmode = 'line'; % default
    fromConfigKey = {'defaults', 'distance2refmode'};
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        refmode = getfield(configs, fromConfigKey{:});
        if iscell(refmode)
            refmode = string(refmode{1});
        end
        if ~ismember(refmode, ["point", "line"])
            refmode = 'line'; % fallback to default
            warning("trial:stats:trialSummary:InvalidConfig", "Invalid config value for 'defaults.distance2refmode': %s. Falling back to 'line'.", refmode);
        end
    end
    [videoDir, videoBaseName, ~] = fileparts(videoFilePath);
    graphics.migrateLegacyCSVRefs2JSON(videoDir);
    
    referenceFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));
    referenceSeedFilePath = referenceFilePath;

    switch refmode
        % Note that in any condition, at this point centerPos already has been converted to image coordinates (top-left is (0,0)) AND adjusted by CenterOffset_px from config
        % Any offset for midpoint/midline is relative to the size of the video frame itself
        case 'point'
            % Default values: midpoint is at center of video frame
            midlineX = vidWidth / 2;
            midlineY = vidHeight / 2;
            if ~isfile(referenceSeedFilePath)
                referenceFiles = dir(fullfile(videoDir, '*.ref.json'));
                if ~isempty(referenceFiles)
                    referenceSeedFilePath = fullfile(videoDir, referenceFiles(end).name);
                end
            end

            % If midpoint exists in reference file, load that as reference point.
            fromfile_ok = false;
            if isfile(referenceSeedFilePath)
                try
                    jsonData = jsondecode(fileread(referenceSeedFilePath));
                    if isfield(jsonData, 'midpoint')
                        if isstruct(jsonData.midpoint) && isfield(jsonData.midpoint, 'x') && isfield(jsonData.midpoint, 'y')
                            midlineX = jsonData.midpoint.x;
                            midlineY = jsonData.midpoint.y;
                            fromfile_ok = true;
                        elseif isnumeric(jsonData.midpoint) && numel(jsonData.midpoint) >= 2
                            midlineX = jsonData.midpoint(1);
                            midlineY = jsonData.midpoint(2);
                            fromfile_ok = true;
                        end
                    end
                catch ME
                    warning('trial:stats:trialSummary:referencePointFilePath:LoadError', 'Error loading reference midpoint from file: %s\n%s', referenceSeedFilePath, ME.message);
                end
            end
            if ~fromfile_ok
                % Use Distance to point when available as secondary fallback if loading from file failed
                % For 'point' mode, this is often much better than just assume the center of the frame
                if ~isempty(windowDistanceToPoint)
                    distFromMidline_cm = windowDistanceToPoint; % These are absolute values, need to determine sign based on X position!
                    assert(size(distFromMidline_cm,1) == size(trialTime,1), "Size mismatch between distFromMidline_cm and trialTime");

                    % Determine sign based on X position relative to the mid-point (X0, Y0)
                    centerPos_cm = [windowXCenter, windowYCenter];
                    % Find the coordinate of the midpoint (where the distance to point was measured from)
                    % EthoVision doesn't provide this directly, so we have to calculate it manually
                    refPoint = findReferencePointLinear(centerPos_cm, distFromMidline_cm);
                    % Since refPoint was calc using the raw X,Y center positions in cm in the data table, we need to re-apply offsets and convert to px
                    refPoint(1) = refPoint(1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
                    refPoint(2) = refPoint(2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
                    refPoint = refPoint / pixelsize; % convert to px
                    midlineX = refPoint(1);
                    midlineY = refPoint(2);
                end
            end


        case 'line'
            % Default values: midline is vertical line at center of video frame
            midlineX = [vidWidth/2, vidWidth/2];
            midlineY = [0, vidHeight];
            if ~isfile(referenceSeedFilePath)
                referenceFiles = dir(fullfile(videoDir, '*.ref.json'));
                if ~isempty(referenceFiles)
                    referenceSeedFilePath = fullfile(videoDir, referenceFiles(end).name);
                end
            end

            % If midline exists in reference file, load that as reference line.
            if isfile(referenceSeedFilePath)
                try
                    jsonData = jsondecode(fileread(referenceSeedFilePath));
                    if isfield(jsonData, 'midline') && isfield(jsonData.midline, 'x') && isfield(jsonData.midline, 'y')
                        if numel(jsonData.midline.x) >= 2 && numel(jsonData.midline.y) >= 2
                            midlineX = [jsonData.midline.x(1), jsonData.midline.x(2)];
                            midlineY = [jsonData.midline.y(1), jsonData.midline.y(2)];
                        end
                    end
                catch ME
                    warning('trial:stats:trialSummary:referenceLineFilePath:LoadError', 'Error loading reference midline from file: %s\n%s', referenceSeedFilePath, ME.message);
                end
            end

        otherwise
            error("Unexpected refmode: %s", refmode);
    end

    % Mirror the centerPos coordinates if specified in config:
    % Note that centerPos here is in cm, but translated to fits image coordinates (top-left is (0,0))
    % If ref is point, simply use the point as the horizontal and/or vertical axis of symmetry
    % If ref is line, use the line as the axis of symmetry
    if strcmpi(refmode, 'point')
        if xflip
            centerPos(:,1) = 2 * (midlineX * pixelsize) - centerPos(:,1);
        end
        if yflip
            centerPos(:,2) = 2 * (midlineY * pixelsize) - centerPos(:,2);
        end
    elseif strcmpi(refmode, 'line')
        centerPos = mirrorPointsAcrossLine(centerPos, midlineX * pixelsize, midlineY * pixelsize);
    end

    
    speakerFlipped = stimPeriodTable{1,'Speaker Channels Flipped'}; % should be the same for the whole trial

    % Infer arena-grid gradient inversion behavior from config.
    invertOnSpeakerFlip = 'x'; % default for compatibility
    invertOnSpeakerFlipPath = {'arena_grid', 'invert_gradient_score_on_speaker_flip'};
    if validator.nestedStructFieldExists(configs, invertOnSpeakerFlipPath)
        invertOnSpeakerFlip = getfield(configs, invertOnSpeakerFlipPath{:});
        if iscell(invertOnSpeakerFlip)
            invertOnSpeakerFlip = invertOnSpeakerFlip{1};
        end
        invertOnSpeakerFlip = string(invertOnSpeakerFlip);
        validInvertModes = ["x", "y", "both", "none"];
        if ~isscalar(invertOnSpeakerFlip) || ~ismember(lower(invertOnSpeakerFlip), validInvertModes)
            warning('trial:stats:trialSummary:InvalidConfig', ...
                "Invalid config value for 'arena_grid.invert_gradient_score_on_speaker_flip': %s. Falling back to 'x'.", ...
                string(invertOnSpeakerFlip));
            invertOnSpeakerFlip = "x";
        else
            invertOnSpeakerFlip = lower(invertOnSpeakerFlip);
        end
    end


    % Check and load .ref.arenagrid.mat if exists
    referenceArenaFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.arenagrid.mat'));
    if ~isfile(referenceArenaFilePath)
        arenaGridScore = [];
    else
        try
            % Init ArenaGrid for score query
            arenaGrid = trial.arenaGrid.ArenaGrid.fromFile(referenceArenaFilePath);

            % ArenaGrid expects pixel coordinates in CRT/image convention:
            % top-left origin with units in pixels.
            centerPosPx = centerPos / pixelsize;
            arenaGridScore = nan(size(centerPosPx, 1), 1);
            validXY = all(isfinite(centerPosPx), 2);

            % Figure out the kvargs for 'invertXGradient' and 'invertYGradient' based on speaker flip and config
            invertXGradient = false;
            invertYGradient = false;
            if speakerFlipped
                switch invertOnSpeakerFlip
                    case 'x'
                        invertXGradient = true;
                    case 'y'
                        invertYGradient = true;
                    case 'both'
                        invertXGradient = true;
                        invertYGradient = true;
                    case 'none'
                        % do nothing
                end
            end

            if any(validXY)
                arenaGridScore(validXY) = arenaGrid.queryScore(centerPosPx(validXY, :), ...
                    'invertXGradient', invertXGradient, ...
                    'invertYGradient', invertYGradient ...
                );
            end
        catch ME
            warning('trial:stats:trialSummary:arenaGridFile:LoadError', 'Error loading arena grid file: %s\n%s', referenceArenaFilePath, ME.message);
            arenaGridScore = [];
        end
    end



    stimKeys = string(stimKeys);
    stimuliCorrected = struct(...
        'left', stimKeys(1), ...
        'right', stimKeys(2) ...
    );
    offset = stimulusStartAbsTime;
    cpdata = table(windowTrialTimeRel, centerPos(:,1), centerPos(:,2), cellstr(windowStimulusName), ...
        'VariableNames', {'Trial time', 'X center', 'Y center', 'Stimulus name'});

    centerpointData = struct(...
        'fps', fpsFromData, ...
        'data', cpdata, ...
        'arenaGridScore', arenaGridScore, ...
        'midline_x_px', midlineX, ...
        'midline_y_px', midlineY, ...
        'px2cm', pixelsize, ... % conversion factor such that cm = px * px2cm
        'stimulusStartTimeOffset', offset, ...
        'stimuliCorrected', stimuliCorrected, ...
        'speakerFlipped', speakerFlipped, ...
        'stimuliMetadata', stimuli ...
    );
end



function refPoint = findReferencePointLinear(xyCoords, distances)
    % Filter out NaN values
    validIdx = ~isnan(xyCoords(:,1)) & ~isnan(xyCoords(:,2)) & ~isnan(distances);
    validCoords = xyCoords(validIdx, :);
    validDistances = distances(validIdx);
    
    n = size(validCoords, 1);
    if n < 2
        error('Need at least 2 valid (non-NaN) points to calculate reference point. Found %d valid points.', n);
    end
    
    % Use first valid point as reference for differencing
    x1 = validCoords(1, 1); y1 = validCoords(1, 2); d1 = validDistances(1);
    
    % Build linear system Ax = b
    A = zeros(n-1, 2);
    b = zeros(n-1, 1);
    
    for i = 2:n
        xi = validCoords(i, 1); yi = validCoords(i, 2); di = validDistances(i);
        A(i-1, :) = 2 * [x1 - xi, y1 - yi];
        b(i-1) = x1^2 - xi^2 + y1^2 - yi^2 + di^2 - d1^2;
    end
    
    % Solve linear system
    refPoint = (A \ b)';
end

function points = mirrorPointsAcrossLine(points, lineX, lineY)
    % Define line passing through P1(x1,y1) and P2(x2,y2)
    x1 = lineX(1); y1 = lineY(1);
    x2 = lineX(2); y2 = lineY(2);
    
    % Line equation: Ax + By + C = 0
    A = y1 - y2;
    B = x2 - x1;
    C = -A*x1 - B*y1;
    
    % Calculate reflection
    M = A^2 + B^2;
    if M > 0
        val = A .* points(:,1) + B .* points(:,2) + C;
        factor = -2 * val / M;
        points(:,1) = points(:,1) + factor * A;
        points(:,2) = points(:,2) + factor * B;
    end
end