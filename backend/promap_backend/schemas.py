"""Response bodies. See docs/backend-api.md."""

from typing import Any

from pydantic import BaseModel, Field


class Health(BaseModel):
    status: str
    version: str
    segmenter: str
    depth: str
    assistant: str


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


class AssistantRequest(BaseModel):
    # The whole scene as the app has it, see schema/scene.schema.json.
    scene: dict[str, Any]
    prompt: str = Field(min_length=1, max_length=500)


class AssistantResponse(BaseModel):
    model: str
    # What changed, or why nothing did. Shown to the user as is.
    message: str
    # Scene ops to apply as one undo step. Already checked: known surfaces,
    # known effects, valid settings, look-and-feel changes only.
    ops: list[dict[str, Any]]
    # Ops the assistant proposed that the check refused, for debugging.
    dropped: list[str]
