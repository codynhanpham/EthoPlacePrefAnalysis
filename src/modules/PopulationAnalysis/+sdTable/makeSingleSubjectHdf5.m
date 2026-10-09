%%MAKESINGLESUBJECTHDF5
% StandardizedTable to single subject HDF5 file
% 
% Given a standardizedTable, a subject metadata struct, and some other optional constraints, output a size-optimized HDF5 file containing the data for that subject.
%
% When standardizedTables is an array of structs, tables containing the same subject metadata will be output together.
%
% [status, message] = makeSingleSubjectHdf5(standardizedTable, subjectMetadata, outputFilePath, varargin)
%
% Inputs:
%   standardizedTable: a standardizedTable struct array
%   subjectMetadata: a struct containing metadata for the subject to filter for
%   outputFilePath: a string specifying the path to the output HDF5 file
% 
% Name-Value Arguments:
%   'stimfileName': a stimfileName of a standardizedTable to filter for, empty to include all (default: '')
%       May be a cell array of strings when the standardizedTable was produced by
%       population.temp.joinStdTableByStim; in that case the elements are joined with
%       '++' to form the final stimfileName string used in the HDF5 layout.
%   'dataTable': one of {'centerpointData', 'bodyparts', 'both'}, specifying which data tables to include in the output HDF5 file (default: 'both')
%   'timeRange': a 1x2 numeric array specifying the time range to include, relative to onset at 0 seconds, in seconds (default: [-Inf, Inf])
%   'arenaBackgound': optional background image to include in the HDF5 file, as a 2D numeric array, to complement the data tables (default: [])
%
% 
% Outputs:
%   status: a logical indicating whether the operation was successful
%   message: a string containing a message about the operation
%
% See also: population.stats.populationPositionOverTime

