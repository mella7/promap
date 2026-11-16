import 'package:calib_core/calib_core.dart';
import 'package:test/test.dart';

void main() {
  test('Gray code round-trips', () {
    for (var n = 0; n < 4096; n++) {
      expect(fromGray(toGray(n)), n);
    }
  });

  test('neighbouring numbers differ in exactly one bit', () {
    for (var n = 0; n < 4095; n++) {
      final diff = toGray(n) ^ toGray(n + 1);
      expect(diff & (diff - 1), 0, reason: 'more than one bit changed at $n');
      expect(diff, isNot(0));
    }
  });

  test('bitsFor covers the range', () {
    expect(bitsFor(1), 1);
    expect(bitsFor(2), 1);
    expect(bitsFor(3), 2);
    expect(bitsFor(160), 8);
    expect(bitsFor(256), 8);
    expect(bitsFor(257), 9);
    expect(bitsFor(640), 10);
  });
}
