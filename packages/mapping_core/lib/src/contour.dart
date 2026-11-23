import 'dart:math';

import 'mask.dart';

/// The outer outline of the largest shape in [mask], as a closed polygon of
/// pixel corners.
///
/// Corner (x, y) is the top-left corner of pixel (x, y), so a single pixel at
/// (0, 0) has the outline (0,0) (1,0) (1,1) (0,1). The outline runs clockwise
/// on screen. Returns an empty list for an empty mask.
List<Point<int>> traceOuterContour(BinaryMask mask) {
  final w = mask.width;
  final h = mask.height;
  final stride = w + 1;
  int key(int x, int y) => y * stride + x;

  // Every pixel edge between the shape and the background, pointing so the
  // shape is on the right-hand side when walking along it.
  final edges = <int, List<int>>{};
  void addEdge(int x0, int y0, int x1, int y1) {
    (edges[key(x0, y0)] ??= <int>[]).add(key(x1, y1));
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!mask.get(x, y)) continue;
      if (!mask.get(x, y - 1)) addEdge(x, y, x + 1, y);
      if (!mask.get(x + 1, y)) addEdge(x + 1, y, x + 1, y + 1);
      if (!mask.get(x, y + 1)) addEdge(x + 1, y + 1, x, y + 1);
      if (!mask.get(x - 1, y)) addEdge(x, y + 1, x, y);
    }
  }

  // Chain the edges into closed loops. Where two loops touch at a corner,
  // take the right turn so the loops stay separate.
  List<Point<int>>? best;
  var bestArea = -1.0;
  while (edges.isNotEmpty) {
    final start = edges.keys.first;
    final loop = <Point<int>>[Point(start % stride, start ~/ stride)];
    var current = start;
    var previous = -1;
    while (true) {
      final options = edges[current]!;
      var chosen = options.first;
      if (options.length > 1 && previous >= 0) {
        final dx = current % stride - previous % stride;
        final dy = current ~/ stride - previous ~/ stride;
        final right = key(current % stride - dy, current ~/ stride + dx);
        if (options.contains(right)) chosen = right;
      }
      options.remove(chosen);
      if (options.isEmpty) edges.remove(current);
      previous = current;
      current = chosen;
      if (current == start) break;
      loop.add(Point(current % stride, current ~/ stride));
    }
    final area = polygonArea(loop).abs();
    if (area > bestArea) {
      bestArea = area;
      best = loop;
    }
  }
  return best ?? <Point<int>>[];
}

/// Signed area of a polygon (shoelace formula).
double polygonArea(List<Point<num>> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum / 2;
}

/// Removes points from a closed polygon that lie within [tolerance] of the
/// simplified outline (Douglas-Peucker). Staircase outlines from a pixel mask
/// collapse to their real corners.
List<Point<double>> simplifyClosed(List<Point<num>> polygon, double tolerance) {
  final points = [for (final p in polygon) Point(p.x.toDouble(), p.y.toDouble())];
  if (points.length <= 3) return points;

  // Split the loop at the point farthest from the first one, then simplify
  // each half as an open line.
  var far = 0;
  var farDistance = -1.0;
  for (var i = 1; i < points.length; i++) {
    final d = points[i].distanceTo(points[0]);
    if (d > farDistance) {
      farDistance = d;
      far = i;
    }
  }
  final first = _simplifyOpen(points.sublist(0, far + 1), tolerance);
  final second =
      _simplifyOpen([...points.sublist(far), points[0]], tolerance);
  return [
    ...first.sublist(0, first.length - 1),
    ...second.sublist(0, second.length - 1),
  ];
}

List<Point<double>> _simplifyOpen(List<Point<double>> points, double tolerance) {
  if (points.length < 3) return points;
  final a = points.first;
  final b = points.last;
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final length = sqrt(dx * dx + dy * dy);

  var index = 0;
  var maxDistance = -1.0;
  for (var i = 1; i < points.length - 1; i++) {
    final p = points[i];
    final d = length == 0
        ? p.distanceTo(a)
        : (dx * (p.y - a.y) - dy * (p.x - a.x)).abs() / length;
    if (d > maxDistance) {
      maxDistance = d;
      index = i;
    }
  }
  if (maxDistance <= tolerance) return [a, b];
  final left = _simplifyOpen(points.sublist(0, index + 1), tolerance);
  final right = _simplifyOpen(points.sublist(index), tolerance);
  return [...left.sublist(0, left.length - 1), ...right];
}
