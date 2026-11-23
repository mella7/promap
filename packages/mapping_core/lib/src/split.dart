import 'dart:math';

import 'package:scene_core/scene_core.dart';

import 'mask.dart';
import 'surfaces.dart';

/// Cuts surface [outline] in two along the straight line through [from] and
/// [to], in projector pixels. The line carries on past both points, so they
/// don't need to be on the edge.
///
/// Returns the two outlines, larger first, or null when the line misses the
/// surface or one side would be smaller than [minArea] pixels. If a side
/// falls apart into several pieces (a U shape cut across both arms) only its
/// largest piece is kept.
(List<Vec2>, List<Vec2>)? splitOutline(
  List<Vec2> outline,
  Vec2 from,
  Vec2 to,
  int width,
  int height, {
  int minArea = 30,
  double simplifyTolerance = 1.5,
}) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  if (dx * dx + dy * dy < 1) return null;

  final whole = BinaryMask.fromPolygon(
      width, height, [for (final v in outline) Point(v.x, v.y)]);
  final left = BinaryMask(width, height);
  final right = BinaryMask(width, height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (whole.data[i] == 0) continue;
      // Which side of the line the pixel centre is on.
      final side = dx * (y - from.y) - dy * (x - from.x);
      (side < 0 ? left : right).data[i] = 1;
    }
  }
  if (left.count < minArea || right.count < minArea) return null;

  final options = SurfaceOptions(
    closeRadius: 1,
    minArea: minArea,
    simplifyTolerance: simplifyTolerance,
    largestPieceOnly: true,
  );
  final a = outlinesOf(left, options: options);
  final b = outlinesOf(right, options: options);
  if (a.isEmpty || b.isEmpty) return null;
  return left.count >= right.count ? (a.first, b.first) : (b.first, a.first);
}
