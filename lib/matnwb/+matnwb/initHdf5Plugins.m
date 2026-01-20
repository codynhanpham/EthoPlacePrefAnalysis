function status = initHdf5Plugins()
    %%INITHDF5PLUGINS Initialize HDF5 plugins for MatNWB
    %
    %   This function ensures that the necessary HDF5 plugins are installed
    %   and initialized for MatNWB to handle NWB files correctly.
    %
    %   If the plugins are not installed or accessible to MATLAB, this
    %   function will attempt to install them via the helpful
    %   Python-based hdf5plugin package. Python, along with the hdf5plugin
    %   will be installed automatically to a temporary location, then the
    %   resulting HDF5 plugins will be copied to a permanent location under
    %   ./resources/hdf5plugin/ relative to this file.
    %
    %   If the plugins are installed but not in MATLAB path, this function
    %   will add them to the MATLAB path for the current session.
    %
    %   The function will also set the HDF5_PLUGIN_PATH environment variable
    %   and prompt for a MATLAB restart as needed to ensure that MATLAB can
    %   locate the HDF5 plugins properly.
    %
    %
    %   USAGE:
    %       status = matnwb.init_hdf5plugins()
    %
    %   OUTPUTS:
    %       status: Boolean indicating whether the HDF5 plugins were
    %               successfully initialized (true) or not (false).
    %

    thisdir = fileparts(mfilename('fullpath'));
    defaultInstallDir = fullfile(thisdir, 'resources', 'hdf5plugin');
    tempdirforpython = fullfile(thisdir, 'resources', 'temp_python_env');

    status = false;

    % Make sure that matnwb is installed first!
    [isAvailable, ~] = matnwb.available();
    if ~isAvailable
        try
            matnwb.install();
        catch ME
            warning('MatNWB installation failed: %s', getReport(ME));
            return;
        end
    end

    if hdf5PluginsAvailable()
        status = true;
        return;
    end

    % Check the default installation directory for HDF5 plugins
    if ~isfolder(defaultInstallDir)
        fprintf("This seem to be the first time you are setting up additional 3rd-party HDF5 plugins on this computer. The NWB format relies on some additional HDF5 plugins for improved storage performance and accessibility. This tool will now try to automate the installation process using the Python-based `hdf5plugin` package. Everything will be sandboxed to a temporary environment and clean up for you afterwards.\nAfter the compatible HDF5 plugins are downloaded, you may be prompted for Administrator privileges to set the HDF5_PLUGIN_PATH environment variable for your system. This is required for MATLAB to locate the HDF5 plugins properly. Please follow the on-screen instructions carefully.\nFor additional information about this, see: <a href=""https://www.mathworks.com/help/matlab/import_export/read-and-write-hdf5-datasets-using-dynamically-loaded-filters.html"">https://www.mathworks.com/help/matlab/import_export/read-and-write-hdf5-datasets-using-dynamically-loaded-filters.html</a>\n");
        installHdf5PluginsFromPython(defaultInstallDir, tempdirforpython); 
    end

    if hdf5PluginsAvailable()
        ensurehdf5pluginspath(defaultInstallDir);
        status = true;
        return;
    end

    % If the plugins are still not available, reinstall it
    if isfolder(defaultInstallDir)
        ensurehdf5pluginspath(defaultInstallDir);
        if hdf5PluginsAvailable()
            status = true;
            return;
        end
        rmdir(defaultInstallDir, 's');
    end
    installHdf5PluginsFromPython(defaultInstallDir, tempdirforpython);
    ensurehdf5pluginspath(defaultInstallDir);
end


function ensurehdf5pluginspath(pluginDir)
    % Ensure that the HDF5 plugin installation directory is added to MATLAB path
    % And set the HDF5_PLUGIN_PATH environment variable
    currentEnv = getenv('HDF5_PLUGIN_PATH');
    
    if hdf5PluginsAvailable()
        return;
    end

    if ~isempty(currentEnv)
        if hdf5PluginsAvailable()
            return;
        else
            if isfolder(pluginDir)
                if ~contains(path, pluginDir)
                    addpath(pluginDir);
                end
                fprintf("\nSetting environment variable:\n\tHDF5_PLUGIN_PATH=%s\n", pluginDir);
                setsystemenv('HDF5_PLUGIN_PATH', pluginDir);
                fprintf("Environment variable HDF5_PLUGIN_PATH updated successfully.\n");
                fprintf("Please restart MATLAB, then run either matnwb.install() or matnwb.initHdf5Plugins() again to make sure the HDF5 plugins are properly accessible.\n");
                error(sprintf("\n\t----- THIS IS NOT AN ERROR -----\nPlease check the message above and restart MATLAB."));
            end
            error('HDF5 plugins not found in the specified directory %s and HDF5_PLUGIN_PATH is already set to %s. Please check your HDF5 plugin installation.', pluginDir, currentEnv);
        end
    end
    
    if isfolder(pluginDir)
        if ~contains(path, pluginDir)
            addpath(pluginDir);
        end
        fprintf("\nSetting environment variable:\n\tHDF5_PLUGIN_PATH=%s\n", pluginDir);
        setsystemenv('HDF5_PLUGIN_PATH', pluginDir);
        fprintf("Environment variable HDF5_PLUGIN_PATH updated successfully.\n");
        fprintf("Please restart MATLAB, then run either matnwb.install() or matnwb.initHdf5Plugins() again to make sure the HDF5 plugins are properly accessible.\n");
        error(sprintf("\n\t----- THIS IS NOT AN ERROR -----\nPlease check the message above and restart MATLAB."));
    end
