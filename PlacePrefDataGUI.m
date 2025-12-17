% PlacePrefDataGUI - Start script for the PlacePrefDataGUI application

function PlacePrefDataGUI(kvargs)
    arguments
        kvargs.Position = [];
    end

    [~, oldPath] = LoadSessionPath();

    %% Validate requested input arguments
    % Validate input arguments, remove completely fields with empty/bad values to use defaults defined in the app
    args = struct();
    
    % Position must be a 1x4 numeric vector if provided, all are numeric, non-nan, and finite
    if ~isempty(kvargs.Position)
        pos = kvargs.Position;
        if isnumeric(pos) && isvector(pos) && numel(pos) == 4 && all(~isnan(pos)) && all(isfinite(pos))
            args.Position = pos;
        end
    end


    %% Start the app with validated arguments
    % LoadSessionPath should already add /src to the path
    mainFcn = str2func("PlacePrefDataGUI_main");
    args = namedargs2cell(args);
    mainFcn('', oldPath, args{:});
end