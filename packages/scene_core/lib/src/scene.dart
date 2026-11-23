import 'dart:convert';

import 'errors.dart';
import 'json_util.dart';
import 'surface.dart';
import 'vec2.dart';

/// Everything needed to project a mapped scene: the projector size, the
/// calibration it was built with, and the surfaces in drawing order (the last
/// surface is drawn on top).
///
/// A scene never changes. Operations return a new one.
class Scene {
  static const int currentVersion = 1;

  final int projectorWidth;
  final int projectorHeight;

  /// Path of the calibration map file this scene belongs to, if any.
  final String? calibration;

  final List<Surface> surfaces;

  Scene({
    required this.projectorWidth,
    required this.projectorHeight,
    this.calibration,
    List<Surface> surfaces = const [],
  }) : surfaces = List.unmodifiable(surfaces) {
    if (projectorWidth <= 0 || projectorHeight <= 0) {
      throw const SceneError('Projector size must be positive');
    }
    final seen = <String>{};
    for (final surface in this.surfaces) {
      if (!seen.add(surface.id)) {
        throw SceneError('Two surfaces share the id "${surface.id}"');
      }
    }
  }

  Surface? surfaceById(String id) {
    for (final surface in surfaces) {
      if (surface.id == id) return surface;
    }
    return null;
  }

  /// Position of the surface in drawing order, or -1.
  int indexOf(String id) => surfaces.indexWhere((s) => s.id == id);

  /// An id no surface uses yet: "s1", "s2" and so on.
  String nextSurfaceId() {
    var highest = 0;
    for (final surface in surfaces) {
      final match = RegExp(r'^s(\d+)$').firstMatch(surface.id);
      if (match == null) continue;
      final number = int.parse(match.group(1)!);
      if (number > highest) highest = number;
    }
    return 's${highest + 1}';
  }

  /// The topmost visible surface under [point], or null.
  Surface? surfaceAt(Vec2 point) {
    for (var i = surfaces.length - 1; i >= 0; i--) {
      final surface = surfaces[i];
      if (surface.visible && surface.contains(point)) return surface;
    }
    return null;
  }

  /// A copy with a different surface list. Used by operations.
  Scene withSurfaces(List<Surface> newSurfaces) => Scene(
        projectorWidth: projectorWidth,
        projectorHeight: projectorHeight,
        calibration: calibration,
        surfaces: newSurfaces,
      );

  /// A copy pointing at a different calibration file. Null clears it.
  Scene withCalibration(String? file) => Scene(
        projectorWidth: projectorWidth,
        projectorHeight: projectorHeight,
        calibration: file,
        surfaces: surfaces,
      );

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'projector': {'width': projectorWidth, 'height': projectorHeight},
        if (calibration != null) 'calibration': calibration,
        'surfaces': [for (final s in surfaces) s.toJson()],
      };

  static Scene fromJson(Object? json) {
    final map = asMap(json, 'A scene');
    final version = asInt(map['version'], 'Scene version');
    if (version != currentVersion) {
      throw FormatException('Scene version $version is not supported');
    }
    final projector = asMap(map['projector'], 'Projector');
    final calibration = map['calibration'];
    return Scene(
      projectorWidth: asInt(projector['width'], 'Projector width'),
      projectorHeight: asInt(projector['height'], 'Projector height'),
      calibration:
          calibration == null ? null : asString(calibration, 'Calibration'),
      surfaces: [
        for (final s in asList(map['surfaces'], 'Surfaces')) Surface.fromJson(s)
      ],
    );
  }

  /// The scene as indented JSON text, ready to write to a file.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Reads a scene from JSON text. Throws [FormatException] when the text is
  /// not a scene and [SceneError] when the scene breaks a rule.
  static Scene decode(String text) => fromJson(jsonDecode(text));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Scene) return false;
    if (other.projectorWidth != projectorWidth ||
        other.projectorHeight != projectorHeight ||
        other.calibration != calibration ||
        other.surfaces.length != surfaces.length) {
      return false;
    }
    for (var i = 0; i < surfaces.length; i++) {
      if (other.surfaces[i] != surfaces[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
      projectorWidth, projectorHeight, calibration, Object.hashAll(surfaces));
}
