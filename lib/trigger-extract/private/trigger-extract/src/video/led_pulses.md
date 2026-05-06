# LED Pulse Extraction

LED- (signal intensity-) based trigger extraction from video sources.

## What This Detector Does

The detector estimates when an LED turns ON and OFF in a video by:

1. Reading a region of interest (ROI) where the LED appears.
2. Converting ROI intensity into a dF/F0-like signal.
3. Building robust thresholds from a calibration trace.
4. Detecting ON and OFF transitions with a state machine.
5. Refining event boundaries with a micro-scan near each trigger point.

Output is a list of events:

- `on_frame`, `off_frame` (1-based indexing)
- `on_time`, `off_time` (seconds)

The detector supports both pulse polarities:

- `PulsePolarity::OnPulses` (default): baseline is OFF, pulses go ON.
- `PulsePolarity::OffPulses`: baseline is ON, pulses go OFF.


## High-Level Pipeline

The detector utilize the OpenCV backend for video decoding and ROI extraction, with multithreading support.

### Pass 1: Sparse Sampling

- Compute baseline intensity over `baseline_frames_range`.
- Compute **macro** sampled trace using `scan_step_size`.
- Compute threshold calibration trace using `threshold_calibration_step_size`.

This keeps detection speed high while allowing stable threshold statistics.

### Pass 2: Threshold Calibration

From the threshold calibration trace:

1. Compute percentile baseline offset.
2. Re-center both traces around that baseline.
3. Recompute percentile cut on the recentered calibration trace.
4. Estimate baseline sigma from values below/at that cut.
5. Compute thresholds:
   - `t_trigger = max(std_threshold * sigma, absolute_dff_threshold)`
   - `t_rise_noise = std_noise_floor * sigma`

### Pass 3: Event Detection + Boundary Refinement

- State machine toggles between SEARCHING_ON and SEARCHING_OFF.
- Macro samples find candidate transitions.
- Micro-scan refines exact boundary in a local window of size `scan_step_size`.
- OFF threshold is adaptive while searching OFF:
   - `on_level_mu = 0.9 * on_level_mu + 0.1 * current_dff`
   - `t_fall_noise = on_level_mu - std_noise_floor * sigma`
- If signal remains ON at video end, event is closed at final frame.

## Decode Modes

`DecodeMode::SparseSeek`

- Uses repeated `CAP_PROP_POS_FRAMES` seeks for macro and micro windows.
- Often good on intra-frame-heavy or seek-friendly media.
- Usually performs well on short videos or when seeking is fast or on long videos with long pulses.

`DecodeMode::StreamingRing`

- Reads forward once from `start_macro - scan_step_size` with a ring buffer.
- Avoids most backward seeks and is often better on compressed GOP video.
- May be necessary if seeking is very slow or if short pulses are missed with sparse seeks.

## Options and Defaults

Current defaults from `Options::default()`:

- `roi_x_range = (0.4375, 0.5625)`
- `roi_y_range = (0.08, 0.215)`
- `decode_mode = DecodeMode::SparseSeek`
- `pulse_polarity = PulsePolarity::OnPulses`
- `scan_step_size = 60 * 30` (1800 frames)
- `threshold_calibration_step_size = 2 * 30` (60 frames)
- `baseline_frames_range = (30*60*1/2-1, 30*60*2-1)` (899..3599, 0-based)
- `std_threshold = 6.5`
- `std_noise_floor = 5.0`
- `baseline_percentile = 10.0`
- `absolute_dff_threshold = 0.001`

Notes on defaults:

- The default `scan_step_size` is intentionally large and favors speed over short-pulse sensitivity. This works well on long videos with long pulses, but may miss short pulses. Adjust as needed.
- Baseline frame range is interpreted as 0-based frame indices and clamped to video length.
