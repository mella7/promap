import 'dart:ui';

import 'package:scene_core/scene_core.dart';

/// Colours handed out to surfaces the app finds by itself.
const surfacePalette = [
  '#FF5A1F',
  '#2EC4B6',
  '#F9C80E',
  '#7B61FF',
  '#E83F6F',
  '#3FA34D',
];

int _argb(String hex) {
  final digits = hex.substring(1);
  final value = int.parse(digits, radix: 16);
  return digits.length == 6 ? 0xFF000000 | value : value;
}

/// The on-screen colour for a surface's content.
Color colorOf(Content content) {
  switch (content) {
    case ColorContent(:final color):
      return Color(_argb(color));
    case ImageContent():
      return const Color(0xFF8C9EFF);
    case EffectContent():
      return const Color(0xFFFFAB40);
    case NoContent():
      return const Color(0xFF9E9E9E);
  }
}

/// How bright the content is on a 0-255 grey scale, for the simulator.
int grayLevelOf(Content content) {
  final argb = switch (content) {
    ColorContent(:final color) => _argb(color),
    ImageContent() => 0xFF8C9EFF,
    EffectContent() => 0xFFFFAB40,
    NoContent() => 0xFF9E9E9E,
  };
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b).round();
}
