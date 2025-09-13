# `./lib/*`

This folder is where you should place any external libraries downloaded from MATLAB Central / File Exchange / GitHub.

After unzipping the library, you should copy the folder as is (including the package date suffix and license file, if they exist) to this folder.

**DO NOT ADD THESE LIBRARY TO PATH MANUALLY** 

All library folders placed in this directory will be dynamically loaded at runtime. If you wish to have access to a library's function for development, please add the individual library folders as needed for the current session only (not permanently).

## `.ignore`

If you have files or subfolders within this directory that you do not want to be loaded (add to path during runtime), you can add them to this file. Provided as a relative path to this (`./lib/`) directory. Wildcards are NOT supported.

Note that you cannot ignore singular files as MATLAB will add to path on the folder level.