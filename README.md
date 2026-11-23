# promap

A phone app that maps projections onto real objects without manual setup.
Connect a phone to a projector, scan the scene, and assign effects to the
surfaces it finds.

The plan and where each step stands is in [ROADMAP.md](ROADMAP.md).

## Layout

| Folder | What it is | Status |
| --- | --- | --- |
| `packages/calib_core` | Structured-light calibration in plain Dart | Done, 25 tests passing |
| `packages/scene_core` | Scene graph, typed operations, undo | Done, 37 tests passing |
| `packages/mapping_core` | Turns camera-space masks and shapes into projector-space surfaces | Written |
| `packages/effects` | Effect format, shaders, themes | Step 5, not started |
| `app` | Flutter app: phone UI, projector output, device layer | Runs on the laptop with the simulator. Phone part needs hardware |
| `backend` | FastAPI service for segmentation, depth, generation, assistant | Step 4, not started |
| `schema` | Scene JSON Schema shared by app and backend | Written |
| `docs` | Notes per step | |
| `scripts` | Small helper scripts, such as the schema check | |

## Run the tests

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

```
cd packages/scene_core
dart pub get
dart test
```

This checks the scene model, all operations and undo.

```
cd packages/mapping_core
dart pub get
dart test
```

This runs the scan simulator, then turns camera-space masks into surfaces and
compares them with the known answer.

The schema check needs Python and `jsonschema`:

```
pip install jsonschema
python scripts/check_schema.py
```

The app has its own setup steps, see [app/README.md](app/README.md):

```
cd app
flutter create --project-name promap_app --org me.mella7 --platforms=linux,android .
flutter test
flutter run -d linux
```

CI runs all of these on every push and pull request.

## Rules

- Secrets go in `.env`, which is ignored by Git. Never put keys in code.
- Each step ends with something you can run.
- Computer-vision code is tested against simulated or recorded input, so it
  never needs the hardware to be checked.
