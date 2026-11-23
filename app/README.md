# promap app

The Flutter app. For now it runs as a Linux desktop app with the scan
simulator in place of the phone camera and the projector, so the whole flow
can be tried before the hardware is set up.

## First-time setup

The repo only holds the Dart code. Generate the platform folders once:

```
cd app
flutter create --project-name promap_app --org me.mella7 --platforms=linux,android .
git status
```

`flutter create .` only adds missing files (the `linux/` and `android/`
folders and a few config files). If `git status` shows it changed
`lib/main.dart`, `pubspec.yaml` or anything in `test/`, put them back with
`git restore <file>`.

## Run it

```
flutter run -d linux
```

That uses built-in demo shapes for "Find surfaces". To go through the
backend instead, start it (see `backend/README.md`) and run:

```
flutter run -d linux --dart-define=PROMAP_BACKEND=http://127.0.0.1:8000
```

If the backend has an API key set, add `--dart-define=PROMAP_API_KEY=...`.
That's fine for development only: anything passed with `--dart-define` ends
up inside the app.

## What you can do

The window has the camera view on the left and the projector output on the
right.

1. **Scan.** The output plays the 32 stripe patterns and the camera view
   shows what the fake camera sees. At the end you get the scan report.
2. **Tap the camera view.** A dot appears on the projector output at the
   matching spot, and in the camera view you can see it land on the box or
   the wall.
3. **Find surfaces.** The app takes a photo under white light and asks for
   surfaces: from the backend if one is set, from built-in demo shapes
   otherwise. The masks go through `mapping_core` and show up as coloured
   surfaces. Undo and redo work on the whole step. If the backend is down
   you get a message saying so, and nothing changes.
4. **Pick a theme.** Every surface gets an animated effect in one step
   (undo takes it back). Tap a surface in the camera view to select it and
   switch its effect, then tune it with the sliders, switches and colour
   dots underneath. Sliders preview live and save one undo step when you
   let go. The frame rate shows in the corner of the output.
5. **Save / Open saved.** Writes the scene and the calibration to
   `~/promap-projects/last` and loads them back, so a mapping survives a
   restart without scanning again.
6. **Try the presets.** Bright room, weak projector, overexposed camera and
   camera aimed away each fail with their own message.
7. **White light / Show mapping** switches between lighting the room and
   showing the surfaces.

## How it's put together

| File | What it does |
| --- | --- |
| `lib/devices/camera_source.dart` | The camera interface. The phone camera plugs in here in step 0 |
| `lib/devices/output_controller.dart` | What the projector shows: white, a pattern or the scene |
| `lib/devices/simulated_camera.dart` | Fake camera that photographs the output through the simulator, plus the presets |
| `lib/scan/scan_controller.dart` | Shows each pattern, waits, captures, then decodes in a background isolate |
| `lib/cloud/surface_finder.dart` | Where surfaces come from: the backend, or demo shapes |
| `lib/cloud/png.dart`, `rle.dart` | Tiny PNG encoder for uploads, decoder for the backend's masks |
| `lib/workbench.dart` | Ties camera, output, scan, calibration and scene store together |
| `lib/ui/effect_painter.dart` | Draws each effect from the `effects` package onto a surface |
| `lib/ui/` | Camera view, animated output view with fps, and the page |

On the phone, `OutputView` goes on the external display and the simulated
camera is replaced by the real one. The rest stays the same.

## Tests

```
flutter test
```

They run a full simulated scan, check that a tap lands within a pixel of the
true spot, find surfaces and undo them, check the bright-room failure, and
render the page once. The cloud tests check the PNG encoder, decode a real
backend reply (`test/fixtures/segment_response.json`) and talk to a small
local HTTP server, including the error cases.
