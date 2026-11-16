import 'dart:typed_data';

/// An 8-bit single-channel image, row by row.
class GrayImage {
  final int width;
  final int height;
  final Uint8List data;

  GrayImage(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image size must be positive, got ${width}x$height');
    }
    if (this.data.length != width * height) {
      throw ArgumentError(
          'Expected ${width * height} bytes, got ${this.data.length}');
    }
  }

  factory GrayImage.filled(int width, int height, int value) {
    final image = GrayImage(width, height);
    image.data.fillRange(0, image.data.length, value);
    return image;
  }

  int at(int x, int y) => data[y * width + x];

  void set(int x, int y, int value) => data[y * width + x] = value;
}
