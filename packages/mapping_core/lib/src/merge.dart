import 'dart:math';

import 'package:scene_core/scene_core.dart';

import 'components.dart';
import 'mask.dart';
import 'surfaces.dart';

/// The outline of surfaces [a] and [b] as one shape, in projector pixels, or
/// null when they don't touch.
///
/// Both outlines are drawn into a [width] x [height] mask, gaps up to [gap]
/// pixels between them are closed (neighbouring surfaces from the scan often
/// have a seam of a pixel or two), and the result is traced again. When that
/// still leaves more than one piece the two are too far apart to be one
/// surface.
List<Vec2>? mergeOutlines(
  List<Vec2> a,
  List<Vec2> b,
  int width,
  int height, {
  int gap = 3,
  double simplifyTolerance = 1.5,
}) {
  final union = _draw(a, width, height);
  final other = _draw(b, width, height);
  for (var i = 0; i < union.data.length; i++) {
    if (other.data[i] == 1) union.data[i] = 1;
  }
  if (union.count == 0) return null;
  if (labelComponents(union.close(gap)).components.length != 1) return null;
  final outlines = outlinesOf(
    union,
    options: SurfaceOptions(
      closeRadius: gap,
      minArea: 1,
      simplifyTolerance: simplifyTolerance,
    ),
  );
  return outlines.length == 1 ? outlines.first : null;
}

BinaryMask _draw(List<Vec2> outline, int width, int height) =>
    BinaryMask.fromPolygon(
        width, height, [for (final v in outline) Point(v.x, v.y)]);
