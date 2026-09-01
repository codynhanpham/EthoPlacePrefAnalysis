function [bool, missing] = available()
    %%AVAILABLE Check if OWLv2-Detect is installed

    persistent cachedRepoDir cachedBool cachedMissing

    thisdir = fileparts(mfilename('fullpath'));

    [~, found] = bootstrapuvhelpernamespace(thisdir, false);
    if ~found
        error('%s', buildmissinguvhelpererror(thisdir));
    end

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


function [helperRoot, found] = bootstrapuvhelpernamespace(thisdir, verbose)
    persistent cachedHelperRoot cachedFound
    if ~isempty(cachedHelperRoot) && cachedFound
        helperRoot = cachedHelperRoot;
        found = cachedFound;
        return;
    end

    found = false;
    helperRoot = '';

    if ~isempty(meta.package.fromName('uv'))
        helperRoot = fileparts(which('uv.install'));
        found = true;
        cachedHelperRoot = helperRoot;
        cachedFound = found;
        return;
    end

    candidateRoots = {
        thisdir
        fullfile(thisdir, '..')
        fullfile(thisdir, '..', '..')
        fullfile(thisdir, '..', '..', 'lib')
        fullfile(thisdir, '..', '..', '..', 'lib')
    };

    for i = 1:numel(candidateRoots)
        root = candidateRoots{i};
        candidatePackageRoots = {
            root
            fullfile(root, 'uv')
        };

        for j = 1:numel(candidatePackageRoots)
            packageRoot = candidatePackageRoots{j};
            installFile = fullfile(packageRoot, '+uv', 'install.m');
            if isfile(installFile)
                addpath(packageRoot);
                helperRoot = packageRoot;
                found = true;
                if verbose
                    fprintf('Found uv helper package at %s\n', installFile);
                end
                cachedHelperRoot = helperRoot;
                cachedFound = found;
                return;
            end
        end
    end
end


function errstr = buildmissinguvhelpererror(thisdir)
    errstr = sprintf([ ...
        '+uv helper namespace is not installed or not on the MATLAB path.\n' ...
        'Searched for helper roots relative to %s in ./ ; ../ ; ../../ ; ../../lib/ ; ../../../lib/.\n' ...
        'If this module (owlv2-detect/+owlv2) is installed as part of a larger package, make sure you also download/install the full package together with the +uv (typically in lib/uv) helper library.' ...
    ], thisdir);
end