function [status, message] = makeSingleSubjectHdf5(standardizedTable, subjectMetadata, outputFilePath, kvargs)
    arguments
        standardizedTable {sdTable.mustBeStandardizedTable}
        subjectMetadata struct {mustBeSubjectMetadata}
        outputFilePath {validator.mustBeValidFilepath}

        kvargs.stimfileName {mustBeText} = '' % note that while this is a scalar most of the time, it can be a cell array of strings if the user provides a joined standardizedTable
        kvargs.dataTable {mustBeMember(kvargs.dataTable, {'centerpointData', 'bodyparts', 'both'})} = 'both'
        kvargs.timeRange (1,2) double = [-Inf, Inf]
        kvargs.arenaBackgound = [] % optional 2D numeric background image
    end

    if kvargs.timeRange(1) > kvargs.timeRange(2)
        error('sdTable:makeSingleSubjectHdf5:InvalidTimeRange', ...
            'timeRange must be a 1x2 array [start, stop] with start <= stop. Got [%g, %g].', ...
            kvargs.timeRange(1), kvargs.timeRange(2));
    end
    if ~isempty(kvargs.arenaBackgound) && (~isnumeric(kvargs.arenaBackgound) || ndims(kvargs.arenaBackgound) ~= 2)
        error('sdTable:makeSingleSubjectHdf5:InvalidArenaBackground', ...
            'arenaBackgound must be an empty array or a 2D numeric array.');
    end

    % Easier handling with char
    outputFilePath = char(string(outputFilePath));

    % Select the stimfile tables to process. Empty filter includes all tables.
    % stimfileName may be a cell/string array when the standardizedTable was produced
    % by population.temp.joinStdTableByStim; such names are joined with '++' to form
    % the final stimfileName string used in the HDF5 layout.
    filterParts = normalizeStimfileNameParts(kvargs.stimfileName);
    filterParts = filterParts(~ismissing(filterParts) & filterParts ~= "");
    allStimfileNames = arrayfun(@(s) joinedStimfileName(s.stimfileName), standardizedTable, 'UniformOutput', false);
    allStimfileNames = string(allStimfileNames);
    if isempty(filterParts)
        selectedIndices = 1:numel(standardizedTable);
    else
        % Match against the joined form so a joined table (cell-array stimfileName)
        % is selected only by its full joined name, not by individual parts.
        filterJoined = strjoin(filterParts, '++');
        selectedIndices = find(allStimfileNames == filterJoined);
    end

    if isempty(selectedIndices)
        error('sdTable:makeSingleSubjectHdf5:NoMatchingStimfile', ...
            'No standardizedTable entries match the requested stimfileName filter: %s\nAvailable stimfiles: %s', ...
            joinedStimfileName(kvargs.stimfileName), ...
            strjoin(cellstr(allStimfileNames), ', '));
    end

    % Locate the subject in each selected table by exact metadata match.
    % subjectIndices(k) == 0 means the subject is absent from that table (skipped).
    subjectIndices = zeros(1, numel(selectedIndices));
    for k = 1:numel(selectedIndices)
        tableIndex = selectedIndices(k);
        subjectIndices(k) = findSubjectIndex(standardizedTable(tableIndex).animalMetadata, subjectMetadata);
    end

    if all(subjectIndices == 0)
        error('sdTable:makeSingleSubjectHdf5:SubjectNotFound', ...
            'Subject metadata not found in any of the selected standardizedTables.\nSearched stimfiles: %s\nSubject metadata: %s', ...
            strjoin(cellstr(allStimfileNames(selectedIndices)), ', '), ...
            utils.io.structprettyprint(subjectMetadata, 4, Inf));
    end

    % Write the HDF5 file atomically: write to a temp file, then move into place.
    [outputFolder, outputName, outputExt] = fileparts(outputFilePath);
    if isempty(outputExt)
        outputExt = '.hdf5';
    end
    if isempty(outputFolder)
        outputFolder = pwd;
    end
    finalPath = fullfile(outputFolder, [outputName, outputExt]);
    tempPath = [tempname(outputFolder), '.hdf5.tmp'];
    cleanupTemp = onCleanup(@() localDeleteIfExists(tempPath)); %#ok<NASGU>

    % Create the HDF5 file up front so attribute writes can open it in RDWR mode
    createFid = H5F.create(tempPath, 'H5F_ACC_TRUNC', 'H5P_DEFAULT', 'H5P_DEFAULT');
    H5F.close(createFid);

    % Root attributes
    h5writeatt(tempPath, '/', 'format_version', int32(2));
    h5writeatt(tempPath, '/', 'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

    % /obs: subject metadata as scalar datasets (anndata-style observation metadata)
    writeSubjectMetadata(tempPath, subjectMetadata);

    % /uns: unstructured metadata (fps, px2cm, arenaBackground)
    writeUnsMetadata(tempPath, standardizedTable, selectedIndices, kvargs);

    % One group per stimfile where the subject was found
    writtenStimfiles = strings(0, 1);
    for k = 1:numel(selectedIndices)
        if subjectIndices(k) == 0
            continue; % skip tables where the subject is absent
        end
        tableIndex = selectedIndices(k);
        subjectIndex = subjectIndices(k);
        stimfileName = joinedStimfileName(standardizedTable(tableIndex).stimfileName);

        groupName = ['/' sanitizeGroupName(stimfileName)];

        includeCenterpoint = any(strcmpi(kvargs.dataTable, {'centerpointData', 'both'}));
        includeBodyparts = any(strcmpi(kvargs.dataTable, {'bodyparts', 'both'}));

        if includeCenterpoint
            writeTableSlice(tempPath, groupName, standardizedTable(tableIndex).centerpointData, ...
                standardizedTable(tableIndex).animalMetadata, subjectIndex, kvargs.timeRange, 'centerpoint');
        end
        if includeBodyparts
            bodypartTable = standardizedTable(tableIndex).bodyparts;
            if ~isempty(bodypartTable) && width(bodypartTable) > 2
                writeTableSlice(tempPath, groupName, bodypartTable, ...
                    standardizedTable(tableIndex).animalMetadata, subjectIndex, kvargs.timeRange, 'bodyparts', ...
                    WriteSharedKeys=~includeCenterpoint);
            end
        end

        writtenStimfiles(end+1, 1) = string(stimfileName); %#ok<AGROW>
    end

    h5writeatt(tempPath, '/', 'stimfileNames', char(strjoin(writtenStimfiles, ';')));

    % Move temp file into final location
    movefile(tempPath, finalPath, 'f');
    clear cleanupTemp;

    status = true;
    message = sprintf('Wrote single-subject HDF5 file for stimfiles: %s', strjoin(writtenStimfiles, ', '));
end


function mustBeSubjectMetadata(subjectMetadata)
    % Validate that subjectMetadata is a struct with required fields
    if ~isstruct(subjectMetadata)
        error('subjectMetadata must be a struct.');
    end
    if isempty(subjectMetadata) || isempty(fieldnames(subjectMetadata))
        error('subjectMetadata cannot be empty.');
    end
    
    requiredFields = {'sex', 'genotype', 'strain', 'age', 'dob', 'cagecode', 'id', 'source'};
    
    missingFields = setdiff(requiredFields, fieldnames(subjectMetadata));
    if ~isempty(missingFields)
        error('subjectMetadata is missing required fields: %s', strjoin(missingFields, ', '));
    end
end

function subjectIndex = findSubjectIndex(animalMetadata, subjectMetadata)
    % Find the column index of the subject in the animalMetadata dictionary by exact
    % field-by-field comparison against all 8 required fields.
    % Returns 0 if not found. Dictionary key order matches the multi-column variable
    % column order (see sdTable.subsetByMetadata and sdTable.ind2metadata).
    subjectIndex = 0;
    keysList = keys(animalMetadata);
    for i = 1:numel(keysList)
        if metadataMatches(animalMetadata(keysList{i}), subjectMetadata)
            subjectIndex = i;
            return;
        end
    end
end

function tf = metadataMatches(candidate, target)
    % Exact equality on all required fields. char/string compared with strcmp,
    % numeric with isequal, datetime with isequal (isequal(NaT, NaT) is true).
    requiredFields = {'sex', 'genotype', 'strain', 'age', 'dob', 'cagecode', 'id', 'source'};
    tf = true;
    for f = 1:numel(requiredFields)
        candidateValue = candidate.(requiredFields{f});
        targetValue = target.(requiredFields{f});
        if ischar(candidateValue) || isstring(candidateValue) || ischar(targetValue) || isstring(targetValue)
            if ~strcmp(char(string(candidateValue)), char(string(targetValue)))
                tf = false;
                return;
            end
        elseif isdatetime(candidateValue) || isdatetime(targetValue)
            if ~(isdatetime(candidateValue) && isdatetime(targetValue)) || ~isequal(candidateValue, targetValue)
                tf = false;
                return;
            end
        else
            if ~isequal(candidateValue, targetValue)
                tf = false;
                return;
            end
        end
    end
end

function writeSubjectMetadata(filePath, subjectMetadata)
    % Write each metadata field as a scalar dataset under /obs
    requiredFields = {'sex', 'genotype', 'strain', 'age', 'dob', 'cagecode', 'id', 'source'};
    for f = 1:numel(requiredFields)
        fieldName = requiredFields{f};
        value = subjectMetadata.(fieldName);
        datasetPath = ['/obs/' fieldName];
        if ischar(value) || isstring(value)
            writeStringDataset(filePath, datasetPath, char(string(value)));
        elseif isdatetime(value)
            if isnat(value)
                writeStringDataset(filePath, datasetPath, '');
            else
                writeStringDataset(filePath, datasetPath, datestr(value, 'yyyy-mm-dd'));
            end
        else
            writeScalarDataset(filePath, datasetPath, double(value));
        end
    end
end

function writeUnsMetadata(filePath, standardizedTable, selectedIndices, kvargs)
    % Write fps and px2cm from the first selected table. These are expected to be
    % consistent across tables for the same subject (enforced upstream by
    % population.stats.populationPositionOverTime).
    fps = NaN;
    px2cm = NaN;
    if ~isempty(selectedIndices)
        fps = standardizedTable(selectedIndices(1)).fps;
        px2cm = standardizedTable(selectedIndices(1)).px2cm;
    end
    writeScalarDataset(filePath, '/uns/fps', fps);
    writeScalarDataset(filePath, '/uns/px2cm', px2cm);

    if ~isempty(kvargs.arenaBackgound)
        writeMatrixDataset(filePath, '/uns/arenaBackground', kvargs.arenaBackgound);
    end
end

function writeTableSlice(filePath, groupName, dataTable, animalMetadata, subjectIndex, timeRange, prefix, kvargs)
    % Extract the subject's column from each multi-column variable, apply the time
    % range row mask, and write time/stimulus/data matrix + column names datasets.
    % 'WriteSharedKeys' controls whether the shared 'time'/'stimulus' datasets are
    % written (they are identical for centerpoint and bodyparts slices of a group).
    arguments
        filePath {mustBeText}
        groupName {mustBeText}
        dataTable table
        animalMetadata (1,1) dictionary
        subjectIndex (1,1) double {mustBePositive}
        timeRange (1,2) double
        prefix {mustBeText}
        kvargs.WriteSharedKeys (1,1) logical = true
    end
    variableNames = dataTable.Properties.VariableNames;

    keyColumns = {'Trial time', 'Stimulus name'};
    dataColumns = setdiff(variableNames, keyColumns, 'stable');

    nRows = height(dataTable);
    nSubjects = numel(keys(animalMetadata));
    dataMatrix = zeros(nRows, numel(dataColumns));
    columnNames = strings(1, numel(dataColumns));
    for c = 1:numel(dataColumns)
        varData = dataTable{:, dataColumns{c}};
        if size(varData, 2) == nSubjects
            % Multi-column variable: take the subject's column
            dataMatrix(:, c) = varData(:, subjectIndex);
        else
            % Scalar column: shared across subjects
            dataMatrix(:, c) = varData(:);
        end
        columnNames(c) = string(dataColumns{c});
    end

    % Apply the time range row mask
    trialTime = dataTable{:, 'Trial time'};
    rowMask = trialTime >= timeRange(1) & trialTime <= timeRange(2);
    if ~any(rowMask)
        error('sdTable:makeSingleSubjectHdf5:NoDataInRange', ...
            'No rows fall within the requested time range [%g, %g] for group %s.', ...
            timeRange(1), timeRange(2), groupName);
    end
    dataMatrix = dataMatrix(rowMask, :);
    trialTime = trialTime(rowMask);
    stimulusNames = string(dataTable{:, 'Stimulus name'});
    stimulusNames = stimulusNames(rowMask);

    % Categorical encoding of stimulus names (anndata-style)
    [stimulusCodes, stimulusCategories] = encodeCategorical(stimulusNames);

    % Write datasets. 'time' and 'stimulus' are shared between the centerpoint and
    % bodyparts slices of the same group (identical time grid), so write them only
    % once per group.
    if kvargs.WriteSharedKeys
        writeMatrixDataset(filePath, [groupName '/time'], trialTime);
        writeIntDataset(filePath, [groupName '/stimulus'], stimulusCodes);
        writeStringArrayDataset(filePath, [groupName '/stimulus_categories'], stimulusCategories);
    end
    writeMatrixDataset(filePath, [groupName '/' prefix], dataMatrix);
    writeStringArrayDataset(filePath, [groupName '/' prefix '_columns'], columnNames);
end

function [codes, categories] = encodeCategorical(values)
    % Encode a string array as int32 codes into a category list (anndata-style)
    [uniqueCategories, ~, codes] = unique(values, 'stable');
    categories = string(uniqueCategories);
    codes = int32(codes);
end

function groupName = sanitizeGroupName(stimfileName)
    % HDF5 group names cannot contain '/' or NUL. Replace with '_' and trim.
    groupName = char(string(stimfileName));
    groupName(groupName == '/') = '_';
    groupName(strtrim(groupName) == "") = '_';
    groupName = strtrim(groupName);
end

function parts = normalizeStimfileNameParts(stimfileName)
    % Normalize a stimfileName (char, string scalar/array, or cellstr) to a 1xN
    % string array of individual stimfile names. A 2D char array is treated as a
    % cellstr-style list of names.
    if iscell(stimfileName)
        parts = string(stimfileName(:));
    elseif ischar(stimfileName) && size(stimfileName, 1) > 1
        parts = string(cellstr(stimfileName));
    else
        parts = string(stimfileName);
        parts = parts(:)';
    end
end

function joinedName = joinedStimfileName(stimfileName)
    % Join multi-element stimfileNames (e.g. produced by
    % population.temp.joinStdTableByStim) with '++' to form the final stimfileName
    % string used in the HDF5 layout (group names, attributes, and messages).
    parts = normalizeStimfileNameParts(stimfileName);
    if numel(parts) > 1
        joinedName = strjoin(parts, '++');
    else
        joinedName = char(parts);
    end
end

function localDeleteIfExists(path)
    if exist(path, 'file')
        delete(path);
    end
end

function writeScalarDataset(filePath, datasetPath, value)
    % Write a scalar double dataset with gzip compression
    h5create(filePath, datasetPath, [1 1], 'DataType', 'double', 'ChunkSize', [1 1], 'Deflate', 6);
    h5write(filePath, datasetPath, value);
end

function writeIntDataset(filePath, datasetPath, values)
    % MATLAB's high-level HDF5 API reverses axes on disk. Write a row vector here
    % so external readers see an N-by-1 column vector.
    n = numel(values);
    h5create(filePath, datasetPath, [1 n], 'DataType', 'int32', ...
        'ChunkSize', [1 min(n, 4096)], 'Deflate', 6);
    h5write(filePath, datasetPath, values(:).');
end

function writeStringDataset(filePath, datasetPath, value)
    % Write a single string as a 1x1 variable-length UTF-8 string dataset.
    % h5write requires a string array for string datasets.
    h5create(filePath, datasetPath, [1 1], 'DataType', 'string');
    h5write(filePath, datasetPath, string(value));
end

function writeStringArrayDataset(filePath, datasetPath, values)
    % MATLAB's high-level HDF5 API reverses axes on disk. Write a row vector here
    % so external readers see an N-by-1 string vector.
    values = string(values(:).');
    h5create(filePath, datasetPath, [1 numel(values)], 'DataType', 'string');
    h5write(filePath, datasetPath, values);
end

function writeMatrixDataset(filePath, datasetPath, matrix)
    % MATLAB's high-level HDF5 API reverses axes on disk. Transpose before writing
    % so external readers see rows as frames and columns as variables.
    matrix = matrix.';
    dims = size(matrix);
    chunk = [dims(1) min(dims(2), 4096)];
    h5create(filePath, datasetPath, dims, 'DataType', 'double', 'ChunkSize', chunk, 'Deflate', 6);
    h5write(filePath, datasetPath, matrix);
    h5writeatt(filePath, datasetPath, 'hdf5_axis_order', 'rows=frames, columns=variables');
end
