function handles = plot(spectrogramDb, kvargs)
    %%PLOT Plot a pre-computed spectrogram database in an interactive uifigure.
    %   Renders the spectrogram (frequency over time) and the amplitude over time of a
    %   spectrogram database struct produced by io.stimuli.spectrogram.precompute. The
    %   stored time x frequency grid is decoupled from pixel space, so the native axes
    %   zoom/pan works on the full-resolution data: zooming in reveals more detail
    %   without recomputation, and zooming out only rescales.
    %
    %   Each input channel gets its own spectrogram + amplitude panel pair. The
    %   spectrogram uses a grayscale colormap on a white background (low frequency at
    %   the bottom, quiet = white, loud = black) with per-channel color limits
    %   auto-stretched from the noise-floor hint stored by precompute
    %   (params.displayFloor), so quiet areas render white instead of mid-gray; a
    %   'Min dB' slider adjusts the floor live. The amplitude panel draws a DAW-style
    %   filled min/max band plus the RMS line using jet-family colors. Spectrogram and
    %   amplitude axes share their time axis (linked X limits), so zoom/pan stays
    %   synchronized across all panels.
    %
    %   USAGE:
    %       handles = io.stimuli.spectrogram.plot(spectrogramDb)
    %       handles = io.stimuli.spectrogram.plot(spectrogramDb, 'FrequencyScale', 'log')
    %
    %   INPUTS:
    %       spectrogramDb: struct as returned by io.stimuli.spectrogram.precompute.
    %           Required fields: fs, time, frequency, spectrogram, dbFloor, dbStep,
    %           amplitudeRms, amplitudePeak, amplitudeMin, amplitudeMax, params.
    %
    %   Name-Value Pair Arguments:
    %       'Parent': (graphics handle) Existing uifigure, uigridlayout, or uipanel to
    %           embed the plot into. Default empty creates a standalone uifigure.
    %       'Colormap': (text or numeric) Colormap for the spectrogram panel: a colormap
    %           name (e.g. 'turbo', resolved as feval(name, 256)) or an M x 3 matrix in
    %           [0, 1]. Default is grayscale (flipud(gray(256))): white = quiet, black = loud.
    %       'DbLimits': (1x2 double) Color limits for the spectrogram in dB, applied to
    %           all channels. Default is per-channel [displayFloor, 0] using the
    %           noise-floor hint from precompute's 'DisplayFloorPercentile' (falling
    %           back to the full [dbFloor, 0] range when the hint is absent).
    %       'FrequencyScale': (text) 'linear' (default) or 'log' initial frequency axis
    %           scale. The window includes a button to toggle at runtime; in log mode the
    %           DC bin (0 Hz) is excluded from view.
    %       'TimeRange': (1x2 double) Initial time window in seconds to display.
    %           Default shows the full [time(1), time(end)] range.
    %       'WindowName': (text) Standalone figure title. Default derives from the
    %           database's 'title' and 'stimfileName' (falling back to
    %           "Spectrogram Viewer" when absent). Ignored when 'Parent' is provided.
    %       'Visible': (logical) Whether the standalone figure is created visible.
    %           Default true. Ignored when 'Parent' is provided.
    %
    %   OUTPUTS:
    %       handles: struct of UI handles for further customization:
    %           UIFigure: the standalone uifigure (empty when embedded via 'Parent').
    %           mainGrid: the root uigridlayout holding the controls and panels.
    %           spectrogramAxes: C x 1 uiaxes array, one per input channel.
    %           amplitudeAxes: C x 1 uiaxes array, one per input channel.
    %           resetButton: 'Reset view' uibutton.
    %           frequencyScaleButton: uibutton toggling linear/log frequency scale.
    %           minDbLabel / minDbSlider: 'Min dB' label and slider adjusting the
    %               spectrogram color-limit floor live (contrast control).
    %           readoutLabel: uilabel showing the cursor's time/frequency position
    %               (standalone figures only; empty when embedded).
    %
    %   See also: io.stimuli.spectrogram.precompute, io.stimuli.spectrogram.validateDatabase, io.stimuli.spectrogram.exportHdf5

    arguments
        spectrogramDb (1,1) struct
        kvargs.Parent = []
        kvargs.Colormap = []
        kvargs.DbLimits double = []
        kvargs.FrequencyScale {mustBeTextScalar} = "linear"
        kvargs.TimeRange double = []
        kvargs.WindowName {mustBeTextScalar} = ""
        kvargs.Visible (1,1) logical = true
    end

    io.stimuli.spectrogram.validateDatabase(spectrogramDb);

    if strtrim(char(string(kvargs.WindowName))) == ""
        windowName = "Spectrogram Viewer";
        if isfield(spectrogramDb, 'title') && ~isempty(spectrogramDb.title)
            windowName = string(spectrogramDb.title);
        end
        if isfield(spectrogramDb, 'stimfileName') && ~isempty(spectrogramDb.stimfileName)
            windowName = sprintf('%s - %s', spectrogramDb.stimfileName, windowName);
        end
    else
        windowName = string(kvargs.WindowName);
    end

    frequencyScale = localValidateChoice(lower(char(string(kvargs.FrequencyScale))), {'linear', 'log'});
    time = spectrogramDb.time(:);
    frequency = spectrogramDb.frequency(:);
    nChannels = size(spectrogramDb.spectrogram, 3);
    tMin = time(1);
    tMax = time(end);
    if isempty(kvargs.DbLimits)
        dbUpperLimit = 0;
        if isfield(spectrogramDb.params, 'displayFloor') && numel(spectrogramDb.params.displayFloor) == nChannels
            perChannelFloor = double(spectrogramDb.params.displayFloor(:));
        else
            perChannelFloor = repmat(spectrogramDb.dbFloor, nChannels, 1);
        end
    else
        dbUpperLimit = kvargs.DbLimits(2);
        perChannelFloor = repmat(kvargs.DbLimits(1), nChannels, 1);
    end
    perChannelFloor = min(max(perChannelFloor, spectrogramDb.dbFloor), dbUpperLimit - 1e-6);
    if isempty(kvargs.Colormap)
        colormapMatrix = flipud(gray(256));
    elseif isnumeric(kvargs.Colormap)
        colormapMatrix = kvargs.Colormap;
        if size(colormapMatrix, 2) ~= 3 || any(colormapMatrix(:) < 0 | colormapMatrix(:) > 1)
            error("io:stimuli:spectrogram:plot:InvalidColormap", ...
                "'Colormap' must be an M x 3 matrix with values in [0, 1].");
        end
    else
        try
            colormapMatrix = feval(char(string(kvargs.Colormap)), 256);
        catch ME
            error("io:stimuli:spectrogram:plot:InvalidColormap", ...
                "Could not resolve colormap name '%s': %s", char(string(kvargs.Colormap)), getReport(ME));
        end
    end
    if isempty(kvargs.TimeRange)
        timeRange = [tMin, tMax];
    else
        timeRange = sort(kvargs.TimeRange);
        if ~isvector(timeRange) || numel(timeRange) ~= 2 || ~all(isfinite(timeRange))
            error("io:stimuli:spectrogram:plot:InvalidTimeRange", ...
                "'TimeRange' must be [start, stop] with finite start <= stop. Got: %s.", mat2str(timeRange));
        end
    end

    if isempty(kvargs.Parent)
        screenSize = get(0, 'ScreenSize');
        figWidth = min(1000, screenSize(3) * 0.9);
        figHeight = min(220 + 300 * nChannels, screenSize(4) * 0.85);
        figPosition = [(screenSize(3) - figWidth) / 2, (screenSize(4) - figHeight) / 2, figWidth, figHeight];
        if kvargs.Visible
            visibility = 'on';
        else
            visibility = 'off';
        end
        handles.UIFigure = uifigure('Name', char(windowName), 'Position', figPosition, 'Visible', visibility);
        parentContainer = handles.UIFigure;
    else
        parentContainer = kvargs.Parent;
        if ~isgraphics(parentContainer) || ~any(strcmp(class(parentContainer), ...
                {'matlab.ui.Figure', 'matlab.ui.container.GridLayout', 'matlab.ui.container.Panel'}))
            error("io:stimuli:spectrogram:plot:InvalidParent", ...
                "'Parent' must be a valid uifigure, uigridlayout, or uipanel handle.");
        end
        handles.UIFigure = [];
    end

    handles.mainGrid = uigridlayout(parentContainer, [1 + 2 * nChannels, 1]);
    handles.mainGrid.RowHeight = [{'fit'}, repmat({'2x', '1x'}, 1, nChannels)];
    handles.mainGrid.ColumnWidth = {'1x'};
    handles.mainGrid.Padding = [5 5 5 5];
    handles.mainGrid.RowSpacing = 5;
    handles.mainGrid.ColumnSpacing = 5;

    jetTable = jet(256);
    bandColor = jetTable(160, :);
    amplitudeMinLimit = min(spectrogramDb.amplitudeMin(:));
    amplitudeMaxLimit = max(spectrogramDb.amplitudeMax(:));
    if amplitudeMaxLimit > amplitudeMinLimit
        amplitudePad = 0.05 * (amplitudeMaxLimit - amplitudeMinLimit);
    else
        amplitudePad = 0.5;
    end

    handles.spectrogramAxes = gobjects(nChannels, 1);
    handles.amplitudeAxes = gobjects(nChannels, 1);
    for c = 1:nChannels
        spectrogramRow = 2 + (c - 1) * 2;
        amplitudeRow = spectrogramRow + 1;

        dB = localDequantize(spectrogramDb, c);
        specAxes = uiaxes(handles.mainGrid);
        specAxes.Layout.Row = spectrogramRow;
        specAxes.Layout.Column = 1;
        specAxes.Color = 'w';
        imagesc(specAxes, time, frequency, dB);
        specAxes.YDir = 'normal';
        colormap(specAxes, colormapMatrix);
        clim(specAxes, [perChannelFloor(c), dbUpperLimit]);
        specAxes.YLabel.String = 'Frequency (Hz)';
        specAxes.XAxis.Visible = 'off';
        specAxes.YScale = frequencyScale;
        specAxes.XLim = timeRange;
        if strcmpi(frequencyScale, 'log')
            specAxes.YLim = [frequency(2), frequency(end)];
        else
            specAxes.YLim = [frequency(1), frequency(end)];
        end
        if nChannels > 1
            specAxes.Title.String = sprintf('Channel %d', c);
        end
        handles.spectrogramAxes(c) = specAxes;

        ampAxes = uiaxes(handles.mainGrid);
        ampAxes.Layout.Row = amplitudeRow;
        ampAxes.Layout.Column = 1;
        ampAxes.Color = 'w';
        hold(ampAxes, 'on');
        fill(ampAxes, [time; flipud(time)], ...
            [spectrogramDb.amplitudeMax(:, c); flipud(spectrogramDb.amplitudeMin(:, c))], ...
            bandColor, 'FaceAlpha', 0.55, 'EdgeColor', 'none', 'DisplayName', 'Min/max');
        plot(ampAxes, time, spectrogramDb.amplitudeRms(:, c), ...
            'Color', [0.1 0.1 0.1], 'LineWidth', 0.8, 'DisplayName', 'RMS');
        hold(ampAxes, 'off');
        ampAxes.YLabel.String = 'Amplitude';
        ampAxes.XLabel.String = 'Time (s)';
        grid(ampAxes, 'on');
        ampAxes.Box = 'on';
        ampAxes.XLim = timeRange;
        ampAxes.YLim = [amplitudeMinLimit - amplitudePad, amplitudeMaxLimit + amplitudePad];
        handles.amplitudeAxes(c) = ampAxes;
    end

    linkaxes([handles.spectrogramAxes; handles.amplitudeAxes], 'x');

    controlsGrid = uigridlayout(handles.mainGrid, [1 5]);
    controlsGrid.Layout.Row = 1;
    controlsGrid.Layout.Column = 1;
    controlsGrid.ColumnWidth = {'fit', 'fit', 'fit', 'fit', '1x'};
    controlsGrid.Padding = [0 0 0 0];

    handles.resetButton = uibutton(controlsGrid, 'Text', 'Reset view', ...
        'ButtonPushedFcn', @(btn, event) localResetView(handles, tMin, tMax, frequency));
    handles.resetButton.Layout.Row = 1;
    handles.resetButton.Layout.Column = 1;

    if strcmpi(frequencyScale, 'log')
        scaleButtonText = 'Linear frequency';
    else
        scaleButtonText = 'Log frequency';
    end
    handles.frequencyScaleButton = uibutton(controlsGrid, 'Text', scaleButtonText, ...
        'Tooltip', 'Toggle the frequency axis between linear and logarithmic scale.', ...
        'ButtonPushedFcn', @(btn, event) localToggleFrequencyScale(btn, handles, frequency));
    handles.frequencyScaleButton.Layout.Row = 1;
    handles.frequencyScaleButton.Layout.Column = 2;

    handles.minDbLabel = uilabel(controlsGrid, 'Text', 'Min dB:');
    handles.minDbLabel.Layout.Row = 1;
    handles.minDbLabel.Layout.Column = 3;

    handles.minDbSlider = uislider(controlsGrid, 'Limits', [spectrogramDb.dbFloor, 0], 'Value', perChannelFloor(1));
    handles.minDbSlider.Layout.Row = 1;
    handles.minDbSlider.Layout.Column = 4;
    handles.minDbSlider.ValueChangedFcn = @(src, event) localUpdateDbFloor(handles, src.Value, dbUpperLimit);

    handles.readoutLabel = [];
    if ~isempty(handles.UIFigure)
        handles.readoutLabel = uilabel(controlsGrid, 'Text', '', 'HorizontalAlignment', 'left');
        handles.readoutLabel.Layout.Row = 1;
        handles.readoutLabel.Layout.Column = 5;
        handles.UIFigure.WindowButtonMotionFcn = @(src, event) localUpdateReadout(handles);
    end
