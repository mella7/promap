import 'content.dart';
import 'errors.dart';
import 'json_util.dart';
import 'scene.dart';
import 'surface.dart';
import 'vec2.dart';

/// One change to a scene.
///
/// Every edit, whether from the UI or later from the AI assistant, is one of
/// these. Each can be applied, described in a sentence and written as JSON.
/// [apply] returns a new scene and throws [SceneError] when the change is not
/// allowed, leaving the original untouched.
sealed class SceneOp {
  const SceneOp();

  Scene apply(Scene scene);

  /// A short sentence for the undo menu and the change log.
  String get description;

  Map<String, Object?> toJson();

  static SceneOp fromJson(Object? json) {
    final map = asMap(json, 'An operation');
    final op = asString(map['op'], 'Operation name');
    String surface() => asString(map['surface'], 'Surface id');
    switch (op) {
      case 'add_surface':
        final index = map['index'];
        return AddSurface(
          Surface.fromJson(map['value']),
          index: index == null ? null : asInt(index, 'Index'),
        );
      case 'remove_surface':
        return RemoveSurface(surface());
      case 'rename_surface':
        return RenameSurface(surface(), asString(map['name'], 'Name'));
      case 'set_label':
        final label = map['label'];
        return SetLabel(
            surface(), label == null ? null : asString(label, 'Label'));
      case 'move_vertex':
        return MoveVertex(surface(), asInt(map['index'], 'Index'),
            Vec2.fromJson(map['position']));
      case 'nudge_vertex':
        return NudgeVertex(surface(), asInt(map['index'], 'Index'),
            asDouble(map['dx'], 'dx'), asDouble(map['dy'], 'dy'));
      case 'set_vertices':
        return SetVertices(surface(), [
          for (final v in asList(map['vertices'], 'Vertices')) Vec2.fromJson(v)
        ]);
      case 'translate_surface':
        return TranslateSurface(
            surface(), asDouble(map['dx'], 'dx'), asDouble(map['dy'], 'dy'));
      case 'set_content':
        return SetContent(surface(), Content.fromJson(map['content']));
      case 'set_opacity':
        return SetOpacity(surface(), asDouble(map['opacity'], 'Opacity'));
      case 'set_visible':
        return SetVisible(surface(), asBool(map['visible'], 'Visible'));
      case 'reorder_surface':
        return ReorderSurface(surface(), asInt(map['index'], 'Index'));
      case 'set_calibration':
        final file = map['file'];
        return SetCalibration(
            file == null ? null : asString(file, 'Calibration file'));
      default:
        throw FormatException('Unknown operation "$op"');
    }
  }
}

/// Replaces the surface with id [id] by `change(surface)`.
Scene _change(Scene scene, String id, Surface Function(Surface) change) {
  final index = scene.indexOf(id);
  if (index < 0) {
    throw SceneError('There is no surface with id "$id"');
  }
  final surfaces = List<Surface>.of(scene.surfaces);
  surfaces[index] = change(surfaces[index]);
  return scene.withSurfaces(surfaces);
}

void _checkVertexIndex(Surface surface, int index) {
  if (index < 0 || index >= surface.vertices.length) {
    throw SceneError('Surface "${surface.id}" has no corner number $index');
  }
}

/// Adds a surface, on top by default or at drawing position [index].
final class AddSurface extends SceneOp {
  final Surface surface;
  final int? index;

  const AddSurface(this.surface, {this.index});

  @override
  Scene apply(Scene scene) {
    if (scene.indexOf(surface.id) >= 0) {
      throw SceneError('A surface with id "${surface.id}" already exists');
    }
    final at = index ?? scene.surfaces.length;
    if (at < 0 || at > scene.surfaces.length) {
      throw SceneError('Position $at is outside the surface list');
    }
    final surfaces = List<Surface>.of(scene.surfaces)..insert(at, surface);
    return scene.withSurfaces(surfaces);
  }

  @override
  String get description => 'Add "${surface.name}"';

  @override
  Map<String, Object?> toJson() => {
        'op': 'add_surface',
        'value': surface.toJson(),
        if (index != null) 'index': index,
      };
}

final class RemoveSurface extends SceneOp {
  final String surface;

  const RemoveSurface(this.surface);

  @override
  Scene apply(Scene scene) {
    final index = scene.indexOf(surface);
    if (index < 0) {
      throw SceneError('There is no surface with id "$surface"');
    }
    final surfaces = List<Surface>.of(scene.surfaces)..removeAt(index);
    return scene.withSurfaces(surfaces);
  }

  @override
  String get description => 'Remove surface';

  @override
  Map<String, Object?> toJson() => {'op': 'remove_surface', 'surface': surface};
}

final class RenameSurface extends SceneOp {
  final String surface;
  final String name;

  const RenameSurface(this.surface, this.name);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.copyWith(name: name));

  @override
  String get description => 'Rename to "$name"';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'rename_surface', 'surface': surface, 'name': name};
}

