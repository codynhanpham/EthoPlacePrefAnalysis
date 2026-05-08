# Trigger Extract
Automatic detection/extraction of common "embedded" trigger events (e.g. LED stim on/offset within a video). This library includes a high-performance implementations through Rust FFI, with a fallback to pure-MATLAB implementation.

## Usage
See available high-level MATLAB functions in the `+triggerExtract` namespace. These functions wraps the low-level Rust FFI functions and handle fallbacks in case the Rust implementations fail for any reason (e.g. missing compiled libraries, unexpected errors, etc.).

To see the pure MATLAB implementations, see the [+triggerExtract/private](./+triggerExtract/private/) folder.

To see the Rust implementations, see the [./private/trigger-extract](./private/trigger-extract/) folder. Note that the Rust code must be compiled into MATLAB-callable libraries before it can be used (i.e., `.dll`, `.so`, `.dylib` files depending on your platform). For more information on how to compile the Rust code, see [Installation](#installation) below.

## Installation
For now, only pre-compiled libraries for Windows x64 are provided. Binaries for other platforms may be added in the future.

On *not-yet supported* platforms, the MATLAB functions will automatically fall back to the pure MATLAB implementations. You do not need to do anything if you are okay with some potential slower performance.

The Rust implementations can easily be 3-4x faster than the pure MATLAB implementations and **significantly** reduce memory usage, especially for longer videos. If you want to take advantage of this, you may want to compile the Rust code yourself if you are on a (currently) unsupported platform.

Please note that for video processing tasks, [OpenCV](https://opencv.org/) is required as the backend through the [OpenCV Rust binding](https://github.com/twistedfall/opencv-rust).

### Prerequisites
1. Install Rust and Cargo from the official website: https://rust-lang.org/tools/install/
2. Install OpenCV on your system. Please check out the detailed guides for your platform [**here**](https://github.com/twistedfall/opencv-rust/blob/master/INSTALL.md). Make sure to note the installation path **AND** set the required environment variables correctly.

### Compilation
1. Clone the repository and/or this specific project folder to your local machine. Then, in the terminal, navigate to the `private/trigger-extract` folder (the one that contains `Cargo.toml`).
2. Run the following command to compile the library:
    ```bash
    cargo build --release
    ```

### Usage in MATLAB
Header files and library search path should be handled automatically for you if you use the default build configuration. Otherwise, have a look at the [`triggerExtract.loadFFILib`](./+triggerExtract/loadFFILib.m) function to see how you should update the library search path.

The MATLAB functions will automatically attempt to load the Rust FFI library when they are called. If you use a non-standard build configuration, you will need to call `triggerExtract.loadFFILib` manually once for each MATLAB session with the correct library path before calling any other functions in the `+triggerExtract` namespace.

If all failed, the the higher-level functions in the `+triggerExtract` namespace will automatically fall back to the pure MATLAB implementations.