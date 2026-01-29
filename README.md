# Place Preference Analysis
This repository contains code for analyzing place preference data collected primarily using EthoVision software, though can be extended to parse and process data from other software via a shared [TrackingProvider](./src/+ui/+trackingPlatforms/README.md) class interface.

The primary tasks include:
- Video playback (plus basic controls: timeline-scrubbing, jumping to specific frame, keyboard shortcuts) with optional overlay of tracking data.
- Parsing raw data files from EthoVision (Media Files and Raw Data Excel files).
- Aligning recorded behavioral data with stimulus events (audio). See more in [Requirements](#requirements).
- Per-trial analysis of time spent in different zones (summarized as heatmap + bar charts) and position over time relative to a reference point/line.
- Population-level analysis across multiple subjects and stimulus conditions.

The program is compatible with linear-zone setups (e.g., two-chamber place preference relative to midline) as well as open-field or Y-maze style arenas (relative to a user-defined reference point/line) with user-defined zones.

## Requirements
- MATLAB ≥2024b or MATLAB Runtime if using the compiled version.
- For now, a ***MasterMetadata*** Excel file with pre-defined headers to associate the video/data files with test subjects' metadata logs, stimulus conditions, and trial timings. See [MasterMetadata Validation](./src/+io/+metadata/isMasterMetadataTable.m) for the required headers.

Additionally, the source code includes a pre-compiled binary, `metadata_extract`, to extract metadata (specifically, chapter/marker timestamps) from `.flac` audio stimulus files. This binary is part of the full `NI-DAQmx Media Player` software used for integrating audio stimulus presentation with EthoVision, whose source code is available at [codynhanpham/nidaq_audioplayer](https://github.com/codynhanpham/nidaq_audioplayer).

### Operating systems
The program is designed to run on all platforms that is supported by MATLAB, including **Windows**, **macOS**, and **Linux**. It is used and tested regularly on Windows 11, Ubuntu 24.04 (Debian-based Linux), and CachyOS (Arch-based Linux).

The only bottleneck at the moment is building the `metadata_extract` binary for macOS as I do not have access to a modern Mac machine to compile it. If you are on macOS, please head to the [nidaq_audioplayer](https://github.com/codynhanpham/nidaq_audioplayer) repository to build the binary from source, then place the compiled binary in the [`./src/+io/+stimuli`](./src/+io/+stimuli) folder.


## Third-Party Software Integration
Support for additional tracking/pose-estimation software, ethogram labeling tools, or other applications will be added to this core repository as needed by our lab workflows and not guaranteed.

Below are some currently supported integrations and short-term future plans.

### DeepLabCut Integration
The program can interface with [DeepLabCut](https://github.com/DeepLabCut/DeepLabCut) (DLC) for pose estimation-based tracking via the `TrackingProvider` class interface. See [DLC Integration](./src/+ui/+trackingPlatforms/+platforms/@DeepLabCut/README.md) for more details on setup and usage.

This integration requires a custom `DLCTool` CLI-based program that exposes basic DLC functionality (e.g., run inference, etc.) in a single-bundle executable.

### SLEAP
Support for [SLEAP](https://sleap.ai/)-based tracking is planned. It will most probably be similar to the DLC integration by extending the `TrackingProvider` class interface.

SLEAP installation and interaction can also be easily automated and save locally on-demand as it's already using [uv](https://docs.astral.sh/uv/reference/installer/), a very nice Python project manager that can dynamically activate corresponding virtual environments and execute Python scripts directly through CLI commands.

### Neurodata Without Borders (NWB)
I/O support for NWB files is being added, backed by the [MatNWB](https://github.com/NeurodataWithoutBorders/matnwb) library. This addition will improve interoperability with other neuroscience data analysis tools and streamline data management workflows.

Automated [MatNWB](https://github.com/NeurodataWithoutBorders/matnwb) AND additional third-party HDF5 filters (e.g., for compression, see [MatNWB Doc](https://matnwb.readthedocs.io/en/latest/pages/tutorials/dynamically_loaded_filters.html) and [MATLAB Doc](https://www.mathworks.com/help/matlab/import_export/read-and-write-hdf5-datasets-using-dynamically-loaded-filters.html)) installation is already fully implemented. Please see [`./lib/matnwb/README.md`](./lib/matnwb/README.md) for more details. This simplifies the setup process significantly, as adding HDF5 plugins manually and ensuring it works on all operating systems is often the biggest hurdle.