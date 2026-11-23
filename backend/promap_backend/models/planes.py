"""Walls, ceiling and floor from a depth map, no extra model.

Depth Anything gives relative inverse depth (disparity): bigger is closer,
with an unknown scale and offset. For a pinhole camera the inverse depth
of a flat surface is a linear function of the pixel position:

    d(x, y) = a*x + b*y + c

and an unknown scale and offset keep it linear. So we can find big flat
surfaces without knowing the camera: look for large regions where the
depth map is one plane in (x, y). A box in front of a wall is a different
plane, so it's left out, and SAM can fill it in.

Steps, on a small copy of the depth map (fast, and smooths out noise):

1. normalise depth to 0..1 and smooth it
2. repeatedly: try planes from the local slope at random pixels, keep the
   one that explains the most remaining pixels, refit it to its inliers
3. keep the solid connected pieces of it, remove them, go again
4. grow each plane back over the band the smoothing blurred, using the
   unsmoothed depth, so neighbouring walls meet at the corner
5. name each from its slope: steep upwards at the top is the ceiling,
   steep downwards at the bottom is the floor. Other big planes reaching
   the edge of the photo are walls. What's left is a flat face of some
   object (a box front) and gets no name, like SAM's surfaces.
"""

from collections import deque
from dataclasses import dataclass

import numpy as np
from PIL import Image

from .base import DepthEstimator, MaskResult, Segmenter


@dataclass
class PlaneOptions:
    work_width: int = 160  # pixels across the small copy we search in
    tolerance: float = 0.02  # max distance from the plane, in depth range
    slope_tolerance: float = 0.35  # how far the local slope may differ, relative
    min_share: float = 0.03  # smallest plane, as a share of the photo
    max_planes: int = 6
    wall_min_share: float = 0.06  # smaller planes are object faces, not walls
    grow_steps: int = 4  # pixels (in the small copy) to grow back at the edges
    tries: int = 200
    seed: int = 0


@dataclass
class Plane:
    mask: np.ndarray  # bool, full photo size
    label: str | None  # wall, ceiling, floor, or None for an object's face
    slope_x: float  # depth change across the photo width
    slope_y: float  # depth change down the photo, per photo width
    share: float


