function output = singleTrialAnalysis(ethovisionXlsx, stimuliDir, masterMetadataTableXlsx, kvargs)
    %SINGLE_TRIAL_ANALYSIS Analyze a single trial's EthoVision data and align it with stimulus events
    %   Assume default parameters
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTableXlsx - The master metadata table loaded from an Excel file
    %
    %   Name-Value Pair Arguments:
    %       - 'NiDaqAudioPlayerBin' (optional, but recommended): Path to the `nidaq_audioplayer` binary (same as one used for stimuli playback) for extracting embedded timestamps.
    %           + On Windows, the default is to search in `%LOCALAPPDATA%/NI-DAQmxAudioPlayer/` (default NSIS installer location)
    %           + On Linux, the default is to search in `~/.local/share/NI-DAQmxAudioPlayer/`
    %           + If not found, an error will be thrown.
    %
    %   Outputs:
    %       output - A struct containing the analysis results:
    %           + animalMetadata - Metadata about the animal (age, sex, strain, genotype, etc.) for grouping
    %           + matchedStimFrameFreq - Frequency of matched stimulus frames (the "preferred" stimuli)

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTableXlsx {mustBeFile}

        kvargs.NiDaqAudioPlayerBin {validator.mustBeFileOrEmpty} = ''
    end


    [header, datatable, units, stimulusFrameRange, animalMetadata] = alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTableXlsx, ...
        NiDaqAudioPlayerBin=kvargs.NiDaqAudioPlayerBin ...
    );

    % Count the frequency of animalMatchedStim (Animal position is in the "active" speaker/stim zone)
    animalMatchedStim = datatable{:,'Animal Matched Stim Name'};
    cats = categories(categorical(animalMatchedStim));
    animalMatchedStimCounts = countcats(categorical(animalMatchedStim));
    matchedStimFrameFreq = dictionary(string(cats), animalMatchedStimCounts);

    % Count the frequency of speaker positions matched (actual)
    speakerPos = datatable{:,'Matched Speaker Position'};
    speakerCats = categories(categorical(speakerPos));
    speakerCounts = countcats(categorical(speakerPos));
    matchedSpeakerPosFreq = dictionary(string(speakerCats), speakerCounts);

    % Count the frequency of stim speaker positions extended (available/original, no match by animal position)
    speakerPosExtended = datatable{:,'Stim Speaker Corrected'};
    speakerCatsExtended = categories(categorical(speakerPosExtended));
    speakerCountsExtended = countcats(categorical(speakerPosExtended));
    matchedSpeakerPosExtendedFreq = dictionary(string(speakerCatsExtended), speakerCountsExtended);

    output = struct(...
        'animalMetadata', animalMetadata, ...
        'matchedStimFrameFreq', matchedStimFrameFreq, ...
        'matchedSpeakerPosFrameFreq', matchedSpeakerPosFreq, ...
        'originalStimFrameFreq', matchedSpeakerPosExtendedFreq ...
    );
end