function canon = canonicalSex(sex)
    %%CANONICALSEX Normalize a sex token to 'Male'/'Female' (case-insensitive)
    %   canon = io.metadata.canonicalSex(sex)
    %
    %   Inputs:
    %       sex - Text scalar, e.g. 'M', 'm', 'male', 'Male', 'F', 'female', ...
    %
    %   Outputs:
    %       canon - 'Male' for m/male variants, 'Female' for f/female variants
    %               (case-insensitive). Unrecognized tokens pass through trimmed.
    %
    %   See also: io.metadata.canonicalGenotype

    arguments
        sex {mustBeTextScalar}
    end

    s = lower(strtrim(char(sex)));
    switch s
        case {'m', 'male'}
            canon = 'Male';
        case {'f', 'female'}
            canon = 'Female';
        otherwise
            canon = strtrim(char(sex));
    end
end
