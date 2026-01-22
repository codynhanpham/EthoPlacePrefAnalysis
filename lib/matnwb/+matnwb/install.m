function [libLocation, hdf5pluginLocation] = install()
    %%INSTALL Install MatNWB and required extensions if not already installed
    %
    %   Then, make sure the core MatNWB library and all required extensions are
    %   available on the MATLAB path (for the current MATLAB session).
    %
    %   This function checks for the presence of MatNWB and its required
    %   extensions. If any components are missing, it installs them from their
    %   respective GitHub repositories.
    %
    %   Since it is no-op when MatNWB and all required extensions are already
    %   installed, it is recommended to call this function at the very start of
    %   your MATLAB scripts that use MatNWB to ensure all dependencies are met.
    %
    %   USAGE:
    %       [libLocation, hdf5pluginLocation] = matnwb.install()
    %
    %   OUTPUTS:
    %       libLocation: Path to the MatNWB installation directory (the core library).
    %       hdf5pluginLocation: Path to the HDF5 plugin installation directory.
    %           (this is the output of getenv('HDF5_PLUGIN_PATH') after initialization).
    
    thisdir = fileparts(mfilename('fullpath'));
    thisdirparent = fileparts(thisdir);
    corePath = fullfile(thisdirparent, 'matnwb');


    [isAvailable, missing] = matnwb.available();
    if isAvailable
        libLocation = corePath;
        ensurepath();
        matnwb.initHdf5Plugins(); % Ensure HDF5 plugins are installed and accessible
        hdf5pluginLocation = getenv('HDF5_PLUGIN_PATH');
        return;
    end


    % Install core matnwb if missing
    if ismember('matnwb', missing)
        fprintf('Library MatNWB is not yet installed for this workspace.\nInstalling from https://github.com/NeurodataWithoutBorders/matnwb.git ...\n');

        coreRepo = 'https://github.com/NeurodataWithoutBorders/matnwb';
        coreDest = fullfile(thisdirparent, 'matnwb');
        clonedOk = false;
        % Try with git first since it's more developer friendly
        try
            ensuregit();

            % Attempt to find the latest tag to clone specific version
            latestTag = getLatestTag(coreRepo);
            % Get first 7 characters if tag is a full commit hash
            if ~startsWith(latestTag, 'v') && strlength(latestTag) == 40
                latestTagShort = extractBetween(latestTag, 1, 7);
            else
                latestTagShort = latestTag;
            end
            
            if latestTag ~= ""
                fprintf('Detected latest release tag: %s\n', latestTagShort);
                gitclone(coreRepo, coreDest, 'Branch', latestTag, 'Depth', 1); 
            else
                fprintf('Could not detect tags, cloning default branch...\n');
                gitclone(coreRepo, coreDest, 'Depth', 1);
            end

            clonedOk = true;
        catch ME
            try
                ensuregit();
                nogit = false;
            catch
                nogit = true;
            end
            if nogit
                fprintf('Git is not available on this system. Falling back to downloading ZIP archive...\n');
            else
                warning('Git clone failed: %s\n\nFalling back to downloading ZIP archive...', getReport(ME));
            end
        end

        if ~clonedOk
            % Fallback to downloading ZIP archive
            branchToDownload = "";
            if exist('latestTag', 'var') && latestTag ~= ""
                branchToDownload = latestTag;
            end
            try
                gitHTTPDownload(coreRepo, coreDest, 'Branch', branchToDownload);
            catch ME
                error('Installation via HTTP archive failed: %s', getReport(ME));
            end
        end


        addpath(coreDest);
        fprintf('Generating core MatNWB classes...\n');
        generateCore(); % Initialize core matnwb after cloning

        % After installation, check if core is now available
        [isAvailable, missing] = matnwb.available();
        if ismember('matnwb', missing)
            % Double check if the cloned directory exists
            cloned = isfolder(coreDest);
            if ~cloned
                error('Core matnwb installation failed: directory not found after cloning.');
            end
            error('Failed to load core matnwb after installation. Please check the installation directory at %s', coreDest);
        end
    end
    if isAvailable
        libLocation = corePath;
        ensurepath();
        matnwb.initHdf5Plugins();
        hdf5pluginLocation = getenv('HDF5_PLUGIN_PATH');
        return;
    end

    % At this point, core matnwb should be installed
    % Ensure the core matnwb is on the MATLAB path
    ensurepath();

    % Install each missing extension
    fprintf('Installing missing NWB extensions: { ''%s'' }\n', strjoin(missing, ''', '''));
    for i = 1:length(missing)
        extName = missing{i};
        fprintf('[%d/%d] Adding NWB extension: "%s" ...\n', i, length(missing), extName);
        try
            nwbInstallExtension(extName);
        catch ME
            % If last err id is 'NWB:Namespace:CacheMissing', run generateCore and retry
            if strcmp(ME.identifier, 'NWB:Namespace:CacheMissing')
                fprintf('Namespace cache missing. Regenerating core matnwb and retrying installation of extension "%s"...\n', extName);
                generateCore();
                nwbInstallExtension(extName); % Retry installation
            else
                rethrow(ME);
            end
        end
    end

    [isAvailable, missing] = matnwb.available();
    if ~isAvailable
        error('MatNWB installation incomplete. Missing components: %s', strjoin(missing, ', '));
    end
    fprintf('MatNWB and all required extensions installed successfully. Checking for additional HDF5 plugins...\n\n');
    libLocation = corePath;
    ensurepath();
    ok = matnwb.initHdf5Plugins();
    if ok
        fprintf(' ✓ All HDF5 plugins are properly installed and accessible.\n');
    end
    hdf5pluginLocation = getenv('HDF5_PLUGIN_PATH');
