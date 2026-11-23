"""Real models through Hugging Face transformers.

- SAM 2.1 (Apache 2.0) for "segment everything", driven by our own loop in
  sam_auto.py rather than the transformers pipeline (see there for why).
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
from .sam_auto import AutoMaskOptions, AutoMaskStats, Predictor, generate_masks


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


def _to_numpy(value: Any) -> np.ndarray:
    if hasattr(value, "detach"):
        value = value.detach().float().cpu().numpy()
    return np.asarray(value)


class _TorchSam2:
    """SAM 2 straight from transformers' Sam2Model, no pipeline."""

    def __init__(self, model: str, device: str):
        try:
            import torch
            from transformers import Sam2Model, Sam2Processor
        except ImportError as error:
            raise ModelUnavailable(
                "The real models need the ml extra: pip install -e '.[ml]' (see backend/README.md)"
            ) from error
        try:
            self.processor = Sam2Processor.from_pretrained(model).image_processor
            self.model = Sam2Model.from_pretrained(model).to(device).eval()
        except Exception as error:  # download or load failure, missing torchvision
            raise ModelUnavailable(f"Could not load {model}: {error}") from error
        self.torch = torch
        self.device = device
        # SAM 2 squashes every photo to this square, so prompts are x and y
        # in 0..1 times this, whatever the photo's shape.
        self.input_side = int(self.processor.size["height"])
        self.embeddings = None

    def set_image(self, image: Image.Image) -> None:
        pixels = self.processor(images=image, return_tensors="pt")["pixel_values"]
        with self.torch.inference_mode():
            self.embeddings = self.model.get_image_embeddings(pixels.to(self.device))

    def predict(self, points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        torch = self.torch
        prompts = torch.from_numpy(points * self.input_side).float().to(self.device)
        prompts = prompts[None, :, None, :]  # one image, n prompts, one point each
        labels = torch.ones(prompts.shape[:3], dtype=torch.int, device=self.device)
        with torch.inference_mode():
            out = self.model(
                image_embeddings=self.embeddings,
                input_points=prompts,
                input_labels=labels,
                multimask_output=True,
            )
        return _to_numpy(out.pred_masks[0]), _to_numpy(out.iou_scores[0])


class SamSegmenter:
    name = "sam2"

    def __init__(
        self,
        model: str = "facebook/sam2.1-hiera-small",
        device: str = "cpu",
        *,
        max_side: int = 1024,
        points_per_batch: int = 16,
        points_per_side: int = 32,
        min_iou: float = 0.75,
        min_stability: float = 0.9,
        predictor: Predictor | None = None,
    ):
        self.model = model
        self.device = device
        self.max_side = max_side
        self.points_per_batch = points_per_batch
        self.points_per_side = points_per_side
        self.min_iou = min_iou
        self.min_stability = min_stability
        self._predictor = predictor
        self._lock = threading.Lock()
        self.last_stats: AutoMaskStats | None = None

    def load(self) -> None:
        """Download and load the weights now instead of on the first photo."""
        with self._lock:
            if self._predictor is None:
                self._predictor = _TorchSam2(self.model, self.device)

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        height, width = image.shape[:2]
        options = AutoMaskOptions(
            points_per_side=self.points_per_side,
            points_per_batch=self.points_per_batch,
            min_iou=self.min_iou,
            min_stability=self.min_stability,
        )
        self.load()
        with self._lock:
            masks, scores = generate_masks(
                self._predictor, _shrink(image, self.max_side), (height, width), options
            )
        self.last_stats = options.stats
        # Scores were already filtered above; clean_masks only shapes surfaces.
        return clean_masks(masks, scores, min_score=0.0)


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
