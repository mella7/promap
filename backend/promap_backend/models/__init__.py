"""Model interfaces and the implementations behind them."""

from .base import DepthEstimator, DepthResult, MaskResult, Segmenter
from .registry import load_depth, load_segmenter

__all__ = [
    "DepthEstimator",
    "DepthResult",
    "MaskResult",
    "Segmenter",
    "load_depth",
    "load_segmenter",
]
