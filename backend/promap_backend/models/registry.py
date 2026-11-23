"""Picks model implementations by name, as set in the environment."""

from .base import DepthEstimator, Segmenter
from .fake import FakeDepth, FakeSegmenter

_SEGMENTERS = {"fake": FakeSegmenter}
_DEPTH = {"fake": FakeDepth}


def load_segmenter(name: str) -> Segmenter:
    try:
        return _SEGMENTERS[name]()
    except KeyError:
        raise ValueError(f"Unknown segmenter '{name}', choose from {sorted(_SEGMENTERS)}") from None


def load_depth(name: str) -> DepthEstimator:
    try:
        return _DEPTH[name]()
    except KeyError:
        raise ValueError(f"Unknown depth model '{name}', choose from {sorted(_DEPTH)}") from None
