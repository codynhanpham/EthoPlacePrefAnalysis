function bool = isconfig(config)
    %%ISCONFIG Validate if the input is a valid configuration struct
    %   This function checks if the provided config struct contains the required fields and valid values.
    %
    %   Inputs:
    %       config - A struct representing configuration settings, ideally loaded via io.config.loadConfigYaml()
    %
    %   Outputs:
    %       bool - A boolean indicating whether the config struct is valid (true) or not (false)
    %
    %   See also: io.config.loadConfigYaml

    arguments
        config (1, 1) struct
    end

    requiredFields = {'preferences', 'defaults', 'tracking_providers', 'CONFIG_ROOT'};

    % Check for required fields
    for i = 1:length(requiredFields)
        if ~isfield(config, requiredFields{i})
            bool = false;
            return;
        end
    end

    % in defaults:
    % - distance2refmode must be either "line" or "point" if it exists
    % - arena_grid_mode must be either "auto", "manual" or "FOV" if it exists (case insensitive)
    if isfield(config, 'defaults')
        if isfield(config.defaults, 'distance2refmode') && ~isempty(char(config.defaults.distance2refmode))
            validModes = {'line', 'point'};
            if ~any(strcmp(config.defaults.distance2refmode, validModes))
                bool = false;
                return;
            end
        end
        if isfield(config.defaults, 'arena_grid_mode') && ~isempty(char(config.defaults.arena_grid_mode))
            validGridModes = {'auto', 'manual', 'FOV'};
            if ~any(strcmpi(config.defaults.arena_grid_mode, validGridModes))
                bool = false;
                return;
            end
        end
    end

    % in arena_grid:
    % - n_tiles must be a 1D, 2-element numeric vector
    if isfield(config, 'arena_grid')
        if ~isfield(config.arena_grid, 'n_tiles')
            bool = false;
            return;
        end
        n_tiles = cell2mat(config.arena_grid.n_tiles);
        if ~isnumeric(n_tiles) || ~isvector(n_tiles) || length(n_tiles) ~= 2
            bool = false;
            return;
        end
    end

    bool = true;
end