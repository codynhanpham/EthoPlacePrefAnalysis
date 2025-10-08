function [output] = findNiDaqAudioPlayerBin(configs)
    %%FINDNIDAQAUDIOPLAYERBIN Finds the path to the NI-DAQmxAudioPlayer binary
    %   This function validates the specified path in configs.yml
    %   or attempts to find it in the default installation locations.
    %
    %   Inputs:
    %       configs (optional) - A struct containing configuration settings, loaded with io.config.loadConfigYaml()
    %
    %   Outputs:
    %       output - The path to the `nidaq_audioplayer`, or empty if not found
    %
    %   See also: io.config.loadConfigYaml, utils.path.localappdata

    arguments
        configs struct = struct();
    end

    persistent cachedNiDaqAudioPlayerBinaryPath;
    if ~isempty(cachedNiDaqAudioPlayerBinaryPath) && isfile(cachedNiDaqAudioPlayerBinaryPath)
        output = cachedNiDaqAudioPlayerBinaryPath;
        return
    end

    fromConfigKey = {'defaults', 'nidaq_audioplayer_bin'};
    fromConfig = '';
    
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        fromConfig = getfield(configs, fromConfigKey{:});
    end

    if ~isempty(fromConfig)
        pth = utils.path.canonicalize(fromConfig, configs.CONFIG_ROOT);
        if isfile(pth)
            output = pth;
            cachedNiDaqAudioPlayerBinaryPath = pth;
            return
        end
    end


    localappdatapath = utils.path.localappdata();
    
    if ispc
        nidaq_audioplayer_bin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'nidaq_audioplayer.exe');
    elseif ismac
        nidaq_audioplayer_bin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'nidaq_audioplayer');
    elseif isunix
        nidaq_audioplayer_bin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'nidaq_audioplayer');
    else
        error('Unsupported platform');
    end
    
    if isfile(nidaq_audioplayer_bin)
        output = nidaq_audioplayer_bin;
        cachedNiDaqAudioPlayerBinaryPath = nidaq_audioplayer_bin;
        return
    else
        warning("io:stimuli:findNiDaqAudioPlayerBin:DefaultInstallationNotFound", "Could not find %s in %%LOCALAPPDATA%%/NI-DAQmxAudioPlayer/. For custom installation paths, please set the '%s' key in configs.yml.", nidaq_audioplayer_bin, strjoin(fromConfigKey, '.'));
        output = '';
        return
    end
end