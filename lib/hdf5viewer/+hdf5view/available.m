function [bool, missing] = available()
    %%AVAILABLE Check if the hdf5view viewer is installed
    %
    %   [bool, missing] = hdf5view.available()
    %
    %   OUTPUTS:
    %       bool: True when the private uv workspace exists and the
    %           hdf5view Python package can be imported in it.
    %       missing: Cell array of missing component names (empty when
    %           bool is true).

    persistent cachedRepoDir cachedBool cachedMissing

    thisdir = fileparts(mfilename('fullpath'));

    [~, found] = bootstrapuvhelpernamespace(thisdir, false);
    if ~found
        error('%s', buildmissinguvhelpererror(thisdir));
    end

    bool = false;
    missing = {'hdf5view'};

    repoDir = fullfile(thisdir, '..', 'private', 'hdf5viewer');

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
        exitCode = uv.run('python -c "import hdf5view; print(hdf5view.__version__)"');
        if exitCode == 0
            bool = true;
            missing = {};
            cachedRepoDir = repoDir;
            cachedBool = true;
            cachedMissing = {};
        end
    catch
        bool = false;
        missing = {'hdf5view'};
    end
end


function errstr = buildmissinguvhelpererror(thisdir)
    errstr = sprintf([ ...
        '+uv helper namespace is not installed or not on the MATLAB path.\n' ...
        'Searched for helper roots relative to %s in ./ ; ../ ; ../../ ; ../../lib/ ; ../../../lib/.\n' ...
        'If this module (hdf5viewer/+hdf5view) is installed as part of a larger package, make sure you also download/install the full package together with the +uv (typically in lib/uv) helper library.' ...
    ], thisdir);
end
