# MatNWB Extras

This is a wrapper around the official [MatNWB](https://github.com/NeurodataWithoutBorders/matnwb) library that provides additional functionality for automated installation and setup of HDF5 plugins required for reading and writing NWB files.

## What this library does
Simply provides a `matnwb.install()` function that:
1. Pulls the MatNWB library and some default extensions from GitHub (for now, `ndx-pose` and `ndx-sound`, which you can change in [`./+matnwb/available.m`](./+matnwb/available.m)) if they are not already installed in the current MATLAB workspace (i.e., the current folder or its clones in the MATLAB path).
2. Checks and automatically installs 3rd-party HDF5 plugins required for reading and writing NWB files using additional compression filters (e.g., `lzf`, `bzip2`, `zstd`, etc.) if they are not already installed on the system.
3. Ensures the `HDF5_PLUGIN_PATH` environment variable is correctly set and available to MATLAB. Will try to set the variable and prompt the user to restart MATLAB if necessary.
4. Ensures the MatNWB library is correctly initialized in the current MATLAB workspace.
5. Is no-op if everything is already installed and set up, so it is safe to call multiple times when you need to ensure MatNWB is ready to use.

For step `[2]`, this library uses the excellent [hdf5plugin](https://github.com/silx-kit/hdf5plugin) Python-based project to handle the installation of HDF5 plugins (also [recommended](https://matnwb.readthedocs.io/en/latest/pages/tutorials/dynamically_loaded_filters.html) by the MatNWB team). After downloaded, the HDF5 plugins are placed in a local folder (by default, `./+matnwb/resources/hdf5plugins/`) and the `HDF5_PLUGIN_PATH` environment variable is set to point to that folder.

For the fully automated installation of Python-based packages, this library uses the [uv](https://docs.astral.sh/uv/reference/installer/) package and project manager. [uv](https://docs.astral.sh/uv/reference/installer/) allows for a seemless, isolated, and fully self-contained Python environment to be created (and even handle installing specific Python versions to that environment for you). The end-user, thus, does not need to have Python or any Python packages installed on their system prior to using this library, and installing this library will not interfere with any existing or future Python installations on the system.

## Usage
### Prerequisites
- Any MATLAB-supported operating system: Windows, macOS, or Linux.
- The [minimum required MATLAB version](https://matnwb.readthedocs.io/en/latest/pages/getting_started/installation.html) specified by the MatNWB library (typically within the last 5 major releases) or newer.
- Internet connection for the initial installation of MatNWB, extensions, and HDF5 plugins.
- ***(Optional)*** `Git` installed and available in your system `PATH`. You can download Git from [git-scm.com](https://git-scm.com/downloads) or through your system's package manager (e.g., `apt`, `brew`, `pacman`, `winget`, etc.).
    - If Git is not available, the library will fall back to downloading ZIP archives of the required repositories from GitHub.
    - Even though it is optional, having Git installed is recommended to reliably resolve the latest **stable** release tags of the MatNWB library and extensions.

### Installation and setup
To use this library, simply clone or download it into your MATLAB project folder or somewhere in your MATLAB path. Only the folder that contains the `+matnwb` package folder (the folder with this README file) needs to be in the MATLAB path.
```matlab
addpath('path/to/this/folder');
```

Then, in your MATLAB code, simply call:
```matlab
matnwb.install();
```
This will pull and ensure that MatNWB, as well as the required HDF5 plugins, are installed and set up correctly for use in your MATLAB workspace.

### The `HDF5_PLUGIN_PATH` environment variable
If you do not currently have a valid `HDF5_PLUGIN_PATH` environment variable set, you may be prompted for Administrator privileges to set the environment variable on your Windows system. If this happens, you will need to restart MATLAB after the installation is complete for the changes to take effect. Simply follow the instructions printed to the MATLAB command window. For macOS and Linux, the `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, or equivalent shell configuration file will be modified automatically to include the `HDF5_PLUGIN_PATH` environment variable, and you will need to restart MATLAB (and possibly your terminal) for the changes to take effect.

If for some reason the `HDF5_PLUGIN_PATH` cannot be set automatically, you can manually set it to point to the folder where the HDF5 plugins were installed (will be printed to the MATLAB command window, by default is `./+matnwb/resources/hdf5plugins/` in the folder where this README file is located). Note that you cannot simply set the environment variable in MATLAB using `setenv()` as the HDF5 library bundled with MATLAB is loaded when MATLAB starts, and thus needs the environment variable to be set prior to starting MATLAB.

### For future sessions
The functions `matnwb.install()` and `matnwb.initHdf5Plugins()` is no-op if everything is already installed and set up correctly. Thus, you can safely call `matnwb.install()` at the start of any MATLAB script or function that uses MatNWB to ensure that everything is set up correctly for that session.

## Uninstallation
As everything is installed locally and self-contained, simply delete the folder where this library is located to uninstall everything.

While often unnecessary to remove the `HDF5_PLUGIN_PATH` environment variable, you can do so manually:

- On Windows (PowerShell):
```powershell
REG delete HKCU\Environment /F /V HDF5_PLUGIN_PATH
```

- On macOS and Linux, `grep` search and remove the line that sets the `HDF5_PLUGIN_PATH` from your shell configuration file (e.g., `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish`, etc.).
```bash
# Find and show the line that sets the variable
grep -n HDF5_PLUGIN_PATH ~/.bashrc ~/.zshrc ~/.config/fish/config.fish  # or other relevant shell config file
# Then manually remove that line from the relevant file(s)
```