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

    [header, datatable, units, stimulusFrameRange, animalMetadata] = io.ethovision.alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTable, ...
        Config=kvargs.Config ...
    );

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

    stimPeriodTable = datatable(stimulusFrameRange(1):stimulusFrameRange(2), :);
    videoFilePath = io.ethovision.mediaPathFromXlsx(ethovisionXlsx);

    if ~isfile(videoFilePath)
        error("Video file not found: %s.\nMake sure your folder structure is exactly how EthoVision exported it, with an 'Export Files' folder and a 'Media Files' folder.", videoFilePath);
    end

    v = VideoReader(videoFilePath);
    vidWidth = v.Width;
    vidHeight = v.Height;
    % stimstartframedata = read(v, stimulusFrameRange(1)); % This assumes a constant frame rate video AND that all frames expected in EthoVision was recorded in the video file, which may not be the case!
    v.CurrentTime = stimPeriodTable{1, 'Trial time'}; % in seconds
    stimstartframedata = readFrame(v);


    pixelsize = ImgWidthFOV_cm / vidWidth; % cm/pixel

    centerPos = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
    centerPos(:,1) = centerPos(:,1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
    centerPos(:,2) = centerPos(:,2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
    % Scale the center pos to cm
    centerPos = centerPos / pixelsize;
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system)
    centerPos(:,2) = vidHeight - centerPos(:,2);

    [N,xedges,yedges] = histcounts2(centerPos(:,1), centerPos(:,2), [(ceil(vidWidth/3)), (ceil(vidHeight/3))]);
    d = N';

    gausFactor = 3; % default for 1920x1080 videos
    % Reduce the gaussian factor for smaller videos, and increase for larger videos based on the larger dimension
    if vidWidth >= vidHeight
        compdim = vidWidth;
        compto = 1920;
    else
        compdim = vidHeight;
        compto = 1080;
    end
    if compdim < compto
        gausFactor = max(1, round(gausFactor * (compdim / compto)));
    elseif compdim > compto
        gausFactor = round(gausFactor * (compdim / compto));
    end

    d = imgaussfilt(d, gausFactor);
    d = log10(d + 1); % log transform for better visualization of low-occupancy areas

    name = strcat(header("Experiment"), " - ", header("Trial name"));
    name = strcat(name, " @ ", string(arenaName));

    screensize = get(0, 'ScreenSize');
    h = 0.72 * screensize(4); w = h * (vidWidth / (vidHeight + 0.26*vidHeight)); % maintain aspect ratio with some extra height for bar chart
    figPos = [(screensize(3)-w)/2, (screensize(4)-h)/2, w, h];
    f = figure('Name', sprintf("%s | %s", name, sprintf("%s - %s - %s", animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype)), 'NumberTitle', 'off', 'Position', figPos, 'ToolBar', 'none');
    t = tiledlayout(f, 4,3, "TileSpacing", "compact", "Padding", "compact");
    
    %% HEATMAP
    a = nexttile(t, [3 3]);
    % Plot the first image frame as background
    imshow(stimstartframedata, 'Parent', a);
    hold on;
    % Turn axis back on to show ticks and labels
    axis(a, 'on');
    alphadata = zeros(size(d));
    alphadata(d > 0.0015) = 1;
    alphadata(d > 0.0015 & d <= 0.005*max(d(:))) = 0.15;
    alphadata(d > 0.005*max(d(:)) & d <= 0.01*max(d(:))) = 0.30;
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


    %% L/R DISTANCE FROM MIDLINE OVER TIME

    fromConfigKey = {'defaults', 'xflip'};
    xflip = false; % default value for compat with older code
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        xflip = getfield(configs, fromConfigKey{:});
        if ~islogical(xflip)
            try
                xflip = logical(xflip);
            catch ME
                xflip = false;
                warning('graphics:trialPlacePref:xflip:InvalidValue', 'Invalid value for xflip in config, must be boolean. Using default false.\n%s', getReport(ME));
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
                warning('graphics:trialPlacePref:yflip:InvalidValue', 'Invalid value for yflip in config, must be boolean. Using default false.\n%s', getReport(ME));
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
            warning("graphics:trialPlacePref:InvalidConfig", "Invalid config value for 'defaults.distance2refmode': %s. Falling back to 'line'.", refmode);
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
    trialTime = stimPeriodTable{:,'Trial time'};
    switch refmode
        % Note that in any condition, at this point centerPos already has been converted to image coordinates (top-left is (0,0)) AND adjusted by CenterOffset_px from config
        % Any offset for midpoint/midline is relative to the size of the video frame itself
        case 'point'
            % Default values: midpoint is at center of video frame
            midlineX = vidWidth / 2;
            midlineY = vidHeight / 2;
            referenceFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));
            referenceSeedFilePath = referenceFilePath;
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
                    warning('graphics:trialPlacePref:referencePointFilePath:LoadError', 'Error loading reference midpoint from file: %s\n%s', referenceSeedFilePath, ME.message);
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
            referenceFilePath = fullfile(videoDir, strcat(videoBaseName, '.ref.json'));
            referenceSeedFilePath = referenceFilePath;
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
                    warning('graphics:trialPlacePref:referenceLineFilePath:LoadError', 'Error loading reference midline from file: %s\n%s', referenceSeedFilePath, ME.message);
                end
            end

        otherwise
            error("Unexpected refmode: %s", refmode);
    end


    % Convert + offset the midline points (currently in px, image coordinates) to cm
    midlineX_cm = (midlineX - ((vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize))) * pixelsize;
    midlineY_cm = (midlineY - ((vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize))) * pixelsize;
    centerPos_cm = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
    centerPos_cm(:,1) = centerPos_cm(:,1) + (vidWidth/2 * pixelsize) + (CenterOffset_px(1) * pixelsize);
    centerPos_cm(:,2) = centerPos_cm(:,2) + (vidHeight/2 * pixelsize) + (CenterOffset_px(2) * pixelsize);
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system, such that top-left is (0,0))
    centerPos_cm(:,2) = vidHeight * pixelsize - centerPos_cm(:,2);

    % Apply x/y flipping by mirroring center positions across the reference
    % point/line before computing distances (consistent with populationPositionOverTime)
    if ~exist('xflip','var'); xflip = false; end
    if ~exist('yflip','var'); yflip = false; end
    if xflip || yflip
        pts = centerPos_cm;
        switch refmode
            case 'point'
                if xflip
                    % Mirror horizontally across vertical line x = midlineX_cm(1)
                    pts(:,1) = 2 * midlineX_cm(1) - pts(:,1);
                end
                if yflip
                    % Mirror vertically across horizontal line y = midlineY_cm(1)
                    pts(:,2) = 2 * midlineY_cm(1) - pts(:,2);
                end
            case 'line'
                if xflip
                    % Mirror across the (potentially oblique) midline itself
                    pts = mirrorPointsAcrossLine(pts, [midlineX_cm(1), midlineX_cm(end)], [midlineY_cm(1), midlineY_cm(end)]);
                end
                if yflip
                    % Vertical mirroring: swap x/y to mirror across the perpendicular
                    % line (same approach used in populationPositionOverTime)
                    pts = mirrorPointsAcrossLine(pts, [midlineY_cm(1), midlineY_cm(end)], [midlineX_cm(1), midlineX_cm(end)]);
                end
            otherwise
                error("Unexpected refmode: %s", refmode);
        end
        centerPos_cm = pts;
    end

    switch refmode
        case 'point'
            % Calculate Euclidean distance from each centerPos to referencePoint
            referencePoint = [midlineX_cm(1), midlineY_cm(1)]; % in cm
            diffs = centerPos_cm - referencePoint; % in cm
            dists = sqrt(sum(diffs.^2, 2)); % in cm
            % Determine sign based on X position relative to the mid-point (X0, Y0) (left = negative, right = positive)
            distFromMidline_cm = sign((centerPos_cm(:,1) - referencePoint(1))) .* dists; % in cm

        case 'line'
            % Calculate perpendicular distance to line defined by midlineX_cm and midlineY_cm
            % Using formula for point to line distance
            A = midlineY_cm(2) - midlineY_cm(1);
            B = midlineX_cm(1) - midlineX_cm(2);
            C = midlineX_cm(2)*midlineY_cm(1) - midlineX_cm(1)*midlineY_cm(2);
            % Distance = (A*x0 + B*y0 + C) / sqrt(A^2 + B^2)
            distFromMidline_cm = (A * centerPos_cm(:,1) + B * centerPos_cm(:,2) + C) / sqrt(A^2 + B^2); % in cm
        otherwise
            error("Unexpected refmode: %s", refmode);
    end

    assert(size(distFromMidline_cm,1) == size(trialTime,1), "Size mismatch between distFromMidline_cm and trialTime");

    a = nexttile(t, [1,2]);
    l = plot(a, trialTime, distFromMidline_cm, 'k-');
    plotXLim = a.XLim; plotYLim = a.YLim; % Save this for later: the default limits should fit the data nicely in plot
    maxY = max(abs(plotYLim));
    plotYLim = [-maxY, maxY]; % Symmetric y-limits
    plotYLim = plotYLim * 1.05; % Add 5% padding Y
    plotXLim = [plotXLim(1), plotXLim(2) + diff(plotXLim) * 0.16]; % Add 16% padding X end for stim labels
    % If the first stim starts at time > 5% of diff(plotXLim), no need to pad the start, otherwise pad start too
    firstStimTime = trialTime(1);
    if firstStimTime <= plotXLim(1) + diff(plotXLim) * 0.05
        padamount = (plotXLim(1) + diff(plotXLim) * 0.05) - firstStimTime;
        plotXLim(1) = plotXLim(1) - padamount;
    end

    hold(a, 'on');
    line(a, [min(0, plotXLim(1)), max(max(trialTime), plotXLim(2))], [0,0], 'Color', [0.5,0.5,0.5], 'LineStyle', ':', 'LineWidth', 1);

    % Plot the left/right color patched regions: rectangle from xlim(1) to xlim(2), y=0 to ylim(2) in red (right), and y=0 to ylim(1) in blue (left)
    patch(a, [plotXLim(1), plotXLim(1), plotXLim(2), plotXLim(2)], [0, plotYLim(2), plotYLim(2), 0], [1,0,0], 'FaceAlpha', 0.04, 'EdgeColor', 'none');
    patch(a, [plotXLim(1), plotXLim(1), plotXLim(2), plotXLim(2)], [plotYLim(1), 0, 0, plotYLim(1)], [0,0,1], 'FaceAlpha', 0.04, 'EdgeColor', 'none');


    % Add text annotation at start of xlim, indicating left/right
    textPaddingX = 0.02 * diff(plotXLim);
    % Rotate 270 degrees to have text vertical along y-axis
    text(a, plotXLim(1) + textPaddingX, (plotYLim(2) - 0)/2, 'Right', 'Color', 'r', 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'cap', 'Rotation', 90, 'Clipping', 'on');
    text(a, plotXLim(1) + textPaddingX, (plotYLim(1) + 0)/2, 'Left', 'Color', 'b', 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'cap', 'Rotation', 90, 'Clipping', 'on');


    % Add the stimuli as shaded regions behind the line plot, color of [0.5 0.5 0.5] if it contains {'Intro', 'Outro', 'ISI'}, else color based on speaker position as in "Stim Speaker Corrected" (contains 'Left' -> blue, 'Right' -> red)
    stims = stimPeriodTable{:,'Chapter Original'};
    ustims = unique(stims(~cellfun(@anymissing, stims)));
    for i = 1:length(ustims)
        stimName = ustims{i};
        stimIdx = find(strcmp(stims, stimName));
        if isempty(stimIdx)
            continue;
        end
        
        % Find the start and end blocks of consecutive frames for this stim
        stimBlocks = NaN(0,2); % each row is [startIdx, endIdx]
        blockStart = stimIdx(1);
        for j = 2:length(stimIdx)
            if stimIdx(j) ~= stimIdx(j-1) + 1
                % Not consecutive, end the previous block
                blockEnd = stimIdx(j-1)+1;
                stimBlocks = [stimBlocks; blockStart, blockEnd]; %#ok<AGROW>
                blockStart = stimIdx(j);
            end
        end
        % Add the last block
        stimBlocks = [stimBlocks; blockStart, stimIdx(end)]; %#ok<AGROW>

        if contains(stimName, {'Intro', 'Outro', 'ISI'})
            stimColor = [0.5, 0.5, 0.5];
        else
            % Get the speaker position for this stim from "Stim Speaker Corrected"
            speakerPosForStim = stimPeriodTable{stimIdx(1), 'Stim Speaker Corrected'};
            if contains(speakerPosForStim, 'Left')
                stimColor = [0, 0, 1]; % blue
            elseif contains(speakerPosForStim, 'Right')
                stimColor = [1, 0, 0]; % red
            else
                stimColor = [0.5, 0.5, 0.5]; % gray for unknown
            end
        end

        % Plot each block as a shaded region
        for j = 1:size(stimBlocks,1)
            blockStartIdx = stimBlocks(j,1);
            blockEndIdx = stimBlocks(j,2);
            xStart = trialTime(blockStartIdx);
            xEnd = trialTime(blockEndIdx);
            % Create a patch (rectangle) for the shaded region
            patchX = [xStart, xEnd, xEnd, xStart];
            patchY = [plotYLim(1), plotYLim(1), plotYLim(2), plotYLim(2)];
            patch(a, patchX, patchY, stimColor, 'FaceAlpha', 0.1, 'EdgeColor', 'none');
        end
    end

    % Bring line plot to front
    uistack(l, 'top');

    % Add text at the end of x-axis indicating the stims
    % text(a, plotXLim(2) - textPaddingX, plotYLim(2) - textPaddingY, 'Right', 'Color', 'r', 'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'top');
    % text(a, plotXLim(2) - textPaddingX, plotYLim(1) + textPaddingY, 'Left', 'Color', 'b', 'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    % We know that when making the bar, left speaker stim is first
    textPaddingY = 0.05 * diff(plotYLim);
    text(a, plotXLim(2) - textPaddingX, plotYLim(1) + textPaddingY, stimKeys{1}, 'Color', 'b', 'FontWeight', 'bold', 'FontSize', 9, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Clipping', 'on');
    text(a, plotXLim(2) - textPaddingX, plotYLim(2) - textPaddingY, stimKeys{end}, 'Color', 'r', 'FontWeight', 'bold', 'FontSize', 9, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Clipping', 'on');

    % allow interactive zooming and panning
    enableDefaultInteractivity(a);
    title(a, 'Distance from Midline Over Time');
    xlabel(a, 'Time (s)');
    ylabel(a, 'Distance from Midline (cm)');
    % a.Toolbar.Visible = 'on';
    % a.Interactions = [zoomInteraction regionZoomInteraction rulerPanInteraction];
    axtoolbar(a, {'export', 'pan', 'zoomin', 'zoomout', 'restoreview'});

    a.XLim = plotXLim; a.YLim = plotYLim; % Restore original limits after enabling interactivity
    hold(a, 'off');
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