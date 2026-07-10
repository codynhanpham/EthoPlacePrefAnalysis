function command = buildOwlv2Command(subcommand, input, text, kvargs)
    if nargin < 4 || isempty(kvargs)
        kvargs = struct();
    end

    commandParts = ["owlv2-detect"];
    subcommand = string(subcommand);
    if subcommand ~= ""
        commandParts(end+1) = subcommand;
    end

    commandParts = [commandParts, buildRequiredArgs(input, text, subcommand)];
    commandParts = [commandParts, buildOptionalArgs(subcommand, kvargs)];

    command = strjoin(commandParts, " ");
end

function parts = buildRequiredArgs(input, text, subcommand)
    parts = string.empty(1, 0);
    inputs = normalizePathList(input, "input");
    parts = [parts, "-i", inputs];

    if subcommand == "black-marks" && isempty(text)
        text = {"black mark"};
    end

    if ~isempty(text)
        texts = normalizeTextList(text, "text");
        parts = [parts, "-t", texts];
    elseif subcommand ~= "black-marks"
        error('The general OWLv2 pipeline requires text queries.');
    end
end

function parts = buildOptionalArgs(subcommand, kvargs)
    parts = string.empty(1, 0);

    parts = [parts, appendCrop(getOpt(kvargs, "Crop", []))];
    parts = [parts, appendFilters(getOpt(kvargs, "Filter", []))];
    parts = [parts, appendScalarOption("-m", getOpt(kvargs, "Model", []), "model")];
    parts = [parts, appendScalarOption("-b", getOpt(kvargs, "BatchSize", []), "batch size")];
    parts = [parts, appendScalarOption("--detection-threshold", getOpt(kvargs, "DetectionThreshold", []), "detection threshold")];
    parts = [parts, appendScalarOption("--log-level", getOpt(kvargs, "LogLevel", []), "log level")];

    if subcommand == "black-marks"
        parts = [parts, appendDurationRange(getOpt(kvargs, "DurationRange", []))];
        parts = [parts, appendScalarOption("-s", getOpt(kvargs, "SampleFrameCount", []), "sample frame count")];
        parts = [parts, appendScalarOption("-n", getOpt(kvargs, "TopNMarks", []), "top n marks")];
    end
end

function value = getOpt(kvargs, fieldName, defaultValue)
    if isstruct(kvargs) && isfield(kvargs, fieldName)
        value = kvargs.(fieldName);
    else
        value = defaultValue;
    end
end