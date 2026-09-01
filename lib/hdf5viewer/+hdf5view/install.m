function [libLocation, installOk] = install(options)
    %%INSTALL Install the hdf5view viewer if not already installed
    %
    %   [libLocation, installOk] = hdf5view.install()
    %   [libLocation, installOk] = hdf5view.install(PythonVersion='3.14')
    %
    %   This creates a uv workspace at ./private/hdf5viewer relative to the
    %   module root, installs `hdf5view` and `pyqt6` into it, and validates
    %   the installation with a Python import probe.
    %
    %   INPUTS (Name-Value):
    %       PythonVersion (text scalar, default '3.14'): Python version used
    %           to initialize the uv workspace.
    %
    %   OUTPUTS:
    %       libLocation: Path to the local uv workspace.
    %       installOk: True when the workspace is available and the import
    %           probe succeeds after installation.

    arguments
        options.PythonVersion {mustBeTextScalar} = '3.14'
    end

    thisdir = fileparts(mfilename('fullpath'));
    thisdirparent = fileparts(thisdir);
    privateDir = fullfile(thisdirparent, 'private');
    repoDir = fullfile(privateDir, 'hdf5viewer');

    if ~isfolder(privateDir)
        mkdir(privateDir);
    end

    if ~isfolder(repoDir)
        mkdir(repoDir);
    end

    [installOk, ~] = hdf5view.available();
    if installOk
        libLocation = repoDir;
        return;
    end

    fprintf('hdf5view is not yet installed for this workspace.\nInstalling into %s ...\n', repoDir);

    currentDir = pwd;
    restoreDir = onCleanup(@() cd(currentDir));
    cd(repoDir);

    fprintf('Initializing uv workspace with Python %s...\n', options.PythonVersion);
    exitCode = uv.cmd(sprintf('init --bare --python %s', char(options.PythonVersion)));
    if exitCode ~= 0
        error('uv init failed while installing hdf5view (exit code %d).', exitCode);
    end

    fprintf('Installing hdf5view and pyqt6 with uv...\n');
    exitCode = uv.cmd('add hdf5view pyqt6');
    if exitCode ~= 0
        error('uv add failed while installing hdf5view (exit code %d).', exitCode);
    end

    fprintf('Validating hdf5view installation...\n');
    exitCode = uv.run('python -c "import hdf5view; print(hdf5view.__version__)"');
    if exitCode ~= 0
        error('hdf5view validation failed (exit code %d).', exitCode);
    end

    clear restoreDir;

    [installOk, missing] = hdf5view.available();
    if ~installOk
        error('hdf5view installation incomplete. Missing components: %s', strjoin(missing, ', '));
    end

    libLocation = repoDir;
end
