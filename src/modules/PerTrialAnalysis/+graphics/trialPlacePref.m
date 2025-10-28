function [f,d] = trialPlacePref(ethovisionXlsx, stimuliDir, masterMetadataTable, kvargs)
    %   Assume default parameters
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTable - The master metadata table loaded from an Excel file
    %
    %   Name-Value Pair Arguments:
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml() to detect the nidaq_audioplayer and/or metadata_extract binary paths.
    %
    %   Outputs:
    %       f - Handle to figure
    %       d - Heatmap data

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTable {validator.mustBeFileOrTable}

        kvargs.Config (1,1) struct = struct()
    end

    configs = kvargs.Config;
    fromConfigKey = {'project_settings', 'EthoVision', 'default_camera_imgwidth_fov_cm'};
    ImgWidthFOV_cm = 58.5; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        ImgWidthFOV_cm = getfield(configs, fromConfigKey{:});
        if iscell(ImgWidthFOV_cm)
            ImgWidthFOV_cm = cell2mat(ImgWidthFOV_cm);
        end
    end

    fromConfigKey = {'project_settings', 'EthoVision', 'default_camera_center_offset_px'};
    CenterOffset_px = [0,0]; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        CenterOffset_px = getfield(configs, fromConfigKey{:});
        CenterOffset_px = cell2mat(CenterOffset_px);
    end

    [header, datatable, units, stimulusFrameRange, animalMetadata] = io.ethovision.alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTable, ...
        Config=kvargs.Config ...
    );

    arenaName = header("Arena name");
    % Check for configs overrides for this arena
    arenaConfigPath = {'project_settings', 'EthoVision', 'arena'};
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

    stimPeriodTable = datatable(stimulusFrameRange(1):stimulusFrameRange(2), :);
    videoFilePath = io.ethovision.mediaPathFromXlsx(ethovisionXlsx);

    if ~isfile(videoFilePath)
        error("Video file not found: %s.\nMake sure your folder structure is exactly how EthoVision exported it, with an 'Export Files' folder and a 'Media Files' folder.", videoFilePath);
    end

    v = VideoReader(videoFilePath);
    vidWidth = v.Width;
    vidHeight = v.Height;
    stimstartframedata = read(v, stimulusFrameRange(1));

    pixelsize = ImgWidthFOV_cm / vidWidth; % cm/pixel

    centerPos = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
    centerPos(:,1) = centerPos(:,1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
    centerPos(:,2) = centerPos(:,2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
    % Scale the center pos to pixels
    centerPos = centerPos / pixelsize;
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system)
    centerPos(:,2) = vidHeight - centerPos(:,2);

    [N,xedges,yedges] = histcounts2(centerPos(:,1), centerPos(:,2), [(ceil(vidWidth/3)), (ceil(vidHeight/3))]);
    d = N';

    d = imgaussfilt(d, 3);
    d = log10(d + 1); % log transform for better visualization of low-occupancy areas

    name = strcat(header("Experiment"), " - ", header("Trial name"));
    
    screensize = get(0, 'ScreenSize');
    h = 0.72 * screensize(4); w = h * (vidWidth / (vidHeight + 0.26*vidHeight)); % maintain aspect ratio with some extra height for bar chart
    figPos = [(screensize(3)-w)/2, (screensize(4)-h)/2, w, h];
    f = figure('Name', sprintf("%s | %s", name, sprintf("%s - %s - %s", animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype)), 'NumberTitle', 'off', 'Position', figPos, 'ToolBar', 'none');
    t = tiledlayout(f, 4,1, "TileSpacing", "compact", "Padding", "compact");
    
    %% HEATMAP
    a = nexttile(t, [3 1]);
    % Plot the first image frame as background
    imshow(stimstartframedata, 'Parent', a);
    hold on;
    % Turn axis back on to show ticks and labels
    axis(a, 'on');
    alphadata = zeros(size(d));
    alphadata(d > 0.001) = 1;
    alphadata(d > 0.001 & d <= 0.005*max(d(:))) = 0.2;
    alphadata(d > 0.005*max(d(:)) & d <= 0.01*max(d(:))) = 0.35;
    alphadata(d > 0.01*max(d(:)) & d <= 0.05*max(d(:))) = 0.5;
    alphadata(d > 0.05*max(d(:)) & d <= 0.18*max(d(:))) = 0.65;
    alphadata(d > 0.18*max(d(:)) & d <= 0.25*max(d(:))) = 0.75;
    alphadata(d > 0.25*max(d(:)) & d <= 0.5*max(d(:))) = 0.85;
    alphadata(d > 0.5*max(d(:)) & d <= 0.75*max(d(:))) = 0.95;
    alphadata(d > 0.75*max(d(:))) = 1;

    % Smooth the alpha data a bit
    alphadata = imgaussfilt(alphadata, 2);

    % Use image coordinates for imagesc to match imshow
    imagesc(a, xedges, yedges, d, 'AlphaData', alphadata);
    % Also plot a red dot at the center position of the first frame
    plot(a, centerPos(1,1), centerPos(1,2), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    axis(a, 'equal');
    colormap(a, jet);
    cb = colorbar;
    cb.Label.String = 'Log10 Occupancy (s)';
    title(sprintf("%s\n%s", name, sprintf("%s - %s - %s", animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype)), "Interpreter", "none");
    xlabel("X Position (cm)");
    ylabel("Y Position (cm)");
    hold off;

    % Change ticks to be every 5 cm
    stepsize = 5 / pixelsize;
    xticks = 0:stepsize:vidWidth;
    set(a, 'XTick', xticks);
    set(a, 'Box', 'on');
    xticklabels = unique(round(xticks * pixelsize / 5) * 5); % Round to nearest 5 cm
    set(a, 'XTickLabel', xticklabels);
    yticks = 0:stepsize:vidHeight;
    set(a, 'YTick', yticks);
    yticklabels = unique(round(yticks * pixelsize / 5) * 5); % Round to nearest 5 cm
    set(a, 'YTickLabel', yticklabels);
    set(a, 'TickDir', 'both', 'TickLength', [0.005, 0.005]);
    set(a, 'XLim', [0, vidWidth], 'YLim', [0, vidHeight]);


    %% BAR CHART

    allstims = stimPeriodTable{:,'Chapter Original'};
    allstims = unique(allstims(~cellfun(@anymissing, allstims)));
    allstims = allstims(~endsWith(allstims, 'ISI'));
    outrointro = {'Outro', 'Intro'};
    allstims = allstims(~startsWith(allstims, outrointro) & ~endsWith(allstims, outrointro));

    % Count the frequency of animalMatchedStim (Animal position is in the "active" speaker/stim zone)
    animalMatchedStim = stimPeriodTable{:,'Animal Matched Stim Name'};
    cats = categories(categorical(animalMatchedStim));
    animalMatchedStimCounts = countcats(categorical(animalMatchedStim));
    matchedStimFrameFreq = dictionary(string(cats), animalMatchedStimCounts);
    missingStims = setdiff(allstims, keys(matchedStimFrameFreq));
    for i = 1:length(missingStims)
        matchedStimFrameFreq(missingStims{i}) = 0;
    end

    % Count the frequency of speaker positions matched (actual)
    speakerPos = stimPeriodTable{:,'Matched Speaker Position'};
    speakerCats = categories(categorical(speakerPos));
    speakerCounts = countcats(categorical(speakerPos));
    matchedSpeakerPosFreq = dictionary(string(speakerCats), speakerCounts);
    % Should includes both "Left Speaker" and "Right Speaker", make sure to fill missing with 0 when not present
    missingSpeakers = setdiff(["Left Speaker", "Right Speaker"], keys(matchedSpeakerPosFreq));
    for i = 1:length(missingSpeakers)
        matchedSpeakerPosFreq(missingSpeakers{i}) = 0;
    end

    % Count the frequency of stim speaker positions extended (available/original, no match by animal position)
    speakerPosExtended = stimPeriodTable{:,'Stim Speaker Corrected'};
    speakerCatsExtended = categories(categorical(speakerPosExtended));
    speakerCountsExtended = countcats(categorical(speakerPosExtended));
    matchedSpeakerPosExtendedFreq = dictionary(string(speakerCatsExtended), speakerCountsExtended);
    % Should includes both "Left Speaker" and "Right Speaker", make sure to fill missing with 0 when not present
    missingSpeakersExtended = setdiff(["Left Speaker", "Right Speaker"], keys(matchedSpeakerPosExtendedFreq));
    for i = 1:length(missingSpeakersExtended)
        matchedSpeakerPosExtendedFreq(missingSpeakersExtended{i}) = 0;
    end

    % For each key in matchedStimFrameFreq, find the key in matchedSpeakerPosFreq that has the same value, log the key with that value for normalization
    stim2speakerMap = configureDictionary("string", "string");
    stimKeys = keys(matchedStimFrameFreq);
    for i = 1:length(stimKeys)
        stimKey = stimKeys{i};
        stimValue = matchedStimFrameFreq(stimKey);
        speakerKey = "";
        speakerKeys = keys(matchedSpeakerPosFreq);
        for j = 1:length(speakerKeys)
            if matchedSpeakerPosFreq(speakerKeys{j}) == stimValue
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
    stimKeys = stimKeys(sortIdx);

    % Normalize matchedStimFrameFreq by matchedSpeakerExtendedFreq
    normalizedFreq = zeros(size(stimKeys));
    for i = 1:length(stimKeys)
        stimKey = stimKeys{i};
        stimValue = matchedStimFrameFreq(stimKey);
        if isKey(stim2speakerMap, stimKey)
            speakerKey = stim2speakerMap(stimKey);
            if isKey(matchedSpeakerPosExtendedFreq, speakerKey)
                speakerValue = matchedSpeakerPosExtendedFreq(speakerKey);
                normalizedFreq(i) = stimValue / speakerValue;
            else
                normalizedFreq(i) = NaN;
            end
        else
            normalizedFreq(i) = NaN;
        end
    end

    for i = 1:length(stimKeys)
        if startsWith(stimKeys{i}, '[Ch1] ')
            stimKeys{i} = extractAfter(stimKeys{i}, '[Ch1] ');
        elseif startsWith(stimKeys{i}, '[Ch2] ')
            stimKeys{i} = extractAfter(stimKeys{i}, '[Ch2] ');
        end
    end

    colors = {'#dbd6d6', '#db2800'}; % Left - Right

    % Create bar chart
    a = nexttile(t, [1,1]);

    % DO NOT categorize stimKeys, keep as string array to preserve order
    b = bar(a, stimKeys, normalizedFreq, 'FaceColor', 'flat', 'EdgeColor', 'k');
    hold on;
    for k = 1:length(colors)
        b.CData(k,:) = hex2rgb(colors{k});
    end
    % Dummy bar for legend
    b_dummy = bar(a, [NaN, NaN], 'FaceColor', colors{2}, 'EdgeColor', 'k'); % Dummy bar for legend
    hold off;
    title(a, 'Normalized Stimulus Preference', 'Interpreter', 'none');
    ylabel(a, 'Normalized Frequency'); % the % of Time Spent in Zone when Zone is Active
    xlabel(a, 'Stimulus Name');
    ylim(a, [0, 1]);
    set(a, 'Box', 'on');
    grid(a, 'on');

    legend([b, b_dummy], speakers, 'Location', 'northeast');
end
