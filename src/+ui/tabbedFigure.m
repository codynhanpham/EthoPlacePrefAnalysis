function [fig, tgroup, tabs] = tabbedFigure(figureProps, tabGroupProps, tabProps)
%%TABBEDFIGURE creates a figure with a tab group and returns the figure and the tab group objects.
%
%   figureProps: a struct of properties to set on the figure object.
%   tabGroupProps: a struct of properties to set on the tab group object.
%   tabProps: a struct of properties to set on each tab object.

    arguments
        figureProps (1, 1) struct
        tabGroupProps (1, 1) struct
        tabProps (1, :) struct
    end

    % Extract any user-defined callbacks to chain later
    [figureProps, userWindowKeyPressFcn] = extractField(figureProps, 'WindowKeyPressFcn');
    [figureProps, userKeyPressFcn] = extractField(figureProps, 'KeyPressFcn');

    figureProps = namedargs2cell(figureProps);
    figureProps = validateFigureProps(figureProps{:});
    tabGroupProps = namedargs2cell(tabGroupProps);
    tabGroupProps = validateTabGroupProps(tabGroupProps{:});

    tabPropsCell = cell(1, numel(tabProps));
    for i = 1:numel(tabProps)
        cellProps = namedargs2cell(tabProps(i));
        tabPropsCell{i} = validateTabProps(cellProps{:});
    end


    fig = figure(figureProps{:});
    tgroup = uitabgroup(fig, tabGroupProps{:});
    tabs = cell(1, numel(tabPropsCell));
    for i = 1:numel(tabPropsCell)
        tabs{i} = uitab(tgroup, tabPropsCell{i}{:});
    end

    % Build a reusable Ctrl+digit tab-switching handler
    tabSwitchHandler = @(src, event) ctrlDigitTabSwitch(src, event, tgroup, tabs);

    % Attach handlers for both WindowKeyPressFcn and KeyPressFcn,
    % still chaining the user-defined handlers if they exist
    fig.WindowKeyPressFcn = makeChainedCallback({tabSwitchHandler, userWindowKeyPressFcn});
    fig.KeyPressFcn = makeChainedCallback({tabSwitchHandler, userKeyPressFcn});
end


function [s, value] = extractField(s, fieldName)
    if isfield(s, fieldName)
        value = s.(fieldName);
        s = rmfield(s, fieldName);
    else
        value = [];
    end
end

function propertyCell = validateFigureProps(props)
    arguments
        props.?matlab.ui.Figure
    end
    propertyCell = namedargs2cell(props);
end

function propertyCell = validateTabGroupProps(props)
    arguments
        props.?matlab.ui.container.TabGroup
    end
    propertyCell = namedargs2cell(props);
end

function propertyCell = validateTabProps(props)
    arguments
        props.?matlab.ui.container.Tab
    end
    propertyCell = namedargs2cell(props);
end

function cb = makeChainedCallback(fcns)
    %MAKECHAINEDCALLBACK Returns a callback that invokes every non-empty
    % function handle in the cell array `fcns` in order with (src, event).
    %
    %   cb = makeChainedCallback({fcn1, fcn2, ...})
    %
    %   Each element can be a function_handle or a cell-array callback
    %   (e.g. {@myHandler, extraArg).  Empty entries are skipped.
    %
    %   If only one non-empty handle remains, `cb` is that handle directly.

    % Strip empties
    fcns = fcns(~cellfun(@isempty, fcns));
    if isempty(fcns)
        cb = @(~,~) [];  % no-op
    elseif numel(fcns) == 1
        cb = fcns{1};
    else
        cb = @(src, event) chainAndDispatch(src, event, fcns);
    end
end

function chainAndDispatch(src, event, fcns)
    for i = 1:numel(fcns)
        f = fcns{i};
        if isa(f, 'function_handle')
            f(src, event);
        else
            % Cell-array callback, e.g. {@myHandler, extraArg}
            feval(f, src, event);
        end
    end
    drawnow;
end

function ctrlDigitTabSwitch(~, event, tgroup, tabs)
    % Ctrl + digit (1-9) switches to the corresponding tab
    if ~isempty(event.Modifier) && any(strcmp(event.Modifier, 'control'))
        digit = str2double(event.Key);
        if ~isnan(digit) && digit >= 1 && digit <= numel(tabs)
            tgroup.SelectedTab = tabs{digit};
            % Bring figure to front — MATLAB's main window has its own
            % Ctrl+# shortcuts; there's no way to avoid bubbling to the main window, 
            % so we just have to make sure the figure is focused after the tab switch.
            figure(tgroup.Parent);
        end
    end
end