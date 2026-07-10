function parts = appendTextListOption(flag, value)
    if isempty(value)
        parts = string.empty(1, 0);
        return;
    end

    texts = normalizeTextList(value, "text");
    parts = [string(flag), texts];
end