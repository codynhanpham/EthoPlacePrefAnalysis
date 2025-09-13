function slowBatchTrialsAnalysis(parentDir, masterMetadataPath, stimPlaylistsDir)
    DATA_DIR = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/ETHOVISION";
    MASTERMETADATA = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/Place Preferences - Master Metadata.xlsx";
    STIM_PLAYLISTS = "D:/JOBS/WashU_Neuroscience/Behavior/WU-SMAC/PlacePreference/Stimuli/playlists";
    
    if nargin >= 1
        DATA_DIR = parentDir; 
    end
    if nargin >= 2
        MASTERMETADATA = masterMetadataPath; 
    end
    if nargin >= 3
        STIM_PLAYLISTS = stimPlaylistsDir; 
    end


    % Filter for EthoVision experiment directories
    dirInfo = dir(DATA_DIR);
    dirInfo = dirInfo([dirInfo.isdir]);
    ethovisionDirs = dirInfo(arrayfun(@(x) isEthovisionDir(fullfile(DATA_DIR, x.name)), dirInfo));

    % A table with variables: "Genotype group"
    resultsTable = table();
    resultsTable = addvars(resultsTable, strings(0), 'NewVariableNames', {'Genotype Group'});

    allEthovisionXlsx = {};

    f = waitbar(0,'Scanning for EthoVision .xlsx files...'); drawnow;

    % Process each EthoVision directory
    for i = 1:numel(ethovisionDirs)
        % List xlsx files in ethovisionDir
        xlsxFiles = dir(fullfile(ethovisionDirs(i).folder, ethovisionDirs(i).name, ['Export Files', filesep, '*.xlsx']));
        thisxlsxs = {xlsxFiles.name};
        thisxlsxs = fullfile(ethovisionDirs(i).folder, ethovisionDirs(i).name, 'Export Files', thisxlsxs);
        % Add to allEthovisionXlsx
        allEthovisionXlsx = [allEthovisionXlsx, thisxlsxs]; %#ok<AGROW>
    end

    allEthovisionXlsx = allEthovisionXlsx';

    waitbar(0, f, 'Processing EthoVision .xlsx files...'); drawnow;

    totalFiles = numel(allEthovisionXlsx);

    for i = 1:totalFiles
        result = singleTrialAnalysis(allEthovisionXlsx{i}, STIM_PLAYLISTS, MASTERMETADATA);
        animalMetadata = result.animalMetadata;
        matchedStimFrameFreq = result.matchedStimFrameFreq;
        matchedSpeakerPosFreq = result.matchedSpeakerPosFrameFreq;
        originalStimFrameFreq = result.originalStimFrameFreq;
        
        % GenotypeGroup = metadata "sex | strain | genotype"
        thisGenotypeGroup = sprintf('%s | %s | %s', animalMetadata.sex, animalMetadata.strain, animalMetadata.genotype);
        
        stims = keys(matchedStimFrameFreq);
        stimsCleaned = stims; % Initialize cleaned stims
        for j = 1:numel(stims)
            if startsWith(stims{j}, '[Ch1] ')
                stimsCleaned{j} = extractAfter(stims{j}, '[Ch1] ');
            elseif startsWith(stims{j}, '[Ch2] ')
                stimsCleaned{j} = extractAfter(stims{j}, '[Ch2] ');
            end
        end

        % If stim not already a column in resultsTable, add it with addvars
        for j = 1:numel(stimsCleaned)
            if ~ismember(stimsCleaned{j}, resultsTable.Properties.VariableNames)
                resultsTable = addvars(resultsTable, zeros(height(resultsTable), 1), 'NewVariableNames', stimsCleaned(j));
            end
        end
        % Same thing for matched and all speakers
        matchedSpeakerPositions = keys(matchedSpeakerPosFreq);
        matchedSpeakerPositionKeys = strcat("Matched ", string(matchedSpeakerPositions));
        for j = 1:numel(matchedSpeakerPositions)
            if ~ismember(matchedSpeakerPositionKeys{j}, resultsTable.Properties.VariableNames)
                resultsTable = addvars(resultsTable, zeros(height(resultsTable), 1), 'NewVariableNames', matchedSpeakerPositionKeys(j));
            end
        end
        allSpeakerPositions = keys(originalStimFrameFreq);
        allSpeakerPositionKeys = strcat("All ", string(allSpeakerPositions));
        for j = 1:numel(allSpeakerPositions)
            if ~ismember(allSpeakerPositionKeys{j}, resultsTable.Properties.VariableNames)
                resultsTable = addvars(resultsTable, zeros(height(resultsTable), 1), 'NewVariableNames', allSpeakerPositionKeys(j));
            end
        end

        % With this genotype group + matched stim data, fill missing with 0s
        % Make sure the tables have same number of vars
        newRow = table(string(thisGenotypeGroup), 'VariableNames', {'Genotype Group'});
        for j = 1:numel(stims)
            newRow.(stimsCleaned{j}) = matchedStimFrameFreq(stims{j});
        end
        for j = 1:numel(matchedSpeakerPositions)
            newRow.(matchedSpeakerPositionKeys{j}) = matchedSpeakerPosFreq(matchedSpeakerPositions{j});
        end
        for j = 1:numel(allSpeakerPositions)
            newRow.(allSpeakerPositionKeys{j}) = originalStimFrameFreq(allSpeakerPositions{j});
        end
        warning('off', 'MATLAB:table:RowsAddedExistingVars');
        resultsTable(end+1:end+height(newRow), newRow.Properties.VariableNames) = newRow;
        warning('on', 'MATLAB:table:RowsAddedExistingVars');

        waitbar(i/totalFiles, f, sprintf('Processing EthoVision .xlsx files... (%d of %d)', i, totalFiles)); drawnow;
    end

    resultsTable = convertvars(resultsTable, "Genotype Group", "categorical");
    assignin('base', 'resultsTable', resultsTable);

    close(f);

    plotBatchResults(resultsTable);
end


function bool = isEthovisionDir(dirPath)
    %ISETHOVISIONDIR Check if the directory is an EthoVision experiment directory
    %   Input path must be a folder, and the content must include:
    %       - An '*.evxt' file
    %       - An 'Export Files' folder
    arguments
        dirPath {mustBeFolder}
    end

    dirInfo = dir(dirPath);
    bool = any(endsWith({dirInfo.name}, '.evxt')) && isfolder(fullfile(dirPath, 'Export Files'));
end