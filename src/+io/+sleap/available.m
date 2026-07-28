function [bool, missing] = available()
    %%AVAILABLE Check whether the local SLEAP installation is available.
    %
    %   [bool, missing] = io.sleap.available() checks the local SLEAP
    %   project without installing or modifying it. The SLEAP doctor
    %   command is used as the authoritative health check.

    persistent cachedSleapDir cachedBool cachedMissing

    thisdir = fileparts(mfilename('fullpath'));
    sleapdir = fullfile(thisdir, 'private', 'sleap-tools');

    bool = false;
    missing = {'sleap-tools'};

    if ~isfolder(sleapdir) || ~isfolder(fullfile(sleapdir, '.venv'))
        return;
    end

    if ~isempty(cachedSleapDir) && isequal(cachedSleapDir, sleapdir) && ...
            cachedBool && isfolder(sleapdir) && isfolder(fullfile(sleapdir, '.venv'))
        bool = cachedBool;
        missing = cachedMissing;
        return;
    end

    if isempty(meta.package.fromName('uv'))
        [~, found] = bootstrapuvhelpernamespace(thisdir, false);
        if ~found
            error('%s', buildmissinguvhelpererror(thisdir));
        end
    end

    currentDir = pwd;
    cleanup = onCleanup(@() cd(currentDir));

    try
        bool = sleapdoctor(sleapdir);
        if bool
            missing = {};
            cachedSleapDir = sleapdir;
            cachedBool = true;
            cachedMissing = {};
        end
    catch
        bool = false;
        missing = {'sleap-tools'};
    end
end
