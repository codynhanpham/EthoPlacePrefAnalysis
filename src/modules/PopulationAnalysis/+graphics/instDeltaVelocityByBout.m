function f = instDeltaVelocityByBout(standardizedTable, kvargs)
    %%INSTDELTAVELOCITYBYBOUT Plot average instantaneous delta velocity aligned by bout onset, binned over time
    %
    %   This function averages the instantaneous delta velocity over time, aligned to bout onset,
    %   for each bout of stimulus presentation in the provided standardizedTable.
    %   It is similar to dF/F0 calculations in calcium imaging, where delta velocity is the change in velocity relative to a baseline period. 
    %
    %
    %   f = population.temp.instDeltaVelocityByBout(standardizedTable, kvargs)
    %
    %   Inputs:
    %       standardizedTable : Struct array in standardized format, as output by population.stats.populationPositionOverTime()
    %
    %   Name-Value Pair Arguments:
    %       'ResponseWindow' : 1x2 double array specifying the time window (in seconds, relative to bout onset) to analyze. Negative values define the baseline period before stimulus start. Default is [-1, 6]. This range should cover the full bout duration and ends before the next bout starts. First element cannot be positive. Second element must be positive. If first element is 0 or NaN, the baseline is taken as the first time bin after bout onset.
    %       'BinWidth' : Scalar double specifying the width of time bins (in seconds) for averaging distance data. Default is NaN, which uses the smallest time resolution available. Set to 0 or NaN for no binning, or Inf for one single bin over the whole ResponseWindow.
    %       'BoutRange' : 1x2 double array specifying which bouts to include. Default is [1, Inf] (all bouts). Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts).
    %
    %   Outputs:
    %       f : Figure handle of the generated plot
    %
    %   See also: population.stats.populationPositionOverTime, graphics.distFromMidlineByTimeBinned


    arguments
        standardizedTable struct {mustBeNonempty}

        kvargs.ResponseWindow (1,2) double = [-1, 6] % in seconds, relative to bout onset
        kvargs.BinWidth (1,1) double = NaN % in seconds, set to 0 or NaN for no binning (use the smallest time resolution available), or Infinity for one single bin over the whole ResponseWindow. BinWidth is clamped to be at most the size of ResponseWindow.
        kvargs.BoutRange (1,2) double = [1, Inf] % which bouts to include. Use integers for bout indices (e.g., [1,3]), or floats in [0,1] for percentage (e.g., [0,0.5] for first 50% of bouts)

        kvargs.Title {validator.mustBeTextScalarOrEmpty} = ''
    end

    % Make sure response window is valid: end > start
    if kvargs.ResponseWindow(2) <= kvargs.ResponseWindow(1)
        error('Invalid ResponseWindow: End time must be greater than Start time.');
    end

    requiredFields = {'stimfileName', 'stimuliSorted', 'animalMetadata', 'centerpointData'};
    missing = setdiff(requiredFields, fieldnames(standardizedTable), 'stable');
    if ~isempty(missing)
        error('The provided standardizedTable is missing required fields: { ''%s'' }', strjoin(missing, ''', '''));
    end

    stimSets = {standardizedTable.stimuliSorted};
    nstimsets = length(stimSets);

    animalStrains = cellfun(@(x) {x.values().strain}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalStrains = unique([animalStrains{:}]);
    nstrains = length(animalStrains);

    animalGenotypes = cellfun(@(x) {x.values().genotype}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalGenotypes = unique([animalGenotypes{:}]);
    ngenotypes = length(animalGenotypes);

    animalSexes = cellfun(@(x) {x.values().sex}, {standardizedTable.animalMetadata}, 'UniformOutput', false);
    animalSexes = unique([animalSexes{:}]);
    nsexes = length(animalSexes);

    % Each plot will be by Per StimSet x Strain x Genotype
    % Within each plot, the stimulus (within the set) will be represented by line style, and Sex by color within each plot
    % With 2 stimuli per set, there will be 2 line styles (e.g., solid for stim that includes 'normal', dashed for the other stimulus --> 4 lines per plot

    % At the onset of each bout, calc the instantaneous absolute velocity, then delta velocity relative to baseline period
    % Bin the distance data into time bins, then average across replicates/animals belonging to the same Strain/Genotype/Sex group

    nplots = nstrains * nstimsets * ngenotypes;

    ncols = ceil(sqrt(nplots));
    nrows = ceil(nplots / ncols);

    [screensize, videoaspect] = deal(get(0, 'ScreenSize'), ncols/nrows);
    [figW, figH] = ui.dynamicFigureSize(videoaspect, 0);

    % Center the figure on the primary screen
    figPos = [(screensize(3)-figW)/2, (screensize(4)-figH)/2, figW, figH];

    f = figure('Name', sprintf("Instantaneous Velocity By Bout (Bin Size: %.3f sec)", kvargs.BinWidth), 'Position', figPos, 'NumberTitle', 'off');
    t = tiledlayout(f, nrows, ncols, 'Padding', 'compact', 'TileSpacing', 'compact');
    t.Title.String = kvargs.Title;
    t.Title.FontWeight = 'bold';

    for stimsetIdx = 1:nstimsets
        thisStimSet = stimSets{stimsetIdx};
        thisStdTable = standardizedTable(stimsetIdx);
        stimPeriodTable = thisStdTable.centerpointData;
        stimPeriodTable = stimPeriodTable(:, ismember(stimPeriodTable.Properties.VariableNames, {'Trial time', 'Stimulus name', 'Distance from Midline'} ));
        trialTime = stimPeriodTable{:, 'Trial time'};
        distanceFromMidlineMatrix = stimPeriodTable{:, 'Distance from Midline'};
        columnByStrainOrder = {thisStdTable.animalMetadata.values().strain};
        columnByGenotypeOrder = {thisStdTable.animalMetadata.values().genotype};
        columnBySexOrder = {thisStdTable.animalMetadata.values().sex};

        


    end

end

function [speed, angle] = calcInstantaneousVelocity(centerpointData, timeVector)
    % Calculate instantaneous velocity (speed and angle) from centerpoint data and time vector
    % centerpointData: Nx2 array of x,y positions over time
    % timeVector: Nx1 array of time points corresponding to centerpointData

    % Calculate differences in position and time
    dx = diff(centerpointData(:,1));
    dy = diff(centerpointData(:,2));
    dt = diff(timeVector);

    % Calculate speed and angle
    speed = sqrt(dx.^2 + dy.^2) ./ dt; % Speed is distance over time
    angle = atan2d(dy, dx); % Angle in degrees, relative to the positive x-axis: 0 degrees is to the right, 90 degrees is up, -90 degrees is down

    % Pad the speed and angle with NaN for the first time point (since diff reduces length by 1)
    speed = [NaN; speed];
    angle = [NaN; angle];
end