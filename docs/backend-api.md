# Backend API

The app sends one camera photo and gets back what the models found. Images go
as the raw request body, not as a form upload. Results are JSON. Nothing is
stored on the server.

Base URL in development: `http://127.0.0.1:8000`

## Authentication

If the server has `PROMAP_API_KEY` set, every `/v1/...` request needs the
same value in the `X-API-Key` header. A missing or wrong key gets `401`.
`/health` never needs a key.

## GET /health

```json
{"status": "ok", "version": "0.1.0", "segmenter": "fake", "depth": "fake"}
```

## POST /v1/segment

Body: the photo, `Content-Type: image/png` or `image/jpeg`. The app sends an
8-bit greyscale PNG of the camera frame taken under white projector light.

```json
{
  "model": "fake",
  "width": 480,
  "height": 360,
  "masks": [
    {"name": "Box top", "label": "box", "score": 0.9, "rle": {"counts": [62610, 80, 400, 80]}}
  ]
}
```

- `width` and `height` are the photo's size. The app refuses a reply whose size
  doesn't match the photo it sent.
- `name` is shown to the user. `label` says what the thing is ("box",
  "window", "wall") and may be null. The fake model gives labels; SAM 2.1
  doesn't, so its surfaces are "Surface 1", "Surface 2" and so on with a
  null label, largest first.
- Masks don't overlap with SAM 2.1: a box in front of a wall is cut out of
  the wall's mask.
- `score` is the model's confidence, 0 to 1.
- `rle.counts` is the mask, run-length encoded (below).

### Mask encoding

Runs over the pixels in row order: left to right, then top to bottom. Runs
alternate between "not in the mask" and "in the mask", and always start with
"not in the mask". So a mask whose first pixel is set starts with a run of 0.
The runs add up to `width * height`.

Example, a 3x2 image:

```
1 1 0
0 1 1      ->  counts [0, 2, 2, 2]
```

## POST /v1/depth

Same body as `/v1/segment`.

```json
{"model": "fake", "width": 480, "height": 360, "png16": "<base64>"}
```

`png16` is a 16-bit greyscale PNG, base64-encoded, the same size as the photo.
0 is the farthest point in the photo and 65535 the closest. It's relative
only: the numbers don't mean centimetres, and two photos can't be compared.
The app doesn't use depth yet.

## Errors

Errors come back as `{"detail": "<message>"}` with these codes:

| Code | When |
| --- | --- |
| 400 | Empty body, not a readable PNG or JPEG, or larger than the side limit |
| 401 | Missing or wrong API key |
| 413 | Upload larger than the byte limit |
| 415 | Content type isn't `image/png` or `image/jpeg` |
| 503 | The configured model can't run, usually because the ml extra isn't installed. The detail says what to do |
