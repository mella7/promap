"""Preloading models at startup, and /ready."""

import threading
import time

from fastapi.testclient import TestClient

from promap_backend.config import Settings
from promap_backend.main import create_app
from promap_backend.models import ModelUnavailable
from promap_backend.models.fake import FakeDepth


class SlowSegmenter:
    name = "slow"

    def __init__(self):
        self.release = threading.Event()
        self.loads = 0

    def load(self):
        self.release.wait(5)
        self.loads += 1

    def segment(self, image):
        return []


class BrokenSegmenter:
    name = "broken"

    def load(self):
        raise ModelUnavailable("The real models need the ml extra")

    def segment(self, image):
        return []


def wait_for(client, status, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        reply = client.get("/ready")
        if reply.status_code == status:
            return reply
        time.sleep(0.02)
    raise AssertionError(f"/ready never answered {status}")


def test_without_preload_ready_at_once():
    with TestClient(create_app(Settings())) as client:
        reply = client.get("/ready")
        assert reply.status_code == 200
        assert reply.json() == {"ready": True, "detail": "Lazy loading"}
        assert client.get("/health").json()["ready"] is True


def test_preload_answers_health_while_loading_then_gets_ready():
    segmenter = SlowSegmenter()
    app = create_app(Settings(preload=True), segmenter=segmenter, depth_model=FakeDepth())
    with TestClient(app) as client:
        assert client.get("/ready").status_code == 503
        health = client.get("/health")
        assert health.status_code == 200 and health.json()["ready"] is False

        segmenter.release.set()
        assert wait_for(client, 200).json()["detail"] == "Models loaded"
        assert segmenter.loads == 1


def test_a_failed_preload_says_why():
    app = create_app(Settings(preload=True), segmenter=BrokenSegmenter(), depth_model=FakeDepth())
    with TestClient(app) as client:
        deadline = time.monotonic() + 5
        while True:
            reply = client.get("/ready")
            assert reply.status_code == 503
            if "ml extra" in reply.json()["detail"]:
                break
            assert time.monotonic() < deadline, "the error never showed up"
            time.sleep(0.02)
        assert client.get("/health").json()["ready"] is False


def test_preload_setting_from_environment(monkeypatch):
    monkeypatch.setenv("PROMAP_PRELOAD", "true")
    assert Settings.from_env().preload is True
    monkeypatch.setenv("PROMAP_PRELOAD", "0")
    assert Settings.from_env().preload is False
