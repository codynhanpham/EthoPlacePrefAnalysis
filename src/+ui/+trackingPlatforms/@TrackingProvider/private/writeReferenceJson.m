function writeReferenceJson(referenceFilePath, refData)
    jsonText = jsonencode(refData);
    fileID = fopen(referenceFilePath, 'w');
    if fileID == -1
        error('ui:trackingPlatforms:TrackingProvider:RefJsonWriteOpenFailed', ...
            'Could not open reference JSON for writing: %s', referenceFilePath);
    end

    cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
    fwrite(fileID, jsonText, 'char');
end