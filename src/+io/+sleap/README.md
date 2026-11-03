# SLEAP I/O

This module provides a convenient interface installing and using [SLEAP](https://sleap.ai/) for pose estimation and tracking.

Additional features are provided for enhanced performance:

- Worker spawning for parallel processing when resources are available.
- Improved TensorRT model exporter to flexibly handle RGB to Grayscale conversion in the same model, you no longer need a dedicated preprocessing step.

## One-Command Installation

With this namespace added to MATLAB's session path, you can install SLEAP and its dependencies with a single command:

```matlab
io.sleap.install()
```

To install optional `sleap-nn` [runtimes/exporters](https://nn.sleap.ai/v0.3.5/reference/cli/#sleap-nn-export), you can specify them with the `NNExport` argument with one of the following options:
- `onnx-cpu` : Install ONNX export dependencies for CPU
- `onnx-gpu` : Install ONNX export dependencies for GPU
- `tensorrt` : Install TensorRT export dependencies for GPU

`sleap-nn` will prefer `tensorrt` if available, otherwise it will fall back to `onnx-gpu` or `onnx-cpu` depending on your system.

```matlab
io.sleap.install('NNExport', 'tensorrt')
```

## Upgrading SLEAP

When there are upstream updates to SLEAP and the pinned dependency versions in [`install.m`](./install.m) is bumped, you can upgrade to the latest version simply by running the install command again. This will uninstall the previous version and install the latest version. Previously selected `NNExport` options will be preserved.

```matlab
io.sleap.install()
```

## Launching SLEAP GUI

This module is mainly used for programmatic integration of SLEAP into MATLAB workflows, but you can also launch the SLEAP GUI (for annotation) from MATLAB with:

```matlab
io.sleap.gui()
```
