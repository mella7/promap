"""Picks model implementations by name, as set in the environment."""

from collections.abc import Callable

from ..config import Settings
from .base import DepthEstimator, Segmenter
from .fake import FakeDepth, FakeSegmenter
from .hf import DepthAnythingEstimator, SamSegmenter
from .planes import MixedSegmenter, PlaneSegmenter

_DEPTH: dict[str, Callable[[Settings], DepthEstimator]] = {
    "fake": lambda s: FakeDepth(),
    "depth_anything_v2": lambda s: DepthAnythingEstimator(s.depth_model, s.device),
}


def _sam(s: Settings) -> SamSegmenter:
    return SamSegmenter(
        s.sam_model,
        s.device,
        max_side=s.model_max_side,
        points_per_batch=s.points_per_batch,
        points_per_side=s.sam_points_per_side,
        min_iou=s.sam_min_iou,
        min_stability=s.sam_min_stability,
    )


# Segmenters get the depth model too, since "planes" finds surfaces in depth.
_SEGMENTERS: dict[str, Callable[[Settings, DepthEstimator], Segmenter]] = {
    "fake": lambda s, d: FakeSegmenter(),
    "sam2": lambda s, d: _sam(s),
    "planes": lambda s, d: PlaneSegmenter(d),
    "sam2_planes": lambda s, d: MixedSegmenter(PlaneSegmenter(d), _sam(s)),
}


def load_depth(settings: Settings) -> DepthEstimator:
    try:
        return _DEPTH[settings.depth](settings)
    except KeyError:
        raise ValueError(
            f"Unknown depth model '{settings.depth}', choose from {sorted(_DEPTH)}"
        ) from None


def load_segmenter(settings: Settings, depth: DepthEstimator | None = None) -> Segmenter:
    """depth: share the server's depth model instead of loading a second one."""
    try:
        make = _SEGMENTERS[settings.segmenter]
    except KeyError:
        raise ValueError(
            f"Unknown segmenter '{settings.segmenter}', choose from {sorted(_SEGMENTERS)}"
        ) from None
    return make(settings, depth if depth is not None else load_depth(settings))
