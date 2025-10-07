# Place Preference Analysis
This repository contains code for analyzing place preference data collected using EthoVision software, though can be extended to parse data from other software as well.

The primary tasks include:
- Parsing raw data files from EthoVision (Media Files and Raw Data Excel files).
- Aligning recorded behavioral data with stimulus events (audio).
- Per-trial analysis of time spent in different zones (summarized as heatmap + bar charts).
- Population-level analysis across multiple subjects and stimulus conditions.

## Requirements
- MATLAB ≥2024b or MATLAB Runtime if using the compiled version.

Additionally, the source code includes a pre-compiled binary, `metadata_extract`, to extract metadata (specifically, chapter/marker timestamps) from `.flac` audio stimulus files. This binary is part of the full `NI-DAQmx Media Player` software used for integrating audio stimulus presentation with EthoVision, whose source code is available at [codynhanpham/nidaq_audioplayer](https://github.com/codynhanpham/nidaq_audioplayer).