import 'package:scene_core/scene_core.dart';

import 'library.dart';
import 'roles.dart';

/// An effect plus settings, as a theme hands it out.
class EffectChoice {
  final String effect;
  final Map<String, Object?> params;

  const EffectChoice(this.effect, [this.params = const {}]);
}

/// A look for the whole scene: one effect list per role. Surfaces of the
/// same role take the choices in turn, so two boxes don't look identical.
class EffectTheme {
  final String id;
  final String name;
  final List<EffectChoice> background;
  final List<EffectChoice> object;

  const EffectTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.object,
  });

  List<EffectChoice> choicesFor(SurfaceRole role) =>
      role == SurfaceRole.background ? background : object;
}

const themes = <EffectTheme>[
  EffectTheme(
    id: 'neon_night',
    name: 'Neon night',
    background: [
      EffectChoice('scanlines', {'color': '#1F4FFF', 'speed': 0.6}),
      EffectChoice('scanlines', {'color': '#7A2BFF', 'speed': 0.4}),
    ],
    object: [
      EffectChoice('neon_outline', {'color': '#FF2BD6'}),
      EffectChoice('edge_trace', {'color': '#3DFFB5'}),
    ],
  ),
  EffectTheme(
    id: 'warm_glow',
    name: 'Warm glow',
    background: [
      EffectChoice('pulse', {'color': '#B34700', 'speed': 0.3, 'depth': 0.5}),
    ],
    object: [
      EffectChoice('color_flood', {'color': '#FFB000', 'speed': 0.5}),
      EffectChoice('pulse', {'color': '#FF5A1F', 'speed': 0.8}),
    ],
  ),
  EffectTheme(
    id: 'starry',
    name: 'Starry',
    background: [
      EffectChoice('sparkles', {'color': '#CFE3FF', 'speed': 0.5}),
    ],
    object: [
      EffectChoice('neon_outline', {'color': '#FFFFFF', 'width': 2}),
    ],
  ),
];

EffectTheme? themeById(String id) {
  for (final t in themes) {
    if (t.id == id) return t;
  }
  return null;
}

/// One `SetContent` per visible surface, assigning effects from [theme] by
/// role. Apply them with `store.applyAll(...)` to make it one undo step.
List<SetContent> themeOps(Scene scene, EffectTheme theme) {
  final used = {for (final role in SurfaceRole.values) role: 0};
  final ops = <SetContent>[];
  for (final surface in scene.surfaces) {
    if (!surface.visible) continue;
    final role = roleOf(surface, scene);
    final choices = theme.choicesFor(role);
    if (choices.isEmpty) continue;
    final choice = choices[used[role]! % choices.length];
    used[role] = used[role]! + 1;
    final spec = effectById(choice.effect);
    if (spec == null) {
      throw StateError('Theme ${theme.id} uses unknown effect ${choice.effect}');
    }
    ops.add(SetContent(surface.id, spec.content(choice.params)));
  }
  return ops;
}
