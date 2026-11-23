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

final RegExp _hex = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

/// ARGB value of a "#RRGGBB" or "#AARRGGBB" string, or null if it isn't one.
int? argbFromHex(String hex) {
  if (!_hex.hasMatch(hex)) return null;
  final digits = hex.substring(1);
  final value = int.parse(digits, radix: 16);
  return digits.length == 6 ? 0xFF000000 | value : value;
}

const _imageColor = 0xFF8C9EFF;
const _effectColor = 0xFFFFAB40;
const _emptyColor = 0xFF9E9E9E;

int _argbOf(Content content) {
  switch (content) {
    case ColorContent(:final color):
      return argbFromHex(color) ?? _emptyColor;
    case ImageContent():
      return _imageColor;
    case EffectContent(:final params):
      final color = params['color'];
      return (color is String ? argbFromHex(color) : null) ?? _effectColor;
    case NoContent():
      return _emptyColor;
  }
}

/// The main on-screen colour of a surface's content. For an effect, its
/// colour setting.
Color colorOf(Content content) => Color(_argbOf(content));

/// How bright the content is on a 0-255 grey scale, for the simulator.
int grayLevelOf(Content content) {
  final argb = _argbOf(content);
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return (0.299 * r + 0.587 * g + 0.114 * b).round();
}
