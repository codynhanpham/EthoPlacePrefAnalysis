@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul 2>&1
if errorlevel 1 (
	>&2 echo ERROR: Unable to access the application directory: "%SCRIPT_DIR%"
	exit /b 1
)

if defined MATLAB_BIN (
	set "MATLAB_COMMAND=%MATLAB_BIN%"
) else (
	set "MATLAB_COMMAND=matlab"
)

where "%MATLAB_COMMAND%" >nul 2>&1
if errorlevel 1 (
	>&2 echo ERROR: MATLAB was not found. Add MATLAB to PATH or set MATLAB_BIN to its executable.
	popd
	exit /b 127
)

start "" /b "%MATLAB_COMMAND%" -desktop -r "try, PlacePrefDataGUI; catch ME, fprintf(2, 'ERROR: %s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end"
if errorlevel 1 (
	>&2 echo ERROR: Unable to launch MATLAB.
	popd
	exit /b 1
)

popd
exit /b 0
