function [libLocation, installOk] = install()
    %%INSTALL Install OWLv2-Detect if not already installed
    %
    %   This installs the OWLv2-Detect repository into ./private/owlv2-detect
    %   for the current MATLAB workspace, then runs `uv sync` in that checkout
    %   and validates the installation with `uv run owlv2-detect -h`.
    %
    %   USAGE:
    %       [libLocation, installOk] = owlv2.install()
    %
    %   OUTPUTS:
    %       libLocation: Path to the local OWLv2-Detect checkout.
    %       installOk: True when the repository is available and the CLI probe
    %           succeeds after installation.

    thisdir = fileparts(mfilename('fullpath'));
    thisdirparent = fileparts(thisdir);
    privateDir = fullfile(thisdirparent, 'private');
    repoName = 'owlv2-detect';
    repoUrl = 'https://github.com/codynhanpham/owlv2-detect';
    repoDir = fullfile(privateDir, repoName);

    if ~isfolder(privateDir)
        mkdir(privateDir);
    end

    [installOk, ~] = owlv2.available();
    if installOk
        libLocation = repoDir;
        return;
    end

    fprintf('OWLv2-Detect is not yet installed for this workspace.\nInstalling from %s ...\n', repoUrl);

    latestTag = "";
    clonedOk = false;

    gitAvailable = true;
    try
        ensuregit();
    catch
        gitAvailable = false;
    end

    if gitAvailable
        try
            latestTag = getLatestTag(repoUrl);
            if latestTag ~= ""
                fprintf('Detected latest release tag: %s\n', latestTag);
                gitclone(repoUrl, repoDir, 'Branch', latestTag, 'Depth', 1);
            else
                fprintf('Could not detect tags, cloning default branch...\n');
                gitclone(repoUrl, repoDir, 'Depth', 1);
            end
            clonedOk = true;
        catch ME
            warning('Git clone failed: %s\n\nFalling back to downloading ZIP archive...', getReport(ME));
        end
    else
        fprintf('Git is not available on this system. Falling back to downloading ZIP archive...\n');
    end

    if ~clonedOk
        branchToDownload = "";
        if latestTag ~= ""
            branchToDownload = latestTag;
        end
        try
            gitHTTPDownload(repoUrl, repoDir, 'Branch', branchToDownload);
        catch ME
            error('Installation via HTTP archive failed: %s', getReport(ME));
        end
    end

    runUvSync(repoDir);

    [installOk, missing] = owlv2.available();
    if ~installOk
        error('OWLv2-Detect installation incomplete. Missing components: %s', strjoin(missing, ', '));
    end

    libLocation = repoDir;
end

function runUvSync(repoDir)
    currentDir = pwd;
    restoreDir = onCleanup(@() cd(currentDir));
    cd(repoDir);

    fprintf('Synchronizing OWLv2-Detect with uv...\n');
    exitCode = uv.cmd('sync');
    if exitCode ~= 0
        error('uv sync failed while installing OWLv2-Detect (exit code %d).', exitCode);
    end

    fprintf('Validating OWLv2-Detect installation...\n');
    exitCode = uv.run('owlv2-detect -h');
    if exitCode ~= 0
        error('OWLv2-Detect validation failed (exit code %d).', exitCode);
    end

    clear restoreDir;
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
        options.Branch {mustBeTextScalar} = ""
        options.Depth (1,1) double = 0
    end

    options.Branch = string(options.Branch);

    if isfolder(destPath)
        fprintf('Directory %s already exists. Skipping clone.\n', destPath);
        return;
    end

    ensuregit();

    [~, repoName, ~] = fileparts(repoUrl);

    gitOpts = "";
    if options.Branch ~= ""
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
    cmd = sprintf('git ls-remote --tags --sort="v:refname" %s', repoUrl);
    [status, cmdout] = system(cmd);

    if status ~= 0
        warning('Failed to retrieve tags from %s. Git output: %s', repoUrl, cmdout);
        tag = "";
        return;
    end

    lines = splitlines(strtrim(cmdout));
    lines(strcmp(lines, '')) = [];

    if isempty(lines)
        tag = "";
        return;
    end

    lastLine = lines{end};
    tokens = regexp(lastLine, 'refs/tags/([^\^]+)', 'tokens');

    if ~isempty(tokens) && ~isempty(tokens{1})
        tag = string(tokens{1}{1});
    else
        parts = strsplit(lastLine, '/');
        tag = string(parts{end});
        tag = strrep(tag, '^{}', '');
    end
end

function command = checkHTTPDownloadTools()
    % Check if common HTTP download tools are available
    % Then, return the command or path to use for downloading files
    % Returns empty if none found

    command = "";

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
        options.Branch {mustBeTextScalar} = ""
    end

    urlPattern = "^(http|https)://[^/]+/.+";
    if isempty(regexp(repoUrl, urlPattern, 'once'))
        error('Invalid repository URL: %s. Must be a complete and valid HTTP/HTTPS URL.', repoUrl);
    end

    latestTag = "";
    try
        latestTag = getLatestTag(repoUrl);
    catch
    end

    if endsWith(repoUrl, '.git')
        repoUrl = extractBefore(repoUrl, strlength(repoUrl) - 3);
    end

    if endsWith(repoUrl, '/')
        repoUrl = extractBefore(repoUrl, strlength(repoUrl));
    end

    options.Branch = string(options.Branch);

    if options.Branch == ""
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

    extractedItems = dir(tempExtractDir);
    dirMask = [extractedItems.isdir] & ~ismember({extractedItems.name}, {'.', '..'});
    extractedDirs = extractedItems(dirMask);

    if isempty(extractedDirs)
        error('Extracted archive does not contain a root directory.');
    end

    sourceDir = fullfile(tempExtractDir, extractedDirs(1).name);

    if ~isfolder(destination)
        mkdir(destination);
    end

    fprintf('Installing to %s...\n', destination);
    movefile(fullfile(sourceDir, '*'), destination);
    clear cleaner;
end