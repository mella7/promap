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

SAM is driven by our own loop in `models/sam_auto.py`, not the transformers
mask-generation pipeline. The pipeline placed its prompt grid wrong on
non-square photos (on a portrait photo only the left 73% got prompts) and
blew every mask up to full size before filtering, which was slow and used
gigabytes. Ours encodes the photo once, spreads a grid of prompts over all
of it, drops unsure (`PROMAP_SAM_MIN_IOU`) and blurry
(`PROMAP_SAM_MIN_STABILITY`) masks and repeats at SAM's 256x256 size, and
only scales up the survivors.

Then `models/postprocess.py` turns them into surfaces: drops tiny and huge
ones, cuts each box out of the wall behind it so surfaces don't overlap, and
keeps the 12 largest.

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

On a CPU, SAM is slow. Encoding the photo takes a couple of seconds, then
every prompt costs about 0.1 s in SAM's mask decoder. The grid is
`PROMAP_SAM_POINTS_PER_SIDE` squared: 32 is 1024 prompts (about 2 minutes on
a laptop), 16 is 256 (under 30 s) and may miss small things. Use 16 on a
laptop; on a GPU 32 takes a few seconds.

Prompts go through in batches of `PROMAP_POINTS_PER_BATCH` (default 16). A
batch of 64 needs about 2.5 GB on top of the model, 16 needs about 0.5 GB.
Same result either way. With an NVIDIA GPU set `PROMAP_DEVICE=cuda`,
install the normal torch build and raise the batch to 64.

The CLI prints where masks drop out, like
`256 prompts -> 768 masks -> 300 sure -> 120 stable -> 30 distinct`. If a
wall you expected is missing, try `--min-iou 0.6 --min-stability 0.8`.

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
| `PROMAP_SAM_POINTS_PER_SIDE` | 32 | SAM prompt grid; 16 is 4x faster, may miss small things |
| `PROMAP_SAM_MIN_IOU` | 0.75 | Drop masks SAM itself scores lower |
| `PROMAP_SAM_MIN_STABILITY` | 0.9 | Drop masks with blurry edges |
| `PROMAP_POINTS_PER_BATCH` | 16 | Prompts per batch; 64 needs about 2.5 GB more memory |
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
