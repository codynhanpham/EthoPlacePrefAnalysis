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

    

end