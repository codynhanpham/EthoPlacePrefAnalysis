"""Direct Python API export for SLEAP-NN top-down models.

This module mirrors the SLEAP-NN export CLI, but calls the Python API
directly so you can export a centroid model + centered-instance model as
both ONNX and TensorRT in one function.

This is a temporary workaround for SLEAP-NN >=0.2.0 and <0.3.0

The main fix for the TensorRT build issue is to make the workspace size
configurable and default it to a larger value than the CLI default.

SLEAP-NN >=0.3.0 exposes `--workspace-size-gb` as a CLI argument, and the unified Predictor API will simplifies things further, so this module will be removed or become deprecated in a future release.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from typing import Optional, Sequence

import torch
from torch import nn


DEFAULT_WORKSPACE_GB = 8.0


class RGBTopDownONNXWrapper(nn.Module):
	"""Adapter that accepts RGB input and converts it to grayscale."""

	def __init__(self, base_wrapper):
		super().__init__()
		self.base_wrapper = base_wrapper

	@staticmethod
	def _rgb_to_grayscale(image):
		if image.shape[-3] != 3:
			return image
		if image.dtype != torch.float32:
			image = image.float()
		r = image[:, 0:1]
		g = image[:, 1:2]
		b = image[:, 2:3]
		return 0.2989 * r + 0.5870 * g + 0.1140 * b

	def forward(self, image):
		return self.base_wrapper.forward(self._rgb_to_grayscale(image))


def _as_path(path: str | Path) -> Path:
	return path if isinstance(path, Path) else Path(path)


def _hash_file(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def _save_training_config(cfg, export_dir: Path, filename: str) -> Path:
	from omegaconf import OmegaConf

	path = export_dir / filename
	OmegaConf.save(cfg, path)
	return path


def export_topdown_tensorrt(
	centroid_model_dir: str | Path,
	centered_instance_model_dir: str | Path,
	output_dir: str | Path | None = None,
	*,
	device: str = "cuda",
	precision: str = "fp16",
	workspace_size_gb: Optional[float] = DEFAULT_WORKSPACE_GB,
	accept_rgb: bool = True,
	max_instances: int = 10,
	max_batch_size: int = 16,
	input_scale: Optional[float] = None,
	input_height: Optional[int] = None,
	input_width: Optional[int] = None,
	crop_size: Optional[int] = None,
	opset_version: int = 17,
	verify: bool = True,
) -> Path:
	"""Export a top-down SLEAP-NN model bundle to ONNX and TensorRT.

	Args:
		centroid_model_dir: Directory containing the centroid checkpoint.
		centered_instance_model_dir: Directory containing the centered-instance
			checkpoint.
		output_dir: Directory where ``model.onnx`` and ``model.trt`` will be
			written. Defaults to ``<centroid_model_dir>/exported_topdown``.
		device: Torch device for export, usually ``"cuda"``.
		precision: TensorRT precision. ``"fp16"`` is recommended here.
		workspace_size_gb: TensorRT builder workspace size in GiB.
		accept_rgb: If True, export a graph that accepts 3-channel RGB input and
			converts it to grayscale inside the model.
		max_instances: Maximum instances per frame.
		max_batch_size: Maximum batch size used in the TensorRT profile.
		input_scale: Optional override for both models' input scaling.
		input_height: Optional export input height override.
		input_width: Optional export input width override.
		crop_size: Optional square crop size override.
		opset_version: ONNX opset version.
		verify: Run ONNX export verification.

	Returns:
		The output directory path.
	"""

	import torch

	from sleap_nn.export.cli import _load_lightning_model
	from sleap_nn.export.exporters import export_to_onnx, export_to_tensorrt
	from sleap_nn.export.metadata import build_base_metadata
	from sleap_nn.export.utils import (
		load_training_config,
		resolve_anchor_part,
		resolve_backbone_type,
		resolve_crop_size,
		resolve_edge_inds,
		resolve_input_scale,
		resolve_input_shape,
		resolve_model_type,
		resolve_node_names,
		resolve_output_stride,
	)
	from sleap_nn.export.wrappers import TopDownONNXWrapper

	if not torch.cuda.is_available():
		raise RuntimeError("TensorRT export requires a CUDA-capable NVIDIA GPU.")

	precision = precision.lower().strip()
	if precision not in {"fp16", "fp32", "tf32"}:
		raise ValueError("precision must be one of: fp16, fp32, tf32")

	centroid_path = _as_path(centroid_model_dir)
	instance_path = _as_path(centered_instance_model_dir)
	export_dir = _as_path(output_dir) if output_dir is not None else centroid_path / "exported_topdown"
	export_dir.mkdir(parents=True, exist_ok=True)

	centroid_cfg = load_training_config(centroid_path)
	instance_cfg = load_training_config(instance_path)

	centroid_model_type = resolve_model_type(centroid_cfg)
	instance_model_type = resolve_model_type(instance_cfg)
	if centroid_model_type != "centroid":
		raise ValueError(f"Expected centroid model directory, got {centroid_model_type!r}.")
	if instance_model_type != "centered_instance":
		raise ValueError(
			f"Expected centered_instance model directory, got {instance_model_type!r}."
		)

	centroid_ckpt = centroid_path / "best.ckpt"
	instance_ckpt = instance_path / "best.ckpt"
	if not centroid_ckpt.exists():
		raise FileNotFoundError(f"Checkpoint not found: {centroid_ckpt}")
	if not instance_ckpt.exists():
		raise FileNotFoundError(f"Checkpoint not found: {instance_ckpt}")

	centroid_backbone = resolve_backbone_type(centroid_cfg)
	instance_backbone = resolve_backbone_type(instance_cfg)

	centroid_model = _load_lightning_model(
		model_type="centroid",
		backbone_type=centroid_backbone,
		cfg=centroid_cfg,
		ckpt_path=centroid_ckpt,
		device=device,
	).model
	instance_model = _load_lightning_model(
		model_type="centered_instance",
		backbone_type=instance_backbone,
		cfg=instance_cfg,
		ckpt_path=instance_ckpt,
		device=device,
	).model

	centroid_model.eval().to(device)
	instance_model.eval().to(device)

	centroid_config_path = _save_training_config(
		centroid_cfg, export_dir, "training_config_centroid.yaml"
	)
	instance_config_path = _save_training_config(
		instance_cfg, export_dir, "training_config_centered_instance.yaml"
	)

	centroid_scale = input_scale if input_scale is not None else resolve_input_scale(centroid_cfg)
	instance_scale = input_scale if input_scale is not None else resolve_input_scale(instance_cfg)
	centroid_stride = resolve_output_stride(centroid_cfg, "centroid")
	instance_stride = resolve_output_stride(instance_cfg, "centered_instance")

	resolved_crop = (crop_size, crop_size) if crop_size is not None else resolve_crop_size(instance_cfg)
	if resolved_crop is None:
		raise ValueError(
			"Top-down export requires crop_size. Pass crop_size or set it in the instance config."
		)

	node_names = resolve_node_names(instance_cfg, "centered_instance")
	edge_inds = resolve_edge_inds(instance_cfg, node_names)

	base_wrapper = TopDownONNXWrapper(
		centroid_model=centroid_model,
		instance_model=instance_model,
		max_instances=max_instances,
		crop_size=resolved_crop,
		centroid_output_stride=centroid_stride,
		instance_output_stride=instance_stride,
		centroid_input_scale=centroid_scale,
		instance_input_scale=instance_scale,
		n_nodes=len(node_names),
	)
	wrapper = RGBTopDownONNXWrapper(base_wrapper) if accept_rgb else base_wrapper
	wrapper.eval().to(device)

	input_shape = resolve_input_shape(
		centroid_cfg,
		input_height=input_height,
		input_width=input_width,
	)
	_, channels, height, width = input_shape
	if accept_rgb:
		channels = 3
		input_shape = (1, channels, height, width)
		if hasattr(base_wrapper.centroid_model, "model"):
			base_wrapper.centroid_model.model = base_wrapper.centroid_model.model.to(device)
		if hasattr(base_wrapper.instance_model, "model"):
			base_wrapper.instance_model.model = base_wrapper.instance_model.model.to(device)

	model_name = f"{centroid_path.name}+{instance_path.name}"
	checkpoint_path = f"centroid:{centroid_ckpt};centered_instance:{instance_ckpt}"
	backbone = (
		f"centroid:{centroid_backbone};centered_instance:{instance_backbone}"
	)
	anchor_part = resolve_anchor_part(centroid_cfg, "centroid")
	training_config_hash = (
		f"centroid:{_hash_file(centroid_config_path)};"
		f"centered_instance:{_hash_file(instance_config_path)}"
	)

	onnx_path = export_dir / "model.onnx"
	export_to_onnx(
		wrapper,
		onnx_path,
		input_shape=input_shape,
		input_dtype=torch.uint8,
		opset_version=opset_version,
		output_names=[
			"centroids",
			"centroid_vals",
			"peaks",
			"peak_vals",
			"instance_valid",
		],
		verify=verify,
	)

	onnx_metadata = build_base_metadata(
		export_format="onnx",
		model_type="topdown",
		model_name=model_name,
		checkpoint_path=checkpoint_path,
		backbone=backbone,
		n_nodes=len(node_names),
		n_edges=len(edge_inds),
		node_names=node_names,
		edge_inds=edge_inds,
		input_scale=centroid_scale,
		input_channels=channels,
		output_stride=instance_stride,
		crop_size=resolved_crop,
		max_instances=max_instances,
		max_batch_size=max_batch_size,
		precision="fp32",
		training_config_hash=training_config_hash,
		training_config_embedded=False,
		input_dtype="uint8",
		normalization="0_to_1",
		peak_threshold=0.2,
		anchor_part=anchor_part,
	)
	onnx_metadata.save(export_dir / "export_metadata.json")

	workspace_gb = DEFAULT_WORKSPACE_GB if workspace_size_gb is None else workspace_size_gb
	trt_workspace_bytes = int(workspace_gb * (1 << 30))
	export_to_tensorrt(
		wrapper,
		export_dir / "model.trt",
		input_shape=input_shape,
		input_dtype=torch.uint8,
		precision=precision,
		max_shape=(max_batch_size, channels, height * 2, width * 2),
		workspace_size=trt_workspace_bytes,
		verbose=True,
	)

	trt_metadata = build_base_metadata(
		export_format="tensorrt",
		model_type="topdown",
		model_name=model_name,
		checkpoint_path=checkpoint_path,
		backbone=backbone,
		n_nodes=len(node_names),
		n_edges=len(edge_inds),
		node_names=node_names,
		edge_inds=edge_inds,
		input_scale=centroid_scale,
		input_channels=channels,
		output_stride=instance_stride,
		crop_size=resolved_crop,
		max_instances=max_instances,
		max_batch_size=max_batch_size,
		precision=precision,
		training_config_hash=training_config_hash,
		training_config_embedded=False,
		input_dtype="uint8",
		normalization="0_to_1",
		peak_threshold=0.2,
		anchor_part=anchor_part,
	)
	trt_metadata.save(export_dir / "model.trt.metadata.json")

	return export_dir


def build_parser() -> argparse.ArgumentParser:
	parser = argparse.ArgumentParser(
		description="Export a SLEAP-NN top-down model bundle to ONNX and TensorRT.",
	)
	parser.add_argument("centroid_model_dir", nargs="?", help="Centroid model directory")
	parser.add_argument(
		"centered_instance_model_dir",
		nargs="?",
		help="Centered-instance model directory",
	)
	parser.add_argument("-o", "--output-dir", default=None, help="Export output directory")
	parser.add_argument("--device", default="cuda", help="Torch device, usually cuda")
	parser.add_argument(
		"--precision",
		default="fp16",
		choices=["fp16", "fp32", "tf32"],
		help="TensorRT precision",
	)
	parser.add_argument(
		"--workspace-size-gb",
		type=float,
		default=DEFAULT_WORKSPACE_GB,
		help="TensorRT builder workspace size in GiB",
	)
	parser.add_argument("--max-instances", type=int, default=20)
	parser.add_argument("--max-batch-size", type=int, default=8)
	parser.add_argument("--input-scale", type=float, default=None)
	parser.add_argument("--input-height", type=int, default=None)
	parser.add_argument("--input-width", type=int, default=None)
	parser.add_argument("--crop-size", type=int, default=None)
	parser.add_argument("--no-accept-rgb", action="store_true", help="Keep a 1-channel export")
	parser.add_argument("--opset-version", type=int, default=17)
	parser.add_argument("--no-verify", action="store_true", help="Skip ONNX verification")
	return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
	parser = build_parser()
	args = parser.parse_args(argv)

	if not args.centroid_model_dir or not args.centered_instance_model_dir:
		parser.print_help()
		return 0

	export_dir = export_topdown_tensorrt(
		args.centroid_model_dir,
		args.centered_instance_model_dir,
		args.output_dir,
		device=args.device,
		precision=args.precision,
		workspace_size_gb=args.workspace_size_gb,
		accept_rgb=not args.no_accept_rgb,
		max_instances=args.max_instances,
		max_batch_size=args.max_batch_size,
		input_scale=args.input_scale,
		input_height=args.input_height,
		input_width=args.input_width,
		crop_size=args.crop_size,
		opset_version=args.opset_version,
		verify=not args.no_verify,
	)
	print(f"Exported to: {export_dir}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
