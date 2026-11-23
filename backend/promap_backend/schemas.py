"""Response bodies. See docs/backend-api.md."""

from pydantic import BaseModel


class Health(BaseModel):
    status: str
    version: str
    segmenter: str
    depth: str


class Rle(BaseModel):
    counts: list[int]


class Mask(BaseModel):
    name: str
    label: str | None
    score: float
    rle: Rle


class SegmentResponse(BaseModel):
    model: str
    width: int
    height: int
    masks: list[Mask]


class DepthResponse(BaseModel):
    model: str
    width: int
    height: int
    # 16-bit greyscale PNG, base64. 0 is the farthest point in the image,
    # 65535 the closest. Relative only.
    png16: str
