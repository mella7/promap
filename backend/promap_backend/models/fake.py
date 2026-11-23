"""Fake models with fixed answers, for building and testing the app.

The shapes are placed as fractions of the image so they line up with the
app's scan simulator (a box in the middle of a wall), whatever the image
size.
"""

import numpy as np

from .base import DepthResult, MaskResult

# (name, label, left, top, right, bottom) as fractions of width and height.
# These match the box and wall patches in the simulator's 480x360 camera.
FAKE_SURFACES = [
    ("Box top", "box", 210 / 480, 130 / 360, 290 / 480, 210 / 360),
    ("Left wall", "wall", 60 / 480, 60 / 360, 180 / 480, 300 / 360),
    ("Right wall", "wall", 310 / 480, 70 / 360, 400 / 480, 290 / 360),
]

# Where the simulator's box is, as fractions of the camera image.
FAKE_BOX = (200 / 480, 120 / 360, 300 / 480, 220 / 360)


def _rect(width: int, height: int, left: float, top: float, right: float, bottom: float):
    mask = np.zeros((height, width), dtype=bool)
    x0, x1 = round(left * width), round(right * width)
    y0, y1 = round(top * height), round(bottom * height)
    mask[y0:y1, x0:x1] = True
    return mask


class FakeSegmenter:
    name = "fake"

    def load(self) -> None:
        pass

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        height, width = image.shape[:2]
        return [
            MaskResult(name=name, label=label, score=0.9, mask=_rect(width, height, *box))
            for name, label, *box in FAKE_SURFACES
        ]


class FakeDepth:
    name = "fake"

    def load(self) -> None:
        pass

    def estimate(self, image: np.ndarray) -> DepthResult:
        height, width = image.shape[:2]
        # A wall that gets slightly closer towards the bottom, with the box
        # standing out in front of it.
        rows = np.linspace(0.3, 0.5, height, dtype=np.float32)
        depth = np.repeat(rows[:, None], width, axis=1)
        depth[_rect(width, height, *FAKE_BOX)] = 0.8
        return DepthResult(depth=depth)
