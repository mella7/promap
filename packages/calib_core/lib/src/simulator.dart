import 'dart:math';
import 'dart:typed_data';

import 'gray_image.dart';
import 'pattern.dart';

/// A region of the camera image that sits on a nearer or farther object, so
/// the projector lands on it with an offset.
class SimBox {
  final int left;
  final int top;
  final int right;
  final int bottom;
  final double shiftX;
  final double shiftY;

  const SimBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.shiftX,
    required this.shiftY,
  });

  bool contains(double u, double v) =>
      u > left && u < right && v > top && v < bottom;
}

/// A fake projector and camera looking at a fake scene.
///
/// It knows the true projector position behind every camera pixel, so tests
/// can compare a decoded map against the right answer. The model covers a
/// tilted surface (homography), camera lens distortion, one object at a
/// different depth, uneven surface colour, room light, projector blur and
/// sensor noise.
class SimScene {
  final int projectorWidth;
  final int projectorHeight;
  final int cameraWidth;
  final int cameraHeight;

  /// Row-major 3x3 matrix taking camera pixels to projector pixels.
  final List<double> homography;

  /// Strength of the camera's radial lens distortion. 0 is a perfect lens.
  final double radialDistortion;

  final SimBox? box;

  /// Camera level with the projector showing black (0-255).
  final double ambient;

  /// Camera level a full-white projector adds on a white surface.
  final double gain;

  /// Standard deviation of the sensor noise in camera levels.
  final double noiseSigma;

  /// Radius in projector pixels of the lens blur.
  final int blurRadius;

  /// When true the surface is a checker of lighter and darker patches.
  final bool texturedSurface;

  final Random _random;

  SimScene({
    required this.projectorWidth,
    required this.projectorHeight,
    required this.cameraWidth,
    required this.cameraHeight,
    this.homography = const [1, 0, 0, 0, 1, 0, 0, 0, 1],
    this.radialDistortion = 0,
    this.box,
    this.ambient = 25,
    this.gain = 150,
    this.noiseSigma = 2,
    this.blurRadius = 1,
    this.texturedSurface = true,
    int seed = 7,
  }) : _random = Random(seed) {
    if (homography.length != 9) {
      throw ArgumentError('homography needs 9 values');
    }
  }

  /// A 480x360 camera looking at a 320x240 projection on a tilted wall with a
  /// box in front of it. Used by the tests and the example.
  factory SimScene.standard({
    double ambient = 25,
    double gain = 150,
    double noiseSigma = 2,
    int blurRadius = 1,
    int seed = 7,
  }) {
    return SimScene(
      projectorWidth: 320,
      projectorHeight: 240,
      cameraWidth: 480,
      cameraHeight: 360,
      homography: const [0.86, 0.05, -45, -0.03, 0.90, -38, 1.2e-4, -0.8e-4, 1],
      radialDistortion: 0.32,
      box: const SimBox(
          left: 200, top: 120, right: 300, bottom: 220, shiftX: 14, shiftY: -6),
      ambient: ambient,
      gain: gain,
      noiseSigma: noiseSigma,
      blurRadius: blurRadius,
      seed: seed,
    );
  }

  /// The true projector position seen at camera position ([u], [v]). The
  /// result can lie outside the projector image.
  Point<double> truth(double u, double v) {
    final xn = (u - cameraWidth / 2) / cameraWidth;
    final yn = (v - cameraHeight / 2) / cameraWidth;
    final r2 = xn * xn + yn * yn;
    final ud = u + (u - cameraWidth / 2) * radialDistortion * r2;
    final vd = v + (v - cameraHeight / 2) * radialDistortion * r2;
    final h = homography;
    final w = h[6] * ud + h[7] * vd + h[8];
    var px = (h[0] * ud + h[1] * vd + h[2]) / w;
    var py = (h[3] * ud + h[4] * vd + h[5]) / w;
    final b = box;
    if (b != null && b.contains(u, v)) {
      px += b.shiftX;
      py += b.shiftY;
    }
    return Point<double>(px, py);
  }

  /// Whether the camera pixel at ([u], [v]) looks at a lit projector pixel.
  bool seesProjector(double u, double v) {
    final p = truth(u, v);
    return p.x >= 0 &&
        p.x <= projectorWidth - 1 &&
        p.y >= 0 &&
        p.y <= projectorHeight - 1;
  }

  /// What the camera records while the projector shows [projected].
  GrayImage capture(GrayImage projected) {
    if (projected.width != projectorWidth ||
        projected.height != projectorHeight) {
      throw ArgumentError('Projected image must match the projector size');
    }
    final source = Float32List(projected.data.length);
    for (var i = 0; i < source.length; i++) {
      source[i] = projected.data[i].toDouble();
    }
    final blurred =
        _boxBlur(source, projectorWidth, projectorHeight, blurRadius);

    final out = GrayImage(cameraWidth, cameraHeight);
    final maxX = projectorWidth - 1.001;
    final maxY = projectorHeight - 1.001;
    for (var v = 0; v < cameraHeight; v++) {
      for (var u = 0; u < cameraWidth; u++) {
        final p = truth(u.toDouble(), v.toDouble());
        var light = 0.0;
        if (p.x >= 0 &&
            p.x <= projectorWidth - 1 &&
            p.y >= 0 &&
            p.y <= projectorHeight - 1) {
          final x = p.x > maxX ? maxX : p.x;
          final y = p.y > maxY ? maxY : p.y;
          final x0 = x.floor();
          final y0 = y.floor();
          final fx = x - x0;
          final fy = y - y0;
          final i = y0 * projectorWidth + x0;
          light = blurred[i] * (1 - fx) * (1 - fy) +
              blurred[i + 1] * fx * (1 - fy) +
              blurred[i + projectorWidth] * (1 - fx) * fy +
              blurred[i + projectorWidth + 1] * fx * fy;
        }
        var albedo = 1.0;
        if (texturedSurface) {
          albedo = ((u ~/ 40) + (v ~/ 40)).isEven ? 0.6 : 1.0;
        }
        var level = ambient + albedo * gain * light / 255.0;
        if (noiseSigma > 0) level += _gaussian() * noiseSigma;
        final rounded = level.round();
        out.data[v * cameraWidth + u] =
            rounded < 0 ? 0 : (rounded > 255 ? 255 : rounded);
      }
    }
    return out;
  }

  /// Runs a whole scan: one captured frame per pattern, in pattern order.
  List<GrayImage> scan(PatternSet patterns) {
    if (patterns.projectorWidth != projectorWidth ||
        patterns.projectorHeight != projectorHeight) {
      throw ArgumentError('Pattern set must match the projector size');
    }
    return [for (final spec in patterns.specs) capture(patterns.render(spec))];
  }

  double _gaussian() {
    var u1 = _random.nextDouble();
    if (u1 < 1e-12) u1 = 1e-12;
    final u2 = _random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }
}

Float32List _boxBlur(Float32List source, int width, int height, int radius) {
  if (radius <= 0) return source;
  final size = 2 * radius + 1;
  final temp = Float32List(source.length);
  final out = Float32List(source.length);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var d = -radius; d <= radius; d++) {
        var xx = x + d;
        if (xx < 0) xx = 0;
        if (xx >= width) xx = width - 1;
        sum += source[row + xx];
      }
      temp[row + x] = sum / size;
    }
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var d = -radius; d <= radius; d++) {
        var yy = y + d;
        if (yy < 0) yy = 0;
        if (yy >= height) yy = height - 1;
        sum += temp[yy * width + x];
      }
      out[y * width + x] = sum / size;
    }
  }
  return out;
}

