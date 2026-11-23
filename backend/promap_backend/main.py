"""HTTP API. Images go in as the raw request body (image/png or image/jpeg),
results come back as JSON. Nothing is stored."""

import base64
import hmac
import io
import json

import numpy as np
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from PIL import Image
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from . import __version__, rle
from .assistant import Assistant, SceneError, load_assistant
from .assistant import run as run_assistant
from .config import Settings
from .images import ACCEPTED_TYPES, ImageError, read_image
from .models import DepthEstimator, ModelUnavailable, Segmenter, load_depth, load_segmenter
from .schemas import (
    AssistantRequest,
    AssistantResponse,
    DepthResponse,
    Health,
    Mask,
    Rle,
    SegmentResponse,
)

MAX_JSON_BYTES = 1_000_000


def create_app(
    settings: Settings | None = None,
    *,
    segmenter: Segmenter | None = None,
    depth_model: DepthEstimator | None = None,
    assistant: Assistant | None = None,
) -> FastAPI:
    """Builds the app. Tests can pass their own models."""
    settings = settings or Settings.from_env()
    depth_model = depth_model or load_depth(settings)
    segmenter = segmenter or load_segmenter(settings, depth_model)
    assistant = assistant or load_assistant(settings.assistant)

    app = FastAPI(title="promap backend", version=__version__)

    def check_key(x_api_key: str | None = Header(default=None)) -> None:
        if not settings.api_key:
            return
        if x_api_key is None or not hmac.compare_digest(x_api_key, settings.api_key):
            raise HTTPException(status_code=401, detail="Missing or wrong API key")

    async def read_upload(request: Request) -> np.ndarray:
        content_type = request.headers.get("content-type", "").split(";")[0].strip()
        if content_type not in ACCEPTED_TYPES:
            raise HTTPException(
                status_code=415,
                detail="Send the image as the body with type image/png or image/jpeg",
            )
        declared = request.headers.get("content-length", "")
        if declared.isdigit() and int(declared) > settings.max_upload_bytes:
            raise HTTPException(status_code=413, detail="Image is too large")
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > settings.max_upload_bytes:
                raise HTTPException(status_code=413, detail="Image is too large")
        try:
            return read_image(bytes(body), settings.max_image_side)
        except ImageError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error

    @app.get("/health", response_model=Health)
    def health() -> Health:
        return Health(
            status="ok",
            version=__version__,
            segmenter=segmenter.name,
            depth=depth_model.name,
            assistant=assistant.name,
        )

    @app.post("/v1/segment", response_model=SegmentResponse, dependencies=[Depends(check_key)])
    async def segment(request: Request) -> SegmentResponse:
        image = await read_upload(request)
        height, width = image.shape[:2]
        # Models are slow and block, so they run off the event loop.
        results = await _run(segmenter.segment, image)
        return SegmentResponse(
            model=segmenter.name,
            width=width,
            height=height,
            masks=[
                Mask(
                    name=r.name,
                    label=r.label,
                    score=round(float(r.score), 4),
                    rle=Rle(counts=rle.encode(r.mask)),
                )
                for r in results
            ],
        )

    @app.post("/v1/depth", response_model=DepthResponse, dependencies=[Depends(check_key)])
    async def depth(request: Request) -> DepthResponse:
        image = await read_upload(request)
        height, width = image.shape[:2]
        values = (await _run(depth_model.estimate, image)).depth.astype(np.float64)
        low, high = float(values.min()), float(values.max())
        scaled = np.zeros_like(values) if high == low else (values - low) / (high - low)
        as16 = np.round(scaled * 65535).astype(np.uint16)
        buffer = io.BytesIO()
        Image.fromarray(as16).save(buffer, format="PNG")
        return DepthResponse(
            model=depth_model.name,
            width=width,
            height=height,
            png16=base64.b64encode(buffer.getvalue()).decode("ascii"),
        )

    @app.post("/v1/assistant", response_model=AssistantResponse, dependencies=[Depends(check_key)])
    async def assist(request: Request) -> AssistantResponse:
        if request.headers.get("content-type", "").split(";")[0].strip() != "application/json":
            raise HTTPException(status_code=415, detail="Send JSON with type application/json")
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > MAX_JSON_BYTES:
                raise HTTPException(status_code=413, detail="Request is too large")
        try:
            ask = AssistantRequest.model_validate(json.loads(body))
        except (ValueError, ValidationError) as error:
            raise HTTPException(status_code=400, detail="Send {scene, prompt} as JSON") from error
        try:
            plan = await run_in_threadpool(run_assistant, assistant, ask.scene, ask.prompt)
        except SceneError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        return AssistantResponse(
            model=assistant.name, message=plan.message, ops=plan.ops, dropped=plan.dropped
        )

    return app


async def _run(function, image):
    try:
        return await run_in_threadpool(function, image)
    except ModelUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


app = create_app()
