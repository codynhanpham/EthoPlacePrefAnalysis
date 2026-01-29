function output = AcousticWaveformSeries(stimulusFile, kvargs)
    %%ACOUSTICWAVEFORMSERIES Convert an audio stimulus file into an NWB AcousticWaveformSeries
    %   This function requires either 'nidaq_audioplayer' or 'metadata_extract' binary
    %   available to do the extraction AND the MatNWB library installed and set up with the 'ndx-sound' NWB extension.
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
    %       output = io.stimuli.nwb.AcousticWaveformSeries(stimulusFile, Name, Value)
    %
    %   INPUTS:
    %       stimulusFile: Path to the stimulus file. Support most popular audio formats, though well tested with .flac and .wav files.
    %
    %   Name-Value Pair Arguments:
    %       'Config': Configuration struct loaded with io.config.loadConfigYaml() to detect the nidaq_audioplayer and/or metadata_extract binary paths.
    %       'BinaryPath': Path to either the 'nidaq_audioplayer' or 'metadata_extract' binary. If both 'Config' and 'BinaryPath' are provided, 'BinaryPath' takes precedence.
    %       'StartingTimeOffset': (double) Starting time offset of this stimulus in seconds for the AcousticWaveformSeries, relative to the start of the NWB file (or the start of the experiment/trial/recording). Default is 0.0.
    %
    %   OUTPUTS:
    %       output: NWB AcousticWaveformSeries object representing the audio stimulus.
    %           - The 'description' field contains the extracted metadata as a JSON string.
    %           - The 'starting_time_rate' field contains the sampling rate of the audio stimulus.
    %           - The 'data' field contains the native audio data stored in a DataPipe with Zstandard compression and shuffle filter applied.
    %           - To use the audio data later on, follow the NWB spec for AcousticWaveformSeries and thus TimeSeries:
    %               + Actual Data = (Raw Data * data_conversion) + data_offset
    %               + Offset the timing of this stimulus by 'starting_time' seconds.
    %
    %   EXAMPLE:
    %       stimulusFile = 'path/to/stimulus.wav';
    %       awSeries = io.stimuli.nwb.AcousticWaveformSeries(stimulusFile, 'StartingTimeOffset', 180.0);
    %       nwbFile = io.nwb.NwbFile(...); % Create an NWB file object
    %
    %
    %   See also: io.config.loadConfigYaml, io.stimuli.findNiDaqAudioPlayerBin, io.stimuli.findAudioMetadataExtractorBin, io.stimuli.extractMetadata

    arguments
        stimulusFile {mustBeTextScalar, mustBeFile}
        kvargs.Config (1,1) struct = struct()
        kvargs.BinaryPath {mustBeTextScalar} = ""
        kvargs.StartingTimeOffset (1,1) double = 0.0
    end

    matnwb.install(); % Ensure MatNWB is installed and set up

    % Extract metadata using the existing function
    metadata = io.stimuli.extractMetadata(stimulusFile, ...
        'Config', kvargs.Config, ...
        'BinaryPath', kvargs.BinaryPath, "JSONOutput", true);
    metadataDecoded = jsondecode(metadata);

    % Determine chunk size
    % Bigger chunk size = higher compression ratio, but more memory usage during read/write
    chunksize = metadataDecoded.channels * (metadataDecoded.bit_depth / 8) * metadataDecoded.sample_rate * 2; % 2 second chunks

    zstdProperty = types.untyped.datapipe.properties.DynamicFilter(types.untyped.datapipe.dynamic.Filter.ZStandard);
    zstdProperty.parameters = 16; % compression level.
    ShuffleProperty = types.untyped.datapipe.properties.Shuffle();
    dynamicProperties = [ShuffleProperty, zstdProperty];

    % Read audio data
    [audioData, fs] = audioread(stimulusFile, 'native'); % Read in native format to preserve bit depth and accuracy, also may reduce memory usage
    audiopipe = types.untyped.DataPipe('data', audioData', 'axis', 2, 'chunkSize', [1, chunksize], 'filters', dynamicProperties);
    [conversion, offset] = calcConversionFactor(class(audioData));

    output = types.ndx_sound.AcousticWaveformSeries('data', audiopipe, 'starting_time', kvargs.StartingTimeOffset, 'starting_time_rate', fs, 'description', metadata, 'data_conversion', conversion, 'data_offset', offset);
end


function [conversionFactor, offset] = calcConversionFactor(dataTypeStr)
    % Scale to [-1.0, 1.0] range for typical sound() or other audio playback functions
    % Returns conversion factor and offset such that: scaled_value = (raw_value * conversionFactor) + offset
    % Per NWB spec: offset is applied AFTER scaling by conversion
    arguments
        dataTypeStr {mustBeTextScalar, mustBeMember(dataTypeStr, ["uint8", "int16", "int32", "single", "double"])}
    end

    dataTypeStr = char(dataTypeStr);

    % for either int16 or int32, simply is 1/double(intmax(dataTypeStr))
    % for uint8 [0, 255]: scale to [0, 2] then offset to [-1, 1]
    switch dataTypeStr
        case "uint8"
            conversionFactor = 2.0 / 255.0; % Scale uint8 [0, 255] to [0, 2.0]
            offset = -1.0; % Shift to [-1.0, 1.0]
        case "int16"
            offset = 0.0;
            conversionFactor = 1.0 / double(intmax('int16')); % Scale to [-1.0, 1.0]
        case "int32"
            offset = 0.0;
            conversionFactor = 1.0 / double(intmax('int32'));
        case "single"
            offset = 0.0;
            conversionFactor = 1.0; % No scaling needed
        case "double"
            offset = 0.0;
            conversionFactor = 1.0; % No scaling needed
        otherwise
            error('Unsupported data type: %s', dataTypeStr);
    end
end