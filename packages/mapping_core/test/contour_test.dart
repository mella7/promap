import 'dart:math';

import 'package:mapping_core/mapping_core.dart';
import 'package:test/test.dart';

Set<Point<double>> asSet(List<Point<num>> points) =>
    {for (final p in points) Point(p.x.toDouble(), p.y.toDouble())};

void main() {
  test('components are found, sized and boxed', () {
    final mask = BinaryMask.rectangle(30, 20, 2, 2, 10, 8);
    final second = BinaryMask.rectangle(30, 20, 15, 12, 28, 18);
    for (var i = 0; i < mask.data.length; i++) {
      mask.data[i] |= second.data[i];
    }
    mask.set(29, 0, true);

    final labels = labelComponents(mask);
    expect(labels.components.length, 3);
    expect([for (final c in labels.bySize) c.area], [78, 48, 1]);

    final big = labels.bySize.first;
    expect([big.minX, big.minY, big.maxX, big.maxY], [15, 12, 27, 17]);
    expect(labels.maskOf(big).count, 78);
  });

  test('pixels touching only at a corner are separate pieces', () {
    final mask = BinaryMask(4, 4);
    mask.set(0, 0, true);
    mask.set(1, 1, true);
    expect(labelComponents(mask).components.length, 2);
  });

  test('a single pixel traces to its four corners', () {
    final mask = BinaryMask(3, 3)..set(1, 1, true);
    expect(traceOuterContour(mask),
        const [Point(1, 1), Point(2, 1), Point(2, 2), Point(1, 2)]);
  });

  test('a rectangle simplifies to its four corners', () {
    final contour = traceOuterContour(BinaryMask.rectangle(20, 20, 2, 3, 10, 9));
    expect(contour.length, 2 * (8 + 6));
    expect(polygonArea(contour), 8 * 6);

    final simple = simplifyClosed(contour, 0.5);
    expect(asSet(simple),
        asSet(const [Point(2, 3), Point(10, 3), Point(10, 9), Point(2, 9)]));
  });

  test('an L shape keeps its six corners', () {
    final mask = BinaryMask.rectangle(20, 20, 2, 2, 12, 6);
    final leg = BinaryMask.rectangle(20, 20, 2, 6, 6, 14);
    for (var i = 0; i < mask.data.length; i++) {
      mask.data[i] |= leg.data[i];
    }
    final simple = simplifyClosed(traceOuterContour(mask), 0.5);
    expect(simple.length, 6);
    expect(polygonArea(simple).abs(), 10 * 4 + 4 * 8);
  });

  test('a shape with a hole traces its outer edge', () {
    final mask = BinaryMask.rectangle(20, 20, 2, 2, 14, 14);
    for (var y = 6; y < 10; y++) {
      for (var x = 6; x < 10; x++) {
        mask.set(x, y, false);
      }
    }
    final contour = traceOuterContour(mask);
    expect(polygonArea(contour).abs(), 12 * 12);
  });

  test('an empty mask has no outline', () {
    expect(traceOuterContour(BinaryMask(5, 5)), isEmpty);
  });

  test('simplify removes points on a straight edge only', () {
    final square = <Point<num>>[
      const Point(0, 0),
      const Point(5, 0),
      const Point(10, 0),
      const Point(10, 10),
      const Point(5, 10.2),
      const Point(0, 10),
    ];
    expect(simplifyClosed(square, 0.5).length, 4);
    expect(simplifyClosed(square, 0.1).length, 5);
  });
}
