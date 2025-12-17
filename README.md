# Place Preference Analysis
This repository contains code for analyzing place preference data collected primarily using EthoVision software, though can be extended to parse data from other software via a shared [TrackingProvider](./src/+ui/+trackingPlatforms/README.md) class interface.

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

## DeepLabCut Integration
The program can interface with DeepLabCut (DLC) for pose estimation-based tracking via the `TrackingProvider` class interface. See [DLC Integration](./src/+ui/+trackingPlatforms/+platforms/@DeepLabCut/README.md) for more details on setup and usage.

This integration requires a custom `DLCTool` CLI-based program that exposes basic DLC functionality (e.g., run inference, etc.) in a single-bundle executable.