def _box_blur(values: np.ndarray, radius: int) -> np.ndarray:
    size = 2 * radius + 1
    padded = np.pad(values.astype(np.float64), radius, mode="edge")
    sums = np.pad(padded.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    window = sums[size:, size:] - sums[:-size, size:] - sums[size:, :-size] + sums[:-size, :-size]
    return window / (size * size)


def _open(mask: np.ndarray, radius: int) -> np.ndarray:
    """Erode then dilate: removes ragged bits and thin bridges."""
    eroded = _box_blur(mask, radius) > 0.999
    return _box_blur(eroded, radius) > 0.001


def _pieces(mask: np.ndarray) -> list[np.ndarray]:
    """4-connected pieces of a small mask, largest first."""
    height, width = mask.shape
    seen = np.zeros_like(mask)
    pieces = []
    for y0, x0 in zip(*np.nonzero(mask), strict=True):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        piece = np.zeros_like(mask)
        queue = deque([(y0, x0)])
        while queue:
            y, x = queue.popleft()
            piece[y, x] = True
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        pieces.append(piece)
    pieces.sort(key=lambda p: int(p.sum()), reverse=True)
    return pieces


def label_for(
    slope_x: float,
    slope_y: float,
    centre_y: float,
    *,
    share: float = 1.0,
    touches_edge: bool = True,
    wall_min_share: float = 0.06,
) -> str | None:
    """centre_y is 0 at the top of the photo and 1 at the bottom."""
    if abs(slope_y) > 1.5 * abs(slope_x) and abs(slope_y) > 0.3:
        if slope_y < 0 and centre_y < 0.5:
            return "ceiling"
        if slope_y > 0 and centre_y > 0.5:
            return "floor"
    if touches_edge and share >= wall_min_share:
        return "wall"
    return None


def _touches_edge(piece: np.ndarray, margin: int = 2) -> bool:
    return bool(
        piece[:margin].any()
        or piece[-margin:].any()
        or piece[:, :margin].any()
        or piece[:, -margin:].any()
    )


def find_planes(depth: np.ndarray, options: PlaneOptions | None = None) -> list[Plane]:
    options = options or PlaneOptions()
    rng = np.random.default_rng(options.seed)
    full_h, full_w = depth.shape
    low, high = np.percentile(depth, [1, 99])
    if high - low < 1e-6:
        return []
    normal = np.clip((depth - low) / (high - low), 0, 1).astype(np.float32)

    width = min(options.work_width, full_w)
    height = max(1, round(full_h * width / full_w))
    small = np.asarray(
        Image.fromarray(normal, mode="F").resize((width, height), Image.Resampling.BOX)
    )
    smooth = _box_blur(small, 2)
    # Slopes in depth range per photo width, so they don't depend on size.
    slope_y, slope_x = np.gradient(smooth)
    slope_x *= width
    slope_y *= width
    ys, xs = np.mgrid[0:height, 0:width] / width

    def inliers(a: float, b: float, c: float, pool: np.ndarray) -> np.ndarray:
        near = np.abs(smooth - (a * xs + b * ys + c)) < options.tolerance
        allowed = options.slope_tolerance * max(float(np.hypot(a, b)), 0.15)
        same_slope = np.hypot(slope_x - a, slope_y - b) < allowed
        return pool & near & same_slope

    total = height * width
    min_pixels = options.min_share * total
    remaining = np.ones((height, width), dtype=bool)
    # (piece, a, b, c, plane number): one plane can have several pieces,
    # like a wall cut in two by a shelf.
    found: list[tuple[np.ndarray, float, float, float, int]] = []
    plane_count = 0
    for _ in range(options.max_planes * 3):
        if len(found) == options.max_planes:
            break
        candidates = np.flatnonzero(remaining)
        if len(candidates) < min_pixels:
            break
        best: tuple[int, np.ndarray, float, float] | None = None
        picks = rng.choice(candidates, size=min(options.tries, len(candidates)), replace=False)
        for pixel in picks:
            a, b = float(slope_x.flat[pixel]), float(slope_y.flat[pixel])
            c = float(smooth.flat[pixel] - a * xs.flat[pixel] - b * ys.flat[pixel])
            hits = inliers(a, b, c, remaining)
            count = int(hits.sum())
            if best is None or count > best[0]:
                best = (count, hits, a, b)
        if best is None:
            break
        _, hits, a, b = best
        for _ in range(2):  # refit to the inliers, then take the inliers again
            if hits.sum() < 3:
                break
            design = np.stack([xs[hits], ys[hits], np.ones(int(hits.sum()))], axis=1)
            a, b, c = np.linalg.lstsq(design, smooth[hits], rcond=None)[0]
            hits = inliers(float(a), float(b), float(c), remaining)

        solid = _open(hits, 2)
        pieces = [p for p in _pieces(solid) if p.sum() >= min_pixels]
        if not pieces:
            remaining &= ~hits  # nothing big here, don't try these pixels again
            continue
        for piece in pieces:
            if len(found) < options.max_planes:
                found.append((piece, float(a), float(b), float(c), plane_count))
            remaining &= ~piece
        plane_count += 1
        remaining &= ~hits

    # Smoothing blurs the slopes near edges, so every plane stops a few
    # pixels short. Grow them back over unclaimed pixels that still sit on
    # the plane in the unsmoothed depth.
    claimed = np.zeros((height, width), dtype=bool)
    for piece, *_ in found:
        claimed |= piece
    for _ in range(options.grow_steps):
        for piece, a, b, c, _ in found:
            ring = (_box_blur(piece, 1) > 0.001) & ~claimed
            fits = ring & (np.abs(small - (a * xs + b * ys + c)) < options.tolerance)
            piece |= fits
            claimed |= fits

    # Name by the whole plane: the piece of wall under a shelf is still wall.
    groups: dict[int, dict[str, float | bool]] = {}
    for piece, _, _, _, number in found:
        group = groups.setdefault(number, {"share": 0.0, "edge": False})
        group["share"] = float(group["share"]) + float(piece.mean())
        group["edge"] = bool(group["edge"]) or _touches_edge(piece)

    planes = []
    for piece, a, b, _, number in found:
        mask = (
            np.asarray(
                Image.fromarray(piece.astype(np.uint8) * 255).resize(
                    (full_w, full_h), Image.Resampling.NEAREST
                )
            )
            > 127
        )
        centre_y = float(np.nonzero(piece)[0].mean() / height)
        share = float(mask.mean())
        label = label_for(
            a,
            b,
            centre_y,
            share=float(groups[number]["share"]),
            touches_edge=bool(groups[number]["edge"]),
            wall_min_share=options.wall_min_share,
        )
        planes.append(Plane(mask, label, a, b, share))
    return planes


class PlaneSegmenter:
    """Surfaces from depth alone: fast, finds walls, ceiling and floor,
    but can't see flat things on a wall (posters, a blind)."""

    name = "planes"

    def __init__(self, depth: DepthEstimator, options: PlaneOptions | None = None):
        self.depth = depth
        self.options = options or PlaneOptions()

    def load(self) -> None:
        self.depth.load()

    def planes(self, image: np.ndarray) -> list[Plane]:
        return find_planes(self.depth.estimate(image).depth, self.options)

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        from .postprocess import clean_masks

        planes = self.planes(image)
        return clean_masks(
            [p.mask for p in planes],
            [1.0] * len(planes),
            labels=[p.label for p in planes],
            min_score=0.0,
        )


class MixedSegmenter:
    """Planes from depth for walls, ceiling and floor, SAM for the things on
    and in front of them. SAM masks that are just a wall again are dropped,
    the rest are cut out of the planes they sit on."""

    def __init__(self, planes: PlaneSegmenter, objects: Segmenter, *, same_iou: float = 0.5):
        self.planes = planes
        self.objects = objects
        self.same_iou = same_iou
        self.name = f"{objects.name}+planes"

    def load(self) -> None:
        self.planes.load()
        self.objects.load()

    @property
    def last_stats(self):
        return getattr(self.objects, "last_stats", None)

    def segment(self, image: np.ndarray) -> list[MaskResult]:
        from .postprocess import _iou, clean_masks

        planes = self.planes.planes(image)
        masks = [p.mask for p in planes]
        scores = [1.0] * len(planes)
        labels: list[str | None] = [p.label for p in planes]
        areas = [int(m.sum()) for m in masks]
        for found in self.objects.segment(image):
            area = int(found.mask.sum())
            same = [
                i
                for i, plane in enumerate(planes)
                if _iou(found.mask, plane.mask, area, areas[i]) > self.same_iou
            ]
            if any(planes[i].label is not None for i in same):
                continue  # SAM found a wall, ceiling or floor again
            # SAM's outline of an object face is sharper than the depth one.
            for i in same:
                masks[i] = found.mask
                scores[i] = found.score
            if not same:
                masks.append(found.mask)
                scores.append(found.score)
                labels.append(found.label)
        return clean_masks(masks, scores, labels=labels, min_score=0.0)
