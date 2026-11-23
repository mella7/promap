import 'dart:math';

import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

/// The outline of pixels [left]..[right) x [top]..[bottom), the way the scan
/// writes it: corners on pixel edges, half a pixel out from the centres.
List<Vec2> box(int left, int top, int right, int bottom) => [
      Vec2(left - 0.5, top - 0.5),
      Vec2(right - 0.5, top - 0.5),
      Vec2(right - 0.5, bottom - 0.5),
      Vec2(left - 0.5, bottom - 0.5),
    ];

double area(List<Vec2> outline) =>
    polygonArea([for (final v in outline) Point(v.x, v.y)]).abs();

void main() {
  test('two boxes side by side become one box', () {
    final merged = mergeOutlines(box(10, 10, 30, 40), box(30, 10, 60, 40), 100, 80);
    expect(merged, isNotNull);
    expect(merged!.length, 4);
    expect(area(merged), closeTo(50 * 30, 1));
    final xs = merged.map((v) => v.x);
    expect(xs.reduce(min), closeTo(9.5, 0.01));
    expect(xs.reduce(max), closeTo(59.5, 0.01));
  });

  test('a seam of a pixel or two is closed', () {
    final merged = mergeOutlines(box(10, 10, 30, 40), box(32, 10, 60, 40), 100, 80);
    expect(merged, isNotNull);
    expect(area(merged!), greaterThan(48 * 30));
  });

  test('an L shape keeps its corner', () {
    final merged = mergeOutlines(box(10, 10, 20, 50), box(20, 40, 50, 50), 100, 80);
    expect(merged, isNotNull);
    expect(merged!.length, 6);
    expect(area(merged), closeTo(10 * 40 + 30 * 10, 1));
  });

  test('surfaces far apart cannot be merged', () {
    expect(mergeOutlines(box(5, 5, 20, 20), box(50, 50, 70, 70), 100, 80), isNull);
  });

  test('a surface inside another merges into the outer one', () {
    final merged = mergeOutlines(box(10, 10, 60, 60), box(20, 20, 30, 30), 100, 80);
    expect(area(merged!), closeTo(50 * 50, 1));
  });
}
