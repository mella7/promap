"""The real-model adapters, run with stand-in pipelines so the tests need
neither torch nor a model download."""

import importlib.util
import io

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from promap_backend import rle
from promap_backend.config import Settings
from promap_backend.main import create_app
from promap_backend.models import ModelUnavailable, load_depth, load_segmenter
from promap_backend.models.hf import DepthAnythingEstimator, SamSegmenter


class StandInPredictor:
    """Behaves like SAM 2 on a photo of a wall with a box on it: points on
    the box give the box, other points give the wall. Each point also gets
    a blurry mask (unstable) and an unsure one (low IoU), like the real
    model's extra outputs."""

    def __init__(self, low_res=64):
        self.low_res = low_res
        self.images = []
        self.points = []

    def set_image(self, image):
        self.images.append(image.size)

    def predict(self, points):
        self.points.append(points.copy())
        n, size = len(points), self.low_res
        ys, xs = (np.mgrid[0:size, 0:size] + 0.5) / size
        in_box = (xs >= 0.25) & (xs < 0.5) & (ys >= 0.25) & (ys < 0.5)
        wall = (ys < 0.9) & ~in_box
        logits = np.full((n, 3, size, size), -8.0, np.float32)
        iou = np.zeros((n, 3), np.float32)
        for i, (x, y) in enumerate(points):
            on_box = 0.25 <= x < 0.5 and 0.25 <= y < 0.5
            logits[i, 0] = np.where(in_box if on_box else wall, 8.0, -8.0)
            iou[i, 0] = 0.95
            logits[i, 1] = np.where(in_box | wall, 0.5, -0.5)  # blurry edge
            iou[i, 1] = 0.9
            logits[i, 2] = np.where(xs < 0.1, 8.0, -8.0)  # sharp but unsure
            iou[i, 2] = 0.3
        return logits, iou


def test_prompts_cover_the_whole_photo_whatever_its_shape():
    predictor = StandInPredictor()
    SamSegmenter(predictor=predictor, points_per_side=8).segment(np.zeros((639, 480, 3), np.uint8))
    points = np.concatenate(predictor.points)
    assert len(points) == 64
    assert points[:, 0].min() < 0.1 and points[:, 0].max() > 0.9
    assert points[:, 1].min() < 0.1 and points[:, 1].max() > 0.9


def test_sam_finds_wall_and_box_at_full_size():
    segmenter = SamSegmenter(predictor=StandInPredictor(), points_per_side=8)
    results = segmenter.segment(np.zeros((360, 480, 3), np.uint8))

    assert [r.name for r in results] == ["Surface 1", "Surface 2"]
    wall, box = results
    assert wall.mask.shape == box.mask.shape == (360, 480)
    assert not np.any(wall.mask & box.mask)
    assert box.mask.sum() == pytest.approx(90 * 120, rel=0.05)


def test_unsure_and_blurry_masks_are_dropped_and_counted():
    segmenter = SamSegmenter(predictor=StandInPredictor(), points_per_side=4)
    segmenter.segment(np.zeros((90, 120, 3), np.uint8))
    stats = segmenter.last_stats
    assert (stats.prompts, stats.masks) == (16, 48)
    assert stats.sure == 32  # the IoU 0.3 ones go
    assert stats.stable == 16  # the blurry ones go
    assert stats.distinct == 2  # wall and box, every repeat merged
    assert "16 prompts" in stats.describe()


def test_thresholds_can_be_loosened():
    segmenter = SamSegmenter(predictor=StandInPredictor(), points_per_side=4, min_iou=0.2)
    segmenter.segment(np.zeros((90, 120, 3), np.uint8))
    assert segmenter.last_stats.sure == 48


def test_big_photos_are_shrunk_before_sam_but_masks_come_back_full_size():
    predictor = StandInPredictor()
    results = SamSegmenter(predictor=predictor, max_side=1024, points_per_side=4).segment(
        np.zeros((1536, 2048, 3), np.uint8)
    )
    assert predictor.images == [(1024, 768)]
    assert results[0].mask.shape == (1536, 2048)


def test_prompts_go_in_small_batches():
    predictor = StandInPredictor()
    SamSegmenter(predictor=predictor, points_per_side=8, points_per_batch=16).segment(
        np.zeros((90, 120, 3), np.uint8)
    )
    assert [len(batch) for batch in predictor.points] == [16, 16, 16, 16]


def test_load_builds_the_model_once(monkeypatch):
    from promap_backend.models import hf

    built = []

    def fake_sam(model, device):
        built.append((model, device))
        return StandInPredictor()

    monkeypatch.setattr(hf, "_TorchSam2", fake_sam)
    segmenter = SamSegmenter(points_per_side=4)
    segmenter.load()
    segmenter.load()
    segmenter.segment(np.zeros((90, 120, 3), np.uint8))
    assert built == [("facebook/sam2.1-hiera-small", "cpu")]


def test_depth_is_resized_to_the_photo():
    def estimator(image):
        width, height = image.size
        small = np.tile(np.linspace(0, 1, width // 2, dtype=np.float32), (height // 2, 1))
        return {"predicted_depth": small[None, :, :]}

    depth = DepthAnythingEstimator(estimator=estimator).estimate(np.zeros((360, 480, 3), np.uint8))
    assert depth.depth.shape == (360, 480)
    assert depth.depth[:, -1].mean() > depth.depth[:, 0].mean()


def test_settings_pick_the_real_models_without_loading_them():
    settings = Settings(segmenter="sam2", depth="depth_anything_v2", device="cuda")
    segmenter = load_segmenter(settings)
    depth = load_depth(settings)
    assert segmenter.name == "sam2" and segmenter.device == "cuda"
    assert segmenter.points_per_side == 32 and segmenter.points_per_batch == 16
    assert depth.name == "depth_anything_v2"


def png(width=480, height=360):
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), (90, 90, 90)).save(buffer, format="PNG")
    return buffer.getvalue()


def test_api_serves_cleaned_sam_masks():
    client = TestClient(
        create_app(
            Settings(), segmenter=SamSegmenter(predictor=StandInPredictor(), points_per_side=8)
        )
    )
    body = client.post("/v1/segment", content=png(), headers={"content-type": "image/png"}).json()

    assert body["model"] == "sam2"
    assert [m["name"] for m in body["masks"]] == ["Surface 1", "Surface 2"]
    assert all(m["label"] is None for m in body["masks"])
    box = rle.decode(body["masks"][1]["rle"]["counts"], 480, 360)
    assert box.sum() == pytest.approx(90 * 120, rel=0.05)


def test_a_model_that_cannot_load_gives_503():
    class Broken:
        name = "broken"

        def segment(self, image):
            raise ModelUnavailable("The real models need the ml extra")

    client = TestClient(create_app(Settings(), segmenter=Broken()))
    response = client.post("/v1/segment", content=png(), headers={"content-type": "image/png"})
    assert response.status_code == 503
    assert "ml extra" in response.json()["detail"]


@pytest.mark.skipif(
    importlib.util.find_spec("transformers") is not None,
    reason="transformers is installed, so this would download a real model",
)
def test_without_transformers_the_error_says_how_to_install():
    with pytest.raises(ModelUnavailable, match="ml extra"):
        SamSegmenter().segment(np.zeros((10, 10, 3), np.uint8))
