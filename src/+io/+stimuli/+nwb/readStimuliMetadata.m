function metadata = readStimuliMetadata(nwbFile)
    %%READSTIMULIMETADATA Read stimuli metadata from an NWB file.
    %
    %   USAGE:
    %       metadata = io.stimuli.readStimuliMetadata(nwbFile)
    %
    %   INPUTS:
    %       nwbFile: Path to the NWB file.
    %
    %   OUTPUTS:
    %       metadata: Struct array containing stimuli metadata.
    %
    %   See also: io.stimuli.extractMetadata, nwb.AcousticWaveformSeries
    arguments
        nwbFile {mustBeFile}
    end

    



end