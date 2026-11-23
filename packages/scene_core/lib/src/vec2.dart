import 'json_util.dart';

/// A point in projector pixels. (0, 0) is the centre of the top-left pixel.
class Vec2 {
  final double x;
  final double y;

  const Vec2(this.x, this.y);

  bool get isFinite => x.isFinite && y.isFinite;

  Vec2 translate(double dx, double dy) => Vec2(x + dx, y + dy);

  /// Stored as a two-number list to keep scene files compact.
  List<Object?> toJson() => [x, y];

  static Vec2 fromJson(Object? json) {
    final list = asList(json, 'A point');
    if (list.length != 2) {
      throw const FormatException('A point must have exactly two numbers');
    }
    return Vec2(asDouble(list[0], 'x'), asDouble(list[1], 'y'));
  }

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}
