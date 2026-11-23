"""Picks model implementations by name, as set in the environment."""

from collections.abc import Callable

from ..config import Settings
from .base import DepthEstimator, Segmenter
from .fake import FakeDepth, FakeSegmenter
from .hf import DepthAnythingEstimator, SamSegmenter

_SEGMENTERS: dict[str, Callable[[Settings], Segmenter]] = {
    "fake": lambda s: FakeSegmenter(),
    "sam2": lambda s: SamSegmenter(
        s.sam_model,
        s.device,
        max_side=s.model_max_side,
        points_per_batch=s.points_per_batch,
        points_per_side=s.sam_points_per_side,
    ),
}
_DEPTH: dict[str, Callable[[Settings], DepthEstimator]] = {
    "fake": lambda s: FakeDepth(),
    "depth_anything_v2": lambda s: DepthAnythingEstimator(s.depth_model, s.device),
}


def load_segmenter(settings: Settings) -> Segmenter:
    try:
        return _SEGMENTERS[settings.segmenter](settings)
    except KeyError:
        raise ValueError(
            f"Unknown segmenter '{settings.segmenter}', choose from {sorted(_SEGMENTERS)}"
        ) from None


def load_depth(settings: Settings) -> DepthEstimator:
    try:
        return _DEPTH[settings.depth](settings)
    except KeyError:
        raise ValueError(
            f"Unknown depth model '{settings.depth}', choose from {sorted(_DEPTH)}"
        ) from None
