// Runs a full scan against the simulator and prints the result.
//
//   dart run example/simulated_scan.dart
import 'dart:io';

import 'package:calib_core/calib_core.dart';

void main() {
  final scene = SimScene.standard();
  final patterns = PatternSet(scene.projectorWidth, scene.projectorHeight);
  print('Projecting ${patterns.specs.length} patterns, '
      'finest stripe ${patterns.minStripeWidth} px');

  final watch = Stopwatch()..start();
  final frames = scene.scan(patterns);
  final captureMs = watch.elapsedMilliseconds;
  watch.reset();
  final result = decodeScan(patterns, frames);
  print('Simulated capture ${captureMs} ms, decode ${watch.elapsedMilliseconds} ms');
  print(result.report);

  // "Tap" the middle of the camera image and see where the projector should
  // draw a dot.
  const tapX = 240;
  const tapY = 180;
  final hit = result.map.cameraToProjector(tapX, tapY);
  final truth = scene.truth(tapX.toDouble(), tapY.toDouble());
  if (hit == null) {
    print('Tap at ($tapX, $tapY): the projector cannot reach that spot');
  } else {
    print('Tap at ($tapX, $tapY) -> projector '
        '(${hit.x.toStringAsFixed(2)}, ${hit.y.toStringAsFixed(2)}), '
        'true answer (${truth.x.toStringAsFixed(2)}, ${truth.y.toStringAsFixed(2)})');
  }

  final file = File('standard_scene.pmap');
  file.writeAsBytesSync(result.map.toBytes());
  print('Saved ${file.path} (${file.lengthSync()} bytes)');
}
