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
end