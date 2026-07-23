function [uvpath, sleapdir] = install(kvargs)
    %%INSTALL Check and Install SLEAP and its dependencies using uv into local isolated environment.
    %
    % This function is no-op if SLEAP is already installed and working. If not, it will install uv and SLEAP into a local directory.
    % The installation script following these steps:
    %   1. Ensure the MATLAB's +uv namespace is available for uv-related operations. Will error, asking to load ../../lib/uv if not found.
    %   2. Create a virtual environment with uv + Python version
    %   3. uv pip install --torch-backend auto "sleap[nn]" "sleap-io" "sleap-nn"
    %   4. Verify the installation by running "uv run sleap doctor"

    arguments
        kvargs.Verbose (1,1) logical = false
    end

    persistent UVPATH SLEAPDIR INSTALLED

    currentpwd = pwd();
    cleanup = onCleanup(@() cd(currentpwd)); % Ensure we return to the original directory when this function is out of scope

    PYTHON_VERSION = '3.13';
    CACHE_VERSION = 1;

    thisdir = fileparts(mfilename('fullpath'));
    sleapproj = 'sleap-tools';
    thisprivatedir = fullfile(thisdir, 'private');
    sleapdir = fullfile(thisprivatedir, sleapproj);
    cacheFile = fullfile(sleapdir, '.sleap_install_cache.mat');

    [uvpath, helperResolved] = ensureuvhelperavailable(thisdir, kvargs.Verbose);

    installed = false;

    % Fast path: in-memory + on-disk cache can skip doctor syscall.
    if INSTALLED & strcmp(UVPATH, uvpath) & strcmp(SLEAPDIR, sleapdir)
        if isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION))
            installed = true;
        end
    elseif isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION))
        installed = true;
    end

    if installed
        INSTALLED = true;
        UVPATH = uvpath;
        SLEAPDIR = sleapdir;
        if kvargs.Verbose
            fprintf('Using cached SLEAP installation status (doctor check skipped).\n');
        end
        return;
    end

    if kvargs.Verbose && helperResolved
        fprintf('Using uv helper backend from a session path bootstrap.\n');
    end

    if kvargs.Verbose
        fprintf('Using uv helper backend at: %s\n', uvpath);
    end
    
    if ~isfolder(sleapdir) || ~isfolder(fullfile(sleapdir, '.venv'))
        fprintf('Creating SLEAP project and virtual environment with Python %s in %s ...\n', PYTHON_VERSION, fullfile(sleapdir, '.venv'));
        cd(thisprivatedir);
        
        cmd = sprintf('init %s --python %s', sleapproj, PYTHON_VERSION);
        [status, cmdOut] = uv.cmd(cmd, UpdateCallbackFcn=@displayuvoutput);
        if status ~= 0
            error('Failed to create SLEAP project. Command output: %s', cmdOut);
        end

        cd(sleapdir);
        [status, cmdOut] = uv.cmd('venv', UpdateCallbackFcn=@displayuvoutput);
        if status ~= 0
            error('Failed to create virtual environment in SLEAP project. Command output: %s', cmdOut);
        end

        fprintf('Installing SLEAP packages into virtual environment ...\n');
        cmd = 'pip install --torch-backend auto "sleap[nn]" "sleap-io" "sleap-nn"';
        fprintf('Running command: \n\tuv %s\n', cmd);
        [status, cmdOut] = uv.cmd(cmd, UpdateCallbackFcn=@displayuvoutput);
        if status ~= 0
            error('Failed to install SLEAP packages. Command output: %s', cmdOut);
        end
        cmd = sprintf('lock');
        [status, cmdOut] = uv.cmd(cmd, UpdateCallbackFcn=@displayuvoutput);
        if status ~= 0
            error('Failed to add SLEAP packages to the project. Command output: %s', cmdOut);
        end
    else
        installed = isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION));
        if ~installed
            installed = sleapdoctor(sleapdir, 'Verbose', kvargs.Verbose);
            if installed
                writeinstallcache(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION));
            else
                clearinstallcache(cacheFile);
            end
        elseif kvargs.Verbose
            fprintf('Using cached SLEAP installation status (doctor check skipped).\n');
        end

        if installed
            INSTALLED = true;
            UVPATH = uvpath;
            SLEAPDIR = sleapdir;
            if kvargs.Verbose
                fprintf('SLEAP project already exists and is working at: %s\n', sleapdir);
            end
            return;
        end
        errstr = sprintf('SLEAP project already exists at %s but failed doctor check. This SLEAP installation is most likely not managed by uv and/or possibly corrupted.\n', sleapdir);
        errstr = [errstr sprintf('To avoid overwriting your existing SLEAP installation, the installer will not attempt to fix it. Please investigate the issue with your existing SLEAP installation or remove/move the existing SLEAP directory and run this installer again.\n')];
        error('%s', errstr);
    end

    fprintf('\nSLEAP project created and packages installed successfully at: %s\n', sleapdir);
    fprintf('\n\nRunning SLEAP doctor post-installation check to verify installation ...\n\n');
    installed = sleapdoctor(sleapdir, 'Verbose', true);
    if installed
        writeinstallcache(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION));
        INSTALLED = true;
        UVPATH = uvpath;
        SLEAPDIR = sleapdir;
        fprintf('uv + SLEAP installed and verified successfully at:\n\t- %s\n\t- %s\n', uvpath, sleapdir);
    else
        clearinstallcache(cacheFile);
        fprintf('uv + SLEAP installation completed but failed doctor check. Please investigate the issue with the installation manually by running "uv run sleap doctor" in the SLEAP directory: %s\n', sleapdir);
    end
