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


class StandInGenerator:
    """Behaves like transformers' mask-generation pipeline: a wall and a box,
    plus a duplicate of the box and a low-confidence mask."""

    def __init__(self):
        self.seen_sizes = []

    def __call__(self, image, points_per_batch, points_per_crop):
        width, height = image.size
        self.seen_sizes.append((width, height))
        self.seen_grid = points_per_crop
        wall = np.zeros((height, width), bool)
        wall[: height * 9 // 10, :] = True
        box = np.zeros((height, width), bool)
        box[height // 4 : height // 2, width // 4 : width // 2] = True
        unsure = np.zeros((height, width), bool)
        unsure[-5:, -50:] = True
        return {
            "masks": [wall, box, box.copy(), unsure],
            "scores": np.array([0.97, 0.95, 0.9, 0.3]),
        }


def test_sam_shrinks_big_photos_and_returns_full_size_masks():
    generator = StandInGenerator()
    segmenter = SamSegmenter(generator=generator, max_side=1024)
    image = np.zeros((1536, 2048, 3), np.uint8)

    results = segmenter.segment(image)

    assert generator.seen_sizes == [(1024, 768)]
    assert [r.name for r in results] == ["Surface 1", "Surface 2"]
    wall, box = results
    assert wall.mask.shape == box.mask.shape == (1536, 2048)
    assert not np.any(wall.mask & box.mask)
    assert box.mask.sum() == pytest.approx(384 * 512, rel=0.02)


def test_sam_leaves_small_photos_alone():
    generator = StandInGenerator()
    SamSegmenter(generator=generator).segment(np.zeros((360, 480, 3), np.uint8))
    assert generator.seen_sizes == [(480, 360)]


def test_sam_grid_density_reaches_the_pipeline():
    generator = StandInGenerator()
    SamSegmenter(generator=generator, points_per_side=16).segment(np.zeros((90, 120, 3), np.uint8))
    assert generator.seen_grid == 16


def test_load_builds_the_pipeline_once(monkeypatch):
    from promap_backend.models import hf

    built = []

    def fake_pipeline(task, model, device):
        built.append(task)
        return StandInGenerator()

    monkeypatch.setattr(hf, "_pipeline", fake_pipeline)
    segmenter = SamSegmenter()
    segmenter.load()
    segmenter.load()
    segmenter.segment(np.zeros((90, 120, 3), np.uint8))
    assert built == ["mask-generation"]


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
    assert segmenter.points_per_side == 32
    assert depth.name == "depth_anything_v2"


def png(width=480, height=360):
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), (90, 90, 90)).save(buffer, format="PNG")
    return buffer.getvalue()


def test_api_serves_cleaned_sam_masks():
    client = TestClient(
        create_app(Settings(), segmenter=SamSegmenter(generator=StandInGenerator()))
    )
    body = client.post("/v1/segment", content=png(), headers={"content-type": "image/png"}).json()

    assert body["model"] == "sam2"
    assert [m["name"] for m in body["masks"]] == ["Surface 1", "Surface 2"]
    assert all(m["label"] is None for m in body["masks"])
    box = rle.decode(body["masks"][1]["rle"]["counts"], 480, 360)
    assert box.sum() == 90 * 120


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
