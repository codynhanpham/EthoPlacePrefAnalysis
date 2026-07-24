function [uvpath, sleapdir] = install(kvargs)
    %%INSTALL Check and Install SLEAP and its dependencies using uv into local isolated environment.
    %
    % This function is no-op if SLEAP is already installed and working. If not, it will install uv and SLEAP into a local directory.
    % The installation script following these steps:
    %   1. Ensure the MATLAB's +uv namespace is available for uv-related operations. Will error, asking to load ../../lib/uv if not found.
    %   2. Create a virtual environment with uv + Python version
    %   3. uv pip install --torch-backend auto "sleap[nn]" "sleap-io" "sleap-nn"
    %   4. Verify the installation by running "uv run sleap doctor"
    %
    % By default, this function does not install the extra ONNX & TensorRT Export dependencies. To install those, pass the kvarg 'NNExport' with one of the following values:
    %   - 'onnx-cpu' : Install ONNX export dependencies for CPU
    %   - 'onnx-gpu' : Install ONNX export dependencies for GPU
    %   - 'tensorrt' : Install TensorRT export dependencies for GPU
    %   - 'current'  : Use the current NNExport state (read from the install cache). If no prior cache exists, this falls back to 'none'.
    %   - []         : (default) Preserve whatever NNExport state is already installed (read from the install cache). On a first-time install with no prior cache, this falls back to 'none'.

    arguments
        kvargs.Verbose (1,1) logical = false
        kvargs.NNExport {mustBeTextScalarOrEmpty, mustBeMember(kvargs.NNExport, {'onnx-cpu', 'onnx-gpu', 'tensorrt', 'none', 'current'})} = 'current'
    end

    persistent UVPATH SLEAPDIR INSTALLED

    currentpwd = pwd();
    cleanup = onCleanup(@() cd(currentpwd)); % Ensure we return to the original directory when this function is out of scope

    PYTHON_VERSION = '3.13';
    CACHE_VERSION = 2;

    thisdir = fileparts(mfilename('fullpath'));
    sleapproj = 'sleap-tools';
    thisprivatedir = fullfile(thisdir, 'private');
    sleapdir = fullfile(thisprivatedir, sleapproj);
    pyscriptsSrcDir = fullfile(thisdir, 'pyscripts');
    cacheFile = fullfile(sleapdir, '.sleap_install_cache.mat');

    % When NNExport is not specified (empty), preserve whatever NNExport
    % state is already installed (read from the install cache). Only fall
    % back to 'none' on a first-time install with no prior cache.
    nnExport = resolveNnExport(cacheFile, kvargs.NNExport, kvargs.Verbose);

    [uvpath, helperResolved] = ensureuvhelperavailable(thisdir, kvargs.Verbose);

    installed = false;

    % Fast path: in-memory + on-disk cache can skip doctor syscall.
    if INSTALLED & strcmp(UVPATH, uvpath) & strcmp(SLEAPDIR, sleapdir)
        if isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION, nnExport, pyscriptsSrcDir))
            installed = true;
        end
    elseif isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION, nnExport, pyscriptsSrcDir))
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

        syncPyscripts(pyscriptsSrcDir, sleapdir, kvargs.Verbose);

        installSleapPackages(sleapdir, nnExport);
    else
        % One-way sync pyscripts into the existing SLEAP project before any
        % cache/doctor checks so source-side edits are reflected in sleapdir.
        syncPyscripts(pyscriptsSrcDir, sleapdir, kvargs.Verbose);

        cacheValid = isinstallcachevalid(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION, nnExport, pyscriptsSrcDir));
        installed = cacheValid;
        if ~installed
            installed = sleapdoctor(sleapdir, 'Verbose', kvargs.Verbose);
            if installed
                % A cache miss can mean that NNExport changed. Reinstall the
                % package so the selected extra dependencies are reflected in
                % the existing environment before refreshing the cache.
                installSleapPackages(sleapdir, nnExport);
                writeinstallcache(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION, nnExport, pyscriptsSrcDir));
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
        writeinstallcache(cacheFile, buildinstallfingerprint(sleapdir, uvpath, PYTHON_VERSION, CACHE_VERSION, nnExport, pyscriptsSrcDir));
        INSTALLED = true;
        UVPATH = uvpath;
        SLEAPDIR = sleapdir;
        fprintf('uv + SLEAP installed and verified successfully at:\n\t- %s\n\t- %s\n', uvpath, sleapdir);
    else
        clearinstallcache(cacheFile);
        fprintf('uv + SLEAP installation completed but failed doctor check. Please investigate the issue with the installation manually by running "uv run sleap doctor" in the SLEAP directory: %s\n', sleapdir);
    end


