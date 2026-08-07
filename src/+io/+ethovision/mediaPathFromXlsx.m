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

    % Normalize separators before comparing paths. EthoVision stores the path
    % using the separator of the machine that performed the export, which
    % may differ from the machine currently loading the XLSX file.
    normalizedXlsxPath = replace(string(ethovisionXlsx), "\", "/");
    normalizedVideoPath = replace(string(videoFilePath), "\", "/");

    % Find the last occurrence of the experiment name in the XLSX path.
    % Matching path components avoids accidental matches inside filenames.
    xlsxParts = split(normalizedXlsxPath, "/");
    expIdx = find(xlsxParts == experimentName, 1, 'last');
    if isempty(expIdx)
        basePath = fileparts(ethovisionXlsx);
    else
        % Retain the original path root (including a leading slash on Linux)
        % while using the current platform's separator for the result.
        basePath = strjoin(xlsxParts(1:expIdx), filesep);
        if startsWith(normalizedXlsxPath, "/") && ~startsWith(basePath, filesep)
            basePath = [filesep, basePath];
        end
    end

    % Get everything after the experiment component in the video path. This
    % works even when the metadata path uses Windows separators on Linux.
    videoParts = split(normalizedVideoPath, "/");
    videoExpIdx = find(videoParts == experimentName, 1, 'last');
    if isempty(videoExpIdx) || videoExpIdx == numel(videoParts)
        % If the experiment name is not present, retain the original behavior.
        mediaPath = videoFilePath;
        return;
    end
    relativeVideoPath = strjoin(videoParts(videoExpIdx + 1:end), filesep);
    mediaPath = fullfile(basePath, relativeVideoPath);
end