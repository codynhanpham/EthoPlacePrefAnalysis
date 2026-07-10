function [bool, missing] = available()
    %%AVAILABLE Check if OWLv2-Detect is installed

    persistent cachedRepoDir cachedBool cachedMissing

    bool = false;
    missing = {'owlv2-detect'};

    thisdir = fileparts(mfilename('fullpath'));
    repoDir = fullfile(thisdir, '..', 'private', 'owlv2-detect');

    if ~isempty(cachedRepoDir) && isequal(cachedRepoDir, repoDir) && cachedBool && isfolder(repoDir)
        bool = cachedBool;
        missing = cachedMissing;
        return;
    end

    if ~isfolder(repoDir)
        return;
    end

    currentDir = pwd;
    restoreDir = onCleanup(@() cd(currentDir));

    try
        cd(repoDir);
        exitCode = uv.run('owlv2-detect -h');
        if exitCode == 0
            bool = true;
            missing = {};
            cachedRepoDir = repoDir;
            cachedBool = true;
            cachedMissing = {};
        end
    catch
        bool = false;
        missing = {'owlv2-detect'};
    end
end