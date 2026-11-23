import 'dart:math';

import 'package:calib_core/calib_core.dart';

import 'mask.dart';

/// Moves a camera-space mask into projector space with a calibration map.
///
/// Every camera pixel in [cameraMask] that the scan decoded marks the
/// projector pixel lighting it. Because the camera and projector have
/// different resolutions and angles, the result has small holes; close it
/// (see [BinaryMask.close]) before tracing outlines.
BinaryMask projectMask(CorrespondenceMap map, BinaryMask cameraMask) {
  if (cameraMask.width != map.cameraWidth ||
      cameraMask.height != map.cameraHeight) {
    throw ArgumentError('Mask is ${cameraMask.width}x${cameraMask.height} but '
        'the camera is ${map.cameraWidth}x${map.cameraHeight}');
  }
  final pw = map.projectorWidth;
  final ph = map.projectorHeight;
  final out = BinaryMask(pw, ph);
  for (var i = 0; i < cameraMask.data.length; i++) {
    if (cameraMask.data[i] == 0 || map.valid[i] == 0) continue;
    final px = (map.projX[i] + 0.5).floor();
    final py = (map.projY[i] + 0.5).floor();
    if (px < 0 || py < 0 || px >= pw || py >= ph) continue;
    out.data[py * pw + px] = 1;
  }
  return out;
}

/// The projector position for camera pixel ([x], [y]).
///
/// When that exact pixel was not decoded (an edge, a shadow, a noisy spot),
/// the nearest decoded pixel within [searchRadius] is used instead. Returns
/// null when there is none, which means the projector cannot reach that
/// spot.
Point<double>? cameraToProjector(CorrespondenceMap map, int x, int y,
    {int searchRadius = 3}) {
  final direct = map.cameraToProjector(x, y);
  if (direct != null) return direct;
  Point<double>? best;
  var bestDistance = double.infinity;
  for (var dy = -searchRadius; dy <= searchRadius; dy++) {
    for (var dx = -searchRadius; dx <= searchRadius; dx++) {
      final d = (dx * dx + dy * dy).toDouble();
      if (d >= bestDistance || d > searchRadius * searchRadius) continue;
      final p = map.cameraToProjector(x + dx, y + dy);
      if (p == null) continue;
      best = p;
      bestDistance = d;
    }
  }
  return best;
}
