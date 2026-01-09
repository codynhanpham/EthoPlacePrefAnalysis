function [summary, centerpointData] = trialSummary(ethovisionXlsx, stimuliDir, masterMetadataTable, kvargs)
    %%TRIALSUMMARY Align EthoVision data to stimulus events and summarize trial information
    %
    %   summary = trial.stats.trialSummary(ethovisionXlsx, stimuliDir, masterMetadataTable)
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTable - The master metadata table loaded from an Excel file with io.metadata.loadMasterMetadata
    %
    %   Name-Value Pair Arguments:
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml()
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
    %               * 'Trial time' - Time in seconds from the start of stimulus period (start at 0s), to get the absolute time relative to the start of trial, add 'stimulusStartTimeOffset'
    %               * 'X center' - The corrected (via config) X center position of the animal in cm 
    %               * 'Y center' - The corrected (via config) Y center position of the animal in cm
    %               * 'Stimulus name' - The name of the stimulus being played at that time
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
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTable {validator.mustBeFileOrTable}

        kvargs.Config (1,1) struct = struct() % The full configuration struct loaded with io.config.loadConfigYaml()
    end

    [header, datatable, units, stimulusFrameRange, animalMetadata, stimuli] = io.ethovision.alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTable, ...
        Config=kvargs.Config ...
    );

    stimPeriodTable = datatable(stimulusFrameRange(1):stimulusFrameRange(2), :);

    allstims = stimPeriodTable{:,'Chapter Original'};
    allstims = unique(allstims(~cellfun(@anymissing, allstims)));
    allstims = allstims(~endsWith(allstims, 'ISI'));
    outrointro = {'Outro', 'Intro'};
    allstims = allstims(~startsWith(allstims, outrointro) & ~endsWith(allstims, outrointro));

    % Animal position is in the "active" speaker/stim zone
    animalMatchedStim = stimPeriodTable{:,'Animal Matched Stim Name'};
    cats = categories(categorical(animalMatchedStim));
    animalMatchedStimCounts = countcats(categorical(animalMatchedStim));
    animalMatchedStimFrameFreq = dictionary(string(cats), animalMatchedStimCounts);
    missingStims = setdiff(allstims, keys(animalMatchedStimFrameFreq));
    for i = 1:length(missingStims)
        animalMatchedStimFrameFreq(missingStims{i}) = 0;
    end

    % Left/Right speaker position of the matched stimulus frames
    stimspeakerMatched = stimPeriodTable{:,'Matched Speaker Position'};
    speakerCats = categories(categorical(stimspeakerMatched));
    speakerCounts = countcats(categorical(stimspeakerMatched));
    stimspeakerMatchedFrameFreq = dictionary(string(speakerCats), speakerCounts);
    missingSpeakers = setdiff(["Left Speaker", "Right Speaker"], keys(stimspeakerMatchedFrameFreq));
    for i = 1:length(missingSpeakers)
        stimspeakerMatchedFrameFreq(missingSpeakers{i}) = 0;
    end

    % Count the frequency of stim speaker positions extended (available/original, no match by animal position)
    stimspeakerExtended = stimPeriodTable{:,'Stim Speaker Corrected'};
    speakerCatsExtended = categories(categorical(stimspeakerExtended));
    speakerCountsExtended = countcats(categorical(stimspeakerExtended));
    stimspeakerOriginalFrameFreq = dictionary(string(speakerCatsExtended), speakerCountsExtended);
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

    [speakers, sortIdx] = sort(values(stim2speakerMap), 'ascend'); % We know that Left* will be sorted before Right*
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

    videoFilePath = io.ethovision.mediaPathFromXlsx(ethovisionXlsx);
    if ~isfile(videoFilePath)
        error("Video file not found: %s.\nMake sure your folder structure is exactly how EthoVision exported it, with an 'Export Files' folder and a 'Media Files' folder.", videoFilePath);
    end

    v = VideoReader(videoFilePath);
    vidWidth = v.Width;
    vidHeight = v.Height;
    pixelsize = ImgWidthFOV_cm / vidWidth; % cm/pixel

    centerPos = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
    centerPos(:,1) = centerPos(:,1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
    centerPos(:,2) = centerPos(:,2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system, such that top-left is (0,0))
    centerPos(:,2) = vidHeight * pixelsize - centerPos(:,2);
    trialTime = stimPeriodTable{:,'Trial time'};


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


    % MidlineX and midlineY, in px, top-left is (0,0), corrected by the relevant .midpoint.csv or .midline.csv data depending on config's defaults.distance2refmode
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
    switch refmode
        % Note that in any condition, at this point centerPos already has been converted to image coordinates (top-left is (0,0)) AND adjusted by CenterOffset_px from config
        % Any offset for midpoint/midline is relative to the size of the video frame itself
        case 'point'
            % Default values: midpoint is at center of video frame
            midlineX = vidWidth / 2;
            midlineY = vidHeight / 2;
            midPointFilePath = fullfile(videoDir, strcat(videoBaseName, '.midpoint.csv'));
            if ~isfile(midPointFilePath)
                % Find any existing midpoint files in the same directory and use that as default
                midPointFiles = dir(fullfile(videoDir, '*.midpoint.csv'));
                if ~isempty(midPointFiles)
                    midPointFilePathFallback = fullfile(videoDir, midPointFiles(end).name);
                    % clone this file to be the current video's midpoint file
                    copyfile(midPointFilePathFallback, midPointFilePath);
                end
            end

            % If midpoint file exists, load that as reference point
            fromfile_ok = false;
            if isfile(midPointFilePath)
                try
                    midpointData = readtable(midPointFilePath);
                    if all(ismember({'x', 'y'}, midpointData.Properties.VariableNames))
                        midlineX = midpointData.x(1);
                        midlineY = midpointData.y(1);
                        fromfile_ok = true;
                    end
                catch ME
                    warning('graphics:trialPlacePref:midPointFilePath:LoadError', 'Error loading existing midpoint file: %s\n%s', midPointFilePath, ME.message);
                end
            end
            if ~fromfile_ok
                % Use Distance to point when available as secondary fallback if loading from file failed
                % For 'point' mode, this is often much better than just assume the center of the frame
                if ismember("Distance to point", stimPeriodTable.Properties.VariableNames)
                    distFromMidline_cm = stimPeriodTable{:,'Distance to point'}; % These are absolute values, need to determine sign based on X position!
                    assert(size(distFromMidline_cm,1) == size(trialTime,1), "Size mismatch between distFromMidline_cm and trialTime");

                    % Determine sign based on X position relative to the mid-point (X0, Y0)
                    centerPos_cm = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
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
            midLineFilePath = fullfile(videoDir, strcat(videoBaseName, '.midline.csv'));
            if ~isfile(midLineFilePath)
                % Find any existing midline files in the same directory and use that as default
                midLineFiles = dir(fullfile(videoDir, '*.midline.csv'));
                if ~isempty(midLineFiles)
                    midLineFilePathFallback = fullfile(videoDir, midLineFiles(end).name);
                    % clone this file to be the current video's midline file
                    copyfile(midLineFilePathFallback, midLineFilePath);
                end
            end
            % If midline file exists, load that as reference line
            if isfile(midLineFilePath)
                try
                    midlineData = readtable(midLineFilePath);
                    if all(ismember({'x', 'y'}, midlineData.Properties.VariableNames))
                        % Get the first two points to define the midline
                        midlineX = midlineData.x(1:2)';
                        midlineY = midlineData.y(1:2)';
                    end
                catch ME
                    warning('graphics:trialPlacePref:midLineFilePath:LoadError', 'Error loading existing midline file: %s\n%s', midLineFilePath, ME.message);
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
    stimKeys = string(stimKeys);
    stimuliCorrected = struct(...
        'left', stimKeys(1), ...
        'right', stimKeys(2) ...
    );
    offset = trialTime(1);
    relativeStimTime = trialTime - offset;
    cpdata = table(relativeStimTime, centerPos(:,1), centerPos(:,2), stimPeriodTable{:,'Chapter Original'}, ...
        'VariableNames', {'Trial time', 'X center', 'Y center', 'Stimulus name'});

    centerpointData = struct(...
        'fps', mean(diff(stimPeriodTable{:,'Trial time'}))^-1, ...
        'data', cpdata, ...
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