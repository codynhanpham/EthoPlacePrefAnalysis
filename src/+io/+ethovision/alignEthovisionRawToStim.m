function [header, datatable, units, stimulusFrameRange, animalMetadata, stimuli] = alignEthovisionRawToStim(ethovisionXlsx, stimuliDir, kvargs)
    %ALIGN_ETHOVISION_RAW_TO_STIM Wrapper around `loadEthovisionXlsx` to add matching stimuli event columns
    %   This function wraps `loadEthovisionXlsx` while taking in additional arguments
    %   to load and add the corresponding stimulus events to a new column in the datatable returned by `loadEthovisionXlsx`.
    %
    %   Inputs:
    %       ethovisionXlsx - Path to the EthoVision exported XLSX file. In general, location of this file should follow the default EthoVision project structure.
    %       stimuliDir     - The directory containing original stimuli `.flac` files with embedded timestamps
    %
    %   Name-Value Pair Arguments:
    %       - 'Config': Configuration struct loaded with io.config.loadConfigYaml()
    %       - 'ArenaName': The name of the arena to load data for. If not specified, data for the first arena found will be loaded.
    %       - 'ExpectedNumVariables' (optional): The number of data columns in the table to expect in EthoVision exported XLSX file. Default max is 50, with empty columns removed.
    %
    %       - 'StimulusProtocol' (optional if `MasterMetadataTable` exists): The name of the stimuli file played during this trial, including the `.flac` extension. This file must exists in `stimuliDir`. If `MasterMetadataTable` is provided, this value will take precedence.
    %       - 'StimStartFrame' (optional if `MasterMetadataTable` exists): The frame number at which the stimulus starts. This is the first frame when the signal LED turns on in the raw recording. If `MasterMetadataTable` is provided, this value will take precedence.
    %       - 'SpeakerFlipped' (optional if `MasterMetadataTable` exists): Indicates whether the speaker was flipped during the trial (Normal: Ch1-Left, Ch2-Right | Flipped: Ch1-Right, Ch2-Left). If `MasterMetadataTable` is provided, this value will take precedence.
    %       - 'MasterMetadataTable' (required when any of 'StimuliFileName', 'StimStartFrame', or 'SpeakerFlipped' is missing): Path to the master metadata table containing information about the trials and stimuli. The following headers are required:
    %           + 'ETHOVISION_FILE': Indicates the EthoVision file associated with the trial, must match the `Experiment` header in `ethovisionXlsx`.
    %           + 'ETHOVISION_TRIAL': The trial number, should be in the file name of `ethovisionXlsx`, and match the numeric part of `Trial name` header.
    %           + 'STIMULUS_PROTOCOL': Value to be used for `StimulusProtocol`.
    %           + 'STIM_START_FRAME': Value to be used for `StimStartFrame`.
    %           + 'HABITUATION_DURATION_SEC': Default used when `STIM_START_FRAME` is missing or NaN, default to 0 if this is also missing or NaN. This value is multiplied by the average frame rate in 'Trial time' column of `ethovisionXlsx`, then +1, to estimate the stimulus start frame.
    %           + 'SPEAKER_FLIPPED': Value to be used for `SpeakerFlipped`.
    %
    %   Outputs:
    %       header   - The header information for the aligned data
    %       datatable - The aligned data table
    %       units    - The units of the data columns
    %       stimulusFrameRange - The frame range for the stimulus as [startFrame, endFrame], inclusive
    %       animalMetadata - A struct containing metadata about the animal (sex, genotype, strain, age)
    %       stimuli  - Metadata of the stimuli used in this trial, including individual stimulus timestamps and durations
    %
    %   See also: io.config.loadConfigYaml, io.ethovision.loadEthovisionXlsx, io.metadata.loadMasterMetadata, io.stimuli.extractMetadata

    arguments
        ethovisionXlsx {mustBeFile}
        stimuliDir {mustBeFolder}
        kvargs.Config (1,1) struct = struct()
        kvargs.ArenaName {validator.mustBeTextScalarOrEmpty} = ''
        kvargs.ExpectedNumVariables {mustBeNumeric} = 50
        kvargs.StimulusProtocol {mustBeTextScalar} = ''
        kvargs.StimStartFrame {mustBePositiveIntOrEmpty} = []
        kvargs.SpeakerFlipped {mustBeNumericLogicalOrEmpty} = []
        kvargs.MasterMetadataTable {validator.mustBeFileTableOrEmpty} = ''
    end
    if isempty(kvargs.MasterMetadataTable) && ~all(~cellfun(@isempty, {kvargs.StimulusProtocol, kvargs.StimStartFrame, kvargs.SpeakerFlipped}))
        error('If MasterMetadataTable is not provided, all of StimulusProtocol, StimStartFrame, and SpeakerFlipped must be specified.');
    end



    % % IMPORTANT: Log the version of the script whenever any changes that affect the outputs are made
    % % Increment the version number following semantic versioning rules, then write a comment with some notes on what changed
    % % Code optimizations that do not affect outputs do not require a version bump
    % % Changing the version number here will force re-alignment and re-saving of aligned files
    % SCRIPT_VERSION = '0.0.0'; % Nothing, just as your template
    % SCRIPT_VERSION = '0.0.1'; % Nothing, just as your template
    % SCRIPT_VERSION = '1.0.0'; % The initial version of this script, uses the full metadata table as hash for results caching
    % SCRIPT_VERSION = '1.1.0'; % Load xlsx header to extract the exact metadata row + actual stimuli file to use as hash components for results caching
    % SCRIPT_VERSION = '1.1.1'; % Also store script version and the full metadata row in saved aligned file for future reference
    % SCRIPT_VERSION = '1.2.0'; % Store stimuli metadata extracted from stimulus file in the aligned file output for convenience
    % % Comment out previous versions, move above this line (do not delete, keep for reference)
    % % and add the new version with notes here
    SCRIPT_VERSION = '1.2.1'; % Fix logic for end-of-stimulus frame calculation




    % Hash and check for existing aligned file to speed up repeated loading
    % The output should be identical if the same inputs are provided (here, assume the stimulus file itself does not change)
    ethovisionXlsxHash = DataHash(ethovisionXlsx, 'SHA-256', 'file');
    manualparams = {kvargs.StimulusProtocol, kvargs.StimStartFrame, kvargs.SpeakerFlipped};
    manualparamsHash = DataHash(manualparams, 'SHA-256');
    configHash = DataHash(kvargs.Config, 'SHA-256');
    masterMetadata = table();
    if istable(kvargs.MasterMetadataTable)
        masterMetadata = kvargs.MasterMetadataTable;
    elseif ~isempty(kvargs.MasterMetadataTable)
        masterMetadata = io.metadata.loadMasterMetadata(kvargs.MasterMetadataTable);
    end
    
    metadataRow = table();

    [header, ~, ~] = io.ethovision.loadEthovisionXlsx(ethovisionXlsx, ExpectedNumVariables=kvargs.ExpectedNumVariables, ArenaName=kvargs.ArenaName, HeaderOnly=true);
    trialName = header("Trial name");
    trialParts = split(trialName, ' ');
    trialNumber = str2double(strtrim(trialParts{end}));
    experimentName = header("Experiment");
    arenaName = header("Arena name"); % just to make sure the arena name is exactly as how EthoVision exported it

    if istable(masterMetadata) && ~isempty(masterMetadata)
        trialMask = (masterMetadata.ETHOVISION_TRIAL == trialNumber) & ...
            (masterMetadata.ETHOVISION_FILE == experimentName) & ...
            (masterMetadata.ETHOVISION_ARENA == arenaName);
        trialRowIdx = find(trialMask, 1);
        metadataRow = masterMetadata(trialRowIdx, :);

        if isempty(kvargs.StimulusProtocol)
            kvargs.StimulusProtocol = char(metadataRow.('STIMULUS_PROTOCOL'));
        end
    end
    if isempty(kvargs.StimulusProtocol)
        error('StimulusProtocol must be specified either directly with StimulusProtocol named-argument or through a non-empty column ''STIMULUS_PROTOCOL'' in MasterMetadataTable.');
    end
    % Find stimulus file
    dirglobpattern = sprintf("%s/**/%s", string(stimuliDir), string(kvargs.StimulusProtocol));
    stimFiles = dir(dirglobpattern);
    if isempty(stimFiles)
        error('No stimulus files found matching pattern %s.', dirglobpattern);
    end
    stimFile = fullfile(stimFiles(1).folder, stimFiles(1).name);
    
    metadatarowHash = DataHash(metadataRow, 'SHA-256');
    stimFileHash = DataHash(stimFile, 'SHA-256', 'file'); % io.stimuli.extractMetadata should have verified file exists

    composite = [char(ethovisionXlsxHash), char(manualparamsHash), char(configHash), char(metadatarowHash), char(stimFileHash), char(SCRIPT_VERSION)];
    ethovisionXlsxHash = DataHash(composite, 'SHA-256');

    [filedir, filename] = fileparts(ethovisionXlsx);
    alignedFile = fullfile(filedir, sprintf("%s - %s.mat", filename, string(ethovisionXlsxHash)));
    if isfile(alignedFile)
        % Load existing aligned file
        s = load(alignedFile, 'header', 'datatable', 'units', 'stimulusFrameRange', 'animalMetadata', 'stimuli');
        header = s.header;
        datatable = s.datatable;
        units = s.units;
        stimulusFrameRange = s.stimulusFrameRange;
        animalMetadata = s.animalMetadata;
        stimuli = s.stimuli;
        return;
    else
        % Check if any other aligned files with different hash exist, warn and remove them
        otherAlignedFiles = dir(fullfile(filedir, sprintf("%s - *.mat", filename)));
        if ~isempty(otherAlignedFiles)
            for i = 1:length(otherAlignedFiles)
                otherFilePath = fullfile(otherAlignedFiles(i).folder, otherAlignedFiles(i).name);
                warning('Removing old aligned file "%s" since inputs have changed.', otherFilePath);
                delete(otherFilePath);
            end
        end
    end


    % Load EthoVision data
    [header, datatable, units] = io.ethovision.loadEthovisionXlsx(ethovisionXlsx, ExpectedNumVariables=kvargs.ExpectedNumVariables, ArenaName=kvargs.ArenaName, HeaderOnly=false);

    % Extract metadata parameters if available from the matching row in master metadata
    sex = ''; genotype = ''; strain = ''; age = ''; cagecode = ''; id = '';
    if ~isempty(metadataRow)
        sex = char(metadataRow.('ANIMAL_SEX'));
        genotype = char(metadataRow.('ANIMAL_GENOTYPE'));
        strain = char(metadataRow.('ANIMAL_STRAIN'));
        age = metadataRow.('ANIMAL_P_AGE');
        cagecode = char(metadataRow.('CAGE_CODE'));
        id = char(metadataRow.('ANIMAL_ID'));

        if isempty(kvargs.StimulusProtocol)
            kvargs.StimulusProtocol = char(metadataRow.('STIMULUS_PROTOCOL'));
        end
        if isempty(kvargs.StimStartFrame)
            stimStartVal = metadataRow.('STIM_START_FRAME');
            if ~isnumeric(stimStartVal)
                stimStartVal = str2double(string(stimStartVal));
            end
            kvargs.StimStartFrame = stimStartVal;
            
            if isempty(kvargs.StimStartFrame) || isnan(kvargs.StimStartFrame)
                habitdur = metadataRow.('HABITUATION_DURATION_SEC');
                if ~isnumeric(habitdur)
                    habitdur = str2double(string(habitdur));
                end
                if isempty(habitdur) || isnan(habitdur)
                    habitdur = 0; % Default to start of trial
                end
                mediafile = io.ethovision.mediaPathFromXlsx(ethovisionXlsx, "Header", header);
                if isfile(mediafile)
                    v = VideoReader(mediafile);
                    fps = v.FrameRate;
                    kvargs.StimStartFrame = habitdur * fps + 1;
                    clear v;
                end
            end
            
            if isempty(kvargs.StimStartFrame) || isnan(kvargs.StimStartFrame)
                kvargs.StimStartFrame = 1;
            end
            kvargs.StimStartFrame = round(kvargs.StimStartFrame);
        end
        if isempty(kvargs.SpeakerFlipped)
            kvargs.SpeakerFlipped = logical(metadataRow.('SPEAKER_FLIPPED'));
        end
    end
    animalMetadata = struct('sex', sex, 'genotype', genotype, 'strain', strain, 'age', age, 'cagecode', cagecode, 'id', id);


    % All of StimulusProtocol, StimStartFrame, and SpeakerFlipped should be non-empty now
    % Do post-processing, more convenient for downstream tasks
    kvargs.SpeakerFlipped = logical(kvargs.SpeakerFlipped);

    % Extract metadata from stimulus file
    metadata = io.stimuli.extractMetadata(stimFile, "Config", kvargs.Config);

    requiredFields = {'chapters', 'duration'};
    if ~isstruct(metadata) || ~all(isfield(metadata, requiredFields))
        missing = setdiff(requiredFields, fieldnames(metadata));
        error('Error parsing metadata JSON output from command: %s\nOutput: %s\n\nMissing fields: %s', command, cmdout, strjoin(missing, ', '));
    end

    if ~isfield(metadata, "chapters") || isempty(metadata.chapters)
        error('No chapter markers found in stimulus file metadata.');
    end
    chapters = metadata.chapters; % Nx1 struct array with fields: timestamp, title, description, startsample

    numRows = size(datatable, 1);
    % Calculate stimulus timing
    timeAtStimStart = datatable{kvargs.StimStartFrame, 'Trial time'};
    stimEndTime = timeAtStimStart + metadata.duration;
    trialTimes = datatable{:, 'Trial time'};
    stimEndFrame = find(trialTimes >= stimEndTime, 1, 'first');
    if isempty(stimEndFrame)
        stimEndFrame = numRows + 1;
    end

    % Pre-allocate with string arrays, should be faster than cell arrays
    chapterOriginal = strings(numRows, 1);
    chapterOriginal(:) = "NONE | Pre-Stimulus";
    animalSameZoneAsStim = zeros(numRows, 1);
    animalMatchedStim = strings(numRows, 1);
    speakerPosExtended = strings(numRows, 1);
    speakerPos = strings(numRows, 1);
    
    % Set post-stimulus values
    if stimEndFrame <= numRows
        chapterOriginal(stimEndFrame:end) = "NONE | Post-Stimulus";
    end

    % Chapter assignment
    if kvargs.StimStartFrame < stimEndFrame
        stimIndices = kvargs.StimStartFrame:(stimEndFrame-1);
        
        if ~isempty(stimIndices)
            % Calculate relative timestamps for all stimulus frames
            relativeTimestamps = trialTimes(stimIndices) - timeAtStimStart;
            chapterTimestamps = [chapters.timestamp];
            
            % Use discretize for efficient chapter assignment than looping over each frame
            chapterIndices = discretize(relativeTimestamps, [-inf, chapterTimestamps, inf]);
            
            % Adjust indices (discretize returns bin number, we want the last valid chapter)
            chapterIndices = max(1, chapterIndices - 1);
            chapterIndices(chapterIndices == 0) = 1; % Handle edge case
            chapterIndices = min(chapterIndices, length(chapters)); % Ensure valid indices
            
            % Vectorized assignment of chapter titles
            validMask = chapterIndices >= 1 & chapterIndices <= length(chapters);
            if any(validMask)
                validStimIndices = stimIndices(validMask);
                validChapterIndices = chapterIndices(validMask);
                
                chapterTitles = {chapters.title};
                assignedTitles = chapterTitles(validChapterIndices);
                
                chapterOriginal(validStimIndices) = string(assignedTitles);

                leftTerm = "Left"; % Default search term for left zone column
                rightTerm = "Right"; % Default search term for right zone column
                zoneMatchMethod = "startsWith"; % Default matching method
                
                zonematchconfigkey = {'tracking_providers', 'EthoVision', 'default_zone_match_method'};
                if validator.nestedStructFieldExists(kvargs.Config, zonematchconfigkey)
                    zoneMatchMethod = getfield(kvargs.Config, zonematchconfigkey{:});
                end
                % Check if this arenaName is specified in the config
                arenaConfigKey = {'tracking_providers', 'EthoVision', 'arena'};
                if validator.nestedStructFieldExists(kvargs.Config, arenaConfigKey)
                    arenas = getfield(kvargs.Config, arenaConfigKey{:});
                    arenaIdx = find(cellfun(@(x) strcmp(x.name, arenaName), arenas), 1);
                    if ~isempty(arenaIdx)
                        % arena.zone should always exists and have left and right fields as per config validation in loadConfigYaml()
                        leftTerm = arenas{arenaIdx}.zone.left;
                        rightTerm = arenas{arenaIdx}.zone.right;
                        if isfield(arenas{arenaIdx}, 'zone_match_method')
                            zoneMatchMethod = arenas{arenaIdx}.zone_match_method;
                        end
                    end
                end

                % All potential "In zone(...)" columns
                inzones = datatable.Properties.VariableNames(startsWith(datatable.Properties.VariableNames, "In zone("));
                % Find columns matching left and right zone names based on config
                datazonenames = cellfun(@(x) parseInZoneText(x), inzones, 'UniformOutput', false);
                inLeftIdx = find(cellfun(@(x) matchedZoneName(x, leftTerm, zoneMatchMethod), datazonenames), 1);
                inLeftText = inzones{inLeftIdx};
                inLeftIdx = find(strcmp(datatable.Properties.VariableNames, inLeftText), 1);
                inRightIdx = find(cellfun(@(x) matchedZoneName(x, rightTerm, zoneMatchMethod), datazonenames), 1);
                inRightText = inzones{inRightIdx};
                inRightIdx = find(strcmp(datatable.Properties.VariableNames, inRightText), 1);


                if ~isempty(inLeftIdx) && ~isempty(inRightIdx)
                    % Get zone data for the valid stimulus frames
                    inLeftData = datatable{validStimIndices, inLeftIdx};
                    inRightData = datatable{validStimIndices, inRightIdx};
                    % replace NaN with 0s (ethovision might failed to extract position of the animal)
                    inLeftData(isnan(inLeftData)) = 0;
                    inRightData(isnan(inRightData)) = 0;

                    % Ensure inLeftData and inRightData are logical arrays
                    inLeftData = logical(inLeftData)';
                    inRightData = logical(inRightData)';
                    
                    % Assign animal same in same zone as stimuli:
                    % - If ~kvargs.SpeakerFlipped: (Left = Ch1, Right = Ch2)
                    %   - If chapter title starts with [Ch1] AND inLeft == true, animalSameZoneAsStim = 1
                    %   - If chapter title starts with [Ch2] AND inRight == true, animalSameZoneAsStim = 1
                    % - If kvargs.SpeakerFlipped: (Left = Ch2, Right = Ch1)
                    %   - If chapter title starts with [Ch1] AND inRight == true, animalSameZoneAsStim = 1
                    %   - If chapter title starts with [Ch2] AND inLeft == true, animalSameZoneAsStim = 1
                    % - The ISI period immediately follows active channels also belong to the same zone

                    if ~kvargs.SpeakerFlipped
                        % Normal configuration: Left = Ch1, Right = Ch2
                        
                        % Create extended masks that include ISI periods following each channel
                        ch1ExtendedMask = false(size(assignedTitles));
                        ch2ExtendedMask = false(size(assignedTitles));

                        ch1Title = '';
                        ch2Title = '';

                        currentChannel = '';
                        for i = 1:length(assignedTitles)
                            title = assignedTitles{i};
                            if startsWith(title, '[Ch1]')
                                currentChannel = 'Ch1';
                                ch1ExtendedMask(i) = true;
                                if isempty(ch1Title)
                                    ch1Title = title;
                                end
                            elseif startsWith(title, '[Ch2]')
                                currentChannel = 'Ch2';
                                ch2ExtendedMask(i) = true;
                                if isempty(ch2Title)
                                    ch2Title = title;
                                end
                            elseif endsWith(title, 'ISI')
                                % ISI continues the current channel
                                if strcmp(currentChannel, 'Ch1')
                                    ch1ExtendedMask(i) = true;
                                elseif strcmp(currentChannel, 'Ch2')
                                    ch2ExtendedMask(i) = true;
                                end
                            else
                                % Non-channel, non-ISI title interrupts the current channel
                                currentChannel = '';
                            end
                        end
                        
                        % Ch1 stimulus when animal is in left zone
                        ch1InLeftMask = ch1ExtendedMask & inLeftData;
                        % Ch2 stimulus when animal is in right zone
                        ch2InRightMask = ch2ExtendedMask & inRightData;
                        
                        sameZoneMask = ch1InLeftMask | ch2InRightMask;
                        animalMatchedStim(validStimIndices(ch1InLeftMask)) = ch1Title;
                        animalMatchedStim(validStimIndices(ch2InRightMask)) = ch2Title;
                        speakerPos(validStimIndices(ch1InLeftMask)) = "Left Speaker";
                        speakerPos(validStimIndices(ch2InRightMask)) = "Right Speaker";
                        speakerPosExtended(validStimIndices(ch1ExtendedMask)) = "Left Speaker";
                        speakerPosExtended(validStimIndices(ch2ExtendedMask)) = "Right Speaker";
                    else
                        % Flipped configuration: Left = Ch2, Right = Ch1
                        
                        % Create extended masks that include ISI periods following each channel
                        ch1ExtendedMask = false(size(assignedTitles));
                        ch2ExtendedMask = false(size(assignedTitles));
                        
                        ch1Title = '';
                        ch2Title = '';

                        currentChannel = '';
                        for i = 1:length(assignedTitles)
                            title = assignedTitles{i};
                            if startsWith(title, '[Ch1]')
                                currentChannel = 'Ch1';
                                ch1ExtendedMask(i) = true;
                                if isempty(ch1Title)
                                    ch1Title = title;
                                end
                            elseif startsWith(title, '[Ch2]')
                                currentChannel = 'Ch2';
                                ch2ExtendedMask(i) = true;
                                if isempty(ch2Title)
                                    ch2Title = title;
                                end
                            elseif endsWith(title, 'ISI')
                                % ISI continues the current channel
                                if strcmp(currentChannel, 'Ch1')
                                    ch1ExtendedMask(i) = true;
                                elseif strcmp(currentChannel, 'Ch2')
                                    ch2ExtendedMask(i) = true;
                                end
                            else
                                % Non-channel, non-ISI title interrupts the current channel
                                currentChannel = '';
                            end
                        end
                        
                        % Ch1 stimulus when animal is in right zone (flipped)
                        ch1InRightMask = ch1ExtendedMask & inRightData;
                        % Ch2 stimulus when animal is in left zone (flipped)
                        ch2InLeftMask = ch2ExtendedMask & inLeftData;
                        
                        sameZoneMask = ch1InRightMask | ch2InLeftMask;
                        animalMatchedStim(validStimIndices(ch1InRightMask)) = ch1Title;
                        animalMatchedStim(validStimIndices(ch2InLeftMask)) = ch2Title;
                        speakerPos(validStimIndices(ch1InRightMask)) = "Right Speaker";
                        speakerPos(validStimIndices(ch2InLeftMask)) = "Left Speaker";
                        speakerPosExtended(validStimIndices(ch1ExtendedMask)) = "Right Speaker";
                        speakerPosExtended(validStimIndices(ch2ExtendedMask)) = "Left Speaker";
                    end
                    
                    animalSameZoneAsStim(validStimIndices(sameZoneMask)) = 1;
                end
            end
        end
    end

    % Add columns to table
    speakerChannelsFlipped = repmat(kvargs.SpeakerFlipped, numRows, 1);
    datatable = addvars(datatable, cellstr(chapterOriginal), speakerChannelsFlipped, speakerPosExtended, animalSameZoneAsStim, animalMatchedStim, speakerPos, ...
        'NewVariableNames', {'Chapter Original', 'Speaker Channels Flipped', 'Stim Speaker Corrected', 'Animal Is Same Zone As Stim', 'Animal Matched Stim Name', 'Matched Speaker Position'});

    stimulusFrameRange = [kvargs.StimStartFrame, stimEndFrame-1];
    % drop thumbnail from stim metadata since it will take up unnecessary space when saving
    if isfield(metadata, 'thumbnail')
        metadata = rmfield(metadata, 'thumbnail');
    end
    
    s = struct('header', header, 'datatable', datatable, 'units', units, ...
        'metadataRow', metadataRow, ... % This has extra metadata that is not in animalMetadata, but available only when MasterMetadataTable is provided
        'stimulusFrameRange', stimulusFrameRange, 'animalMetadata', animalMetadata, ...
        'ethovisionXlsxHash', ethovisionXlsxHash, 'stimFileHash', stimFileHash, 'stimuli', metadata, "ALIGNMENT_SCRIPT_VERSION", SCRIPT_VERSION);
    save(alignedFile, '-struct', 's');
    stimuli = metadata; % for output
end

% Helper functions (same as before)
function mustBePositiveIntOrEmpty(value)
    if isempty(value)
        return;
    end
    mustBePositive(value);
    mustBeInteger(value);
end

function mustBeNumericLogicalOrEmpty(value)
    if isempty(value)
        return;
    end
    mustBeNumericOrLogical(value);
end


function [zoneName, option] = parseInZoneText(text)
    % Parse text in format: "In zone(<ZoneName> / <Option>)"
    pattern = 'In zone\(([^'']+)\s*/\s*(.+)\)';
    tokens = regexp(text, pattern, 'tokens', 'once');
    
    if ~isempty(tokens)
        zoneName = strtrim(string(tokens{1}));
        option = strtrim(string(tokens{2}));
    else
        zoneName = "";
        option = "";
        warning('Text does not match expected format: %s', text);
    end
end

function bool = matchedZoneName(input, matchedTo, method)
    switch method
        case "exact"
            bool = strcmp(input, matchedTo);
        case "startsWith"
            bool = startsWith(input, matchedTo);
        case "endsWith"
            bool = endsWith(input, matchedTo);
        case "contains"
            bool = contains(input, matchedTo);
        otherwise
            error('Unknown zone match method: %s', method);
    end
end