end

function setsystemenv(varname, value)
    % Set environment variable persistently for the system
    if ispc
        % Windows
        cmd = sprintf('powershell -Command "Start-Process powershell -ArgumentList @(''-NoProfile'', ''-Command'', ''setx %s \\\"%s\\\"'') -Verb RunAs -WindowStyle Hidden -Wait"', varname, value);
        [s,cmdout] = system(cmd);
        if s ~= 0
            error('Failed to set system environment variable %s. Command output: %s', varname, cmdout);
        end
    elseif isunix
        % Mac & Linux
        homeDir = getenv('HOME');
        bashrcPath = fullfile(homeDir, '.bashrc');
        zshrcPath = fullfile(homeDir, '.zshrc');
        fishConfigPath = fullfile(homeDir, '.config', 'fish', 'config.fish');
        blockHeader = sprintf('\n# HDF5 Plugins\n');
        exportBlock = sprintf('%sexport %s="%s"\n\n', blockHeader, varname, value);
        fishBlock = sprintf('%sset -gx %s "%s"\n\n', blockHeader, varname, value);

        if isfile(bashrcPath)
            fid = fopen(bashrcPath, 'a');
            fprintf(fid, exportBlock);
            fclose(fid);
        end
        if isfile(zshrcPath)
            fid = fopen(zshrcPath, 'a');
            fprintf(fid, exportBlock);
            fclose(fid);
        end

        % Only add to fish if user already has config; avoid creating new shell config
        if isfile(fishConfigPath)
            fid = fopen(fishConfigPath, 'a');
            fprintf(fid, fishBlock);
            fclose(fid);
        end
    else
        warning('Unsupported operating system for setting persistent environment variables.');
    end
end




function bool = hdf5PluginsAvailable()
    % Since Zstandard compression is only available when the HDF5 plugins are
    % properly installed and accessible to MATLAB, we can check for that by
    % attempting to initialize the Zstandard filter.

    try
        types.untyped.datapipe.dynamic.Filter.ZStandard; % Attempt to access the ZStandard filter type defined in MatNWB
    catch
        error('Failed to import DynamicFilter class from MatNWB. Ensure MatNWB is installed correctly and added to the MATLAB path first before adding 3rd-party HDF5 plugins.');
    end

    try
        types.untyped.datapipe.properties.DynamicFilter(types.untyped.datapipe.dynamic.Filter.ZStandard);
        bool = true;
    catch
        bool = false;
    end
end

