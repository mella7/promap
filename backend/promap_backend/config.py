"""Settings from environment variables (see .env.example)."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    segmenter: str = "fake"
    depth: str = "fake"
    assistant: str = "rules"
    api_key: str = ""
    max_upload_bytes: int = 10_000_000
    max_image_side: int = 4096

    # Real models.
    sam_model: str = "facebook/sam2.1-hiera-small"
    depth_model: str = "depth-anything/Depth-Anything-V2-Small-hf"
    device: str = "cpu"
    model_max_side: int = 1024
    points_per_batch: int = 16
    sam_points_per_side: int = 32
    sam_min_iou: float = 0.75
    sam_min_stability: float = 0.9

    @classmethod
    def from_env(cls) -> "Settings":
        env = os.environ.get
        defaults = cls()
        return cls(
            segmenter=env("PROMAP_SEGMENTER", defaults.segmenter),
            depth=env("PROMAP_DEPTH", defaults.depth),
            assistant=env("PROMAP_ASSISTANT", defaults.assistant),
            api_key=env("PROMAP_API_KEY", defaults.api_key),
            max_upload_bytes=int(env("PROMAP_MAX_UPLOAD_BYTES", str(defaults.max_upload_bytes))),
            max_image_side=int(env("PROMAP_MAX_IMAGE_SIDE", str(defaults.max_image_side))),
            sam_model=env("PROMAP_SAM_MODEL", defaults.sam_model),
            depth_model=env("PROMAP_DEPTH_MODEL", defaults.depth_model),
            device=env("PROMAP_DEVICE", defaults.device),
            model_max_side=int(env("PROMAP_MODEL_MAX_SIDE", str(defaults.model_max_side))),
            points_per_batch=int(env("PROMAP_POINTS_PER_BATCH", str(defaults.points_per_batch))),
            sam_points_per_side=int(
                env("PROMAP_SAM_POINTS_PER_SIDE", str(defaults.sam_points_per_side))
            ),
            sam_min_iou=float(env("PROMAP_SAM_MIN_IOU", str(defaults.sam_min_iou))),
            sam_min_stability=float(
                env("PROMAP_SAM_MIN_STABILITY", str(defaults.sam_min_stability))
            ),
        )
