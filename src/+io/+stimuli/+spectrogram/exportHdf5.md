# `exportHdf5` Output Format

Specification of the HDF5 file produced by `io.stimuli.spectrogram.exportHdf5`.

The layout follows the repository's HDF5 conventions (see
[`makeSingleSubjectHdf5.md`](../../modules/PopulationAnalysis/+sdTable/makeSingleSubjectHdf5.md)):
anndata-flavored unstructured metadata under `/uns`, gzip (deflate) compression, chunked
datasets, `hdf5_axis_order` attributes, and MATLAB axis reversal on disk so external
readers see rows = time frames.

## Goals

- **Compact**: spectrograms are stored quantized (uint8 dB by default, as produced by
  `precompute`), yielding files smaller than the raw audio.
- **Self-describing**: the shared DSP configuration lives under `/uns`, per-dataset
  attributes carry units/quantization, and group names carry the stimulus identity.
- **Pixel-space decoupled**: the full time × frequency grid is stored as data; zooming
  and rendering happen downstream (`io.stimuli.spectrogram.plot`).
- **Multi-stimulus**: many stimuli (and multi-channel stimuli) share one file when their
  DSP configuration matches.

## File layout

```
/                                      (root attributes, see below)
├── uns/                               shared DSP configuration (all databases identical)
│   ├── fs                             double, sample rate (Hz)
│   ├── hop_samples                    double, STFT hop in samples
│   ├── window_samples                 double, Hann window length in samples
│   ├── overlap_ratio                  double, 1 - hop/window
│   ├── nfft                           double, FFT length (= window_samples)
│   ├── db_floor                       double, dB of quantization level 0
│   ├── db_step                        double, dB per uint8 level (-db_floor/255)
│   ├── display_floor_percentile       double, percentile used for the noise-floor hint
│   ├── window_function                string, "hann"
│   ├── channel_mode                   string, "all" or "mono"
│   ├── precision                      string, "uint8" | "single" | "double"
│   └── reference                      string, "peak"
└── <stimfileName>/                    one group per source stimulus file
    └── <title>/                       one group per unique stimulus title
        ├── time                       F×1 double, frame-center times (s, segment start = 0)
        ├── frequency                  B×1 double, bin centers (Hz), 0..Nyquist inclusive
        ├── spectrogram                F×B×C array, quantized dB (see below)
        ├── display_floor              C×1 double, per-channel noise-floor hint (dB)
        ├── amplitude_rms              F×C double
        ├── amplitude_peak             F×C double
        ├── amplitude_min              F×C double
        └── amplitude_max              F×C double
```

`F` = time frames, `B` = frequency bins (`nfft/2 + 1`), `C` = channels of that stimulus.
Channel counts and durations may differ between stimuli; the DSP configuration must not.

`<stimfileName>` is the audio file's base name + extension (e.g.
`20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac`), with `/` replaced by `_`.
`<title>` is the stimulus chapter title (also `/`-sanitized); a missing title becomes
`untitled`.

## Root attributes

| Attribute | Type | Meaning |
|---|---|---|
| `format_version` | int32 | Format version, currently `1` |
| `created` | string | Write timestamp, `yyyy-MM-dd HH:mm:ss` |
| `hdf5_layout` | string | Always `"spectrogramdb"` |
| `stimfileNames` | string | `;`-separated unique stimfile names written as groups |

## `spectrogram` dataset and quantization

- Written so external readers (h5py) see shape `(F, B, C)`: dimension 1 = time frames,
  dimension 2 = frequency bins, dimension 3 = channels
  (`hdf5_axis_order = "dim1=time frames, dim2=frequency bins, dim3=channels"`).
- With `precision = "uint8"` (default): values are quantized dB levels, 0..255, where
  `dB = db_floor + level * db_step` and `0 dB` = the global peak of that database. The
  dataset carries `units = "dB"`, `reference = "peak"`, and a `quantization` attribute.
  All-silent data is stored at level 0 (the floor), not at full scale.
- With `precision = "single"` / `"double"`: values are dB floats relative to the peak,
  with all-silent data stored as `-Inf`.

### `display_floor`

Per-channel noise-floor estimate (the `DisplayFloorPercentile` percentile of that
stimulus's dB values). Viewers should use `[display_floor(c), 0]` as default color
limits so quiet areas render white (`io.stimuli.spectrogram.plot` does this, with a
live slider).

## Storage details

- All datasets use **gzip (deflate) compression, level 6**, chunked along the time
  axis (≈2^18 elements per spectrogram chunk; ≈4096 rows for vectors/matrices).
- Amplitudes are stored as **double**; `time`/`frequency`/`display_floor` as double
  vectors; strings as variable-length UTF-8.
- The file is written atomically: data goes to a temporary file which is moved into
  place only after a successful write. An existing file is an error unless
  `'Overwrite', true` is passed.

## MATLAB reading example

```matlab
filePath = 'spectrograms.hdf5';
time = h5read(filePath, '/<stimfileName>/<title>/time');          % 1×F -> F×1
time = time(:);
frequency = h5read(filePath, '/<stimfileName>/<title>/frequency');
frequency = frequency(:);
specRaw = h5read(filePath, '/<stimfileName>/<title>/spectrogram'); % C×B×F
spec = permute(specRaw, [2, 3, 1]);   % -> B×F×C (bins x time x channels)
dbFloor = h5read(filePath, '/uns/db_floor');
dbStep = h5read(filePath, '/uns/db_step');
spectrogramDb = dbFloor + double(spec) * dbStep;                   % dB, rel. peak
amp = h5read(filePath, '/<stimfileName>/<title>/amplitude_rms');   % C×F
amp = amp.';                                                       % -> F×C
displayFloor = h5read(filePath, '/<stimfileName>/<title>/display_floor');
```

The raw HDF5 shapes are `time (F, 1)`, `frequency (B, 1)`, `display_floor (C, 1)`,
`spectrogram (F, B, C)`, and amplitudes `(F, C)`. MATLAB `h5read` returns the reversed
axis order, hence the reshapes/transposes above.

## Python (h5py) reading example

```python
import h5py
with h5py.File("spectrograms.hdf5", "r") as f:
    group = f["<stimfileName>/<title>"]
    time = group["time"][()]              # (F,)
    frequency = group["frequency"][()]    # (B,)
    spec = group["spectrogram"][()]       # (F, B, C)
    db = f["uns/db_floor"][()] + spec.astype(float) * f["uns/db_step"][()]
    amp = group["amplitude_rms"][()]      # (F, C)
```

## Matching semantics

- All databases in one export must match exactly on `fs`, hop, window, `nfft`, window
  function, channel mode, precision, `db_floor`, and `db_step` (numeric via `isequal`,
  strings case-insensitively). On mismatch the export fails with
  `io:stimuli:spectrogram:exportHdf5:ConfigMismatch` and the databases should be saved
  as separate files.
- Each `(stimfileName, title)` pair must be unique within one file
  (`DuplicateGroup` error).
- The output file must not exist unless `'Overwrite', true` is passed (`FileExists`).
