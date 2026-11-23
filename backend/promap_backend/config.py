"""Settings from environment variables (see .env.example)."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    segmenter: str = "fake"
    depth: str = "fake"
    api_key: str = ""
    max_upload_bytes: int = 10_000_000
    max_image_side: int = 4096

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            segmenter=os.environ.get("PROMAP_SEGMENTER", "fake"),
            depth=os.environ.get("PROMAP_DEPTH", "fake"),
            api_key=os.environ.get("PROMAP_API_KEY", ""),
            max_upload_bytes=int(os.environ.get("PROMAP_MAX_UPLOAD_BYTES", "10000000")),
            max_image_side=int(os.environ.get("PROMAP_MAX_IMAGE_SIDE", "4096")),
        )
