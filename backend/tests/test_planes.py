"""Walls, ceiling and floor from depth, on a made-up room corner."""

import numpy as np
import pytest

from promap_backend.config import Settings
from promap_backend.models import load_segmenter
from promap_backend.models.base import MaskResult
from promap_backend.models.planes import (
    MixedSegmenter,
    PlaneOptions,
    PlaneSegmenter,
    find_planes,
    label_for,
)
from promap_backend.models.postprocess import clean_masks

H, W = 480, 360


def corner_room(box=True):
    """Inverse depth of a room corner seen from inside: corner at x=180,
    walls get closer towards the sides, ceiling above y=80 gets closer
    towards the top, floor below y=400 gets closer towards the bottom.
    Optionally a box standing well in front of the left wall."""
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    depth = 0.2 + np.abs(xs - 180) / 300
    ceiling = ys < 80
    depth[ceiling] = (0.6 + (80 - ys) / 100)[ceiling]
    floor = ys >= 400
    depth[floor] = (0.6 + (ys - 400) / 100)[floor]
    if box:
        depth[200:300, 60:140] = 1.6
    return depth


def region(mask, top, bottom, left, right):
    return mask[top:bottom, left:right].mean()


def test_finds_two_walls_ceiling_and_floor():
    planes = find_planes(corner_room())
    labels = sorted(str(p.label) for p in planes)
    assert labels == ["None", "ceiling", "floor", "wall", "wall"]  # None: the box front
    by_label = {p.label: p for p in planes}
    assert region(by_label["ceiling"].mask, 10, 70, 20, 340) > 0.9
    assert region(by_label["floor"].mask, 410, 470, 20, 340) > 0.9
    left, right = sorted((p for p in planes if p.label == "wall"), key=lambda p: p.slope_x)
    assert region(right.mask, 120, 380, 220, 340) > 0.9  # gets closer to the right
    assert region(left.mask, 120, 190, 20, 160) > 0.9


def test_a_box_in_front_is_not_part_of_the_wall():
    planes = find_planes(corner_room())
    for plane in planes:
        if plane.label is not None:
            assert region(plane.mask, 205, 295, 65, 135) < 0.05
    (face,) = [p for p in planes if p.label is None]
    assert region(face.mask, 215, 285, 75, 125) > 0.95


def test_neighbouring_walls_meet_at_the_corner():
    planes = find_planes(corner_room(box=False))
    walls = sorted((p for p in planes if p.label == "wall"), key=lambda p: p.slope_x)
    covered = walls[0].mask | walls[1].mask
    assert region(covered, 120, 380, 160, 200) > 0.9  # no gap along the corner


def test_flat_depth_gives_nothing():
    assert find_planes(np.full((50, 60), 0.5, np.float32)) == []


def test_small_planes_are_ignored():
    planes = find_planes(corner_room(box=False), PlaneOptions(min_share=0.5))
    assert planes == []


@pytest.mark.parametrize(
    ("slope_x", "slope_y", "centre_y", "label"),
    [
        (0.0, -2.0, 0.1, "ceiling"),
        (0.0, 2.0, 0.9, "floor"),
        (1.0, 0.1, 0.5, "wall"),
        (0.0, 0.0, 0.5, None),  # small and not reaching the edge: an object's face
        (0.0, 0.0, 0.5, "wall"),  # facing the camera straight on
        (0.0, 2.0, 0.2, "wall"),  # floor-like slope but at the top: not a floor
    ],
)
def test_labels_from_slope(slope_x, slope_y, centre_y, label):
    small_inside = label is None
    got = label_for(
        slope_x,
        slope_y,
        centre_y,
        share=0.02 if small_inside else 0.3,
        touches_edge=not small_inside,
    )
    assert got == label


class StaticDepth:
    name = "static"

    def __init__(self, depth):
        self.depth = depth

    def load(self):
        pass

    def estimate(self, image):
        from promap_backend.models.base import DepthResult

        return DepthResult(depth=self.depth)


class BoxFinder:
    """Stands in for SAM: finds the box, and the right wall again."""

    name = "sam2"

    def load(self):
        pass

    def segment(self, image):
        box = np.zeros((H, W), bool)
        box[200:300, 60:140] = True
        wall = np.zeros((H, W), bool)
        wall[80:400, 185:] = True
        return clean_masks([box, wall], [0.9, 0.9], min_score=0)


def test_plane_segmenter_names_its_surfaces():
    results = PlaneSegmenter(StaticDepth(corner_room())).segment(np.zeros((H, W, 3), np.uint8))
    assert sorted(r.name for r in results) == ["Ceiling", "Floor", "Surface 1", "Wall", "Wall 2"]
    assert all(isinstance(r, MaskResult) for r in results)


def test_mixed_adds_objects_and_skips_walls_sam_found_again():
    segmenter = MixedSegmenter(PlaneSegmenter(StaticDepth(corner_room())), BoxFinder())
    results = segmenter.segment(np.zeros((H, W, 3), np.uint8))

    assert segmenter.name == "sam2+planes"
    names = sorted(r.name for r in results)
    assert names == ["Ceiling", "Floor", "Surface 1", "Wall", "Wall 2"]
    box = next(r for r in results if r.name == "Surface 1")
    assert box.label is None
    assert box.mask.sum() == 100 * 80
    stacked = np.sum([r.mask for r in results], axis=0)
    assert stacked.max() == 1  # nothing overlaps


def test_registry_builds_planes_on_the_given_depth_model():
    depth = StaticDepth(corner_room())
    segmenter = load_segmenter(Settings(segmenter="planes"), depth)
    assert segmenter.name == "planes" and segmenter.depth is depth
    mixed = load_segmenter(Settings(segmenter="sam2_planes"), depth)
    assert mixed.name == "sam2+planes"
