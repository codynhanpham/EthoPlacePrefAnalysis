function [helperRoot, found] = bootstrapuvhelpernamespace(thisdir, verbose)
    persistent cachedHelperRoot cachedFound
    if ~isempty(cachedHelperRoot) && cachedFound && isfile(fullfile(cachedHelperRoot, '+uv', 'install.m'))
        addpath(cachedHelperRoot, '-begin');
        rehash path;
        if isempty(which('uv.install'))
            cachedHelperRoot = '';
            cachedFound = false;
        else
            helperRoot = cachedHelperRoot;
            found = cachedFound;
            return;
        end
    end

    found = false;
    helperRoot = '';

    installFile = which('uv.install');
    if ~isempty(installFile) && isfile(installFile)
        helperRoot = fileparts(fileparts(installFile));
        addpath(helperRoot, '-begin');
        rehash path;
        found = true;
        cachedHelperRoot = helperRoot;
        cachedFound = found;
        return;
    end

    candidateRoots = {
        thisdir
        fullfile(thisdir, '..')
        fullfile(thisdir, '..', '..', '..')
        fullfile(thisdir, '..', '..',  'lib')
        fullfile(thisdir, '..', '..', '..', 'lib')
        fullfile(thisdir, '..', '..', '..', '..', 'lib')
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
                addpath(packageRoot, '-begin');
                rehash path;
                if isempty(which('uv.install'))
                    continue;
                end
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
