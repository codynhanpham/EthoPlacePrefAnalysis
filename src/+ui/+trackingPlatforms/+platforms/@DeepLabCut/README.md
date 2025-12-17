# DeepLabCut Tracking Platform for Place Preference Analysis

This module provides integration with DeepLabCut (DLC) for pose estimation-based tracking within the Place Preference Analysis application. It wraps around the [`/src/+io/+dlc`](/src/+io/+dlc/) module to facilitate the communication and data processing with DLC.

This module relies on a custom PyInstaller-bundle of DLC, called **`DLCTool`**, that expose DLC functionality via a command-line interface (CLI). For now, this bundle is yet to be publicly released, but planned for future availability. Contact the authors if you need immediate access.

## Checklist
This module is not yet fully integrated into the main application. Use this checklist to track progress:
- [x] Customize DLC model via configs
- [x] Run DLC inference from within the application, both per-trial and batch modes
- [x] Parse DLC output files and preview tracking data overlay on video
- [ ] Set up zone definitions and compute zone occupancy metrics using DLC tracking data
- [ ] Per-trial place preference analysis using DLC tracking data
- [ ] Population-level analysis across multiple subjects using DLC tracking data