end


function dB = localDequantize(spectrogramDb, channelIndex)
    spec = spectrogramDb.spectrogram(:, :, channelIndex);
    if isfield(spectrogramDb, 'params') && isfield(spectrogramDb.params, 'precision') ...
            && strcmpi(spectrogramDb.params.precision, 'uint8')
        dB = spectrogramDb.dbFloor + double(spec) * spectrogramDb.dbStep;
    else
        dB = double(spec);
    end
end


function choice = localValidateChoice(value, allowed)
    if ~ismember(value, allowed)
        error("io:stimuli:spectrogram:plot:InvalidChoice", ...
            "Invalid choice '%s'. Must be one of: %s.", value, strjoin(allowed, ', '));
    end
    choice = value;
end


function localResetView(handles, tMin, tMax, frequency)
    for c = 1:numel(handles.spectrogramAxes)
        specAxes = handles.spectrogramAxes(c);
        specAxes.XLim = [tMin, tMax];
        if strcmp(specAxes.YScale, 'log')
            specAxes.YLim = [frequency(2), frequency(end)];
        else
            specAxes.YLim = [frequency(1), frequency(end)];
        end
        handles.amplitudeAxes(c).XLim = [tMin, tMax];
    end
end


function localToggleFrequencyScale(frequencyScaleButton, handles, frequency)
    for c = 1:numel(handles.spectrogramAxes)
        specAxes = handles.spectrogramAxes(c);
        if strcmp(specAxes.YScale, 'log')
            specAxes.YScale = 'linear';
            specAxes.YLim = [frequency(1), frequency(end)];
        else
            specAxes.YScale = 'log';
            specAxes.YLim = [frequency(2), frequency(end)];
        end
    end
    if strcmp(handles.spectrogramAxes(1).YScale, 'log')
        frequencyScaleButton.Text = 'Linear frequency';
    else
        frequencyScaleButton.Text = 'Log frequency';
    end
