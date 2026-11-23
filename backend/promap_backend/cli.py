"""Try the models on a photo without the app.

    python -m promap_backend.cli segment room.jpg
    python -m promap_backend.cli depth room.jpg

Writes room.surfaces.png (each surface in its own colour over the photo) or
room.depth.png (closer is brighter) next to the photo and prints what it
found. Loading the model (and downloading it the first time) is timed apart
from the run itself, so the run time is what a request to the server costs.
"""

import argparse
import sys
import time
from dataclasses import replace
from pathlib import Path

import numpy as np
from PIL import Image

from .config import Settings
from .images import ImageError, read_image
from .models import ModelUnavailable, load_depth, load_segmenter

PALETTE = [
    (255, 90, 31),
    (46, 196, 182),
    (249, 200, 14),
    (123, 97, 255),
    (232, 63, 111),
    (63, 163, 77),
    (46, 139, 255),
    (255, 43, 214),
]


def overlay(image: np.ndarray, masks: list[np.ndarray]) -> Image.Image:
    out = image.astype(np.float32) * 0.45
    for index, mask in enumerate(masks):
        colour = np.array(PALETTE[index % len(PALETTE)], dtype=np.float32)
        out[mask] = out[mask] * 0.4 + colour * 0.6
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def depth_image(depth: np.ndarray) -> Image.Image:
    low, high = float(depth.min()), float(depth.max())
    scaled = np.zeros_like(depth) if high == low else (depth - low) / (high - low)
    return Image.fromarray((scaled * 255).astype(np.uint8))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m promap_backend.cli", description=__doc__)
    parser.add_argument("task", choices=["segment", "depth"])
    parser.add_argument("photo", type=Path)
    parser.add_argument("--out", type=Path, help="where to write the result image")
    parser.add_argument("--segmenter", default="sam2", help="fake or sam2 (default sam2)")
    parser.add_argument("--depth", default="depth_anything_v2", help="fake or depth_anything_v2")
    parser.add_argument("--device", help="cpu or cuda (default from PROMAP_DEVICE, else cpu)")
    parser.add_argument(
        "--points", type=int, help="SAM prompt grid per side (default 32; 16 is ~4x faster)"
    )
    parser.add_argument("--max-side", type=int, help="shrink the photo to this before SAM")
    parser.add_argument("--min-iou", type=float, help="drop SAM masks it scores below this")
    parser.add_argument(
        "--min-stability", type=float, help="drop SAM masks with blurrier edges than this"
    )
    parser.add_argument("--runs", type=int, default=1, help="run this many times to time it")
    args = parser.parse_args(argv)

    settings = replace(Settings.from_env(), segmenter=args.segmenter, depth=args.depth)
    if args.device:
        settings = replace(settings, device=args.device)
    if args.points:
        settings = replace(settings, sam_points_per_side=args.points)
    if args.max_side:
        settings = replace(settings, model_max_side=args.max_side)
    if args.min_iou is not None:
        settings = replace(settings, sam_min_iou=args.min_iou)
    if args.min_stability is not None:
        settings = replace(settings, sam_min_stability=args.min_stability)

    try:
        image = read_image(args.photo.read_bytes(), settings.max_image_side)
    except (OSError, ImageError) as error:
        print(f"Cannot read {args.photo}: {error}", file=sys.stderr)
        return 1

    height, width = image.shape[:2]
    try:
        model = load_segmenter(settings) if args.task == "segment" else load_depth(settings)
        started = time.perf_counter()
        model.load()
        print(f"{model.name}: loaded in {time.perf_counter() - started:.1f} s")

        for run in range(1, max(1, args.runs) + 1):
            started = time.perf_counter()
            if args.task == "segment":
                result = model.segment(image)
            else:
                result = model.estimate(image)
            print(f"  run {run}: {time.perf_counter() - started:.1f} s ({width}x{height})")

        if args.task == "segment":
            out = args.out or args.photo.with_suffix(".surfaces.png")
            overlay(image, [r.mask for r in result]).save(out)
            stats = getattr(model, "last_stats", None)
            if stats is not None:
                print(f"  {stats.describe()}")
            print(f"{len(result)} surfaces")
            for r in result:
                share = 100 * r.mask.sum() / (width * height)
                print(f"  {r.name}: {share:.1f}% of the photo, score {r.score:.2f}")
        else:
            out = args.out or args.photo.with_suffix(".depth.png")
            depth_image(result.depth).save(out)
    except ModelUnavailable as error:
        print(error, file=sys.stderr)
        return 2
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
