# Step 1 - Calibration core

Done when: a simulated scan with blur and room light decodes to within about
one pixel of the true map, and the tests pass with one command.

## Check it

```
cd packages/calib_core
dart pub get
dart test
dart run example/simulated_scan.dart
```

## What the tests cover

- Gray code round trip and the one-bit-per-step property
- Pattern count, order, inverse pairs and minimum stripe width
- Exact decode of a perfect one-to-one setup
- Sub-pixel accuracy on a tilted wall with lens distortion and a box
- A blurry projector with a noisy camera
- Sharp depth edges after smoothing
- Each failure verdict: too bright, too dim, overexposed, no signal, partial view
- Save and load, bad files, and the projector-to-camera lookup

## Open points for step 2

- Record real capture sets and replay them through `decodeScan`.
- Tune `minContrast` and the verdict thresholds on real frames.
- Decode time on a phone at full camera resolution has not been measured.
