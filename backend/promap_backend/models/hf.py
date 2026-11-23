"""Real models through Hugging Face transformers.

- SAM 2.1 (Apache 2.0) for "segment everything".
- Depth Anything V2 Small (Apache 2.0) for relative depth.

Both load lazily on first use, so the server starts fast and the fake
models still work without torch installed. Only one inference runs per
model at a time; on a small GPU or a laptop CPU two at once would only
fight over memory.
"""

import threading
from collections.abc import Callable
from typing import Any

import numpy as np
from PIL import Image

from .base import DepthResult, MaskResult
from .postprocess import clean_masks


class ModelUnavailable(RuntimeError):
    """The model can't run here, usually because the ml extra isn't installed."""


def _pipeline(task: str, model: str, device: str) -> Callable[..., Any]:
    try:
        from transformers import pipeline
    except ImportError as error:
        raise ModelUnavailable(
            "The real models need the ml extra: pip install -e '.[ml]' (see backend/README.md)"
        ) from error
    try:
        return pipeline(task, model=model, device=device)
    except Exception as error:  # download or load failure
        raise ModelUnavailable(f"Could not load {model}: {error}") from error


def _shrink(image: np.ndarray, max_side: int) -> Image.Image:
    pil = Image.fromarray(image)
    width, height = pil.size
    scale = max_side / max(width, height)
    if scale >= 1:
        return pil
    return pil.resize((round(width * scale), round(height * scale)), Image.Resampling.BILINEAR)


def _to_list(values: Any) -> list[float]:
    if values is None:
        return []
    if hasattr(values, "tolist"):
        values = values.tolist()
    return [float(v) for v in values]


def _to_numpy(value: Any) -> np.ndarray:
    if hasattr(value, "detach"):
        value = value.detach().cpu().numpy()
    return np.asarray(value)


class SamSegmenter:
    name = "sam2"

    def __init__(
        self,
        model: str = "facebook/sam2.1-hiera-small",
        device: str = "cpu",
        *,
        max_side: int = 1024,
        points_per_batch: int = 64,
        points_per_side: int = 32,
        generator: Callable[..., Any] | None = None,
    ):
        self.model = model
        self.device = device
        self.max_side = max_side
        self.points_per_batch = points_per_batch
        self.points_per_side = points_per_side
        self._generator = generator
        self._lock = threading.Lock()

    def load(self) -> None:
        """Download and load the weights now instead of on the first photo."""
        with self._lock:
            if self._generator is None:
                self._generator = _pipeline("mask-generation", self.model, self.device)

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        height, width = image.shape[:2]
        small = _shrink(image, self.max_side)
        self.load()
        with self._lock:
            # SAM drops a points_per_side x points_per_side grid of prompts on
            # the photo. The time grows with the square, so 16 is about 4x
            # faster than 32 and still finds walls, boards and boxes.
            output = self._generator(
                small,
                points_per_batch=self.points_per_batch,
                points_per_crop=self.points_per_side,
            )

        masks = []
        for raw in output["masks"]:
            mask = _to_numpy(raw).astype(bool)
            mask = np.squeeze(mask)
            if mask.shape != (height, width):
                resized = Image.fromarray(mask.astype(np.uint8) * 255).resize(
                    (width, height), Image.Resampling.NEAREST
                )
                mask = np.asarray(resized) > 127
            masks.append(mask)
        scores = _to_list(output.get("scores"))
        if len(scores) != len(masks):
            scores = [1.0] * len(masks)
        return clean_masks(masks, scores)


class DepthAnythingEstimator:
    name = "depth_anything_v2"

    def __init__(
        self,
        model: str = "depth-anything/Depth-Anything-V2-Small-hf",
        device: str = "cpu",
        *,
        estimator: Callable[..., Any] | None = None,
    ):
        self.model = model
        self.device = device
        self._estimator = estimator
        self._lock = threading.Lock()

    def load(self) -> None:
        """Download and load the weights now instead of on the first photo."""
        with self._lock:
            if self._estimator is None:
                self._estimator = _pipeline("depth-estimation", self.model, self.device)

    def estimate(self, image: np.ndarray) -> DepthResult:
        height, width = image.shape[:2]
        self.load()
        with self._lock:
            output = self._estimator(Image.fromarray(image))

        # Depth Anything predicts relative inverse depth: larger is closer,
        # which is what the API promises.
        depth = np.squeeze(_to_numpy(output["predicted_depth"])).astype(np.float32)
        if depth.shape != (height, width):
            depth = np.asarray(
                Image.fromarray(depth, mode="F").resize((width, height), Image.Resampling.BICUBIC),
                dtype=np.float32,
            )
        return DepthResult(depth=depth)