function installHdf5PluginsFromPython(installDir, tempPythonDir)
    % Install HDF5 plugins using Python's hdf5plugin package
    %% Recipe:
    % 1. Install uv (https://astral.sh/uv/) to a temporary location, this will take care of Python and virtualenv setup
    % Windows:
    % > powershell -ExecutionPolicy ByPass -c {$env:UV_INSTALL_DIR = "[installDir]";irm https://astral.sh/uv/install.ps1 | iex}
    % Mac & Linux:
    % > curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="[installDir]" sh
    % 2. Create a virtual environment and install hdf5plugin
    % mkdir [tempPythonDir] && cd [tempPythonDir]
    % uv init --python 3.13 && uv add --link-mode=copy hdf5plugin
    % 3. Make a temporary python script, showpath.py in the same temp dir with content: import hdf5plugin;print(hdf5plugin.PLUGINS_PATH)
    % 4. Run the script to get the plugin path
    % uv run showpath.py
    % 5. Copy the content of that path to the permanent installDir
    % 6. Clean up the temporary python environment
    % 7. Add the installDir to MATLAB path and set HDF5_PLUGIN_PATH env variable
    %%

    if ~isfolder(tempPythonDir)
        mkdir(tempPythonDir);
    end
    currDir = pwd();
    cd(tempPythonDir);

    if ispc % Windows
        try
            % Step 1: Install uv
            fprintf('Installing uv to temporary directory %s ...\n', tempPythonDir);
            % Properly quote the PowerShell -Command to prevent CMD from parsing the pipeline
            % Also set UV_INSTALL_DIR so uv installs into tempPythonDir
            psScript = sprintf('& { $env:UV_INSTALL_DIR = ''%s''; irm ''https://astral.sh/uv/install.ps1'' | iex }', tempPythonDir);
            fullCmd = ['powershell -NoProfile -ExecutionPolicy Bypass -Command "', psScript, '"'];
            [psStatus, psOut] = system(fullCmd);
            if psStatus ~= 0
                error('Failed to install uv via PowerShell. Command output: %s', psOut);
            end

            % Step 2: Create virtual environment and install hdf5plugin
            fprintf('Creating virtual environment and installing hdf5plugin ...\n');
            % Resolve uv.exe path within the chosen install directory
            uvExeCandidates = {fullfile(tempPythonDir, 'uv.exe'), fullfile(tempPythonDir, 'bin', 'uv.exe')};
            uvExe = '';
            for i = 1:numel(uvExeCandidates)
                if isfile(uvExeCandidates{i})
                    uvExe = uvExeCandidates{i};
                    break;
                end
            end
            if isempty(uvExe)
                uvExe = 'uv'; % fallback to PATH if not found
            end

            [st1, out1] = system(sprintf('"%s" init --python 3.13', uvExe));
            if st1 ~= 0
                error('uv init failed: %s', out1);
            end
            [st2, out2] = system(sprintf('"%s" add --link-mode=copy hdf5plugin', uvExe));
            if st2 ~= 0
                error('uv add hdf5plugin failed: %s', out2);
            end

            % Step 3: Create temporary Python script to get plugin path
            scriptPath = fullfile(tempPythonDir, 'showpath.py');
            fid = fopen(scriptPath, 'w');
            fprintf(fid, 'import hdf5plugin; print(hdf5plugin.PLUGINS_PATH)');
            fclose(fid);

            % Step 4: Run the script to get the plugin path
            fprintf('Retrieving HDF5 plugin path from Python ...\n');
            [status, cmdout] = system(sprintf('"%s" run showpath.py', uvExe));
            if status ~= 0
                error('Failed to run Python script to get HDF5 plugin path: %s', cmdout);
            end
            pluginPath = strtrim(cmdout);

            % Step 5: Copy plugins to permanent installDir
            fprintf('Copying HDF5 plugins to %s ...\n', installDir);
            copyfile(pluginPath, installDir);

            % Step 6: Clean up temporary Python environment
            fprintf('Cleaning up temporary Python environment ...\n');
            cd(currDir);
            rmdir(tempPythonDir, 's');

            
        catch ME
            cd(currDir);
            warning('Failed to install HDF5 plugins via Python: %s', getReport(ME));
            return;
        end
    elseif isunix % Mac & Linux
        try
            % Step 1: Install uv
            fprintf('Installing uv to temporary directory %s ...\n', tempPythonDir);
            % Use curl to install uv to tempPythonDir
            shellCmd = sprintf('curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="%s" sh', tempPythonDir);
            [shStatus, shOut] = system(shellCmd);
            if shStatus ~= 0
                error('Failed to install uv via shell. Command output: %s', shOut);
            end

            % Step 2: Create virtual environment and install hdf5plugin
            fprintf('Creating virtual environment and installing hdf5plugin ...\n');
            uvExeCandidates = {fullfile(tempPythonDir, 'uv'), fullfile(tempPythonDir, 'bin', 'uv')};
            uvExe = '';
            for i = 1:numel(uvExeCandidates)
                if isfile(uvExeCandidates{i})
                    uvExe = uvExeCandidates{i};
                    break;
                end
            end
            if isempty(uvExe)
                uvExe = 'uv'; % fallback to PATH if not found
            end

            [st1, out1] = system(sprintf('"%s" init --python 3.13', uvExe));
            if st1 ~= 0
                error('uv init failed: %s', out1);
            end
            [st2, out2] = system(sprintf('"%s" add --link-mode=copy hdf5plugin', uvExe));
            if st2 ~= 0
                error('uv add hdf5plugin failed: %s', out2);
            end

            % Step 3: Create temporary Python script to get plugin path
            scriptPath = fullfile(tempPythonDir, 'showpath.py');
            fid = fopen(scriptPath, 'w');
            fprintf(fid, 'import hdf5plugin; print(hdf5plugin.PLUGINS_PATH)');
            fclose(fid);

            % Step 4: Run the script to get the plugin path
            fprintf('Retrieving HDF5 plugin path from Python ...\n');
            [status, cmdout] = system(sprintf('"%s" run showpath.py', uvExe));
            if status ~= 0
                error('Failed to run Python script to get HDF5 plugin path: %s', cmdout);
            end
            pluginPath = strtrim(cmdout);

            % Step 5: Copy plugins to permanent installDir
            fprintf('Copying HDF5 plugins to %s ...\n', installDir);
            copyfile(pluginPath, installDir);

            % Step 6: Clean up temporary Python environment
            fprintf('Cleaning up temporary Python environment ...\n');
            cd(currDir);
            rmdir(tempPythonDir, 's');

        catch ME
            cd(currDir);
            warning('Failed to install HDF5 plugins via Python: %s', getReport(ME));
            return;
        end
    else
        error('Unsupported operating system for HDF5 plugin installation.');
    end

    % Step 7: Add installDir to MATLAB path and set HDF5_PLUGIN_PATH
    ensurehdf5pluginspath(installDir);
end