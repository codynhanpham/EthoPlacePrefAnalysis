# HDF5 Viewer

A MATLAB wrapper around the popular Python [`hdf5view`](https://github.com/tgwoodcock/hdf5view) library for viewing HDF5 files, simplifying installation and usage.

## Installation

### Prerequisites

This module requires the companion [../uv/+uv](../uv/README.md) helper module. Ideally, both modules are placed in the same `lib/` directory.

All Python dependencies and interactions are handled with `uv` to abstract away the annoying bits (Python installation, virtual environments, etc.). To see more information, see the helper `uv` module, as well as the source [uv](https://docs.astral.sh/uv/) library.

### Runtime

In MATLAB, add the folder with this README file to your session path. If the `../uv` helper module is not in the same parent directory or not already in MATLAB session path, add it as well.

#### `available()`

To check if the `+hdf5view` module is available, run:

```matlab
status = hdf5view.available()
```

The function returns `true` if the module is available, and `false` otherwise.

#### `install()`

To install the `+hdf5view` module, run:

```matlab
[libLocation, installStatus] = hdf5view.install()
```

The function returns the location of the installed library and a status indicating whether the installation probe succeeded (i.e., `import hdf5view` succeeds inside the installed environment).

The Python version used for the workspace defaults to `3.14` and can be overridden with a name-value argument (useful if a newer Python release is missing wheels for one of the dependencies):

```matlab
hdf5view.install(PythonVersion='3.13')
```

The installation is local to this module only, saved to a uv workspace at `./private/hdf5viewer/` relative to this README file. As long as you invoke any of the `hdf5view` functions from this module, the virtual environment will be automatically resolved and activated for you.

Under the hood, this function will initialize a new uv workspace with `uv init --bare --python <version>`, then install `hdf5view` and `pyqt6` with `uv add`.

> **Note:** the installation probe intentionally does *not* run `hdf5view -h`. `hdf5view` is a GUI script (not a console script), so it may have no usable stdout when probed headlessly. Instead, the probe imports the package and prints its version.

#### `file(filename)`

To open an HDF5 file in the viewer, run:

```matlab
hdf5view.file('path/to/file.h5')
```

This open the file in the `hdf5view` GUI.

You can also open multiple files as tabs within the same GUI window by simply passing in multiple filenames, or a single cell array/string array of filenames:

```matlab
hdf5view.file('file1.h5', 'file2.h5', 'file3.h5')
% or
hdf5view.file({'file1.h5', 'file2.h5', 'file3.h5'})
```

The inputs are validated with MATLAB's built-in `mustBeFile` function, and the viewer will only be launched if all files exist.

Opening multiple files at once requires `hdf5view >= 0.2.7` (the currently published release); `uv add` always installs the latest version, so this is satisfied by a fresh install.

If the viewer is not installed, it will be automatically installed first. The installation check status is cached for the duration of the MATLAB session: if the viewer is already installed, subsequent calls to `install()` will be no-ops.

The viewer is launched **non-blocking** as a detached process: MATLAB starts the viewer directly with the virtual environment's Python interpreter (via a Java `ProcessBuilder`, i.e. no shell and no quoting pitfalls) and returns immediately, while the viewer window opens on its own. Output from the viewer process is redirected to a temporary log file.

The `status` return value is `true` when the viewer process was launched successfully:

```matlab
status = hdf5view.file('path/to/file.h5')
```


## Uninstallation

Everything is local to this module. Simply delete the `private/hdf5viewer/` folder to uninstall the viewer and its virtual environment. Then, if you want to reinstall, simply call `hdf5view.install()` again.

You can also completely remove this module altogether by deleting the folder containing this README file.
