import 'package:scene_core/scene_core.dart';

import 'params.dart';

/// One effect in the library.
class EffectSpec {
  /// Stored in the scene as `EffectContent.effect`. Never change an id once
  /// scenes use it.
  final String id;
  final String name;
  final String description;
  final List<ParamSpec> params;

  const EffectSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.params,
  });

  ParamSpec? param(String key) {
    for (final p in params) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// Every setting with a valid value: given values are checked and clamped,
  /// missing ones get their default, unknown keys are dropped.
  Map<String, Object> resolve(Map<String, Object?> given) =>
      {for (final p in params) p.key: p.normalise(given[p.key])};

  /// Scene content for this effect with [overrides] applied on top of the
  /// defaults.
  EffectContent content([Map<String, Object?> overrides = const {}]) =>
      EffectContent(id, params: resolve(overrides));
}

const _speed = ParamSpec.number('speed', 'Speed', 1, min: 0.1, max: 4);

/// All effects, in the order the picker shows them.
const effectLibrary = <EffectSpec>[
  EffectSpec(
    id: 'neon_outline',
    name: 'Neon outline',
    description: 'A glowing line around the edge that breathes.',
    params: [
      ParamSpec.color('color', 'Colour', '#FF2BD6'),
      _speed,
      ParamSpec.number('width', 'Line width', 4, min: 1, max: 20),
    ],
  ),
  EffectSpec(
    id: 'color_flood',
    name: 'Colour flood',
    description: 'Colour fills the surface from one side, then starts over.',
    params: [
      ParamSpec.color('color', 'Colour', '#FF7A1A'),
      _speed,
      ParamSpec.toggle('vertical', 'Fill upwards', true),
    ],
  ),
  EffectSpec(
    id: 'pulse',
    name: 'Pulse',
    description: 'The whole surface fades in and out.',
    params: [
      ParamSpec.color('color', 'Colour', '#FFB000'),
      _speed,
      ParamSpec.number('depth', 'Strength', 0.8, min: 0, max: 1),
    ],
  ),
  EffectSpec(
    id: 'scanlines',
    name: 'Scanlines',
    description: 'Stripes that slide across the surface.',
    params: [
      ParamSpec.color('color', 'Colour', '#2E8BFF'),
      _speed,
      ParamSpec.number('spacing', 'Spacing', 16, min: 4, max: 80),
    ],
  ),
  EffectSpec(
    id: 'sparkles',
    name: 'Sparkles',
    description: 'Points of light that twinkle inside the surface.',
    params: [
      ParamSpec.color('color', 'Colour', '#FFFFFF'),
      _speed,
      ParamSpec.number('density', 'Density', 1, min: 0.1, max: 4),
    ],
  ),
  EffectSpec(
    id: 'edge_trace',
    name: 'Edge trace',
    description: 'A bright spot runs around the edge, leaving a fading tail.',
    params: [
      ParamSpec.color('color', 'Colour', '#3DFFB5'),
      _speed,
      ParamSpec.number('tail', 'Tail length', 0.25, min: 0.05, max: 0.9),
    ],
  ),
];

EffectSpec? effectById(String id) {
  for (final e in effectLibrary) {
    if (e.id == id) return e;
  }
  return null;
}
