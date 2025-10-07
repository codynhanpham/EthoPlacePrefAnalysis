function mediaPath = mediaPathFromXlsx(ethovisionXlsx, kvargs)
    %%MEDIAPATHFROMXLSX Get the corresponding media path for this EthoVision XLSX file
    %   Given the path to an EthoVision exported XLSX file, return the path to its corresponding (raw) media file.
    %
    %   Inputs:
    %       ethovisionXlsx - Path to the EthoVision exported XLSX file
    %
    %   Name-Value Pair Arguments:
    %       'Header' - (optional) If the ethovisionXlsx file was loaded elsewhere, provide the header output here to skip re-loading the file. Otherwise, when this is empty, the function will load the file to get the header.
    %       'ExpectedNumVariables' - (optional) The number of data columns in the table to expect when loading the EthoVision XLSX file. Default max is 50, with empty columns removed.
    %
    %   Outputs:
    %       mediaPath - The path to the corresponding media file, or empty if not found. Note that this function does not check if the media file actually exists.
    arguments
        ethovisionXlsx {mustBeFile}
        kvargs.Header = configureDictionary("string", "string");
        kvargs.ExpectedNumVariables {mustBeNumeric} = 50
    end

    if isempty(kvargs.Header) || isempty(keys(kvargs.Header))
        [headers, ~, ~] = io.ethovision.loadEthovisionXlsx(ethovisionXlsx, ExpectedNumVariables=kvargs.ExpectedNumVariables);
    else
        headers = kvargs.Header;
    end

    requiredKeys = ["Experiment", "Video file"];
    if ~all(ismember(requiredKeys, keys(headers)))
        error('The provided EthoVision XLSX file does not contain the required headers: %s', strjoin(requiredKeys, ', '));
    end

    experimentName = headers("Experiment");
    videoFilePath = headers("Video file");

    % Find the last occurrence of the experiment name in the path
    % Check if the path contains ":\" to use the correct file separator
    if contains(ethovisionXlsx, ':\')
        sep = '\';
    else
        sep = '/';
    end
    pathParts = strsplit(ethovisionXlsx, sep);
    expIdx = find(strcmp(pathParts, experimentName), 1, 'last');
    % Keep the path up to and including the experiment name
    if isempty(expIdx)
        basePath = fileparts(ethovisionXlsx);
    else
        basePath = fullfile(pathParts{1:expIdx});
    end
    % Get everything after the experiment name in the video file path
    videoSubPath = strsplit(videoFilePath, [char(experimentName), sep]);
    
    if numel(videoSubPath) < 2
        % If experiment name not found, return the original video file path
        mediaPath = videoFilePath;
        return;
    else
        relativeVideoPath = fullfile(videoSubPath{2:end});
    end
    mediaPath = fullfile(basePath, relativeVideoPath);
end