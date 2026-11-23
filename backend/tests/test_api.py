import base64
import io

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from promap_backend import rle
from promap_backend.config import Settings
from promap_backend.main import create_app


def png(width=480, height=360, value=128) -> bytes:
    buffer = io.BytesIO()
    Image.new("L", (width, height), value).save(buffer, format="PNG")
    return buffer.getvalue()


@pytest.fixture
def client():
    return TestClient(create_app(Settings()))


def test_health(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["segmenter"] == "fake"


def test_segment_returns_the_fake_surfaces(client):
    response = client.post("/v1/segment", content=png(), headers={"content-type": "image/png"})
    assert response.status_code == 200
    body = response.json()
    assert (body["width"], body["height"], body["model"]) == (480, 360, "fake")
    names = [m["name"] for m in body["masks"]]
    assert names == ["Box top", "Left wall", "Right wall"]

    box = rle.decode(body["masks"][0]["rle"]["counts"], 480, 360)
    ys, xs = np.nonzero(box)
    assert (xs.min(), xs.max(), ys.min(), ys.max()) == (210, 289, 130, 209)


def test_masks_scale_with_the_image(client):
    body = client.post(
        "/v1/segment", content=png(960, 720), headers={"content-type": "image/png"}
    ).json()
    box = rle.decode(body["masks"][0]["rle"]["counts"], 960, 720)
    assert box.sum() == 160 * 160


def test_jpeg_is_accepted(client):
    buffer = io.BytesIO()
    Image.new("RGB", (64, 48), (10, 20, 30)).save(buffer, format="JPEG")
    response = client.post(
        "/v1/segment", content=buffer.getvalue(), headers={"content-type": "image/jpeg"}
    )
    assert response.status_code == 200


def test_depth_is_a_16_bit_png_with_the_box_closest(client):
    body = client.post("/v1/depth", content=png(), headers={"content-type": "image/png"}).json()
    image = Image.open(io.BytesIO(base64.b64decode(body["png16"])))
    depth = np.asarray(image)
    assert depth.shape == (360, 480)
    assert depth[170, 250] == depth.max()
    assert depth[10, 10] < depth[350, 10]


@pytest.mark.parametrize(
    "content,content_type,status",
    [
        (b"", "image/png", 400),
        (b"not an image", "image/png", 400),
        (png(), "text/plain", 415),
        (png(), "application/octet-stream", 415),
    ],
)
def test_bad_uploads_are_refused(client, content, content_type, status):
    response = client.post("/v1/segment", content=content, headers={"content-type": content_type})
    assert response.status_code == status


def test_gif_is_refused_even_with_a_png_header(client):
    buffer = io.BytesIO()
    Image.new("L", (8, 8)).save(buffer, format="GIF")
    response = client.post(
        "/v1/segment", content=buffer.getvalue(), headers={"content-type": "image/png"}
    )
    assert response.status_code == 400


def test_size_limits():
    client = TestClient(create_app(Settings(max_upload_bytes=1000, max_image_side=100)))
    padded = png(300, 300, 0) + b"\0" * 2000
    big_file = client.post("/v1/segment", content=padded, headers={"content-type": "image/png"})
    assert big_file.status_code == 413
    big_image = client.post(
        "/v1/segment", content=png(200, 50), headers={"content-type": "image/png"}
    )
    assert big_image.status_code == 400
    assert "limit" in big_image.json()["detail"]


def test_api_key():
    client = TestClient(create_app(Settings(api_key="s3cret")))
    url, body, kind = "/v1/segment", png(), {"content-type": "image/png"}

    def status(key=None):
        headers = dict(kind) if key is None else {**kind, "x-api-key": key}
        return client.post(url, content=body, headers=headers).status_code

    assert status() == 401
    assert status("nope") == 401
    assert status("s3cret") == 200
    assert client.get("/health").status_code == 200


def test_unknown_model_name_fails_at_startup():
    with pytest.raises(ValueError):
        create_app(Settings(segmenter="nope"))
