import 'dart:typed_data';

import 'package:calib_core/calib_core.dart';
import 'package:test/test.dart';

void main() {
  late CorrespondenceMap map;

  setUpAll(() {
    final scene = SimScene.standard();
    final patterns = PatternSet(320, 240);
    map = decodeScan(patterns, scene.scan(patterns)).map;
  });

  test('save and load give back the same map', () {
    final copy = CorrespondenceMap.fromBytes(map.toBytes());

    expect(copy.cameraWidth, map.cameraWidth);
    expect(copy.cameraHeight, map.cameraHeight);
    expect(copy.projectorWidth, map.projectorWidth);
    expect(copy.projectorHeight, map.projectorHeight);
    expect(copy.valid, map.valid);
    expect(copy.projX, map.projX);
    expect(copy.projY, map.projY);
  });

  test('loading rejects files that are not calibration maps', () {
    expect(() => CorrespondenceMap.fromBytes(Uint8List(10)),
        throwsFormatException);
    expect(() => CorrespondenceMap.fromBytes(Uint8List(64)),
        throwsFormatException);
    final truncated = map.toBytes().sublist(0, 1000);
    expect(() => CorrespondenceMap.fromBytes(Uint8List.fromList(truncated)),
        throwsFormatException);
  });

  test('pixels outside the image or the projection return null', () {
    expect(map.cameraToProjector(-1, 0), isNull);
    expect(map.cameraToProjector(0, 9999), isNull);
    // The top-left camera corner looks past the edge of the projection.
    expect(map.cameraToProjector(0, 0), isNull);
  });

  test('the inverse map leads back to the camera pixel', () {
    // Same view as the standard scene but without the box, so every
    // projector pixel is seen from exactly one place.
    final scene = SimScene(
      projectorWidth: 320,
      projectorHeight: 240,
      cameraWidth: 480,
      cameraHeight: 360,
      homography: const [0.86, 0.05, -45, -0.03, 0.90, -38, 1.2e-4, -0.8e-4, 1],
      radialDistortion: 0.32,
    );
    final patterns = PatternSet(320, 240);
    final flat = decodeScan(patterns, scene.scan(patterns)).map;
    final inverse = flat.buildInverse();
    var checked = 0;
    for (var v = 60; v < 320; v += 13) {
      for (var u = 70; u < 420; u += 17) {
        final p = flat.cameraToProjector(u, v);
        if (p == null) continue;
        final back = inverse.projectorToCamera(p.x.round(), p.y.round());
        expect(back, isNotNull);
        expect((back!.x - u).abs(), lessThan(2.0));
        expect((back.y - v).abs(), lessThan(2.0));
        checked++;
      }
    }
    expect(checked, greaterThan(200));
  });

  test('hole filling raises coverage above what was measured', () {
    final measuredOnly = map.buildInverse(holeFillPasses: 0);
    final filled = map.buildInverse(holeFillPasses: 8);
    int count(Uint8List mask) => mask.fold(0, (a, b) => a + b);

    expect(measuredOnly.measuredCoverage, greaterThan(0.9));
    expect(count(filled.valid), greaterThan(count(measuredOnly.valid)));
    expect(inverseNull(filled, -1, 0), isTrue);
  });
}

bool inverseNull(InverseMap inverse, int x, int y) =>
    inverse.projectorToCamera(x, y) == null;
