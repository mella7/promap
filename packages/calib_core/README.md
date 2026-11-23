# calib_core

Works out which projector pixel lights each camera pixel. Plain Dart, no
Flutter and no device code, so it runs and tests on a laptop.

## How it works

1. `PatternSet` lists the images to project: white, black, then Gray-code
   stripes for x and y, each followed by its inverse.
2. The app projects each one and captures a camera frame (the simulator does
   this in tests).
3. `decodeScan` compares every stripe frame with its inverse, rebuilds the
   projector position per camera pixel, smooths it to sub-pixel precision and
   returns a `CorrespondenceMap` plus a `QualityReport`.

```dart
final patterns = PatternSet(1280, 720);
final frames = <GrayImage>[/* one camera frame per patterns.specs entry */];
final result = decodeScan(patterns, frames);

if (result.report.usable) {
  final spot = result.map.cameraToProjector(tapX, tapY); // null if unlit
  final bytes = result.map.toBytes();                     // save to a file
} else {
  print(result.report.message);                           // show to the user
}
```

## Choices worth knowing

- **Stripe width.** Projector pixels are grouped into cells of 2 (default
  `coarseShift: 1`), so the finest stripe is 4 pixels wide. A soft or slightly
  out-of-focus projector cannot show 1-pixel stripes reliably. A 720p
  projector needs 40 patterns.
- **Inverse patterns.** Each bit is read by comparing a pattern with its
  inverse at the same pixel, so surface colour and room light cancel out.
- **Sub-pixel step.** The raw decode is exact to one cell. Averaging each
  pixel with neighbours on the same surface brings the median error in the
  simulated scene from about 0.8 to about 0.2 projector pixels. Neighbours
  whose position differs by more than 1.5 cells are left out, so edges between
  objects stay sharp.
- **Coordinates.** Pixel centres: projector pixel 0 is centred at 0.0.

## Scan verdicts

| Verdict | Meaning | Map usable |
| --- | --- | --- |
| `ok` | Scan complete | Yes |
| `partialCoverage` | Camera sees under 60% of the projection | Yes |
| `overexposed` | Over 25% of the lit area is clipped | Yes, but rescan |
| `tooDim` | Projection visible but weak | No |
| `tooBright` | Room light drowns the projection | No |
| `noSignal` | Camera does not see the projection | No |

## Simulator

`SimScene` is a fake projector and camera with a known answer. It models a
tilted surface, camera lens distortion, a box at a different depth, patchy
surface colour, room light, projector blur and sensor noise.
`SimScene.standard()` is the scene the tests use.

## Not here yet

- Real capture sets recorded from a phone and projector (step 2).
- Projector lens parameters and real depth (step 8).
