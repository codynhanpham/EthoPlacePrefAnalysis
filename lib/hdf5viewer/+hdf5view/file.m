function status = file(varargin)
    %%FILE Open HDF5 file(s) in the hdf5view GUI (non-blocking).
    %
    %   hdf5view.file('path/to/file.h5')
    %   hdf5view.file('file1.h5', 'file2.h5', 'file3.h5')
    %   hdf5view.file({'file1.h5', 'file2.h5', 'file3.h5'})
    %
    %   Accepts one or more filenames, or a single cell array / string
    %   array of filenames. All files are opened as tabs within one
    %   hdf5view GUI window.
    %
    %   The viewer is launched as a detached process (directly with the
    %   virtual environment's Python interpreter via a Java ProcessBuilder,
    %   i.e. no shell and no quoting) and this function returns
    %   immediately (non-blocking).
    %
    %   If the viewer is not installed yet, it is installed automatically
    %   first (see hdf5view.install).
    %
    %   INPUTS:
    %       filename (repeated): One or more paths to existing HDF5 files,
    %           or a single cell array / string array of paths.
    %
    %   OUTPUT:
    %       status - True when the viewer process was launched successfully.

    % Parse inputs: one or more filenames (or a single cell/string array).
    rawFiles = varargin;

    if isscalar(rawFiles) && (iscell(rawFiles{1}) || (isstring(rawFiles{1}) && ~isscalar(rawFiles{1})))
        % Single cell array or string array of filenames was passed in.
        rawFiles = rawFiles{1};
        if iscell(rawFiles)
            rawFiles = rawFiles(:).';
        end
    end

    files = normalizeFileList(rawFiles);

    [projectDir, installOk] = hdf5view.install();

    if ~installOk || isempty(projectDir)
        error('hdf5view installation not found. Please run hdf5view.install() first and ensure that hdf5view is installed correctly.');
    end

    thisdir = fileparts(mfilename('fullpath'));
    launcherScript = fullfile(thisdir, 'private', 'launch_hdf5view.py');

    if ~isfile(launcherScript)
        error('hdf5view launcher script not found: %s', launcherScript);
    end

    pythonBin = venvPythonBin(projectDir);
    if ~isfile(pythonBin)
        error('Python interpreter not found in the hdf5view virtual environment: %s', pythonBin);
    end

    % Serialize the file list to JSON and pass it through an environment
    % variable. Environment variables are never subject to command-line
    % parsing, so paths with spaces cannot be re-split on any OS.
    filesCell = cell(1, numel(files));
    for i = 1:numel(files)
        filesCell{i} = char(files(i));
    end

    command = java.util.ArrayList();
    command.add(char(pythonBin));
    command.add(char(launcherScript));

    try
        builder = java.lang.ProcessBuilder(command);
        builder.directory(java.io.File(char(projectDir)));
        builder.environment().put('HDF5VIEW_FILES_JSON', char(jsonencode(filesCell)));
        % Discard stdout/stderr (the GUI does not use the console); the
        % process keeps running independently of MATLAB.
        logFile = java.io.File(char([tempname, '.log']));
        builder.redirectErrorStream(true);
        builder.redirectOutput(logFile);
        builder.start();
        status = true;
    catch ME
        error('Failed to launch hdf5view: %s', getReport(ME, 'basic'));
    end
end

function pythonBin = venvPythonBin(projectDir)
    %VENVPYTHONBIN Full path to the Python interpreter inside the uv venv.

    if ispc
        pythonBin = fullfile(projectDir, '.venv', 'Scripts', 'python.exe');
    else
        pythonBin = fullfile(projectDir, '.venv', 'bin', 'python');
    end
end
