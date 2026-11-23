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

## Real models

Two real models are wired in, both Apache 2.0 so they're fine for a
commercial app:

| Setting | Model | What it does |
| --- | --- | --- |
| `PROMAP_SEGMENTER=sam2` | SAM 2.1 small (`facebook/sam2.1-hiera-small`) | Finds every surface in the photo. No names, so they come back as "Surface 1", "Surface 2" |
| `PROMAP_DEPTH=depth_anything_v2` | Depth Anything V2 Small | Relative depth, closer is larger |

SAM returns lots of overlapping masks. `models/postprocess.py` cleans them
up: drops unsure, tiny and huge ones, removes duplicates, cuts each box out
of the wall behind it so surfaces don't overlap, and keeps the 12 largest.

### Install (CPU laptop)

PyTorch is big, so it's an extra. Get the CPU builds of torch and
torchvision first, they're much smaller than the default ones with CUDA.
SAM's image processor needs torchvision, so don't skip it:

```
source .venv/bin/activate
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
pip install -e ".[dev,ml]"
```

The first run downloads the weights into `~/.cache/huggingface` (roughly
200 MB for SAM 2.1 small and 100 MB for Depth Anything V2 Small).

### Try them on a photo

Take a photo of your wall with a box in front of it, then:

```
python -m promap_backend.cli segment room.jpg
python -m promap_backend.cli depth room.jpg
```

That writes `room.surfaces.png` (each surface in its own colour) and
`room.depth.png` (closer is brighter). It prints the load time and the run
time apart: the load includes the download the first time, the run is what
one request to the server costs. `--runs 3` repeats the run, since the first
one on a CPU is often a bit slower. For SAM, `--points 16` and
`--max-side 768` try the faster settings without touching `.env`.

### Run the server with them

```
PROMAP_SEGMENTER=sam2 PROMAP_DEPTH=depth_anything_v2 uvicorn promap_backend.main:app
```

On a CPU, segmenting a whole photo can take a while. SAM prompts a grid of
`PROMAP_SAM_POINTS_PER_SIDE` x `PROMAP_SAM_POINTS_PER_SIDE` points (default
32, so 1024 prompts), and the time grows with that. 16 is about 4x faster and
still finds walls, boards and boxes; it may miss small things. Lowering
`PROMAP_MODEL_MAX_SIDE` (default 1024) helps a bit too.
`PROMAP_POINTS_PER_BATCH` only trades memory for speed, it doesn't change the
result. With an NVIDIA GPU set `PROMAP_DEVICE=cuda` and install the normal
torch build.

The app's simulator photo is a checker wall, so SAM will happily find every
checker square in it. That's expected: judge the model on real photos with
the CLI, and keep using `fake` for the simulator.

If the ml extra isn't installed, the server still starts and the fake
models work. Asking for a real one returns 503 with a message saying what
to install.

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
| `PROMAP_SEGMENTER` | `fake` | `fake` or `sam2` |
| `PROMAP_DEPTH` | `fake` | `fake` or `depth_anything_v2` |
| `PROMAP_SAM_MODEL` | `facebook/sam2.1-hiera-small` | Any SAM 2.x checkpoint on Hugging Face |
| `PROMAP_DEPTH_MODEL` | `depth-anything/Depth-Anything-V2-Small-hf` | Keep to Small: Base and Large are non-commercial |
| `PROMAP_DEVICE` | `cpu` | `cpu` or `cuda` |
| `PROMAP_MODEL_MAX_SIDE` | 1024 | Photos are shrunk to this before SAM |
| `PROMAP_POINTS_PER_BATCH` | 64 | Lower uses less memory |
| `PROMAP_API_KEY` | empty | If set, requests need it in the `X-API-Key` header |
| `PROMAP_MAX_UPLOAD_BYTES` | 10000000 | Larger uploads get 413 |
| `PROMAP_MAX_IMAGE_SIDE` | 4096 | Larger images get 400, checked before decoding |

## Adding another model

1. Write a class with a `name` and a `segment(image)` (or `estimate(image)`)
   method in `promap_backend/models/`, following `base.py` and `hf.py`.
2. Register it in `models/registry.py`.
3. Set `PROMAP_SEGMENTER` (or `PROMAP_DEPTH`) to its name.

The API and the app don't change. Check the model's licence first (see the
notes in the roadmap); some popular ones are non-commercial.

## Tests

```
pytest
ruff check .
```
