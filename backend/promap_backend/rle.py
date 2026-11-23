"""Run-length encoding for masks.

A mask is sent as a list of run lengths over the pixels in row order (left
to right, top to bottom). Runs alternate between 0 and 1 and always start
with 0, so a mask whose first pixel is set starts with a run of length 0.
The runs add up to width * height.
"""

import numpy as np


def encode(mask: np.ndarray) -> list[int]:
    flat = np.asarray(mask, dtype=bool).ravel()
    if flat.size == 0:
        return []
    changes = np.flatnonzero(flat[1:] != flat[:-1]) + 1
    bounds = np.concatenate(([0], changes, [flat.size]))
    runs = np.diff(bounds).tolist()
    if flat[0]:
        runs.insert(0, 0)
    return [int(r) for r in runs]


def decode(counts: list[int], width: int, height: int) -> np.ndarray:
    if sum(counts) != width * height:
        raise ValueError(f"runs add up to {sum(counts)}, expected {width * height}")
    flat = np.zeros(width * height, dtype=bool)
    position = 0
    for index, run in enumerate(counts):
        if run < 0:
            raise ValueError("runs must not be negative")
        if index % 2 == 1:
            flat[position : position + run] = True
        position += run
    return flat.reshape(height, width)
