import numpy as np
import pytest

from promap_backend.models.postprocess import clean_masks


def rect(left, top, right, bottom, shape=(100, 200)):
    mask = np.zeros(shape, dtype=bool)
    mask[top:bottom, left:right] = True
    return mask


def test_box_is_cut_out_of_the_wall_behind_it():
    wall = rect(0, 0, 200, 90)
    box = rect(80, 40, 120, 80)
    results = clean_masks([wall, box], [0.95, 0.9])

    assert [r.name for r in results] == ["Surface 1", "Surface 2"]
    big, small = results
    assert small.mask.sum() == 40 * 40
    assert not np.any(big.mask & small.mask)
    assert big.mask.sum() + small.mask.sum() == wall.sum()


def test_duplicates_keep_one():
    a = rect(10, 10, 60, 60)
    b = rect(11, 10, 60, 60)
    results = clean_masks([a, b], [0.9, 0.99])
    assert len(results) == 1


def test_unsure_tiny_and_huge_masks_are_dropped():
    sure = rect(10, 10, 60, 60)
    unsure = rect(100, 10, 150, 60)
    tiny = rect(0, 90, 5, 95)
    huge = rect(0, 0, 200, 100)
    results = clean_masks([sure, unsure, tiny, huge], [0.9, 0.5, 0.99, 0.99])
    assert len(results) == 1
    assert results[0].mask.sum() == 50 * 50


def test_mask_eaten_by_smaller_ones_is_dropped():
    big = rect(0, 0, 20, 20)
    left = rect(0, 0, 10, 20)
    right = rect(10, 0, 20, 20)
    results = clean_masks([big, left, right], [0.9, 0.9, 0.9], min_area_share=0.001)
    assert sorted(int(r.mask.sum()) for r in results) == [200, 200]


def test_count_is_capped_largest_first():
    masks = [rect(i * 20, 0, i * 20 + 10 + i, 50) for i in range(8)]
    results = clean_masks(masks, [0.9] * 8, max_surfaces=3)
    assert [int(r.mask.sum()) for r in results] == [17 * 50, 16 * 50, 15 * 50]


def test_empty_and_bad_input():
    assert clean_masks([], []) == []
    with pytest.raises(ValueError):
        clean_masks([rect(0, 0, 5, 5)], [])
    with pytest.raises(ValueError):
        clean_masks([rect(0, 0, 5, 5), rect(0, 0, 5, 5, shape=(10, 10))], [0.9, 0.9])
