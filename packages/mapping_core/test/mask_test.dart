import 'dart:math';

import 'package:mapping_core/mapping_core.dart';
import 'package:test/test.dart';

void main() {
  test('rectangle sets exactly the pixels inside', () {
    final mask = BinaryMask.rectangle(10, 8, 2, 1, 6, 4);
    expect(mask.count, 4 * 3);
    expect(mask.get(2, 1), isTrue);
    expect(mask.get(5, 3), isTrue);
    expect(mask.get(6, 3), isFalse);
    expect(mask.get(-1, 0), isFalse);
  });

  test('polygon fill matches the rectangle it describes', () {
    final fromPolygon = BinaryMask.fromPolygon(10, 8, const [
      Point(1.5, 0.5),
      Point(5.5, 0.5),
      Point(5.5, 3.5),
      Point(1.5, 3.5),
    ]);
    expect(fromPolygon.data, BinaryMask.rectangle(10, 8, 2, 1, 6, 4).data);
  });

  test('dilate and erode grow and shrink by the radius', () {
    final mask = BinaryMask.rectangle(20, 20, 8, 8, 12, 12);
    expect(mask.dilate(1).count, 6 * 6);
    expect(mask.dilate(2).count, 8 * 8);
    expect(mask.erode(1).count, 2 * 2);
    expect(mask.erode(2).count, 0);
    expect(mask.dilate(0).data, mask.data);
  });

  test('close fills a small hole and keeps the outline', () {
    final mask = BinaryMask.rectangle(20, 20, 4, 4, 16, 16);
    mask.set(10, 10, false);
    mask.set(11, 10, false);
    final closed = mask.close(1);
    expect(closed.get(10, 10), isTrue);
    expect(closed.get(11, 10), isTrue);
    expect(closed.count, 12 * 12);
  });

  test('erosion keeps a shape attached to the border', () {
    final mask = BinaryMask.rectangle(10, 10, 0, 0, 5, 10);
    final eroded = mask.erode(1);
    expect(eroded.get(0, 0), isTrue);
    expect(eroded.get(4, 5), isFalse);
    expect(eroded.count, 4 * 10);
  });

  test('bad sizes are rejected', () {
    expect(() => BinaryMask(0, 5), throwsArgumentError);
    expect(() => BinaryMask.rectangle(4, 4, 0, 0, 1, 1).dilate(-1),
        throwsArgumentError);
  });
}
