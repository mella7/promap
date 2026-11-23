import 'errors.dart';
import 'json_util.dart';

/// What a surface shows.
sealed class Content {
  const Content();

  Map<String, Object?> toJson();

  static Content fromJson(Object? json) {
    final map = asMap(json, 'Content');
    final type = asString(map['type'], 'Content type');
    switch (type) {
      case 'none':
        return const NoContent();
      case 'color':
        return ColorContent(asString(map['color'], 'Color'));
      case 'image':
        return ImageContent(asString(map['source'], 'Image source'));
      case 'effect':
        final params = map['params'];
        return EffectContent(
          asString(map['effect'], 'Effect name'),
          params: params == null ? const {} : asMap(params, 'Effect params'),
        );
      default:
        throw FormatException('Unknown content type "$type"');
    }
  }
}

/// Nothing is projected on the surface.
final class NoContent extends Content {
  const NoContent();

  @override
  Map<String, Object?> toJson() => {'type': 'none'};

  @override
  bool operator ==(Object other) => other is NoContent;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'none';
}

/// A flat colour, written as #RRGGBB or #AARRGGBB.
final class ColorContent extends Content {
  static final RegExp _pattern = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

  final String color;

  ColorContent(String color) : color = color.toUpperCase() {
    if (!_pattern.hasMatch(color)) {
      throw SceneError('"$color" is not a colour like #RRGGBB or #AARRGGBB');
    }
  }

  @override
  Map<String, Object?> toJson() => {'type': 'color', 'color': color};

  @override
  bool operator ==(Object other) =>
      other is ColorContent && other.color == color;

  @override
  int get hashCode => color.hashCode;

  @override
  String toString() => 'color $color';
}

/// An image file or generated texture, by path or URL.
final class ImageContent extends Content {
  final String source;

  ImageContent(this.source) {
    if (source.trim().isEmpty) {
      throw const SceneError('An image needs a source');
    }
  }

  @override
  Map<String, Object?> toJson() => {'type': 'image', 'source': source};

  @override
  bool operator ==(Object other) =>
      other is ImageContent && other.source == source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'image $source';
}

/// An effect from the effect library with its settings.
final class EffectContent extends Content {
  final String effect;

  /// Effect settings such as colour, speed and intensity. JSON values only.
  final Map<String, Object?> params;

  EffectContent(this.effect, {Map<String, Object?> params = const {}})
      : params = Map.unmodifiable(params) {
    if (effect.trim().isEmpty) {
      throw const SceneError('An effect needs a name');
    }
    if (!isJsonValue(params)) {
      throw const SceneError(
          'Effect params may only hold numbers, strings, booleans, lists and maps');
    }
  }

  @override
  Map<String, Object?> toJson() =>
      {'type': 'effect', 'effect': effect, 'params': params};

  @override
  bool operator ==(Object other) =>
      other is EffectContent &&
      other.effect == effect &&
      deepEquals(other.params, params);

  @override
  int get hashCode => Object.hash(effect, deepHash(params));

  @override
  String toString() => 'effect $effect';
}
