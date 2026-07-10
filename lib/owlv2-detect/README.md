# OWLv2 Detect - MATLAB Interface
This is a wrapper to provide a MATLAB interface to the OWLv2 Detect command line tool. It allows you to easily install, validate, and run OWLv2 Detect commands from within MATLAB.

## API Overview

The MATLAB package exposes a small set of entry points in the `owlv2` package:

### `owlv2.install()`
Installs OWLv2 Detect into the workspace-local `private/owlv2-detect` checkout if it is not already available.

Returns:

- `libLocation`: path to the local OWLv2 Detect checkout
- `installOk`: logical flag indicating whether the CLI probe succeeded

### `owlv2.available()`
Checks whether the local OWLv2 Detect checkout is available and the CLI responds to `owlv2-detect -h`.

Returns:

- `bool`: logical flag indicating availability
- `missing`: cell array of missing components

### `owlv2.run(input, text, kvargs)`
Runs the default OWLv2 Detect pipeline, which maps to the CLI default `owlv2-detect` entry point.

Use this for general zero-shot detection. The wrapper forwards the required input path(s) and text prompt(s), then appends any optional keyword arguments that are not empty.

### `owlv2.general(input, text, kvargs)`
Runs the explicit `owlv2-detect general ...` CLI subcommand.

This is the same general detection pipeline as `owlv2.run`, but with the subcommand spelled out explicitly.

### `owlv2.blackmarks(input, kvargs)`
Runs the `owlv2-detect black-marks ...` CLI subcommand for pooled video mark detection.

If `kvargs.Text` is omitted, the wrapper uses the default text prompt `black mark`.

## Supported Arguments

The wrapper passes MATLAB keyword arguments through to the CLI and skips empty values.

Common options accepted by `run` and `general`:

- `Crop`: numeric vector with 4 elements, mapped to `-c`
- `Filter`: nested cell array of `{type, value}` pairs, mapped to repeated `-f TYPE VALUE`
- `Model`: Hugging Face model ID, mapped to `-m`
- `BatchSize`: scalar batch size, mapped to `-b`
- `DetectionThreshold`: scalar score threshold, mapped to `--detection-threshold`
- `LogLevel`: log level, mapped to `--log-level`

Options accepted only by `blackmarks`:

- `DurationRange`: numeric vector with 2 elements, mapped to `-r`
- `SampleFrameCount`: scalar frame sample count, mapped to `-s`
- `TopNMarks`: scalar pooled mark count, mapped to `-n`
- `Text`: prompt text used for black-mark detection, mapped to `-t`

## CLI Behavior

The upstream CLI prints JSON results to stdout. When you run the command with `LogLevel = "quiet"` (default), stdout is the JSON payload only, so downstream MATLAB code can decode it directly:

```matlab
[exitCode, stdout] = owlv2.run("path/to/image.png", {"person", "dog"}, LogLevel="quiet");
results = jsondecode(stdout);
```

That `jsondecode(stdout)` call produces a MATLAB struct array for the returned detections.

## Examples

```matlab
[libLocation, installOk] = owlv2.install();

[exitCode, stdout] = owlv2.run("path/to/image.png", {"person", "dog"}, ...
	LogLevel="quiet");

[exitCode, stdout] = owlv2.general("path/to/image.png", {"person", "dog"}, ...
	Crop=[0 0 0 0], ...
	Filter={{"brightness", 0.2}, {"contrast", 0.1}}, ...
	LogLevel="quiet");

[exitCode, stdout] = owlv2.blackmarks("path/to/video.mp4", ...
	Text="black mark", ...
	DurationRange=[0.1 0.9], ...
	SampleFrameCount=8, ...
	TopNMarks=4, ...
	LogLevel="quiet");
```

## Notes

- `owlv2.install()` is safe to call before running any pipeline; it reuses the local checkout once installation has succeeded.
- The wrapper validates the installation by probing `owlv2-detect -h` inside the downloaded repository.
- The CLI output format is an array of JSON objects, so `jsondecode(stdout)` is the simplest way to turn the results into MATLAB data structures.
