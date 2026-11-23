import 'dart:math';

import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

List<Vec2> box(int left, int top, int right, int bottom) => [
      Vec2(left - 0.5, top - 0.5),
      Vec2(right - 0.5, top - 0.5),
      Vec2(right - 0.5, bottom - 0.5),
      Vec2(left - 0.5, bottom - 0.5),
    ];

double area(List<Vec2> outline) =>
    polygonArea([for (final v in outline) Point(v.x, v.y)]).abs();

void main() {
  test('a vertical cut gives two boxes, larger first', () {
    final halves = splitOutline(
        box(10, 10, 70, 40), const Vec2(49.5, 20), const Vec2(49.5, 30), 100, 80);
    expect(halves, isNotNull);
    final (big, small) = halves!;
    expect(area(big), closeTo(40 * 30, 1));
    expect(area(small), closeTo(20 * 30, 1));
    expect(big.length, 4);
    expect(small.length, 4);
  });

  test('the two points can be anywhere on the line', () {
    // Both points left of the box, the line still crosses it.
    final halves = splitOutline(
        box(10, 10, 70, 40), const Vec2(0, 24.5), const Vec2(5, 24.5), 100, 80);
    final (a, b) = halves!;
    expect(area(a) + area(b), closeTo(60 * 30, 2));
  });

  test('a diagonal cut keeps all the pixels', () {
    final (a, b) = splitOutline(
        box(10, 10, 60, 60), const Vec2(10, 10), const Vec2(60, 60), 100, 80)!;
    expect(area(a) + area(b), closeTo(50 * 50, 60));
  });

  test('a line that misses the surface does nothing', () {
    expect(
        splitOutline(box(10, 10, 40, 40), const Vec2(80, 0), const Vec2(80, 10),
            100, 80),
        isNull);
  });

  test('a cut that leaves a sliver is refused', () {
    expect(
        // One column of 20 pixels on one side, under the 30-pixel minimum.
        splitOutline(box(10, 10, 40, 30), const Vec2(10.5, 0),
            const Vec2(10.5, 10), 100, 80),
        isNull);
  });

  test('two equal points are not a line', () {
    expect(
        splitOutline(box(10, 10, 40, 40), const Vec2(20, 20),
            const Vec2(20, 20), 100, 80),
        isNull);
  });
}