end


function localUpdateDbFloor(handles, minDb, dbUpperLimit)
    minDb = min(minDb, dbUpperLimit - 1e-6);
    for c = 1:numel(handles.spectrogramAxes)
        clim(handles.spectrogramAxes(c), [minDb, dbUpperLimit]);
    end
end


function localUpdateReadout(handles)
    pointerPosition = handles.UIFigure.CurrentPoint;
    readouts = {};
    for c = 1:numel(handles.spectrogramAxes)
        readouts{end+1} = localReadoutForAxes(handles.spectrogramAxes(c), pointerPosition, 'Hz'); %#ok<AGROW>
        readouts{end+1} = localReadoutForAxes(handles.amplitudeAxes(c), pointerPosition, 'amp'); %#ok<AGROW>
    end
    readouts = readouts(~cellfun(@isempty, readouts));
    if isempty(readouts)
        return;
    end
    handles.readoutLabel.Text = strjoin(readouts, '   |   ');
end


function text = localReadoutForAxes(axesHandle, pointerPosition, unit)
    text = '';
    if ~isvalid(axesHandle)
        return;
    end
    axesPosition = getpixelposition(axesHandle);
    inside = pointerPosition(1) >= axesPosition(1) && pointerPosition(1) <= axesPosition(1) + axesPosition(3) ...
        && pointerPosition(2) >= axesPosition(2) && pointerPosition(2) <= axesPosition(2) + axesPosition(4);
    if ~inside
        return;
    end
    point = axesHandle.CurrentPoint(1, :);
    if strcmp(unit, 'Hz')
        text = sprintf('t = %.3f s, f = %.0f Hz', point(1), point(2));
    else
        text = sprintf('t = %.3f s, amp = %.4g', point(1), point(2));
    end
end