end

function ensuregit()
    % Ensure that git is available on the system
    [status, ~] = system('git --version');
    if status ~= 0
        error('Git is not available on this system. Please install Git <a href="https://git-scm.com/downloads">https://git-scm.com/downloads</a> to proceed.');
    end
end

function gitclone(repoUrl, destPath, options)
    %%GITCLONE Clone a git repository to the specified destination path
    arguments
        repoUrl {mustBeTextScalar}
        destPath {mustBeTextScalar}
        options.Branch {mustBeTextScalar} = "" % Empty means default branch, or 'latest' for the latest release tag
        options.Depth (1,1) double = 0 % 0 means full clone
    end

    options.Branch = string(options.Branch);

    if isfolder(destPath)
        fprintf('Directory %s already exists. Skipping clone.\n', destPath);
        return;
    end

    ensuregit();

    [~, repoName, ~] = fileparts(repoUrl);

    % Build git options string
    gitOpts = "";
    if options.Branch ~= ""
        % If 'latest' is specified, find the latest tag
        if options.Branch == "latest"
            latestTag = getLatestTag(repoUrl);
            if latestTag ~= ""
                options.Branch = latestTag;
                fprintf('Cloning [%s] with latest release tag: %s\n', repoName, latestTag);
            else
                warning('Could not determine latest tag for [%s]. Cloning default branch instead.', repoName);
                options.Branch = "";
            end
        end
        gitOpts = gitOpts + " -b " + options.Branch;
    end
    if options.Depth > 0
        gitOpts = gitOpts + " --depth " + num2str(options.Depth);
    end

    cmd = sprintf('git clone%s %s "%s"', gitOpts, repoUrl, destPath);
    
    [status, cmdout] = system(cmd);
    if status ~= 0
        error('Failed to clone repository from %s. Error: %s', repoUrl, cmdout);
    else
        fprintf('Successfully cloned repository from %s to %s\n', repoUrl, destPath);
    end
end

function tag = getLatestTag(repoUrl)
    % GETLATESTTAG Retrieve the latest git tag from a remote repository
    
    % Sort by version refname to ensure we get the highest version last
    cmd = sprintf('git ls-remote --tags --sort="v:refname" %s', repoUrl);
    [status, cmdout] = system(cmd);
    
    if status ~= 0
        warning('Failed to retrieve tags from %s. Git output: %s', repoUrl, cmdout);
        tag = "";
        return;
    end
    
    % Split output into lines and remove empty ones
    lines = splitlines(strtrim(cmdout));
    lines(strcmp(lines, '')) = [];
    
    if isempty(lines)
        tag = "";
        return;
    end
    
    % Take the last line (highest version)
    lastLine = lines{end};
    
    % Extract the tag name. Format matches: HASH<tab>refs/tags/TAGNAME[^{}]
    % We want to capture 'TAGNAME' and ignore optional '^{}'
    tokens = regexp(lastLine, 'refs/tags/([^\^]+)', 'tokens');
    
    if ~isempty(tokens) && ~isempty(tokens{1})
        tag = string(tokens{1}{1});
    else
        % Fallback: manual split if regex fails
        parts = strsplit(lastLine, '/');
        tag = string(parts{end});
        tag = strrep(tag, '^{}', '');
    end
end

function ensurepath()
    % Ensure that the core matnwb path is added to MATLAB path
    thisdir = fileparts(mfilename('fullpath'));
    thisdirparent = fileparts(thisdir);
    corePath = fullfile(thisdirparent, 'matnwb');
    if ~contains(path, corePath)
        addpath(corePath);
    end
end


function command = checkHTTPDownloadTools()
    % Check if common HTTP download tools are available
    % Then, return the command or path to use for downloading files
    % Returns empty if none found

    command = "";

    % wget, curl, or powershell
    [status, ~] = system('wget --version');
    if status == 0
        command = "wget";
        return;
    end
    [status, ~] = system('curl --version');
    if status == 0
        command = "curl";
        return;
    end
    [status, ~] = system('powershell -Command "Get-Command Invoke-WebRequest"');
    if status == 0
        command = "powershell";
        return;
    end
