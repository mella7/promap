import 'content.dart';
import 'errors.dart';
import 'json_util.dart';
import 'vec2.dart';

/// One mappable face of the real scene: a polygon in projector pixels plus
/// what to show on it.
class Surface {
  final String id;

  /// The name the user sees, such as "Box top".
  final String name;

  /// What the surface is, as found by segmentation, such as "window". Null
  /// when unknown.
  final String? label;

  /// Corners in projector pixels, in drawing order. At least three.
  final List<Vec2> vertices;

  final Content content;

  /// 0 is invisible, 1 is fully opaque.
  final double opacity;

  final bool visible;

  Surface({
    required this.id,
    required this.name,
    required List<Vec2> vertices,
    this.label,
    this.content = const NoContent(),
    this.opacity = 1.0,
    this.visible = true,
  }) : vertices = List.unmodifiable(vertices) {
    if (id.trim().isEmpty) {
      throw const SceneError('A surface needs an id');
    }
    if (name.trim().isEmpty) {
      throw const SceneError('A surface needs a name');
    }
    if (this.vertices.length < 3) {
      throw SceneError('Surface "$id" needs at least three corners');
    }
    if (!this.vertices.every((v) => v.isFinite)) {
      throw SceneError('Surface "$id" has a corner that is not a number');
    }
    if (!(opacity >= 0 && opacity <= 1)) {
      throw SceneError('Opacity must be between 0 and 1, got $opacity');
    }
  }

  Surface copyWith({
    String? name,
    List<Vec2>? vertices,
    Content? content,
    double? opacity,
    bool? visible,
  }) {
    return Surface(
      id: id,
      name: name ?? this.name,
      label: label,
      vertices: vertices ?? this.vertices,
      content: content ?? this.content,
      opacity: opacity ?? this.opacity,
      visible: visible ?? this.visible,
    );
  }

  /// A copy with a different label. Pass null to clear it.
  Surface withLabel(String? newLabel) {
    return Surface(
      id: id,
      name: name,
      label: newLabel,
      vertices: vertices,
      content: content,
      opacity: opacity,
      visible: visible,
    );
  }

  /// Area in square projector pixels.
  double get area {
    var sum = 0.0;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// Whether [point] lies inside the polygon.
  bool contains(Vec2 point) {
    var inside = false;
    for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
      final a = vertices[i];
      final b = vertices[j];
      final crosses = (a.y > point.y) != (b.y > point.y);
      if (crosses &&
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (label != null) 'label': label,
        'vertices': [for (final v in vertices) v.toJson()],
        'content': content.toJson(),
        'opacity': opacity,
        'visible': visible,
      };

  static Surface fromJson(Object? json) {
    final map = asMap(json, 'A surface');
    final label = map['label'];
    final opacity = map['opacity'];
    final visible = map['visible'];
    final content = map['content'];
    return Surface(
      id: asString(map['id'], 'Surface id'),
      name: asString(map['name'], 'Surface name'),
      label: label == null ? null : asString(label, 'Surface label'),
      vertices: [
        for (final v in asList(map['vertices'], 'Surface vertices'))
          Vec2.fromJson(v)
      ],
      content: content == null ? const NoContent() : Content.fromJson(content),
      opacity: opacity == null ? 1.0 : asDouble(opacity, 'Opacity'),
      visible: visible == null ? true : asBool(visible, 'Visible'),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Surface) return false;
    if (other.id != id ||
        other.name != name ||
        other.label != label ||
        other.content != content ||
        other.opacity != opacity ||
        other.visible != visible ||
        other.vertices.length != vertices.length) {
      return false;
    }
    for (var i = 0; i < vertices.length; i++) {
      if (other.vertices[i] != vertices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      id, name, label, content, opacity, visible, Object.hashAll(vertices));

  @override
  String toString() => 'Surface($id, "$name", ${vertices.length} corners)';
}
