function [f,d] = trialHeatmap(ethovisionXlsx, stimuliDir, masterMetadataTableXlsx, kvargs)
    %   Assume default parameters
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTableXlsx - The master metadata table loaded from an Excel file
    %
    %   Name-Value Pair Arguments:
    %       - 'NiDaqAudioPlayerBin' (optional, but recommended): Path to the `nidaq_audioplayer` binary (same as one used for stimuli playback) for extracting embedded timestamps.
    %           + On Windows, the default is to search in `%LOCALAPPDATA%/NI-DAQmxAudioPlayer/` (default NSIS installer location)
    %           + On Linux, the default is to search in `~/.local/share/NI-DAQmxAudioPlayer/`
    %           + If not found, an error will be thrown.
    %
    %       - 'ImgWidthFOV_cm' (optional): Physical width of the camera's field of view in cm to calculate the pixel size. Default is 58.5 cm.
    %       - 'CenterOffset_cm' (optional): [x,y] offset in cm to translate the origin (0,0) to match the arena center. Default is [0,0].
    %
    %   Outputs:
    %       f - Handle to figure
    %       d - Heatmap data

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTableXlsx {mustBeFile}

        kvargs.NiDaqAudioPlayerBin {validator.mustBeFileOrEmpty} = ''
        kvargs.ImgWidthFOV_cm (1,1) double {mustBePositive} = 58.5
        kvargs.CenterOffset_cm (1,2) double = [0,0]
    end


    [header, datatable, units, stimulusFrameRange, animalMetadata] = alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTableXlsx, ...
        NiDaqAudioPlayerBin=kvargs.NiDaqAudioPlayerBin ...
    );

    stimPeriodTable = datatable(stimulusFrameRange(1):stimulusFrameRange(2), :);

    ethovisionParentDir = fileparts(fileparts(ethovisionXlsx));
    videoFilePathParts = strsplit(header("Video file"), filesep);
    videoFileShortPath = strjoin(videoFilePathParts(end-1:end), filesep);
    videoFilePath = fullfile(ethovisionParentDir, videoFileShortPath);

    if ~isfile(videoFilePath)
        error("Video file not found: %s.\nMake sure your folder structure is exactly how EthoVision exported it, with an 'Export Files' folder and a 'Media Files' folder.", videoFilePath);
    end

    v = VideoReader(videoFilePath);
    vidWidth = v.Width;
    vidHeight = v.Height;
    stimstartframedata = read(v, stimulusFrameRange(1));

    pixelsize = kvargs.ImgWidthFOV_cm / vidWidth; % cm/pixel

    centerPos = [stimPeriodTable{:,'X center'}, stimPeriodTable{:,'Y center'}];
    centerPos(:,1) = centerPos(:,1) + (vidWidth/2 * pixelsize) + kvargs.CenterOffset_cm(1);
    centerPos(:,2) = centerPos(:,2) + (vidHeight/2 * pixelsize) + kvargs.CenterOffset_cm(2);
    % Scale the center pos to pixels
    centerPos = centerPos / pixelsize;
    
    % Convert to image coordinates (flip Y-axis to match imshow coordinate system)
    centerPos(:,2) = vidHeight - centerPos(:,2);

    [N,xedges,yedges] = histcounts2(centerPos(:,1), centerPos(:,2), [(ceil(vidWidth/4)), (ceil(vidHeight/4))]);
    d = N';

    d = imgaussfilt(d, 2);
    d = log10(d + 1); % log transform for better visualization of low-occupancy areas

    f = figure('Name', sprintf("%s | %s", header("Trial name"), sprintf("%s - %s - %s", animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype)), 'NumberTitle', 'off');
    a = axes(f);
    % Plot the first image frame as background
    imshow(stimstartframedata, 'Parent', a);
    hold on;
    % Turn axis back on to show ticks and labels
    axis(a, 'on');
    % h = imagesc(a, xedges, yedges, d);
    alphadata = zeros(size(d));
    alphadata(d > 0.001) = 1;
    alphadata(d > 0.001 & d <= 0.25*max(d(:))) = 0.6;
    alphadata(d > 0.25*max(d(:)) & d <= 0.5*max(d(:))) = 0.8;
    alphadata(d > 0.5*max(d(:)) & d <= 0.75*max(d(:))) = 0.9;
    alphadata(d > 0.75*max(d(:))) = 1;
    % Use image coordinates for imagesc to match imshow
    imagesc(a, xedges, yedges, d, 'AlphaData', alphadata);
    % Also plot a red dot at the center position of the first frame
    plot(a, centerPos(1,1), centerPos(1,2), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    hold off;
    axis(a, 'equal');
    colormap(a, jet);
    cb = colorbar;
    cb.Label.String = 'Log10 Occupancy (s)';
    title(sprintf("%s\n%s", header("Trial name"), sprintf("%s - %s - %s", animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype)));
    xlabel("X Position (cm)");
    ylabel("Y Position (cm)");

    % Change ticks to be every 5 cm instead of pixels
    stepsize = 5 / pixelsize; % 5 cm in pixels
    xticks = 0:stepsize:vidWidth;
    set(a, 'XTick', xticks);
    set(a, 'Box', 'off');
    xticklabels = unique(round(xticks * pixelsize / 5) * 5); % Round to nearest 5 cm
    set(a, 'XTickLabel', xticklabels);
    yticks = 0:stepsize:vidHeight;
    set(a, 'YTick', yticks);
    yticklabels = unique(round(yticks * pixelsize / 5) * 5); % Round to nearest 5 cm
    set(a, 'YTickLabel', yticklabels);
end