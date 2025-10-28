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


    fromConfigKey = {'project_settings', 'EthoVision', 'arena'};
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        % If arena is specified, make sure each arena has the required fields: name, zone
        requiredFields = {'name', 'zone'};
        result = cellfun(@(x) all(isfield(x, requiredFields)), configs.project_settings.EthoVision.arena);
        if ~all(result)
            error('Each arena in configuration must have the required fields: %s', strjoin(requiredFields, ', '));
        end
        % Each zone must have left and right fields
        result = cellfun(@(x) all(isfield(x.zone, {'left', 'right'})), configs.project_settings.EthoVision.arena);
        if ~all(result)
            error('Each arena.zone in configuration must have the required fields: left, right');
        end
    end
end