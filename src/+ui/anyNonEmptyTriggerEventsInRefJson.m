function [bool, nonemptyEventsVideoFilePaths] = anyNonEmptyTriggerEventsInRefJson(videoFilePaths, kvargs)
    %ANYNONEMPTYTRIGGEREVENTSINREFJSON Check if any .ref.json files corresponding to the provided video file paths contain non-empty trigger events.
    arguments
        videoFilePaths {mustBeNonempty, mustBeFile}
        kvargs.RefSuffix {mustBeTextScalar} = '.ref.json' % suffix to append after the video file base name to find the reference JSON file
        kvargs.ScanAllNonEmpty (1,1) logical = false % if true, will scan all .ref.json files and return all video file paths that have non-empty trigger events, instead of returning after finding the first one
    end

    videoFilePaths = cellstr(videoFilePaths); % Ensure it's a cell array of strings for consistent processing
    kvargs.RefSuffix = char(kvargs.RefSuffix);

    bool = false;
    nonemptyEventsVideoFilePaths = cell(0,1); % Initialize as empty cell array to hold video file paths with non-empty trigger events
    didCanonicalizeAll = false;

    for i = 1:numel(videoFilePaths)
        videoFilePath = videoFilePaths{i};
        [videoDir, videoBaseName, ~] = fileparts(videoFilePath);
        referenceFilePath = fullfile(videoDir, strcat(videoBaseName, kvargs.RefSuffix));

        if isfile(referenceFilePath)
            refData = jsondecode(fileread(referenceFilePath));

            [triggerEventsCanonical, isCanonical, isUsable] = canonicalizeTriggerEvents(refData);
            if isUsable && ~isCanonical
                refData.trigger_events = triggerEventsCanonical;
                writeRefJson(referenceFilePath, refData);

                if ~didCanonicalizeAll
                    % It's likely that all files in a folder are requested at the same time,
                    % and if one is in the old form (flatten [1x2] event instead of nested), the rest are as well.
                    canonicalizeAllRefJson(videoFilePaths, kvargs.RefSuffix);
                    didCanonicalizeAll = true;
                end
            end

            if hasNonEmptyTriggerEvents(refData)
                bool = true;
                nonemptyEventsVideoFilePaths{end+1} = videoFilePath; %#ok<AGROW> % Append to the list of video file paths with non-empty trigger events
                if ~kvargs.ScanAllNonEmpty
                    return; % Exit early since we found a non-empty trigger_events
                end
            end
        end
    end
end

function tf = hasNonEmptyTriggerEvents(refData)
    tf = false;
    if ~isstruct(refData) || ~isfield(refData, 'trigger_events')
        return;
    end

    triggerEvents = refData.trigger_events;
    if isnumeric(triggerEvents) || iscell(triggerEvents) || isstring(triggerEvents) || ischar(triggerEvents)
        tf = ~isempty(triggerEvents);
        return;
    end

    if isstruct(triggerEvents)
        tf = ~isempty(fieldnames(triggerEvents));
        return;
    end

    tf = ~isempty(triggerEvents);
end

function [pairsCell, isCanonical, isUsable] = canonicalizeTriggerEvents(refData)
    pairsCell = cell(1, 0);
    isCanonical = true;
    isUsable = false;

    if ~isstruct(refData) || ~isfield(refData, 'trigger_events')
        return;
    end

    triggerEvents = refData.trigger_events;
    if isempty(triggerEvents)
        return;
    end

    if isnumeric(triggerEvents)
        vals = double(triggerEvents);
        % Handle some cases where MATLAB auto flatten single 1x2 event
        if isvector(vals) && numel(vals) == 2 && all(isfinite(vals))
            pairsCell = {reshape(vals, 1, 2)};
            isCanonical = false;
            isUsable = true;
            return;
        end
        if ismatrix(vals) && size(vals, 2) == 2 && all(isfinite(vals), 'all')
            nEvents = size(vals, 1);
            pairsCell = cell(1, nEvents);
            for ii = 1:nEvents
                pairsCell{ii} = vals(ii, :);
            end
            isCanonical = nEvents ~= 1;
            isUsable = true;
            return;
        end
        return;
    end

    if iscell(triggerEvents)
        nEvents = numel(triggerEvents);
        tempPairs = cell(1, nEvents);
        for ii = 1:nEvents
            row = triggerEvents{ii};
            if ~(isnumeric(row) && numel(row) == 2 && all(isfinite(row)))
                return;
            end
            tempPairs{ii} = double(reshape(row, 1, 2));
        end
        pairsCell = tempPairs;
        isCanonical = true;
        isUsable = true;
    end
end

function writeRefJson(referenceFilePath, refData)
    jsonText = jsonencode(refData);
    fileID = fopen(referenceFilePath, 'w');
    if fileID == -1
        warning('anyNonEmptyTriggerEventsInRefJson:RefJsonWriteOpenFailed', ...
            'Could not open reference JSON for writing: %s', referenceFilePath);
        return;
    end

    cleaner = onCleanup(@() fclose(fileID)); %#ok<NASGU>
    fwrite(fileID, jsonText, 'char');
end

function canonicalizeAllRefJson(videoFilePaths, refSuffix)
    for i = 1:numel(videoFilePaths)
        videoFilePath = videoFilePaths{i};
        [videoDir, videoBaseName, ~] = fileparts(videoFilePath);
        referenceFilePath = fullfile(videoDir, strcat(videoBaseName, refSuffix));

        if ~isfile(referenceFilePath)
            continue;
        end

        try
            refData = jsondecode(fileread(referenceFilePath));
        catch
            continue;
        end

        [triggerEventsCanonical, isCanonical, isUsable] = canonicalizeTriggerEvents(refData);
        if isUsable && ~isCanonical
            refData.trigger_events = triggerEventsCanonical;
            writeRefJson(referenceFilePath, refData);
        end
    end
end