function key = protocolKey(fileName)
    %PROTOCOLKEY Canonical match key for a stimulus file name.
    %
    %   key = cohort.internal.protocolKey(fileName)
    %
    %   Normalizes a stimulus file name so that variations of the SAME
    %   protocol compare as equal (or near-equal), while different protocols
    %   stay far apart. Applied transformations, in order:
    %       1. lower-case, trim;
    %       2. strip the file extension;
    %       3. strip a leading date-like token (e.g. '20260204_', '2026-02-04-');
    %       4. strip trailing version/variation tokens ('_v3d', '-v2', ' v10a', ...)
    %          repeatedly;
    %       5. collapse whitespace.
    %   Example: '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3d.flac' and
    %   '20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac' both become
    %   'normal-whitenoise_27x_[5-10s]isi'.

    arguments
        fileName {mustBeTextScalar}
    end

    raw = lower(strtrim(char(string(fileName))));
    stem = raw;
    stripped = regexprep(stem, '\.[a-z0-9]{1,6}$', '');
    if ~isempty(stripped)
        stem = stripped;
    end

    s = stem;
    stripped = regexprep(s, '^\d{4}-?\d{2}-?\d{2}[_\-\s]*', '');
    if strlength(string(stripped)) > 0
        s = stripped;
    end

    while true
        stripped = regexprep(s, '[_\-\s]*v\d+[a-z]?$', '');
        if strcmp(stripped, s)
            break;
        end
        if strlength(string(stripped)) == 0
            break; % never reduce the key to nothing
        end
        s = stripped;
    end

    s = regexprep(s, '\s+', ' ');
    key = string(s);

    if strlength(key) == 0
        key = string(stem);
    end
end
