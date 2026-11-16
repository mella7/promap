# promap

A phone app that maps projections onto real objects without manual setup.
Connect a phone to a projector, scan the scene, and assign effects to the
surfaces it finds.

## Layout

| Folder | What it is | Status |
| --- | --- | --- |
| `packages/calib_core` | Structured-light calibration in plain Dart | Step 1, written |
| `packages/scene_core` | Scene graph, typed operations, undo | Step 3, not started |
| `packages/effects` | Effect format, shaders, themes | Step 5, not started |
| `app` | Flutter app: phone UI, projector output, device layer | Steps 0 and 2, needs hardware |
| `backend` | FastAPI service for segmentation, depth, generation, assistant | Step 4, not started |
| `schema` | Scene JSON Schema shared by app and backend | Step 3, not started |
| `docs` | Notes per step | |

## Run step 1

You need the Dart SDK 3.4 or newer (it ships with Flutter).

```
cd packages/calib_core
dart pub get
dart test
dart run example/simulated_scan.dart
```

`dart test` runs a full scan against a simulated projector and camera and
checks the decoded map against the known answer. The example prints the scan
report and saves a calibration file.

## Rules

- Secrets go in `.env`, which is ignored by Git. Never put keys in code.
- Each step ends with something you can run.
- Computer-vision code is tested against simulated or recorded input, so it
  never needs the hardware to be checked.
