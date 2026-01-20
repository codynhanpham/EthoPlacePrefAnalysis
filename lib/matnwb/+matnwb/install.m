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
        fprintf('Library matnwb is not yet installed for this workspace.\nInstalling from https://github.com/NeurodataWithoutBorders/matnwb.git ...\n');
        ensuregit();

        coreRepo = 'https://github.com/NeurodataWithoutBorders/matnwb.git';
        coreDest = fullfile(thisdirparent, 'matnwb');
        gitclone(coreRepo, coreDest);
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

function gitclone(repoUrl, destPath)
    %%GITCLONE Clone a git repository to the specified destination path
    
    % Make sure git is available
    ensuregit();

    cmd = sprintf('git clone %s %s', repoUrl, destPath);
    [status, cmdout] = system(cmd);
    if status ~= 0
        error('Failed to clone repository from %s. Error: %s', repoUrl, cmdout);
    else
        fprintf('Successfully cloned repository from %s to %s\n', repoUrl, destPath);
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