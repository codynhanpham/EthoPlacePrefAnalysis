#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
if ! cd -- "$SCRIPT_DIR"; then
	printf 'ERROR: Unable to access the application directory: %s\n' "$SCRIPT_DIR" >&2
	exit 1
fi

MATLAB_BIN="${MATLAB_BIN:-matlab}"
if ! command -v "$MATLAB_BIN" >/dev/null 2>&1; then
	printf 'ERROR: MATLAB was not found. Add MATLAB to PATH or set MATLAB_BIN to its executable.\n' >&2
	exit 127
fi

nohup "$MATLAB_BIN" -desktop -r "try, PlacePrefDataGUI; catch ME, fprintf(2, 'ERROR: %s\n', getReport(ME, 'extended', 'hyperlinks', 'off')); end" \
	>/dev/null 2>&1 </dev/null &

if [ "$?" -ne 0 ]; then
	printf 'ERROR: Unable to launch MATLAB.\n' >&2
	exit 1
fi

exit 0
