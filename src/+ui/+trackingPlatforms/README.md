# Tracking Platforms

This directory contains a set of classes and utilities for integrating various tracking platforms into the EthoPlacePrefAnalysis pipeline. Each tracking platform is encapsulated in its own class, allowing for modular and extensible tracking solutions.

As a baseline, the `@TrackingProvider` class serves as an abstract base class for all tracking platform implementations. It defines the necessary interface and common functionality that all derived tracking platform classes must implement. In other words, this acts as a wrapper around different tracking systems to provide a consistent API for the rest of the analysis framework.

## Development

### Adding a New Tracking Platform
Generally, to add a new tracking platform, you would first need to check the following requirements:
1. The platform must be able to perform the tasks expected by the analysis pipeline, all of which are defined in the `@TrackingProvider` abstract class.
2. There must be a way to run the platform's tracking algorithms programmatically, either through a command-line interface, API, or SDK.
    1. It would be great if the platform supports MATLAB natively, but this is not strictly necessary.
    2. If there is any form of CLI or API available, a MATLAB wrapper can be created to interface with it via system() calls or HTTP requests.
    3. If the platform requires dependency installation and/or virtual environments, ensure that you handle this carefully within your MATLAB wrapper and unload/deactivate those environments after use to avoid conflicts.
    4. Ideally, if you can containerize or bundle the platform with its dependencies (say, a Python-based platform can be bundled via PyInstaller), that is strongly recommended.
        1. You can always interact with external executables via system() calls in MATLAB, avoiding dependency conflicts.
        2. Provides a cleaner user experience, as users won't have to install complex dependencies manually.
3. The platform should be able to export tracking data in a format that can be easily parsed and integrated into the EthoPlacePrefAnalysis pipeline (e.g., CSV, JSON, H5, Parquet, MAT files, etc.).

After confirming the above requirements, you can proceed to implement the new tracking platform by following these steps:
1. Make the new tracking platform interface available in MATLAB
    1. If the platform has a MATLAB SDK, API, or library (MATLAB File Exchange submission, etc.), simply put it in the root `/lib` directory of this project. The program will automatically add it to the MATLAB session path when initialized.
    2. If you need to create a MATLAB wrapper around a CLI or API, create a new directory under either `/lib` or `/src/+io/+yournewplatform` and implement the necessary functions to interact with the platform.
2. Create a new class that inherits from `@TrackingProvider`, save it under `/src/+ui/+trackingPlatforms/+platforms/YourNewPlatform/YourNewPlatform.m`
    1. This ensure that the new platform is discoverable by the `listAvailablePlatforms()` static method in `@TrackingProvider`.
3. Using the installed SDK/API/wrapper in step 1, implement all the abstract methods defined in `@TrackingProvider` to provide the necessary functionality for your new tracking platform.
4. If your platform requires specific configuration or setup parameraters, provide examples and document them clearly in `configs.yml` files and provide default values where appropriate.
5. Add any additional helper functions or utilities as needed to support your tracking platform. These are often not used directly by the core analysis pipeline, but can be useful if you implement your own extension component. An example would be some shell scripts to automate the download of pre-trained models or datasets required by your tracking platform.
6. Test your new tracking platform implementation thoroughly to ensure it works as expected within the **EthoPlacePrefAnalysis** pipeline.