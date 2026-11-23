import 'package:calib_core/calib_core.dart';
import 'package:test/test.dart';

/// A camera that sees the switch [delayMs] late, sampled every [stepMs].
List<BrightnessSample> frames(int delayMs,
    {int stepMs = 33, int dark = 12, int bright = 200, int untilMs = 900}) {
  return [
    for (var t = -100; t <= untilMs; t += stepMs)
      BrightnessSample(Duration(milliseconds: t),
          (t >= delayMs ? bright : dark).toDouble()),
  ];
}

void main() {
  test('finds the first bright frame after the switch', () {
    final delay = findDelay(frames(250))!;
    // Frames come every 33 ms, so the answer is the first frame at or after
    // 250 ms.
    expect(delay.inMilliseconds, greaterThanOrEqualTo(250));
    expect(delay.inMilliseconds, lessThan(250 + 33));
  });

  test('no delay gives the first frame', () {
    expect(findDelay(frames(0, stepMs: 10))!.inMilliseconds, lessThanOrEqualTo(10));
  });

  test('a slow fade counts from halfway', () {
    final samples = [
      const BrightnessSample(Duration(milliseconds: -20), 10),
      const BrightnessSample(Duration(milliseconds: 50), 10),
      const BrightnessSample(Duration(milliseconds: 100), 60),
      const BrightnessSample(Duration(milliseconds: 150), 130),
      const BrightnessSample(Duration(milliseconds: 200), 200),
    ];
    expect(findDelay(samples), const Duration(milliseconds: 150));
  });

  test('a camera that never sees the flash gives null', () {
    expect(findDelay(frames(5000)), isNull);
    expect(findDelay(frames(100, bright: 20)), isNull, reason: 'too small a rise');
  });

  test('needs frames from before and after the switch', () {
    expect(findDelay([const BrightnessSample(Duration(milliseconds: 10), 200)]),
        isNull);
  });

  test('mean level of an image', () {
    final image = GrayImage.filled(40, 30, 100);
    for (var x = 0; x < 20; x++) {
      for (var y = 0; y < 30; y++) {
        image.set(x, y, 200);
      }
    }
    expect(meanLevel(image, step: 1), closeTo(150, 0.01));
    expect(meanLevel(image), closeTo(150, 1));
  });

  test('settle time pads the delay and never goes under the minimum', () {
    expect(settleFor(Duration.zero), const Duration(milliseconds: 30));
    expect(settleFor(const Duration(milliseconds: 300)),
        const Duration(milliseconds: 420));
  });
}
