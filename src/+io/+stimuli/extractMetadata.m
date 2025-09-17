function metadata = extractMetadata(stimulusFile, kvargs)
    %%EXTRACTMETADATA Extract metadata from a stimulus file.
    %   This function requires either 'nidaq_audioplayer' or 'metadata_extract' binary
    %   available to do the extraction.
    %
    %   Install the required binaries from: https://github.com/codynhanpham/nidaq_audioplayer
    %       - Use the full installer for the complete installation with the audio player, playlist generator, and metadata extractor.
    %       - Simply download only the 'metadata_extract' binary if you only need to run this function.
    %
    %       - If not using the full installer OR you installed to a custom location, please
    %       specify the path to the binary using the 'BinaryPath' parameter.
    %       - Ideally, if use this function as part of the main MATLAB GUI, you can set the paths in the config YAML file:
    %           + 'nidaq_audioplayer_bin' : Path to the 'nidaq_audioplayer' binary
    %           + 'audio_metadata_extract_bin' : Path to the 'metadata_extract' binary
    %         then provide the parsed config struct with the 'Config' parameter.
    %
    %
    %   USAGE:
    %       metadata = io.stimuli.extractMetadata(stimulusFile)
    %       metadata = io.stimuli.extractMetadata(stimulusFile, 'BinaryPath', '/path/to/binary')
    %
    %   INPUTS:
    %       stimulusFile: Path to the stimulus file. Support most popular audio formats, though well tested with .flac and .wav files.
    %
    %   Name-Value Pair Arguments:
    %       'Config': Configuration struct loaded with io.config.loadConfigYaml() to detect the nidaq_audioplayer and/or metadata_extract binary paths.
    %       'BinaryPath': Path to either the 'nidaq_audioplayer' or 'metadata_extract' binary. If both 'Config' and 'BinaryPath' are provided, 'BinaryPath' takes precedence.
    %
    %   OUTPUTS:
    %       metadata: Struct containing the extracted metadata.
    %
    %   See also: io.config.loadConfigYaml, io.stimuli.findNiDaqAudioPlayerBin, io.stimuli.findAudioMetadataExtractorBin

    arguments
        stimulusFile {mustBeTextScalar, mustBeFile}
        kvargs.Config (1,1) struct = struct()
        kvargs.BinaryPath {mustBeTextScalar} = ""
    end


    % Validate stimulus file, we don't care about the output here
    audioinfo(stimulusFile);


    % Determine the binary path
    binaryPath = '';
    if kvargs.BinaryPath ~= "" && isfile(kvargs.BinaryPath)
        binaryPath = kvargs.BinaryPath;
    else
        warning("off", "io:stimuli:findAudioMetadataExtractorBin:DefaultInstallationNotFound");
        metbin = io.stimuli.findAudioMetadataExtractorBin(kvargs.Config);
        metbin = char(metbin);
        warning("on", "io:stimuli:findAudioMetadataExtractorBin:DefaultInstallationNotFound");

        warning("off", "io:stimuli:findNiDaqAudioPlayerBin:DefaultInstallationNotFound");
        nibin = io.stimuli.findNiDaqAudioPlayerBin(kvargs.Config);
        nibin = char(nibin);
        warning("on", "io:stimuli:findNiDaqAudioPlayerBin:DefaultInstallationNotFound");

        if ~isempty(metbin)
            binaryPath = metbin;
        elseif ~isempty(nibin)
            binaryPath = nibin;
        end
    end

    if isempty(binaryPath) || ~isfile(binaryPath)
        error("io:stimuli:extractMetadata:BinaryNotFound", "Could not find either 'nidaq_audioplayer' or 'metadata_extract' binary. Please install from: https://github.com/codynhanpham/nidaq_audioplayer");
    end

    commandNi = sprintf('"%s" metadata -i "%s"', binaryPath, stimulusFile);
    commandMet = sprintf('"%s" -i "%s"', binaryPath, stimulusFile);

    % Try running the commands and capturing the output, metadata_extract preferred
    [status, cmdout] = system(commandMet);
    if status ~= 0
        [status, cmdout] = system(commandNi);
    end
    if status ~= 0
        error("io:stimuli:extractMetadata:CommandFailed", "Failed to run the metadata extraction command. Please ensure the binary is functional.");
    end

    % Parse the output
    try
        metadata = jsondecode(cmdout);
    catch ME
        error("io:stimuli:extractMetadata:JSONDecodeFailed", "Failed to decode JSON output from command:\n\t%s\n%s", command, getReport(ME));
    end


    % Post-process metadata validation here
    % For now, it is not necessary
    % ...

end