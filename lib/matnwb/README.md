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
As in MATLAB's documentation for [Dynamically Loaded Filters](https://www.mathworks.com/help/matlab/import_export/read-and-write-hdf5-datasets-using-dynamically-loaded-filters.html), the `HDF5_PLUGIN_PATH` environment variable must be set to point to the folder where the HDF5 plugins are installed for MATLAB to be able to use them. This environment variable must be set before MATLAB loads the integrated HDF5 library on startup. There are 2 options for this: either setting the environment variable permanently on the system (via registry on Windows, or shell configuration files on macOS and Linux), or set it in the `startup.m` file of your MATLAB user profile. Setting `HDF5_PLUGIN_PATH` system-wide will also allows other applications that use HDF5 to access the plugins, while setting it in `startup.m` isolates it to MATLAB only.

**This library will try to set the `HDF5_PLUGIN_PATH` environment variable automatically for you by updating the `startup.m` file for your MATLAB user profile** (or creating one if it does not exist). This way, no critial system files are modified unsupervised, and the change is isolated to MATLAB only. Moreover, as `startup.m` in your `userpath` is owned by you (often in your `~/Documents/MATLAB/` folder by default), no special permissions are required, making the installation possible in managed environments. You can find your `startup.m` file location by running `which('startup')` in MATLAB. 

> *If you have multiple `userpath` folders configured in MATLAB, the first one returned by **`userpath()`** will be used to create or update the `startup.m` file.*

After the library is installed and the `startup.m` file is modified, you can inspect the file to see the changes made in MATLAB:
```matlab
edit(which('startup')); % Open the startup.m file in the MATLAB editor
```

**After a fresh install and modification of the `startup.m` file, you must restart MATLAB** for the changes to take effect. After restarting MATLAB, you can verify that the `HDF5_PLUGIN_PATH` environment variable is set correctly by running:
```matlab
getenv('HDF5_PLUGIN_PATH') % where the plugins are installed

% Or more conclusively, check if MatWNB and MATLAB can access the plugins:
matnwb.install(); % no-op if everything is set up correctly, returns the path to MatNWB core library
```



### For future sessions
The functions `matnwb.install()` and `matnwb.initHdf5Plugins()` are no-op if everything is already installed and set up correctly. Thus, you can safely call `matnwb.install()` at the start of any MATLAB script or function that uses MatNWB to ensure that everything is set up correctly for that session.

## Uninstallation
As everything is installed locally and self-contained, simply delete the folder where this library is located to uninstall everything.

While often unnecessary to remove the `HDF5_PLUGIN_PATH` environment variable, you can do so manually by updating your `startup.m` file to remove the line that sets the variable:
```matlab
edit(which('startup')); % Open the startup.m file in the MATLAB editor
```
Then, delete the line that looks like:
```matlab
setenv('HDF5_PLUGIN_PATH', 'path/to/hdf5plugins');
```