function [refData, isLoaded, parseErrorMessage] = readReferenceJson(referenceFilePath)
    refData = struct();
    isLoaded = true;
    parseErrorMessage = "";

    if ~isfile(referenceFilePath)
        return;
    end

    try
        refData = jsondecode(fileread(referenceFilePath));
    catch ME
        refData = struct();
        isLoaded = false;
        parseErrorMessage = string(ME.message);
    end
end