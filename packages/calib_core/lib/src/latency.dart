import 'gray_image.dart';

/// How bright one camera frame was, and when it was taken relative to the
/// moment the output switched from black to white.
class BrightnessSample {
  final Duration at;
  final double level;

  const BrightnessSample(this.at, this.level);

  @override
  String toString() => 'BrightnessSample(${at.inMilliseconds} ms, '
      '${level.toStringAsFixed(1)})';
}

/// Mean grey level of [image], reading every [step]th pixel in both
/// directions (a full read is wasted effort for an average).
double meanLevel(GrayImage image, {int step = 4}) {
  var sum = 0;
  var count = 0;
  for (var y = 0; y < image.height; y += step) {
    final row = y * image.width;
    for (var x = 0; x < image.width; x += step) {
      sum += image.data[row + x];
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

/// The delay between the output switching from black to white (at time zero)
/// and the camera seeing it: the time of the first frame that's at least
/// halfway between the dark level and the bright level.
///
/// Samples before time zero give the dark level, the brightest sample gives
/// the bright level. Returns null when the frames never brighten by
/// [minRise] levels: the camera can't see the projection, or it never
/// switched.
///
/// With screen mirroring this is mostly the mirroring delay, plus the
/// camera's own. A scan has to wait at least this long after each pattern.
Duration? findDelay(List<BrightnessSample> samples, {double minRise = 20}) {
  final before = [for (final s in samples) if (s.at <= Duration.zero) s.level];
  final after = [for (final s in samples) if (s.at > Duration.zero) s];
  if (before.isEmpty || after.isEmpty) return null;

  final dark = before.reduce((a, b) => a + b) / before.length;
  var bright = after.first.level;
  for (final s in after) {
    if (s.level > bright) bright = s.level;
  }
  if (bright - dark < minRise) return null;

  final halfway = dark + (bright - dark) / 2;
  for (final s in after) {
    if (s.level >= halfway) return s.at;
  }
  return null;
}

/// How long to wait after showing a pattern, given a measured [delay]: a
/// third more for frames that arrive late, plus a little, never under
/// [minimum].
Duration settleFor(Duration delay,
    {Duration minimum = const Duration(milliseconds: 30)}) {
  final padded = Duration(
      microseconds: (delay.inMicroseconds * 4 ~/ 3) +
          const Duration(milliseconds: 20).inMicroseconds);
  return padded < minimum ? minimum : padded;
}
