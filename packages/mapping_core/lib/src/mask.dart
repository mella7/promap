import 'dart:math';
import 'dart:typed_data';

/// A yes/no image: 1 where a pixel belongs to the shape, 0 elsewhere.
class BinaryMask {
  final int width;
  final int height;
  final Uint8List data;

  BinaryMask(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Mask size must be positive, got ${width}x$height');
    }
    if (this.data.length != width * height) {
      throw ArgumentError(
          'Expected ${width * height} values, got ${this.data.length}');
    }
  }

  /// A mask of the pixels whose centres lie inside [polygon].
  factory BinaryMask.fromPolygon(
      int width, int height, List<Point<double>> polygon) {
    final mask = BinaryMask(width, height);
    if (polygon.length < 3) return mask;
    var minX = polygon.first.x, maxX = polygon.first.x;
    var minY = polygon.first.y, maxY = polygon.first.y;
    for (final p in polygon) {
      minX = min(minX, p.x);
      maxX = max(maxX, p.x);
      minY = min(minY, p.y);
      maxY = max(maxY, p.y);
    }
    final x0 = max(0, minX.floor());
    final x1 = min(width - 1, maxX.ceil());
    final y0 = max(0, minY.floor());
    final y1 = min(height - 1, maxY.ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (pointInPolygon(x.toDouble(), y.toDouble(), polygon)) {
          mask.data[y * width + x] = 1;
        }
      }
    }
    return mask;
  }

  /// A mask of the axis-aligned rectangle from ([left], [top]) inclusive to
  /// ([right], [bottom]) exclusive.
  factory BinaryMask.rectangle(
      int width, int height, int left, int top, int right, int bottom) {
    final mask = BinaryMask(width, height);
    for (var y = max(0, top); y < min(height, bottom); y++) {
      for (var x = max(0, left); x < min(width, right); x++) {
        mask.data[y * width + x] = 1;
      }
    }
    return mask;
  }

  bool get(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return data[y * width + x] != 0;
  }

  void set(int x, int y, bool value) => data[y * width + x] = value ? 1 : 0;

  /// Number of pixels in the shape.
  int get count {
    var total = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != 0) total++;
    }
    return total;
  }

  /// Grows the shape by [radius] pixels in every direction (square window).
  BinaryMask dilate(int radius) => _filter(radius, grow: true);

  /// Shrinks the shape by [radius] pixels. The window is cut off at the
  /// image border, so a shape touching the border stays attached to it.
  BinaryMask erode(int radius) => _filter(radius, grow: false);

  /// Dilate then erode: fills holes and gaps up to about 2 x [radius]
  /// pixels wide without changing the outline much.
  BinaryMask close(int radius) {
    if (radius <= 0) return copy();
    return dilate(radius).erode(radius);
  }

  BinaryMask copy() => BinaryMask(width, height, Uint8List.fromList(data));

  BinaryMask _filter(int radius, {required bool grow}) {
    if (radius < 0) throw ArgumentError('radius must not be negative');
    if (radius == 0) return copy();
    // A square window splits into a row pass and a column pass.
    final rows = _pass(data, width, height, radius, grow, horizontal: true);
    final cols = _pass(rows, width, height, radius, grow, horizontal: false);
    return BinaryMask(width, height, cols);
  }

  @override
  String toString() => 'BinaryMask(${width}x$height, $count set)';
}

Uint8List _pass(Uint8List source, int width, int height, int radius, bool grow,
    {required bool horizontal}) {
  final out = Uint8List(source.length);
  final lines = horizontal ? height : width;
  final length = horizontal ? width : height;
  final prefix = Int32List(length + 1);
  for (var line = 0; line < lines; line++) {
    for (var i = 0; i < length; i++) {
      final index = horizontal ? line * width + i : i * width + line;
      prefix[i + 1] = prefix[i] + (source[index] != 0 ? 1 : 0);
    }
    for (var i = 0; i < length; i++) {
      final lo = max(0, i - radius);
      final hi = min(length - 1, i + radius);
      final ones = prefix[hi + 1] - prefix[lo];
      final on = grow ? ones > 0 : ones == hi - lo + 1;
      final index = horizontal ? line * width + i : i * width + line;
      out[index] = on ? 1 : 0;
    }
  }
  return out;
}

/// Even-odd test: whether ([x], [y]) lies inside [polygon].
bool pointInPolygon(double x, double y, List<Point<double>> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[i];
    final b = polygon[j];
    if ((a.y > y) != (b.y > y) &&
        x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}
