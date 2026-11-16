import 'package:calib_core/calib_core.dart';
import 'package:test/test.dart';

void main() {
  test('720p set has the expected size and order', () {
    final set = PatternSet(1280, 720);
    expect(set.cellSize, 2);
    expect(set.minStripeWidth, 4);
    expect(set.bitsX, 10);
    expect(set.bitsY, 9);
    expect(set.specs.length, 2 + 2 * (10 + 9));
    expect(set.specs[0].kind, PatternKind.white);
    expect(set.specs[1].kind, PatternKind.black);
    expect(set.specs[2].axis, StripeAxis.columns);
    expect(set.specs[2].bit, 9);
    expect(set.specs[2].inverted, isFalse);
    expect(set.specs[3].inverted, isTrue);
    expect(set.specs.last.axis, StripeAxis.rows);
    expect(set.specs.last.bit, 0);
  });

  test('white and black frames are flat', () {
    final set = PatternSet(64, 48);
    expect(set.render(set.specs[0]).data.every((v) => v == 255), isTrue);
    expect(set.render(set.specs[1]).data.every((v) => v == 0), isTrue);
  });

  test('every stripe pattern is the exact opposite of its inverse', () {
    final set = PatternSet(64, 48);
    for (var i = 2; i < set.specs.length; i += 2) {
      final normal = set.render(set.specs[i]);
      final inverse = set.render(set.specs[i + 1]);
      for (var j = 0; j < normal.data.length; j++) {
        expect(normal.data[j] + inverse.data[j], 255);
      }
    }
  });

  test('no stripe is narrower than minStripeWidth away from the edges', () {
    final set = PatternSet(128, 64, coarseShift: 1);
    final finest = set.render(
        set.specs.firstWhere((s) => s.axis == StripeAxis.columns && s.bit == 0));
    var run = 1;
    final runs = <int>[];
    for (var x = 1; x < 128; x++) {
      if (finest.at(x, 0) == finest.at(x - 1, 0)) {
        run++;
      } else {
        runs.add(run);
        run = 1;
      }
    }
    // The first run starts at the image edge and may be half width.
    for (final r in runs.skip(1)) {
      expect(r, greaterThanOrEqualTo(set.minStripeWidth));
    }
  });

  test('the rendered patterns spell out each pixel\'s cell index', () {
    final set = PatternSet(40, 24, coarseShift: 1);
    final images = [for (final s in set.specs) set.render(s)];
    for (var x = 0; x < 40; x++) {
      var code = 0;
      var index = 2;
      for (var bit = set.bitsX - 1; bit >= 0; bit--) {
        if (images[index].at(x, 5) == 255) code |= 1 << bit;
        index += 2;
      }
      expect(fromGray(code), x >> 1);
    }
  });

  test('rejects bad sizes', () {
    expect(() => PatternSet(0, 10), throwsArgumentError);
    expect(() => PatternSet(10, 10, coarseShift: 9), throwsArgumentError);
  });
}
