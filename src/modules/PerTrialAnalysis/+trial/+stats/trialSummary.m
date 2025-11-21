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
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml() to detect the nidaq_audioplayer and/or metadata_extract binary paths.
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
    %           + stimulusStartTimeOffset - The time offset in seconds from the start of the trial to the start of the stimulus period
    %           + stimuliCorrected - A struct with fields: neg and pos, each containing a scalar string of the stimulus names played on that side, corrected by (flipped?) speaker position
    %               * left: stimulus name played on left side
    %               * right: stimulus name played on right side
    %           + speakerFlipped - Boolean indicating if the speaker positions were flipped for this trial
    %               Whether this trial had the left/right speaker positions flipped compared to the default configuration originally
    %        stimuliMetadata - metadata of the stimuli used in this trial, including individual stimulus timestamps and durations
    %
    %
    %   See also: io.ethovision.alignEthovisionRawToStim, io.metadata.loadMasterMetadata, io.config.loadConfigYaml, io.stimuli.extractMetadata

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTable {validator.mustBeFileOrTable}

        kvargs.Config (1,1) struct = struct()
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
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system)
    centerPos(:,2) = vidHeight - centerPos(:,2);
    trialTime = stimPeriodTable{:,'Trial time'};


    % MidlineX and midlineY, corrected by midline_xoffset_px an midline_yoffset_px from config
    midlineX = vidWidth / 2;
    midlineY = vidHeight / 2;
    % Add offset here



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
        'midline_xoffset_px', midlineX, ...
        'midline_yoffset_px', midlineY, ...
        'px2cm', pixelsize, ... % conversion factor such that cm = px * px2cm
        'stimulusStartTimeOffset', offset, ...
        'stimuliCorrected', stimuliCorrected, ...
        'speakerFlipped', speakerFlipped, ...
        'stimuliMetadata', stimuli ...
    );

end