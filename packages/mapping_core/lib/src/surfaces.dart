import 'dart:math';

import 'package:calib_core/calib_core.dart';
import 'package:scene_core/scene_core.dart';

import 'components.dart';
import 'contour.dart';
import 'mask.dart';
import 'projection.dart';

/// A shape found in the camera image, for example one segmentation result.
class CameraMask {
  final BinaryMask mask;

  /// The name the user sees, such as "Box top".
  final String name;

  /// What the shape is, such as "window". Null when unknown.
  final String? label;

  const CameraMask(this.mask, {required this.name, this.label});
}

/// Tuning for [surfaceOpsFromMasks]. Sizes are in projector pixels.
class SurfaceOptions {
  /// Gaps narrower than about twice this are filled before tracing.
  final int closeRadius;

  /// Pieces smaller than this many pixels are dropped as noise.
  final int minArea;

  /// How far, in pixels, the simplified outline may stray from the traced
  /// one. Higher gives fewer corners.
  final double simplifyTolerance;

  /// Keep only the largest piece of each mask instead of one surface per
  /// piece.
  final bool largestPieceOnly;

  const SurfaceOptions({
    this.closeRadius = 2,
    this.minArea = 30,
    this.simplifyTolerance = 1.5,
    this.largestPieceOnly = false,
  });
}

/// The outline polygons, in projector pixels, of the pieces of one
/// projector-space mask, largest first.
///
/// Corners are moved by half a pixel so they sit on pixel edges in the scene's
/// coordinates, where (0, 0) is the centre of the top-left pixel.
List<List<Vec2>> outlinesOf(BinaryMask projectorMask,
    {SurfaceOptions options = const SurfaceOptions()}) {
  final closed = projectorMask.close(options.closeRadius);
  final labels = labelComponents(closed);
  var pieces = labels.bySize.where((c) => c.area >= options.minArea).toList();
  if (options.largestPieceOnly && pieces.length > 1) {
    pieces = [pieces.first];
  }

  final maxX = projectorMask.width - 0.5;
  final maxY = projectorMask.height - 0.5;
  final outlines = <List<Vec2>>[];
  for (final piece in pieces) {
    final contour = traceOuterContour(labels.maskOf(piece));
    final simple = simplifyClosed(contour, options.simplifyTolerance);
    if (simple.length < 3) continue;
    final outline = [
      for (final p in simple)
        Vec2(min(max(p.x - 0.5, -0.5), maxX), min(max(p.y - 0.5, -0.5), maxY))
    ];
    if (polygonArea([for (final v in outline) Point(v.x, v.y)]).abs() < 1) {
      continue;
    }
    outlines.add(outline);
  }
  return outlines;
}

/// Builds one [AddSurface] operation per piece of every mask, ready to apply
/// to [scene] as a single undo step with `store.applyAll(...)`.
///
/// Masks are in camera pixels; the resulting surfaces are in projector
/// pixels. A mask that falls on an edge between two objects at different
/// depths usually splits into two pieces in projector space, and each becomes
/// its own surface ("Box", "Box 2"). New ids continue from the scene's
/// existing ones.
List<AddSurface> surfaceOpsFromMasks(
  Scene scene,
  CorrespondenceMap map,
  List<CameraMask> masks, {
  SurfaceOptions options = const SurfaceOptions(),
}) {
  if (map.projectorWidth != scene.projectorWidth ||
      map.projectorHeight != scene.projectorHeight) {
    throw ArgumentError('The calibration map and the scene are for '
        'different projector sizes');
  }
  final ids = _IdSequence(scene);
  final ops = <AddSurface>[];
  for (final cameraMask in masks) {
    final outlines =
        outlinesOf(projectMask(map, cameraMask.mask), options: options);
    for (var i = 0; i < outlines.length; i++) {
      ops.add(AddSurface(Surface(
        id: ids.next(),
        name: i == 0 ? cameraMask.name : '${cameraMask.name} ${i + 1}',
        label: cameraMask.label,
        vertices: outlines[i],
      )));
    }
  }
  return ops;
}

/// Hands out "s1", "s2"... starting after the highest id in the scene.
class _IdSequence {
  int _number;

  _IdSequence(Scene scene)
      : _number = int.parse(scene.nextSurfaceId().substring(1)) - 1;

  String next() => 's${++_number}';
}
