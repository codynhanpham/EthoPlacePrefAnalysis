# `makeSingleSubjectHdf5` Output Format

Specification of the HDF5 file produced by `sdTable.makeSingleSubjectHdf5`.

The layout is inspired by [anndata](https://anndata.readthedocs.io/) (AnnData): observation metadata under `/obs`, unstructured metadata under `/uns`, and one group per stimulus file holding the subject's time series as compact matrices with categorical stimulus labels.

## Goals

- **Size-optimized**: one contiguous gzip-compressed matrix per data table compresses far better than many small datasets; the repetitive `Stimulus name` column is stored as `int32` codes into a small category list (anndata-style categoricals).
- **Self-describing**: column names, categories, and metadata are stored alongside the data; no external schema is needed to interpret the file.
- **Multi-stimfile aware**: when the input `standardizedTable` is a struct array, the same subject is extracted from every stimfile table where it appears and written as one group per stimfile.

## File layout

```
/                                  (root attributes, see below)
├── obs/                           subject metadata, one scalar dataset per field
│   ├── sex                        string
│   ├── genotype                   string
│   ├── strain                     string
│   ├── age                        double
│   ├── dob                        string, ISO-8601 "yyyy-mm-dd" ("" if NaT)
│   ├── cagecode                   string
│   ├── id                         string
│   └── source                     string
├── uns/                           unstructured metadata
│   ├── fps                        double, standardized framerate
│   ├── px2cm                      double, pixels-to-centimeters factor
│   └── arenaBackground            2D double dataset (only if provided)
└── <stimfileName>/                one group per stimfile where the subject was found
    ├── time                       N×1 double, seconds relative to stimulus onset (0 = onset)
    ├── stimulus                   N×1 int32, zero-based codes into stimulus_categories
    ├── stimulus_categories        C×1 string, unique stimulus names in first-appearance order
    ├── centerpoint                N×4 double matrix (see below)
    ├── centerpoint_columns        4×1 string, column names for centerpoint
    ├── bodyparts                  N×M double matrix (only if present and requested)
    └── bodyparts_columns          M×1 string, column names for bodyparts
```

`<stimfileName>` is the stimfile's base name + extension (e.g. `20260204_Normal-WhiteNoise_27x_[5-10s]ISI_v3.flac`), with any `/` characters replaced by `_`.

When the source `standardizedTable` was produced by `population.temp.joinStdTableByStim`, its `stimfileName` is a cell array of the included stimfile names (e.g. `{"stim-v1.flac"; "stim-v2.flac"}`). In that case the elements are joined with `++` to form the final stimfileName string used for the group name and the `stimfileNames` root attribute — e.g. `stim-v1.flac++stim-v2.flac`. The `StimfileName` filter must likewise use the joined form (a single string with `++`, or a cell array whose elements joined with `++` equal the table's joined name).

## Root attributes

| Attribute | Type | Meaning |
|---|---|---|
| `format_version` | int32 | Format version, currently `1` |
| `created` | string | Write timestamp, `yyyy-MM-dd HH:mm:ss` |
| `stimfileNames` | string | `;`-separated list of stimfiles written as groups |

## Datasets

### `time`

`N×1` double. Trial time in seconds, aligned to stimulus onset at `0` (negative = pre-stimulus). Subsetted to the requested `timeRange` before writing.

### `stimulus` / `stimulus_categories`

The per-frame stimulus label, stored anndata-style: `stimulus` holds `int32` codes (index into `stimulus_categories`, zero-based when read with h5py; 1-based when read with MATLAB `h5read`). Sentinel labels such as `NONE | Pre-Stimulus` and `NONE | Post-Stimulus` appear as ordinary categories.

### `centerpoint` / `centerpoint_columns`

`N×C` double matrix, one column per data variable of the source `centerpointData` table (typically `X center`, `Y center`, `Arena Grid Score`, `Distance from Midline` — the order follows the source table, so always read `centerpoint_columns` rather than assuming an order). Each multi-column variable (one column per subject in the source table) is reduced to the matched subject's single column. Units: centimeters; sign convention: negative = toward `stimuliSorted(1)`, positive = toward `stimuliSorted(2)`.

### `bodyparts` / `bodyparts_columns`

Same structure as `centerpoint`, for the source `bodyparts` table (paired `X <node>` / `Y <node>` columns, e.g. `X Nose`, `Y Nose`). Omitted when the source table is empty or `dataTable` excludes it.

## Storage details

- All numeric data is written as **double** (no precision loss).
- All datasets use **gzip (deflate) compression, level 6**, chunked (~4096 rows per chunk; scalar datasets use 1×1 chunks).
- String datasets are variable-length UTF-8.
- The file is written atomically: data goes to a temporary file which is moved into place only after a successful write.

## MATLAB reading example

```matlab
filePath = 'subject.hdf5';
time = h5read(filePath, '/<stimfileName>/time');
data = h5read(filePath, '/<stimfileName>/centerpoint');   % C×N (transposed)
columns = h5read(filePath, '/<stimfileName>/centerpoint_columns');
codes = h5read(filePath, '/<stimfileName>/stimulus');      % 1-based codes
categories = h5read(filePath, '/<stimfileName>/stimulus_categories');
stimNames = categories(codes);
```

Note: MATLAB `h5write`/`h5read` use HDF5 dimension order, so an `N×C` MATLAB matrix is stored as a `C×N` HDF5 dataset; transpose after reading. The `matlab_orientation` attribute on each matrix dataset documents this (`rows=frames, cols=variables` in MATLAB orientation).

## Matching semantics

The subject is located in each stimfile's `animalMetadata` dictionary by **exact equality on all 8 required fields** (`sex`, `genotype`, `strain`, `age`, `dob`, `cagecode`, `id`, `source`); strings compare case-sensitively, `datetime` values with `isequal` (NaT matches NaT). Dictionary key order matches the multi-column variable column order. Stimfile tables where the subject is absent are skipped; an error is raised only if the subject is found in none of the selected tables.
