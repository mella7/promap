/// The kinds of setting an effect can have.
enum ParamKind { color, number, toggle }

/// One setting of an effect, such as its colour or speed.
class ParamSpec {
  final String key;

  /// Shown in the UI.
  final String label;
  final ParamKind kind;
  final Object defaultValue;

  /// Range for numbers.
  final double min;
  final double max;

  const ParamSpec.color(this.key, this.label, String this.defaultValue)
      : kind = ParamKind.color,
        min = 0,
        max = 0;

  const ParamSpec.number(this.key, this.label, double this.defaultValue,
      {required this.min, required this.max})
      : kind = ParamKind.number;

  const ParamSpec.toggle(this.key, this.label, bool this.defaultValue)
      : kind = ParamKind.toggle,
        min = 0,
        max = 0;

  static final RegExp _hex = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

  /// [value] made valid for this setting: numbers are clamped, wrong types
  /// and bad colours fall back to the default.
  Object normalise(Object? value) {
    switch (kind) {
      case ParamKind.color:
        if (value is String && _hex.hasMatch(value)) return value.toUpperCase();
        return defaultValue;
      case ParamKind.number:
        if (value is num && value.isFinite) {
          return value.toDouble().clamp(min, max).toDouble();
        }
        return defaultValue;
      case ParamKind.toggle:
        return value is bool ? value : defaultValue;
    }
  }
}
