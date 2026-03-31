function [uvbin, uvdir] = install()
    %%INSTALL Install uv to a local directory and return the path to the main uv executable
    %   This will install uv to a local directory (./private/bin) and return the path to the main uv executable. The installation location is also returned as a second output for convenience.
    %
    %   [uvbin, uvdir] = uv.install()
    %
    %   Outputs:
    %       uvbin (char): path to the main uv executable
    %       uvdir (char): path to the directory where uv is installed

    persistent UVBIN UVDIR SYSTEMUV
    
    systemwhich = 'which';
    if ispc
        systemwhich = 'where';
    end
    [whichStatus, whichOut] = system(sprintf('%s uv', systemwhich));
    if whichStatus == 0
        sysuv = cleancmdoutput(whichOut);
    else
        sysuv = '';
    end

    if ~isempty(sysuv)
        SYSTEMUV = sysuv;
    end
    if (~isempty(UVBIN) && ~isempty(UVDIR) && isfile(UVBIN) && isfolder(UVDIR)) || (~isempty(SYSTEMUV) && isfile(SYSTEMUV))
        if ~isempty(SYSTEMUV)
            UVBIN = SYSTEMUV;
            [~, uvdir, ~] = fileparts(SYSTEMUV);
            uvbin = SYSTEMUV;
            UVDIR = uvdir;
        else
            uvbin = UVBIN;
            uvdir = UVDIR;
        end 
        return;
    end

    thisfilepath = fileparts(mfilename('fullpath'));
    uvdir = fullfile(thisfilepath, 'private', 'bin');
    if ~isfolder(uvdir)
        mkdir(uvdir);
    end
    binsuffix = '';
    if ispc
        binsuffix = '.exe';
    end

    % Install uv to the specified directory
    if ispc
        % Properly quote the PowerShell -Command to prevent CMD from parsing the pipeline
        % Also set UV_UNMANAGED_INSTALL so uv installs into uvdir
        psScript = sprintf('& { $env:UV_UNMANAGED_INSTALL = ''%s''; irm ''https://astral.sh/uv/install.ps1'' | iex }', uvdir);
        fullCmd = ['powershell -NoProfile -ExecutionPolicy Bypass -Command "', psScript, '"'];
        [psStatus, psOut] = system(fullCmd);
        if psStatus ~= 0
            error('Failed to install uv via PowerShell. Command output: %s', psOut);
        end
        uvbin = fullfile(uvdir, ['uv', binsuffix]);
        % After installation, see if uv is now available
        [status, cmdOut] = system(sprintf('"%s" --version', uvbin));
        if status ~= 0
            error('uv installation failed to activate. Command output: %s', cmdOut);
        end
    elseif isunix
        % Log the base output of system commands (occured on some Linux installations)
        [~, basesystemoutput] = system('echo');
        basesystemoutput = strtrim(basesystemoutput);

        % Download the installer script using websave
        installerPath = fullfile(uvdir, 'uv_install.sh');
        try 
            websave(installerPath, 'https://astral.sh/uv/install.sh');
        catch ME
            error('Failed to download uv installer: %s', ME.message);
        end
        % Run the installer
        shellCmd = sprintf('env UV_UNMANAGED_INSTALL="%s" sh "%s"', uvdir, installerPath);
        [shStatus, shOut] = system(shellCmd);
        if shStatus ~= 0
            error('Failed to install uv via shell. Command output: %s', cleancmdoutput(shOut, basesystemoutput));
        end

        uvbin = fullfile(uvdir, ['uv', binsuffix]);
        % After installation, see if uv is now available
        [status, cmdOut] = system(sprintf('"%s" --version', uvbin));
        if status ~= 0
            error('uv installation failed to activate. Command output: %s', cleancmdoutput(cmdOut, basesystemoutput));
        end
    else
        error('Unsupported operating system for uv installation');
    end

    UVBIN = uvbin;
    UVDIR = uvdir;
end

function cleaned = cleancmdoutput(raw)
    persistent basesystemoutput
    if isempty(basesystemoutput)
        [~, basesystemoutput] = system('echo');
        basesystemoutput = strtrim(basesystemoutput);
    end

    cleaned = strtrim(raw);
    if startsWith(cleaned, basesystemoutput)
        cleaned = strtrim(extractAfter(cleaned, strlength(basesystemoutput)));
    end
    cleaned = strtrim(cleaned);
end