end

function [status, destination] = httpDownload(url, destination)
    % HTTPDOWNLOAD Download a file from a URL to the specified destination
    % using available HTTP download tools (wget, curl, or powershell)
    % or MATLAB's built-in websave function.
    % Returns status (0 for success) and the destination path.

    command = checkHTTPDownloadTools();
    
    status = -1;
    if command ~= ""
        if command == "wget"
            cmd = sprintf('wget -O "%s" "%s"', destination, url);
        elseif command == "curl"
            cmd = sprintf('curl -L -o "%s" "%s"', destination, url);
        elseif command == "powershell"
            cmd = sprintf('powershell -Command "Invoke-WebRequest -Uri ''%s'' -OutFile ''%s''"', url, destination);
        else
            % Should not happen given checkHTTPDownloadTools
            cmd = "";
        end

        if cmd ~= ""
            [status, cmdout] = system(cmd);
            if status ~= 0
                warning('System download tool "%s" failed: %s\nFalling back to MATLAB websave...', command, cmdout);
            end
        end
    end

    if status ~= 0
        % Fallback to websave
        try
            websave(destination, url);
            status = 0;
        catch ME
            if command == ""
                error('No HTTP download tool available and native websave() failed: %s', ME.message);
            else
                error('Download failed using %s and websave() fallback: %s', command, ME.message);
            end
        end
    end
end


function [status, destination] = gitHTTPDownload(repoUrl, destination, options)
    % GITHTTPDOWNLOAD Download a git repository as a ZIP archive from GitHub
    % and extract it to the specified destination directory.
    arguments
        repoUrl {mustBeTextScalar}
        destination {mustBeTextScalar}
        options.Branch {mustBeTextScalar} = "" % Empty means default branch, or 'latest' for the latest release tag
    end

    % Validate URL: http or https with at least one route after domain
    urlPattern = "^(http|https)://[^/]+/.+";
    if isempty(regexp(repoUrl, urlPattern, 'once'))
        error('Invalid repository URL: %s. Must be a complete and valid HTTP/HTTPS URL.', repoUrl);
    end

    latestTag = "";
    try
        latestTag = getLatestTag(repoUrl);
    catch
        % Ignore errors in getting latest tag, user may not have Git installed
    end

    if endsWith(repoUrl, '.git')
        repoUrl = extractBefore(repoUrl, strlength(repoUrl) - 3);
    end
    
    if endsWith(repoUrl, '/')
        repoUrl = extractBefore(repoUrl, strlength(repoUrl));
    end

    options.Branch = string(options.Branch);

    % Construct the ZIP download URL
    if options.Branch == ""
        % Use HEAD to get default branch if no specific branch/tag provided
        ref = "HEAD";
    elseif options.Branch == "latest"
        if latestTag == ""
            ref = "HEAD";
        else
            ref = latestTag;
        end
    else
        ref = options.Branch;
    end
    
    zipUrl = repoUrl + "/archive/" + ref + ".zip";
    
    % Create temporary directory for download and extraction
    tempExtractDir = tempname();
    mkdir(tempExtractDir);
    cleaner = onCleanup(@() rmdir(tempExtractDir, 's'));
    
    zipFile = fullfile(tempExtractDir, "repo.zip");
    
    fprintf('Downloading %s...\n', zipUrl);
    try
        status = httpDownload(zipUrl, zipFile);
    catch ME
        error('Failed to download repository from %s. Reason: %s', zipUrl, ME.message);
    end
    
    if status ~= 0
        error('Download failed with status %d', status);
    end
    
    fprintf('Extracting archive...\n');
    try
        unzip(zipFile, tempExtractDir);
    catch ME
        error('Failed to unzip archive. Reason: %s', ME.message);
    end
    
    % The zip file usually contains a single top-level directory (e.g., 'matnwb-master')
    % We need to find this directory and move its contents
    extractedItems = dir(tempExtractDir);
    dirMask = [extractedItems.isdir] & ~ismember({extractedItems.name}, {'.', '..'});
    extractedDirs = extractedItems(dirMask);
    
    if isempty(extractedDirs)
        error('Extracted archive does not contain a root directory.');
    end
    
    % Assume the first directory is the repo root
    % This is most likely the case for GitHub ZIP archives
    sourceDir = fullfile(tempExtractDir, extractedDirs(1).name);
    
    % Ensure destination exists
    if ~isfolder(destination)
        mkdir(destination);
    end
    
    fprintf('Installing to %s...\n', destination);
    movefile(fullfile(sourceDir, '*'), destination);
end