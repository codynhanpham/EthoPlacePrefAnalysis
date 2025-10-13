# FFmpeg MATLAB Tools

This module contains some MATLAB functions that interface with FFmpeg for media processing tasks.

## Installation
1. Download this module and add it to your MATLAB path (no need to add subfolders, just the parent folder containing this README is enough).
2. Make sure [FFmpeg](https://www.ffmpeg.org/download.html) is available on your system. There are 2 options:
    1. Install FFmpeg system/user-wide such that it is accessible from any command line (recommended).
    2. Grab the FFmpeg binaries and place them in the `./+ffmpeg/bin/` folder within this module. Use this option if you do not have admin rights on your machine or cannot modify your system path.
3. Check if the installation was successful by running `[status, bin] = ffmpeg.available()` in MATLAB. If `status` is true, FFmpeg is available, and `bin` contains the path to the FFmpeg binary being used.

## Usage
The main function provided is `ffmpeg.run(cmd)`, which takes a command string `cmd` (the part after `ffmpeg` in a typical FFmpeg command) and executes it using the FFmpeg binary. For example:
```matlab
[status, cmdout] = ffmpeg.run('-i input.mp4 -c:v libx264 output.mp4');
```

There are some other pre-defined functions inside the `+ffmpeg` folder, see the individual function help for details.