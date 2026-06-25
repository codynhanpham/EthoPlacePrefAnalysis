function fig = mecp2_pilot_stats()

    MECP2_MALE_KO = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/In-House/Mecp2/20260611_standardizedTable_MalesKOOnly__n16+Baseline.mat";
    C57_MALE_WT = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/In-House/C57/20260611_standardizedTable_MalesOnly+Baseline__NO_OUTLIER__n=15.mat";

    OUTPUTDIR = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/POPULATION/In-House/Mecp2/Male Mecp2 KO vs. C57 WT";

    mecp2Data = load(MECP2_MALE_KO).standardizedTables;
    c57Data = load(C57_MALE_WT).standardizedTables;

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), 1/1);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    fig = struct( ...
        'Name', "Male MECP2 KO vs. Male C57 WT", ...
        'Position', figPos, 'NumberTitle', 'off' ...
    );

    tabNames = { ...
        "State Progression", ...
        "Distance Progression", ...
        "Distance", ...
        "Speed", ...
        "Activity Duration" ...
    };

    tabStruct = struct('Title', tabNames);
    
    [fig, tgroup, tabs] = ui.tabbedFigure(fig, struct(), tabStruct);

    mergedTable(1) = population.temp.joinStdTableByStim(mecp2Data(1), c57Data(1));
    mergedTable(2) = population.temp.joinStdTableByStim(mecp2Data(2), c57Data(2));
    assignin('base', 'mergedTable', mergedTable);

    SHOW_DATA_POINTS = false;

    BIN_WIDTH = 6;
    MEAN_WINDOW_FRAMES = 30;
    PROGRESSION_TIME_BIN_MODE = "categorical";
    PAIRING_CONTEXT_TIME_BIN_MODE = "categorical";
    INCLUDE_MOVEMENT_COVARIATE = true;
    RANDOM_SLOPE = false;

    runStamp = datestr(now, 'yyyymmdd_HHMMSS');
    outputDir = fullfile(OUTPUTDIR, 'outputs', ['mecp2_pilot_stats_' runStamp]);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    logTxtPath = fullfile(outputDir, ['mecp2_pilot_stats_' runStamp '_command_window.log']);
    diary(logTxtPath);
    diary on;
    cleanupDiary = onCleanup(@() diary('off'));

    % Plot State Progression into tab 1
    tbl = plotProgressionInTab(tabs{1}, mergedTable, "state", "BinWidth", BIN_WIDTH, "YLim", [-0.4, 0.4],"ShowDataPoints", SHOW_DATA_POINTS, "MeanWindowFrames", MEAN_WINDOW_FRAMES);
    % Save the table to a csv file in the output directory
    writetable(tbl, fullfile(outputDir, 'state_progression_table.csv'));

    % Plot Distance Progression into tab 2
    tbl = plotProgressionInTab(tabs{2}, mergedTable, "distance", "BinWidth", BIN_WIDTH, "YLim", [-0.4, 0.4],"ShowDataPoints", SHOW_DATA_POINTS, "MeanWindowFrames", MEAN_WINDOW_FRAMES);
    % Save the table to a csv file in the output directory
    writetable(tbl, fullfile(outputDir, 'distance_progression_table.csv'));
    
    % Plot locomotion in window relative to stim onset (t=0) across bins.
    % Examples: [-4,0] => 4s before to onset; [-2,2] => 2s before to 2s after.
    % Use NaN for window end to use the dynamic stimulus bout end, e.g. [0, NaN] => from onset to end of stimulus + ISI
    % NaN cannot be used for window start.
    QC_LOCOMOTION_RELATIVE_STIM_ONSET_WINDOW_SECONDS = [0, NaN];
    plotDistanceRelStimInTab(tabs{3}, mergedTable, "BinWidth", BIN_WIDTH, "RelativeStimOnsetWindowSeconds", QC_LOCOMOTION_RELATIVE_STIM_ONSET_WINDOW_SECONDS, "YLim", [], "ShowDataPoints", SHOW_DATA_POINTS);

    plotSpeedRelStimInTab(tabs{4}, mergedTable, "BinWidth", BIN_WIDTH, "RelativeStimOnsetWindowSeconds", QC_LOCOMOTION_RELATIVE_STIM_ONSET_WINDOW_SECONDS, "YLim", [0, 10], "ShowDataPoints", SHOW_DATA_POINTS);

    ACTIVE_SPEED_THRESHOLD = 5; % cm/s, for defining "active" vs. "inactive" bouts
    ACTIVE_SPEED_DURATION_THRESHOLD_SECONDS = 1.5; % seconds, minimum duration with speed > active threshold to be considered an active bout
    INACTIVE_SPEED_THRESHOLD = 2.5; % cm/s, for defining "inactive" bouts
    INACTIVE_SPEED_DURATION_THRESHOLD_SECONDS = 4; % seconds, minimum duration with speed < inactive threshold to be considered an inactive bout
    plotActivityDurationRelStimInTab(tabs{5}, mergedTable, ...
        "BinWidth", BIN_WIDTH, ...
        "RelativeStimOnsetWindowSeconds", [-2, 8], ...
        "ActiveSpeedThreshold", ACTIVE_SPEED_THRESHOLD, ...
        "ActiveDurationThresholdSeconds", ACTIVE_SPEED_DURATION_THRESHOLD_SECONDS, ...
        "InactiveSpeedThreshold", INACTIVE_SPEED_THRESHOLD, ...
        "InactiveDurationThresholdSeconds", INACTIVE_SPEED_DURATION_THRESHOLD_SECONDS, ...
        "YLim", [], ...
        "ShowDataPoints", SHOW_DATA_POINTS);



    % Statistics: LME trajectory + slope tests (numeric time-bin by default)
    stats = struct();
    stats.state = runProgressionStats(mergedTable, "state", ...
        "BinWidth", BIN_WIDTH, ...
        "MeanWindowFrames", MEAN_WINDOW_FRAMES, ...
        "TimeBinMode", PROGRESSION_TIME_BIN_MODE, ...
        "IncludeMovementCovariate", INCLUDE_MOVEMENT_COVARIATE, ...
        "RandomSlope", RANDOM_SLOPE, ...
        "Verbose", true);

    stats.distance = runProgressionStats(mergedTable, "distance", ...
        "BinWidth", BIN_WIDTH, ...
        "MeanWindowFrames", MEAN_WINDOW_FRAMES, ...
        "TimeBinMode", PROGRESSION_TIME_BIN_MODE, ...
        "IncludeMovementCovariate", INCLUDE_MOVEMENT_COVARIATE, ...
        "RandomSlope", RANDOM_SLOPE, ...
        "Verbose", true);


    % Pairing-context analysis on Normal stimulus: within-strain and cross-strain
    stats.pairing.state = runPairingContextStats(stats.state, mergedTable, "state", ...
        "TimeBinMode", PAIRING_CONTEXT_TIME_BIN_MODE, ...
        "IncludeMovementCovariate", INCLUDE_MOVEMENT_COVARIATE, ...
        "RandomSlope", RANDOM_SLOPE, ...
        "Verbose", true);
    stats.pairing.distance = runPairingContextStats(stats.distance, mergedTable, "distance", ...
        "TimeBinMode", PAIRING_CONTEXT_TIME_BIN_MODE, ...
        "IncludeMovementCovariate", INCLUDE_MOVEMENT_COVARIATE, ...
        "RandomSlope", RANDOM_SLOPE, ...
        "Verbose", true);

    % Compact cross-metric summary table.
    stats.summary = summarizeProgressionStats(stats);

    % Save analysis tables in TSV-compatible format.
    stats.export = saveProgressionStatsTables(stats, outputDir, runStamp);
    stats.export.commandWindowLogTxt = logTxtPath;

    fprintf('\nSaved stats exports to: %s\n', outputDir);

    % Expose stats for downstream inspection
    setappdata(fig, 'progressionStats', stats);
    assignin('base', 'progressionStats', stats);
    assignin('base', 'progressionStatsSummary', stats.summary);
    assignin('base', 'progressionStatsExport', stats.export);

    diary off;

end
