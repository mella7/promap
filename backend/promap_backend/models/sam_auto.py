"""Our own "segment everything" loop around SAM 2.

We don't use the transformers mask-generation pipeline because of two
problems found on the first real photo:

- It scales the prompt grid as if the photo were padded to a square, but
  SAM 2 squashes the photo to 1024x1024. On a portrait photo the prompts
  only covered the left 73%, so the right wall and the blind were never
  asked about.
- It blows every mask up to full photo size before filtering. That's 192
  full-size float masks per batch: slow (128 s on a laptop CPU) and heavy
  enough that one run got killed for memory.

Here the image is encoded once, prompts cover the whole photo, every
mask is scored and deduplicated at SAM's own 256x256 output size, and
only the few survivors are scaled up to the photo.

The predictor is passed in, so this file needs no torch and the tests can
use a stand-in.
"""

from dataclasses import dataclass, field
from typing import Protocol

import numpy as np
from PIL import Image


class Predictor(Protocol):
    def set_image(self, image: Image.Image) -> None:
        """Encodes the photo once."""
        ...

    def predict(self, points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """points: (n, 2), x and y in 0..1 of the photo.

        Returns low-res mask logits (n, k, h, w) and predicted IoU (n, k),
        k masks per point (SAM 2 gives 3: part, object, whole)."""
        ...


@dataclass
class AutoMaskStats:
    prompts: int = 0
    masks: int = 0
    sure: int = 0
    stable: int = 0
    distinct: int = 0

    def describe(self) -> str:
        return (
            f"{self.prompts} prompts -> {self.masks} masks -> {self.sure} sure"
            f" -> {self.stable} stable -> {self.distinct} distinct"
        )


@dataclass
class AutoMaskOptions:
    points_per_side: int = 32
    points_per_batch: int = 16
    min_iou: float = 0.75
    min_stability: float = 0.9
    stability_offset: float = 1.0
    duplicate_iou: float = 0.7
    max_masks: int = 48
    stats: AutoMaskStats = field(default_factory=AutoMaskStats)


def point_grid(per_side: int) -> np.ndarray:
    """Centres of a per_side x per_side grid, as x, y in 0..1."""
    steps = (np.arange(per_side, dtype=np.float32) + 0.5) / per_side
    xs, ys = np.meshgrid(steps, steps)
    return np.stack([xs.ravel(), ys.ravel()], axis=1)


def stability(logits: np.ndarray, offset: float) -> np.ndarray:
    """How much a mask changes if the cut-off moves by +-offset.

    1.0 means a crisp edge. Low values mean a blurry, unsure mask."""
    flat = logits.reshape(logits.shape[0], -1)
    inner = (flat > offset).sum(axis=1)
    outer = (flat > -offset).sum(axis=1)
    return np.where(outer > 0, inner / np.maximum(outer, 1), 0.0)


def _dedupe(masks: np.ndarray, order: np.ndarray, max_iou: float, limit: int) -> list[int]:
    """Greedy: walk masks best first, keep one unless it overlaps a kept one."""
    flat = masks.reshape(masks.shape[0], -1).astype(np.float32)
    areas = flat.sum(axis=1)
    kept: list[int] = []
    for index in order:
        if areas[index] == 0:
            continue
        if kept:
            inter = flat[kept] @ flat[index]
            union = areas[kept] + areas[index] - inter
            if np.any(inter / np.maximum(union, 1) > max_iou):
                continue
        kept.append(int(index))
        if len(kept) == limit:
            break
    return kept


def generate_masks(
    predictor: Predictor, image: Image.Image, size: tuple[int, int], options: AutoMaskOptions
) -> tuple[list[np.ndarray], list[float]]:
    """Returns full-size boolean masks (height x width = size) and scores."""
    height, width = size
    stats = options.stats
    predictor.set_image(image)
    grid = point_grid(options.points_per_side)
    stats.prompts = len(grid)

    logits_kept: list[np.ndarray] = []
    scores_kept: list[float] = []
    for start in range(0, len(grid), options.points_per_batch):
        logits, iou = predictor.predict(grid[start : start + options.points_per_batch])
        logits = logits.reshape(-1, *logits.shape[-2:])
        iou = iou.reshape(-1)
        stats.masks += len(iou)

        sure = iou >= options.min_iou
        stats.sure += int(sure.sum())
        steady = stability(logits, options.stability_offset)
        keep = sure & (steady >= options.min_stability)
        stats.stable += int(keep.sum())

        # Kept as float16 at low res: a few hundred of these is a few MB.
        logits_kept.extend(logits[keep].astype(np.float16))
        scores_kept.extend((iou[keep] * steady[keep]).tolist())

    if not logits_kept:
        return [], []

    low_res = np.stack(logits_kept)
    scores = np.array(scores_kept, dtype=np.float32)
    best_first = np.argsort(-scores, kind="stable")
    chosen = _dedupe(low_res > 0, best_first, options.duplicate_iou, options.max_masks)
    stats.distinct = len(chosen)

    masks = []
    for index in chosen:
        small = Image.fromarray(low_res[index].astype(np.float32), mode="F")
        big = np.asarray(small.resize((width, height), Image.Resampling.BILINEAR))
        masks.append(big > 0)
    return masks, [float(scores[i]) for i in chosen]
