function tf = localNameMatchesReference(localName, referenceName, hasOverride)
    localName = string(strtrim(localName));
    referenceName = string(strtrim(referenceName));

    if strlength(localName) == 0 || strlength(referenceName) == 0
        tf = false;
        return;
    end

    if strcmpi(localName, referenceName)
        tf = true;
        return;
    end

    if hasOverride
        tf = contains(localName, referenceName, 'IgnoreCase', true) || ...
            contains(referenceName, localName, 'IgnoreCase', true);
        return;
    end

    tf = false;
end
