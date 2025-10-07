function summary = trialSummary(ethovisionXlsx, stimuliDir, masterMetadataTable, kvargs)
    %%TRIALSUMMARY Align EthoVision data to stimulus events and summarize trial information
    %
    %   summary = trial.stats.trialSummary(ethovisionXlsx, stimuliDir, masterMetadataTable)
    %
    %   Inputs:
    %       ethovisionXlsx - The EthoVision data loaded from an Excel file
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %       masterMetadataTable - The master metadata table loaded from an Excel file with io.metadata.loadMasterMetadata
    %
    %   Name-Value Pair Arguments:
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml() to detect the nidaq_audioplayer and/or metadata_extract binary paths.
    %
    %   Outputs:
    %       summary - A struct containing the analysis results:
    %           + animalMetadata - Metadata about the animal (age, sex, strain, genotype)
    %           + animalMatchedStim - Dictionary of stimulus names with # frame count where the animal was in the "active" stimulus zone
    %           + stimspeakerMatched - Left/Right speaker position of the matched stimulus frames (same as animalMatchedStim but with speaker position)
    %           + stimspeakerOriginal - Left/Right speaker position of the original stimulus, in frames, as designed in the stimulus file regardless of animal position
    %
    %   See also: io.ethovision.alignEthovisionRawToStim, io.metadata.loadMasterMetadata, io.config.loadConfigYaml

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        masterMetadataTable {validator.mustBeFileOrTable}

        kvargs.Config (1,1) struct = struct()
    end

    [header, datatable, units, stimulusFrameRange, animalMetadata] = io.ethovision.alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, ...
        MasterMetadataTable=masterMetadataTable, ...
        Config=kvargs.Config ...
    );

    stimPeriodTable = datatable(stimulusFrameRange(1):stimulusFrameRange(2), :);

    allstims = stimPeriodTable{:,'Chapter Original'};
    allstims = unique(allstims(~cellfun(@anymissing, allstims)));
    allstims = allstims(~endsWith(allstims, 'ISI'));
    outrointro = {'Outro', 'Intro'};
    allstims = allstims(~startsWith(allstims, outrointro) & ~endsWith(allstims, outrointro));

    % Animal position is in the "active" speaker/stim zone
    animalMatchedStim = stimPeriodTable{:,'Animal Matched Stim Name'};
    cats = categories(categorical(animalMatchedStim));
    animalMatchedStimCounts = countcats(categorical(animalMatchedStim));
    animalMatchedStimFrameFreq = dictionary(string(cats), animalMatchedStimCounts);
    missingStims = setdiff(allstims, keys(animalMatchedStimFrameFreq));
    for i = 1:length(missingStims)
        animalMatchedStimFrameFreq(missingStims{i}) = 0;
    end

    % Left/Right speaker position of the matched stimulus frames
    stimspeakerMatched = stimPeriodTable{:,'Matched Speaker Position'};
    speakerCats = categories(categorical(stimspeakerMatched));
    speakerCounts = countcats(categorical(stimspeakerMatched));
    stimspeakerMatchedFrameFreq = dictionary(string(speakerCats), speakerCounts);
    missingSpeakers = setdiff(["Left Speaker", "Right Speaker"], keys(stimspeakerMatchedFrameFreq));
    for i = 1:length(missingSpeakers)
        stimspeakerMatchedFrameFreq(missingSpeakers{i}) = 0;
    end

    % Count the frequency of stim speaker positions extended (available/original, no match by animal position)
    stimspeakerExtended = stimPeriodTable{:,'Stim Speaker Corrected'};
    speakerCatsExtended = categories(categorical(stimspeakerExtended));
    speakerCountsExtended = countcats(categorical(stimspeakerExtended));
    stimspeakerOriginalFrameFreq = dictionary(string(speakerCatsExtended), speakerCountsExtended);
    missingSpeakersExtended = setdiff(["Left Speaker", "Right Speaker"], keys(stimspeakerOriginalFrameFreq));
    for i = 1:length(missingSpeakersExtended)
        stimspeakerOriginalFrameFreq(missingSpeakersExtended{i}) = 0;
    end

    summary = struct(...
        'animalMetadata', animalMetadata, ...
        'animalMatchedStim', animalMatchedStimFrameFreq, ...
        'stimspeakerMatched', stimspeakerMatchedFrameFreq, ...
        'stimspeakerOriginal', stimspeakerOriginalFrameFreq ...
    );
end