"""Turning raw "segment everything" output into surfaces worth mapping.

SAM-style models return many overlapping masks: a wall, the same wall
again, the wall plus the box in front of it, a speck of dust. For
projection mapping we want a clean set of separate surfaces, so:

1. drop masks the model isn't sure about, and ones too small or too big
2. drop near-duplicates
3. give every pixel to the smallest mask that covers it, so a box face
   is cut out of the wall behind it instead of overlapping it
4. drop whatever became too small after that, keep the largest few
"""

import numpy as np

from .base import MaskResult


def clean_masks(
    masks: list[np.ndarray],
    scores: list[float],
    *,
    labels: list[str | None] | None = None,
    min_area_share: float = 0.005,
    max_area_share: float = 0.95,
    min_score: float = 0.8,
    duplicate_iou: float = 0.85,
    max_surfaces: int = 12,
) -> list[MaskResult]:
    if len(masks) != len(scores):
        raise ValueError("Need one score per mask")
    labels = labels if labels is not None else [None] * len(masks)
    if len(labels) != len(masks):
        raise ValueError("Need one label per mask")
    if not masks:
        return []
    shape = masks[0].shape
    total = float(shape[0] * shape[1])
    min_area = min_area_share * total
    max_area = max_area_share * total

    candidates = []
    for mask, score, label in zip(masks, scores, labels, strict=True):
        mask = np.asarray(mask, dtype=bool)
        if mask.shape != shape:
            raise ValueError("All masks must be the same size")
        area = int(mask.sum())
        if score < min_score or area < min_area or area > max_area:
            continue
        candidates.append((mask, float(score), area, label))

    # Largest first, so duplicates keep the bigger, earlier one.
    candidates.sort(key=lambda c: c[2], reverse=True)
    kept: list[tuple[np.ndarray, float, int, str | None]] = []
    for mask, score, area, label in candidates:
        if any(
            _iou(mask, other, area, other_area) > duplicate_iou for other, _, other_area, _ in kept
        ):
            continue
        kept.append((mask, score, area, label))

    # Paint from largest to smallest: each pixel ends up owned by the
    # smallest mask covering it.
    owner = np.full(shape, -1, dtype=np.int32)
    for index, (mask, _, _, _) in enumerate(kept):
        owner[mask] = index

    results = []
    for index, (_, score, _, label) in enumerate(kept):
        own = owner == index
        area = int(own.sum())
        if area < min_area:
            continue
        results.append((own, score, area, label))

    results.sort(key=lambda r: r[2], reverse=True)
    results = results[:max_surfaces]
    names = _names([label for *_, label in results])
    return [
        MaskResult(name=name, label=label, score=round(score, 4), mask=mask)
        for name, (mask, score, _, label) in zip(names, results, strict=True)
    ]


def _names(labels: list[str | None]) -> list[str]:
    """ "Wall", "Wall 2", "Ceiling" for labelled ones, "Surface 1", "Surface 2"
    for the rest."""
    seen: dict[str, int] = {}
    names = []
    for label in labels:
        key = (label or "surface").lower()
        seen[key] = seen.get(key, 0) + 1
        count = seen[key]
        if label is None:
            names.append(f"Surface {count}")
        else:
            names.append(label.capitalize() if count == 1 else f"{label.capitalize()} {count}")
    return names


def _iou(a: np.ndarray, b: np.ndarray, area_a: int, area_b: int) -> float:
    inter = int(np.logical_and(a, b).sum())
    union = area_a + area_b - inter
    return inter / union if union else 0.0
