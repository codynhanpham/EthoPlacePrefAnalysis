function [output] = findAudioMetadataExtractorBin(configs)
    %%FINDAUDIOMETADATAEXTRACTORBIN Finds the path to the MetadataExtract binary
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

    persistent cachedAudioMetadataExtractorBinaryPath;
    if ~isempty(cachedAudioMetadataExtractorBinaryPath) && isfile(cachedAudioMetadataExtractorBinaryPath)
        output = cachedAudioMetadataExtractorBinaryPath;
        return
    end

    fromConfigKey = {'defaults', 'audio_metadata_extract_bin'};
    fromConfig = '';
    
    if validator.nestedStructFieldExists(configs, fromConfigKey)
        fromConfig = getfield(configs, fromConfigKey{:});
    end

    if ~isempty(fromConfig)
        pth = utils.path.canonicalize(fromConfig, configs.CONFIG_ROOT);
        if isfile(pth)
            output = pth;
            cachedAudioMetadataExtractorBinaryPath = pth;
            return
        end
    end


    localappdatapath = utils.path.localappdata();

    if ~isfolder(fullfile(localappdatapath, 'NI-DAQmxAudioPlayer'))
        warning("io:stimuli:findAudioMetadataExtractorBin:DefaultInstallationNotFound", "Could not find NI-DAQmxAudioPlayer/ directory in %%LOCALAPPDATA%%. For custom installation paths, please set the '%s' key in configs.yml.", strjoin(fromConfigKey, '.'));
        output = '';
        return
    end

    if ispc
        metadataExtractBin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'metadata_extract.exe');
    elseif ismac
        metadataExtractBin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'metadata_extract');
    elseif isunix
        metadataExtractBin = fullfile(localappdatapath, 'NI-DAQmxAudioPlayer', 'metadata_extract');
    else
        error('Unsupported platform');
    end
    
    
    if isfile(metadataExtractBin)
        output = metadataExtractBin;
        cachedAudioMetadataExtractorBinaryPath = metadataExtractBin;
        return
    else
        % Try to check if the pre-bundled binary is included in the installation
        % TO DEV: this binary is small, so to reduce user friction, we can just include it in the repo, right next to this file; just make sure to update it when the binary changes
        thisfiledir = fileparts(mfilename('fullpath'));
        if ispc
            metadataExtractBin = fullfile(thisfiledir, 'metadata_extract.exe');
        else
            metadataExtractBin = fullfile(thisfiledir, 'metadata_extract');
        end
        if isfile(metadataExtractBin)
            output = metadataExtractBin;
            cachedAudioMetadataExtractorBinaryPath = metadataExtractBin;
            return
        end

        warning("io:stimuli:findAudioMetadataExtractorBin:DefaultInstallationNotFound", "Could not find %s in %%LOCALAPPDATA%%/NI-DAQmxAudioPlayer/. For custom installation paths, please set the '%s' key in configs.yml.", metadataExtractBin, strjoin(fromConfigKey, '.'));
        output = '';
        return
    end
end