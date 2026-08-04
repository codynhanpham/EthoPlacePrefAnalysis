function info = parseAlignedCacheFileName(fileName, kvargs)
    %PARSEALIGNEDCACHEFILENAME Parse provider-labeled and legacy aligned cache names.
    arguments
        fileName {mustBeTextScalar}
        kvargs.ExpectedDataBaseName {mustBeTextScalar} = ""
        kvargs.ExpectedTrackingPlatform {mustBeTextScalar} = ""
    end

    info = struct( ...
        'isAlignedCache', false, ...
        'isLegacy', false, ...
        'isProviderLabeled', false, ...
        'dataBaseName', "", ...
        'trackingPlatform', "", ...
        'compositeHash', "", ...
        'fileName', string(fileName));

    [~, baseName, extension] = fileparts(char(fileName));
    if ~strcmpi(extension, '.mat')
        return;
    end

    baseName = string(baseName);
    expectedBaseName = string(kvargs.ExpectedDataBaseName);
    expectedTrackingPlatform = string(kvargs.ExpectedTrackingPlatform);
    if strlength(expectedBaseName) > 0
        expectedPrefix = expectedBaseName + " - ";
        if startsWith(baseName, expectedPrefix)
            suffix = extractAfter(baseName, strlength(expectedPrefix));
            suffixParts = split(suffix, '-');
            compositeHash = strtrim(suffixParts(end));
            if ~isCompositeHash(compositeHash)
                return;
            end

            info.dataBaseName = expectedBaseName;
            info.compositeHash = compositeHash;
            if isscalar(suffixParts)
                info.isLegacy = true;
                info.isAlignedCache = true;
            else
                trackingPlatform = strtrim(strjoin(suffixParts(1:end-1), '-'));
                if strlength(trackingPlatform) == 0
                    return;
                end
                if strlength(expectedTrackingPlatform) > 0 && ...
                        ~strcmpi(trackingPlatform, expectedTrackingPlatform)
                    return;
                end
                info.trackingPlatform = trackingPlatform;
                info.isProviderLabeled = true;
                info.isAlignedCache = true;
            end
            return;
        end
    end

    parts = split(baseName, '-');
    if numel(parts) < 2
        return;
    end

    compositeHash = strtrim(parts(end));
    if ~isCompositeHash(compositeHash)
        return;
    end

    legacyBaseName = removeDelimiterPadding(strjoin(parts(1:end-1), '-'));
    if strlength(legacyBaseName) == 0
        return;
    end

    if numel(parts) >= 3
        trackingPlatform = strtrim(parts(end-1));
        providerBaseName = removeDelimiterPadding(strjoin(parts(1:end-2), '-'));
        if strlength(trackingPlatform) > 0 && strlength(providerBaseName) > 0
            info.isAlignedCache = true;
            info.isProviderLabeled = true;
            info.dataBaseName = providerBaseName;
            info.trackingPlatform = trackingPlatform;
            info.compositeHash = compositeHash;
            return;
        end
    end

    info.isAlignedCache = true;
    info.isLegacy = true;
    info.dataBaseName = legacyBaseName;
    info.compositeHash = compositeHash;
end

function baseName = removeDelimiterPadding(baseName)
    baseName = string(baseName);
    if endsWith(baseName, " ")
        baseName = extractBefore(baseName, strlength(baseName));
    end
end

function tf = isCompositeHash(value)
    tf = ~isempty(regexp(char(value), '^[0-9A-Fa-f]{64}$', 'once'));
end
