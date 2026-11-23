"""What every model has to provide. Real models (SAM, Depth Anything and so
on) implement the same interfaces as the fake ones, so the API and the app
don't change when a model is swapped."""

from dataclasses import dataclass
from typing import Protocol

import numpy as np


@dataclass
class MaskResult:
    name: str
    label: str | None
    score: float
    mask: np.ndarray  # bool, height x width


@dataclass
class DepthResult:
    # float32, height x width. Relative only: larger means closer, the scale
    # means nothing on its own.
    depth: np.ndarray


class Segmenter(Protocol):
    name: str

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        """Finds surfaces in an RGB image (height x width x 3, uint8)."""
        ...


class DepthEstimator(Protocol):
    name: str

    def estimate(self, image: np.ndarray) -> DepthResult:
        """Estimates relative depth for an RGB image."""
        ...
