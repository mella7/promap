# mapping_core

The bridge between the camera and the projector. It takes shapes found in the
camera image, such as segmentation masks from the AI, and turns them into
surfaces in projector pixels, using the calibration map from `calib_core`.
The result is a list of `scene_core` operations, so finding surfaces is one
undo step like any other edit. Plain Dart, no Flutter.

## How a mask becomes a surface

1. **Project.** Every camera pixel in the mask that the scan decoded marks the
   projector pixel lighting it (`projectMask`).
2. **Close.** The camera and projector have different resolutions and angles,
   so the projected mask has small holes. A dilate-then-erode pass fills them
   (`BinaryMask.close`).
3. **Split.** The mask is split into connected pieces and pieces under
   `minArea` pixels are dropped as noise (`labelComponents`).
4. **Trace.** The outer edge of each piece is followed pixel by pixel
   (`traceOuterContour`).
5. **Simplify.** The staircase outline is reduced to its real corners
   (`simplifyClosed`, Douglas-Peucker).
6. **Add.** Each piece becomes an `AddSurface` operation with a fresh id
   (`surfaceOpsFromMasks`).

```dart
final ops = surfaceOpsFromMasks(store.scene, calibration, [
  CameraMask(boxTopMask, name: 'Box top', label: 'box'),
  CameraMask(wallMask, name: 'Wall', label: 'wall'),
]);
store.applyAll(ops, label: 'Find surfaces');
```

Working in projector space is what makes this hold up at depth edges. A mask
that covers both a box and the wall behind it lands in two separate places on
the projector, so it splits into two surfaces ("Wall", "Wall 2") instead of
one wrong polygon. `largestPieceOnly` keeps just the biggest.

`cameraToProjector` is the tap lookup: the projector position for a camera
pixel, falling back to the nearest decoded pixel when the tapped one was not
decoded.

## Accuracy

Against the simulator's known answer, the box face and a large wall patch
both come out at an IoU of about 0.98 (measured in a Python prototype of the
same steps; the Dart tests require at least 0.95).

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `closeRadius` | 2 | Holes up to about 4 projector pixels wide are filled |
| `minArea` | 30 | Pieces smaller than this many projector pixels are dropped |
| `simplifyTolerance` | 1.5 | How far the outline may move when corners are removed |
| `largestPieceOnly` | false | One surface per mask instead of one per piece |

## Merging surfaces

`mergeOutlines(a, b, width, height)` draws two outlines into one mask,
closes seams up to 3 pixels (neighbouring surfaces from a scan often have
one), and traces the result again. It returns null when the two still don't
touch, so the app can refuse instead of making a surface with two pieces.

## Not here yet

- Holes inside a surface are filled, not kept. A window frame with the glass
  cut out would need holes in `scene_core` first.
- Splitting one flat-looking mask into faces where it bends needs depth, which
  comes with the backend (step 4).
