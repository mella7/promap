import 'dart:math';

import 'package:calib_core/calib_core.dart';
import 'package:test/test.dart';

/// Distance in projector pixels between the decoded and the true position,
/// for every decoded camera pixel that really looks at the projection.
class ErrorStats {
  final List<double> sorted;
  final int falsePositives;
  final int visible;

  ErrorStats(this.sorted, this.falsePositives, this.visible);

  double get median => sorted[sorted.length ~/ 2];
  double get p95 => sorted[(sorted.length * 0.95).floor()];
  double get max => sorted.last;
  double get coverage => sorted.length / visible;
}

ErrorStats measure(CorrespondenceMap map, SimScene scene) {
  final errors = <double>[];
  var falsePositives = 0;
  var visible = 0;
  for (var v = 0; v < scene.cameraHeight; v++) {
    for (var u = 0; u < scene.cameraWidth; u++) {
      final sees = scene.seesProjector(u.toDouble(), v.toDouble());
      if (sees) visible++;
      final decoded = map.cameraToProjector(u, v);
      if (decoded == null) continue;
      if (!sees) {
        falsePositives++;
        continue;
      }
      final truth = scene.truth(u.toDouble(), v.toDouble());
      errors.add(sqrt(pow(decoded.x - truth.x, 2) + pow(decoded.y - truth.y, 2)));
    }
  }
  errors.sort();
  return ErrorStats(errors, falsePositives, visible);
}

void main() {
  test('a perfect one-to-one setup decodes every pixel to its own cell', () {
    final scene = SimScene(
      projectorWidth: 64,
      projectorHeight: 48,
      cameraWidth: 64,
      cameraHeight: 48,
      ambient: 0,
      gain: 200,
      noiseSigma: 0,
      blurRadius: 0,
      texturedSurface: false,
    );
    final patterns = PatternSet(64, 48);
    final result = decodeScan(patterns, scene.scan(patterns),
        options: const DecodeOptions(refineRadius: 0));

    expect(result.map.validCount, 64 * 48);
    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < 64; x++) {
        final p = result.map.cameraToProjector(x, y)!;
        expect((p.x - x).abs(), lessThanOrEqualTo(0.5));
        expect((p.y - y).abs(), lessThanOrEqualTo(0.5));
      }
    }
    expect(result.report.verdict, ScanVerdict.ok);
    expect(result.report.projectorCoverage, 1.0);
  });

  test('a realistic scene decodes to sub-pixel accuracy', () {
    final scene = SimScene.standard();
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));
    final stats = measure(result.map, scene);

    expect(stats.coverage, greaterThan(0.97));
    expect(stats.median, lessThan(0.4));
    expect(stats.p95, lessThan(0.9));
    expect(stats.falsePositives, lessThan(50));
    expect(result.report.verdict, ScanVerdict.ok);
    expect(result.report.projectorCoverage, greaterThan(0.9));
  });

  test('refinement beats the raw decode', () {
    final patterns = PatternSet(320, 240);
    final raw = decodeScan(patterns, SimScene.standard().scan(patterns),
        options: const DecodeOptions(refineRadius: 0));
    final refined = decodeScan(patterns, SimScene.standard().scan(patterns));
    final rawStats = measure(raw.map, SimScene.standard());
    final refinedStats = measure(refined.map, SimScene.standard());

    expect(rawStats.median, lessThan(1.2));
    expect(refinedStats.median, lessThan(rawStats.median / 2));
  });

  test('a blurry projector and a noisy camera still decode', () {
    final scene = SimScene.standard(blurRadius: 2, noiseSigma: 5);
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));
    final stats = measure(result.map, scene);

    expect(stats.coverage, greaterThan(0.95));
    expect(stats.median, lessThan(0.5));
    expect(stats.p95, lessThan(1.2));
    expect(result.report.usable, isTrue);
  });

  test('the depth step at the box edge is not smeared', () {
    final scene = SimScene.standard(noiseSigma: 0);
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));
    final stats = measure(result.map, scene);

    // The box is shifted by 14 projector pixels. Averaging across its edge
    // would produce errors of several pixels.
    expect(stats.max, lessThan(3.5));
  });

  test('a bright room is reported as too bright', () {
    final scene = SimScene.standard(ambient: 210, gain: 30);
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));

    expect(result.report.verdict, ScanVerdict.tooBright);
    expect(result.report.usable, isFalse);
  });

  test('a weak projection in a dark room is reported as too dim', () {
    final scene = SimScene.standard(gain: 35);
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));

    expect(result.report.verdict, ScanVerdict.tooDim);
  });

  test('an overexposed camera is reported', () {
    final scene = SimScene.standard(gain: 400);
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));

    expect(result.report.verdict, ScanVerdict.overexposed);
    expect(result.report.saturatedFraction, greaterThan(0.9));
  });

  test('a camera pointed away from the projection reports no signal', () {
    final scene = SimScene(
      projectorWidth: 320,
      projectorHeight: 240,
      cameraWidth: 480,
      cameraHeight: 360,
      homography: const [1, 0, 10000, 0, 1, 10000, 0, 0, 1],
    );
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));

    expect(result.report.verdict, ScanVerdict.noSignal);
    expect(result.map.validCount, lessThan(50));
  });

  test('seeing only part of the projection is reported', () {
    final scene = SimScene(
      projectorWidth: 320,
      projectorHeight: 240,
      cameraWidth: 480,
      cameraHeight: 360,
      homography: const [0.86, 0.05, -275, -0.03, 0.90, -38, 1.2e-4, -0.8e-4, 1],
    );
    final patterns = PatternSet(320, 240);
    final result = decodeScan(patterns, scene.scan(patterns));

    expect(result.report.verdict, ScanVerdict.partialCoverage);
    expect(result.report.usable, isTrue);
  });

  test('the wrong number of frames is rejected', () {
    final patterns = PatternSet(64, 48);
    expect(() => decodeScan(patterns, [GrayImage(8, 8)]), throwsArgumentError);
  });
}