end
function fp = buildinstallfingerprint(sleapdir, uvpath, pythonVersion, cacheVersion)
    fp = struct();
    fp.CacheVersion = cacheVersion;
    fp.SleapDir = sleapdir;
    fp.UvPath = uvpath;
    fp.PythonVersion = pythonVersion;

    watchFiles = {
        fullfile(sleapdir, 'pyproject.toml')
        fullfile(sleapdir, 'uv.lock')
        fullfile(sleapdir, '.python-version')
        fullfile(sleapdir, '.venv', 'pyvenv.cfg')
    };

    fileState = repmat(struct('Path', '', 'Exists', false, 'Bytes', 0, 'Datenum', 0), numel(watchFiles), 1);
    for i = 1:numel(watchFiles)
        d = dir(watchFiles{i});
        fileState(i).Path = watchFiles{i};
        fileState(i).Exists = ~isempty(d);
        if ~isempty(d)
            fileState(i).Bytes = d.bytes;
            fileState(i).Datenum = d.datenum;
        end
    end
    fp.FileState = fileState;
end


function ok = isinstallcachevalid(cacheFile, fingerprint)
    ok = false;
    if ~isfile(cacheFile)
        return;
    end

    try
        data = load(cacheFile, 'cache');
    catch
        return;
    end

    if ~isfield(data, 'cache')
        return;
    end
    if ~isfield(data.cache, 'Fingerprint')
        return;
    end

    ok = isequaln(data.cache.Fingerprint, fingerprint);
end


function writeinstallcache(cacheFile, fingerprint)
    cache = struct();
    cache.Timestamp = datetime('now');
    cache.Fingerprint = fingerprint;
    save(cacheFile, 'cache');
end


function clearinstallcache(cacheFile)
    if isfile(cacheFile)
        delete(cacheFile);
    end
end


function [uvpath, helperResolved] = ensureuvhelperavailable(thisdir, verbose)
    helperResolved = false;
    try
        [uvpath, ~] = uv.install();
        return;
    catch ME
        if ~isuvnamespacemissingerror(ME)
            rethrow(ME);
        end
    end

    [helperRoot, found] = bootstrapuvhelpernamespace(thisdir, verbose);
    if ~found
        error('%s', buildmissinguvhelpererror(thisdir));
    end
    helperResolved = true;
    if verbose
        fprintf('Added uv helper root to MATLAB path for this session: %s\n', helperRoot);
    end

    try
        [uvpath, ~] = uv.install();
    catch ME
        if isuvnamespacemissingerror(ME)
            error('%s', buildmissinguvhelpererror(thisdir));
        end
        rethrow(ME);
    end
end


function [helperRoot, found] = bootstrapuvhelpernamespace(thisdir, verbose)
    found = false;
    helperRoot = '';

    candidateRoots = {
        thisdir
        fullfile(thisdir, '..')
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
                return;
            end
        end
    end
end


function errstr = buildmissinguvhelpererror(thisdir)
    errstr = sprintf([ ...
        '+uv helper namespace is not installed or not on the MATLAB path.\n' ...
        'Searched for helper roots relative to %s in ./, ../, and ../../lib.\n' ...
        'If +io/+sleap is installed as part of a package, make sure you also download/install the full package together with the +uv helper library.' ...
    ], thisdir);
end


function ok = isuvnamespacemissingerror(ME)
    if isempty(ME)
        ok = false;
        return;
    end
    ok = strcmp(ME.identifier, 'MATLAB:UndefinedFunction') || ...
        contains(ME.message, 'Undefined function or variable ''uv''') || ...
        contains(ME.message, 'Undefined function or variable ''uv.install''') || ...
        contains(ME.message, 'Undefined function ''uv.install''');
end


function ok = sleapdoctor(sleapdir, kvargs)
    arguments
        sleapdir (1,:) char
        kvargs.Verbose (1,1) logical = false
    end
    if ~isfolder(sleapdir) || ~isfolder(fullfile(sleapdir, '.venv'))
        ok = false;
        return;
    end

    currentdir = pwd;
    cleanup = onCleanup(@() cd(currentdir)); % Ensure we return to the original directory when this function is out of scope

    cd(sleapdir); % Change to the SLEAP directory to run sleap commands
    [status, cmdOut] = uv.cmd('run sleap doctor');
    notfounderrincl = {'Failed to spawn: `sleap`','Caused by: program not found'};

    if status ~= 0
        % if the cmdout include not found errors, SLEAP is simply not installed yet, simply return false without error
        if any(contains(cmdOut, notfounderrincl))
            ok = false;
            return;
        end
        error('SLEAP doctor check failed. Command output: %s', cmdOut);
    else
        if kvargs.Verbose
            fprintf('SLEAP doctor check passed successfully. STDOUT:\n%s\n\n', cmdOut);
        end
    end
    ok = (status == 0);
end


function displayuvoutput(line)
    if isempty(line)
        return;
    end
    fprintf('%s\n', line);
end
