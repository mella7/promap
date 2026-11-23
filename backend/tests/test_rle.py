import numpy as np
import pytest

from promap_backend import rle


def test_round_trip_random_masks():
    rng = np.random.default_rng(3)
    for _ in range(20):
        mask = rng.random((17, 23)) > 0.5
        assert np.array_equal(rle.decode(rle.encode(mask), 23, 17), mask)


def test_runs_start_with_background():
    mask = np.array([[1, 1, 0], [0, 1, 1]], dtype=bool)
    assert rle.encode(mask) == [0, 2, 2, 2]
    assert rle.encode(np.zeros((2, 3), bool)) == [6]
    assert rle.encode(np.ones((2, 3), bool)) == [0, 6]


def test_decode_rejects_wrong_totals():
    with pytest.raises(ValueError):
        rle.decode([1, 2], 2, 2)