end

function mustBeTextScalarOrEmpty(x)
    if isempty(x)
        return;
    end
    mustBeTextScalar(x);
end

function fp = buildinstallfingerprint(sleapdir, uvpath, pythonVersion, cacheVersion, nnExport, pyscriptsSrcDir)
    fp = struct();
    fp.CacheVersion = cacheVersion;
    fp.SleapDir = sleapdir;
    fp.UvPath = uvpath;
    fp.PythonVersion = pythonVersion;
    fp.NNExport = char(nnExport);
    fp.PyscriptsSrcDir = char(pyscriptsSrcDir);

    watchFiles = {
        fullfile(sleapdir, 'pyproject.toml')
        fullfile(sleapdir, 'uv.lock')
        fullfile(sleapdir, '.python-version')
        fullfile(sleapdir, '.venv', 'pyvenv.cfg')
    };

    fileState = repmat(struct('Path', '', 'Exists', false, 'Bytes', 0, 'Datenum', 0, 'Hash', ''), numel(watchFiles), 1);
    for i = 1:numel(watchFiles)
        d = dir(watchFiles{i});
        fileState(i).Path = watchFiles{i};
        fileState(i).Exists = ~isempty(d);
        if ~isempty(d)
            fileState(i).Bytes = d.bytes;
            fileState(i).Datenum = d.datenum;
            fileState(i).Hash = filesha256(watchFiles{i});
        end
    end
    fp.FileState = fileState;

    % Include source pyscripts file hashes so cache invalidates when the
    % source files change (regardless of whether they have been synced yet).
    fp.PyscriptsState = pyscriptsfilestate(pyscriptsSrcDir);
end


function state = pyscriptsfilestate(pyscriptsSrcDir)
    state = repmat(struct('Path', '', 'Exists', false, 'Bytes', 0, 'Datenum', 0, 'Hash', ''), 0, 1);
    if isempty(pyscriptsSrcDir) || ~isfolder(pyscriptsSrcDir)
        return;
    end
    listing = dir(fullfile(pyscriptsSrcDir, '**', '*.*'));
    listing = listing([listing.isdir] == 0);
    for i = 1:numel(listing)
        srcPath = fullfile(listing(i).folder, listing(i).name);
        relPath = strrep(srcPath, [pyscriptsSrcDir filesep], '');
        s = struct();
        s.Path = relPath;
        s.Exists = true;
        s.Bytes = listing(i).bytes;
        s.Datenum = listing(i).datenum;
        s.Hash = filesha256(srcPath);
        state(end+1, 1) = s; %#ok<AGROW>
    end
end


