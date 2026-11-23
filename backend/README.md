# promap backend

The cloud side of promap. It takes one camera photo and sends back what the
AI found in it. For now the models are fakes with fixed answers that line up
with the app's simulator, so the app-to-cloud path can be built and tested
before any real model is picked.

Nothing is stored. Each request is an image in, JSON out.

## Run it

```
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn promap_backend.main:app --reload
```

Check it's up: `curl http://127.0.0.1:8000/health`

Then start the app against it:

```
cd app
flutter run -d linux --dart-define=PROMAP_BACKEND=http://127.0.0.1:8000
```

Or in Docker:

```
docker build -t promap-backend backend
docker run --rm -p 8000:8000 promap-backend
```

## Endpoints

| Method and path | Body | Returns |
| --- | --- | --- |
| `GET /health` | | status, version, which models are loaded |
| `POST /v1/segment` | PNG or JPEG image as the raw body | surfaces as named masks |
| `POST /v1/depth` | PNG or JPEG image as the raw body | relative depth as a 16-bit PNG |

The full format, including how masks are encoded, is in
[docs/backend-api.md](../docs/backend-api.md). Interactive docs are at
`http://127.0.0.1:8000/docs` while it runs.

## Settings

All from environment variables, see `.env.example`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `PROMAP_SEGMENTER` | `fake` | Which segmentation model to load |
| `PROMAP_DEPTH` | `fake` | Which depth model to load |
| `PROMAP_API_KEY` | empty | If set, requests need it in the `X-API-Key` header |
| `PROMAP_MAX_UPLOAD_BYTES` | 10000000 | Larger uploads get 413 |
| `PROMAP_MAX_IMAGE_SIDE` | 4096 | Larger images get 400, checked before decoding |

## Adding a real model

1. Write a class with a `name` and a `segment(image)` (or `estimate(image)`)
   method in `promap_backend/models/`, following `base.py`.
2. Register it in `models/registry.py`.
3. Set `PROMAP_SEGMENTER` to its name.

The API and the app don't change. Check the model's licence first (see the
notes in the roadmap); some popular ones are non-commercial.

## Tests

```
pytest
ruff check .
```
