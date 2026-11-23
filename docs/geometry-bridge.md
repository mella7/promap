# Geometry bridge (mapping_core)

Part of step 4, written early because it needs no hardware. It connects the
calibration map to the scene: segmentation masks in camera pixels go in,
projector-space surfaces come out as `AddSurface` operations.

## Check it

```
cd packages/mapping_core
dart pub get
dart analyze
dart test
```

## What the tests cover

- Rectangle and polygon fill, dilate, erode, close, border handling
- Connected pieces, sizes and bounding boxes, corner-touching pixels
- Outline tracing of a pixel, a rectangle, an L shape and a shape with a hole
- Simplification keeping real corners and removing straight-edge points
- On the simulator: a box face and a wall patch match the true shape
  (IoU above 0.95), a mask across a depth edge splits into two surfaces,
  tiny and unreachable masks give nothing, ids continue from the scene, and
  the operations apply and undo as one step
- The tap fallback to the nearest decoded pixel
