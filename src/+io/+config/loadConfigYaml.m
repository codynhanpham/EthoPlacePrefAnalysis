function configs = loadConfigYaml(configFile)
    %%LOADCONFIGYAML Load configuration from a YAML file.
    %
    %   This function returns a struct containing configuration parameters
    %   loaded from a specified YAML file.
    %
    %   Input:
    %       configFile - Path to the YAML configuration file.
    %
    %   Output:
    %       configs - Struct containing the loaded configuration parameters.

    arguments
        configFile {validator.mustBeFileOrEmpty}
    end

    if isempty(configFile)
        configs = struct();
        return;
    end


    ymlText = fileread(configFile);
    configs = yaml.load(ymlText);
    parentdir = fileparts(configFile);
    if parentdir ~= ""
        configs.CONFIG_ROOT = cd(cd(parentdir));
    else
        configs.CONFIG_ROOT = pwd;
    end

    % Validate defaults
    if isfield(configs, 'defaults')
        if isfield(configs.defaults, 'distance2refmode') && ~isempty(char(configs.defaults.distance2refmode))
            validModes = {'line', 'point'};
            if ~any(strcmp(configs.defaults.distance2refmode, validModes))
                error('Invalid value for defaults.distance2refmode: %s. Valid options are: %s', configs.defaults.distance2refmode, strjoin(validModes, ', '));
            end
        end

        if isfield(configs.defaults, 'arena_grid_mode') && ~isempty(char(configs.defaults.arena_grid_mode))
            validGridModes = {'auto', 'manual', 'FOV'};
            if ~any(strcmpi(configs.defaults.arena_grid_mode, validGridModes))
                error('Invalid value for defaults.arena_grid_mode: %s. Valid options are: %s', configs.defaults.arena_grid_mode, strjoin(validGridModes, ', '));
            end
            if strcmpi(configs.defaults.arena_grid_mode, 'FOV') % Normalize FOV to uppercase for consistency
                configs.defaults.arena_grid_mode = "FOV";
            end
        end
    end
    % Validate arena_grid
    if isfield(configs, 'arena_grid')
        if ~isfield(configs.arena_grid, 'n_tiles')
            error('Missing required field arena_grid.n_tiles in configuration.');
        end
        n_tiles = cell2mat(configs.arena_grid.n_tiles);
        if ~isnumeric(n_tiles) || ~isvector(n_tiles) || length(n_tiles) ~= 2
            error('Invalid value for arena_grid.n_tiles: must be a 1D numeric vector with 2 elements (e.g., [5, 3]).');
        end
        configs.arena_grid.n_tiles = n_tiles; % Ensure n_tiles is stored as a numeric vector
    end

    fromConfigKey = {'tracking_providers', 'EthoVision', 'arena'};
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        % If arena is specified, make sure each arena has the required fields: name, zone
        requiredFields = {'name', 'zone'};
        result = cellfun(@(x) all(isfield(x, requiredFields)), configs.tracking_providers.EthoVision.arena);
        if ~all(result)
            error('Each arena in configuration must have the required fields: %s', strjoin(requiredFields, ', '));
        end
        % Each zone must have left and right fields
        result = cellfun(@(x) all(isfield(x.zone, {'left', 'right'})), configs.tracking_providers.EthoVision.arena);
        if ~all(result)
            error('Each arena.zone in configuration must have the required fields: left, right');
        end
    end

end