function hash = filesha256(filePath)
    hash = '';
    try
        fid = fopen(filePath, 'r');
        if fid < 0
            return;
        end
        cleanup = onCleanup(@() fclose(fid));
        [content, ~] = fread(fid, '*uint8');
        md = java.security.MessageDigest.getInstance('SHA-256');
        md.update(typecast(content, 'int8'));
        digestBytes = md.digest();
        b = double(digestBytes);
        b(b < 0) = b(b < 0) + 256;
        hash = lower(reshape(dec2hex(b, 2).', 1, []));
    catch
        d = dir(filePath);
        if ~isempty(d)
            hash = sprintf('%d_%d', d.bytes, d.datenum);
        end
    end
end


function syncPyscripts(srcDir, sleapdir, verbose)
    % One-way sync of files from srcDir (pyscripts) into sleapdir.
    % Copies only files that are missing or whose SHA-256 differs from the
    % source. Files in sleapdir that are not in srcDir are left untouched
    % (one-way sync, no deletion).
    if isempty(srcDir) || ~isfolder(srcDir)
        if verbose
            fprintf('No pyscripts source directory found at %s; skipping sync.\n', srcDir);
        end
        return;
    end
    if ~isfolder(sleapdir)
        if verbose
            fprintf('SLEAP project directory does not exist yet at %s; skipping pyscripts sync.\n', sleapdir);
        end
        return;
    end

    listing = dir(fullfile(srcDir, '**', '*.*'));
    listing = listing([listing.isdir] == 0);
    copied = 0;
    skipped = 0;
    for i = 1:numel(listing)
        srcPath = fullfile(listing(i).folder, listing(i).name);
        relPath = strrep(srcPath, [srcDir filesep], '');
        dstPath = fullfile(sleapdir, relPath);

        needCopy = true;
        if isfile(dstPath)
            srcHash = filesha256(srcPath);
            dstHash = filesha256(dstPath);
            if ~isempty(srcHash) && ~isempty(dstHash) && strcmp(srcHash, dstHash)
                needCopy = false;
            end
        end

        if needCopy
            dstParent = fileparts(dstPath);
            if ~isfolder(dstParent)
                mkdir(dstParent);
            end
            copyfile(srcPath, dstPath);
            copied = copied + 1;
            if verbose
                fprintf('Synced pyscripts file: %s -> %s\n', relPath, dstPath);
            end
        else
            skipped = skipped + 1;
        end
    end

    if verbose
        fprintf('pyscripts sync complete: %d copied, %d up-to-date.\n', copied, skipped);
    end
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


function nnExport = resolveNnExport(cacheFile, requested, verbose)
    % Resolve the effective NNExport value.
    % If the caller passed a concrete value (onnx-cpu/onnx-gpu/tensorrt/none),
    % honor it. If the caller passed [] or 'current' (default), preserve
    % whatever NNExport is already recorded in the install cache so we don't
    % clobber an existing export-capable install with 'none'. Falls back to
    % 'none' only when there is no prior cache (first-time install).
    validValues = {'onnx-cpu', 'onnx-gpu', 'tensorrt', 'none', 'current'};

    if ~isempty(requested) && ~strcmp(requested, 'current')
        nnExport = char(requested);
        return;
    end

    cached = '';
    if isfile(cacheFile)
        try
            data = load(cacheFile, 'cache');
            if isfield(data, 'cache') && isfield(data.cache, 'Fingerprint') && isfield(data.cache.Fingerprint, 'NNExport')
                cached = char(data.cache.Fingerprint.NNExport);
            end
        catch
            cached = '';
        end
    end

    if ~isempty(cached) && ismember(cached, setdiff(validValues, {'current'}))
        nnExport = cached;
        if verbose
            fprintf('NNExport resolved to ''current''; preserving cached NNExport state: %s\n', nnExport);
        end
    else
        nnExport = 'none';
        if verbose
            fprintf('NNExport resolved to ''current'' and no prior cache found; defaulting to ''none''.\n');
        end
    end
end


function installSleapPackages(sleapdir, nnExport)
    currentdir = pwd();
    cleanup = onCleanup(@() cd(currentdir));
    cd(sleapdir);

    fprintf('Installing SLEAP packages into virtual environment ...\n');
    cmd = 'pip install --torch-backend auto "sleap[nn]" "sleap-io"';
    sleapnn = 'sleap-nn';
    if strcmp(nnExport, 'onnx-cpu')
        sleapnn = [sleapnn '[export]'];
    elseif strcmp(nnExport, 'onnx-gpu')
        sleapnn = [sleapnn '[export-gpu]'];
    elseif strcmp(nnExport, 'tensorrt')
        sleapnn = [sleapnn '[export-gpu,tensorrt]'];
    elseif strcmp(nnExport, 'none')
        % Do nothing, don't add any extra dependencies.
    end
    cmd = sprintf('%s "%s"', cmd, sleapnn);
    fprintf('Running command: \n\tuv %s\n', cmd);
    [status, cmdOut] = uv.cmd(cmd, UpdateCallbackFcn=@displayuvoutput);
    if status ~= 0
        error('Failed to install SLEAP packages. Command output: %s', cmdOut);
    end

    [status, cmdOut] = uv.cmd('lock', UpdateCallbackFcn=@displayuvoutput);
    if status ~= 0
        error('Failed to add SLEAP packages to the project. Command output: %s', cmdOut);
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