/// Sets or clears what the surface is, such as "window".
final class SetLabel extends SceneOp {
  final String surface;
  final String? label;

  const SetLabel(this.surface, this.label);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.withLabel(label));

  @override
  String get description => label == null ? 'Clear label' : 'Label as "$label"';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'set_label', 'surface': surface, 'label': label};
}

/// Puts one corner at an exact position.
final class MoveVertex extends SceneOp {
  final String surface;
  final int index;
  final Vec2 position;

  const MoveVertex(this.surface, this.index, this.position);

  @override
  Scene apply(Scene scene) => _change(scene, surface, (s) {
        _checkVertexIndex(s, index);
        final vertices = List<Vec2>.of(s.vertices);
        vertices[index] = position;
        return s.copyWith(vertices: vertices);
      });

  @override
  String get description => 'Move corner';

  @override
  Map<String, Object?> toJson() => {
        'op': 'move_vertex',
        'surface': surface,
        'index': index,
        'position': position.toJson(),
      };
}

/// Shifts one corner by a few pixels.
final class NudgeVertex extends SceneOp {
  final String surface;
  final int index;
  final double dx;
  final double dy;

  const NudgeVertex(this.surface, this.index, this.dx, this.dy);

  @override
  Scene apply(Scene scene) => _change(scene, surface, (s) {
        _checkVertexIndex(s, index);
        final vertices = List<Vec2>.of(s.vertices);
        vertices[index] = vertices[index].translate(dx, dy);
        return s.copyWith(vertices: vertices);
      });

  @override
  String get description => 'Nudge corner';

  @override
  Map<String, Object?> toJson() => {
        'op': 'nudge_vertex',
        'surface': surface,
        'index': index,
        'dx': dx,
        'dy': dy,
      };
}

/// Replaces the whole outline of a surface.
final class SetVertices extends SceneOp {
  final String surface;
  final List<Vec2> vertices;

  const SetVertices(this.surface, this.vertices);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.copyWith(vertices: vertices));

  @override
  String get description => 'Reshape surface';

  @override
  Map<String, Object?> toJson() => {
        'op': 'set_vertices',
        'surface': surface,
        'vertices': [for (final v in vertices) v.toJson()],
      };
}

/// Shifts a whole surface.
final class TranslateSurface extends SceneOp {
  final String surface;
  final double dx;
  final double dy;

  const TranslateSurface(this.surface, this.dx, this.dy);

  @override
  Scene apply(Scene scene) => _change(
      scene,
      surface,
      (s) => s.copyWith(
          vertices: [for (final v in s.vertices) v.translate(dx, dy)]));

  @override
  String get description => 'Move surface';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'translate_surface', 'surface': surface, 'dx': dx, 'dy': dy};
}

final class SetContent extends SceneOp {
  final String surface;
  final Content content;

  const SetContent(this.surface, this.content);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.copyWith(content: content));

  @override
  String get description => 'Set content to $content';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'set_content', 'surface': surface, 'content': content.toJson()};
}

final class SetOpacity extends SceneOp {
  final String surface;
  final double opacity;

  const SetOpacity(this.surface, this.opacity);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.copyWith(opacity: opacity));

  @override
  String get description => 'Set opacity to ${(opacity * 100).round()}%';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'set_opacity', 'surface': surface, 'opacity': opacity};
}

final class SetVisible extends SceneOp {
  final String surface;
  final bool visible;

  const SetVisible(this.surface, this.visible);

  @override
  Scene apply(Scene scene) =>
      _change(scene, surface, (s) => s.copyWith(visible: visible));

  @override
  String get description => visible ? 'Show surface' : 'Hide surface';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'set_visible', 'surface': surface, 'visible': visible};
}

/// Moves a surface to drawing position [index]. 0 is the bottom.
final class ReorderSurface extends SceneOp {
  final String surface;
  final int index;

  const ReorderSurface(this.surface, this.index);

  @override
  Scene apply(Scene scene) {
    final from = scene.indexOf(surface);
    if (from < 0) {
      throw SceneError('There is no surface with id "$surface"');
    }
    if (index < 0 || index >= scene.surfaces.length) {
      throw SceneError('Position $index is outside the surface list');
    }
    final surfaces = List<Surface>.of(scene.surfaces);
    final moved = surfaces.removeAt(from);
    surfaces.insert(index, moved);
    return scene.withSurfaces(surfaces);
  }

  @override
  String get description => 'Reorder surface';

  @override
  Map<String, Object?> toJson() =>
      {'op': 'reorder_surface', 'surface': surface, 'index': index};
}

/// Points the scene at a calibration file, or clears it with null.
final class SetCalibration extends SceneOp {
  final String? file;

  const SetCalibration(this.file);

  @override
  Scene apply(Scene scene) => scene.withCalibration(file);

  @override
  String get description =>
      file == null ? 'Clear calibration' : 'Use calibration $file';

  @override
  Map<String, Object?> toJson() => {'op': 'set_calibration', 'file': file};
}
