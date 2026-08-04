# SLEAP Tracking Platform for Place Preference Analysis

This module provides integration with SLEAP for pose estimation-based tracking within the Place Preference Analysis application. It wraps around the [`/src/+io/+sleap`](/src/+io/+sleap/) module to facilitate the communication and data processing with SLEAP.

The installation of SLEAP is fully automated via a simple `io.sleap.install()` function call that checks and only sets up SLEAP when missing, no-op otherwise. Even `uv` will be installed automatically and locally if the +sleap module is downloaded together with the main repository. The [`/lib/uv`](/lib/uv/README.md) global library handles the installation and setup of `uv` for all platforms, including Windows, macOS, and Linux.

This function creates a separate and isolated SLEAP installation in the `/src/+io/+sleap/private/sleap-tools` folder, so it does not interfere with any existing SLEAP installation on the system.


## Checklist
This module is now fully integrated into the main application. Use this checklist to track progress and capabilities:
- [x] Customize SLEAP model via configs
- [x] All `sleap-nn predict` CLI options are supported via config and `io.sleap.predict()` function call
- [x] Run SLEAP inference from within the application, both per-trial and batch modes
- [x] First-class inference progress and ETA feedback in MATLAB GUI
- [x] Parse SLEAP output files and preview tracking data overlay on video
- [x] Preserve SLEAP skeleton and bodypart in visualization and exports
- [x] Zone definitions inferred via the global *.ref.json file (left/right side of arena, with flipping support)
- [x] Per-trial place preference analysis using SLEAP tracking data
- [x] Population-level analysis across multiple subjects using SLEAP tracking data