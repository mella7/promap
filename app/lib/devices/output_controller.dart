import 'dart:math';

import 'package:calib_core/calib_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';

import '../ui/colors.dart';

enum OutputMode { black, white, pattern, scene }

/// What the projector is showing right now.
///
/// The output view draws it on screen, and the simulated camera "sees" it
/// through [toGray]. On a phone the same view will be shown on the external
/// display.
class OutputController extends ChangeNotifier {
  final int width;
  final int height;

  OutputController(this.width, this.height);

  OutputMode _mode = OutputMode.white;
  GrayImage? _pattern;
  Scene? _scene;
  Point<double>? _dot;
  String? _selected;

  OutputMode get mode => _mode;
  GrayImage? get pattern => _pattern;
  Scene? get scene => _scene;

  /// A marker in projector pixels, for tap-to-light.
  Point<double>? get dot => _dot;

  /// Id of the surface drawn highlighted.
  String? get selected => _selected;

  void showBlack() => _set(OutputMode.black);

  void showWhite() => _set(OutputMode.white);

  void showPattern(GrayImage image) {
    if (image.width != width || image.height != height) {
      throw ArgumentError('Pattern must be ${width}x$height');
    }
    _pattern = image;
    _set(OutputMode.pattern);
  }

  void showScene(Scene scene) {
    _scene = scene;
    _set(OutputMode.scene);
  }

  void setDot(Point<double>? dot) {
    _dot = dot;
    notifyListeners();
  }

  void select(String? surfaceId) {
    _selected = surfaceId;
    notifyListeners();
  }

  void _set(OutputMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// The current output as a grey image at projector resolution.
  GrayImage toGray() {
    switch (_mode) {
      case OutputMode.black:
        return GrayImage(width, height);
      case OutputMode.white:
        return GrayImage.filled(width, height, 255);
      case OutputMode.pattern:
        return _pattern ?? GrayImage(width, height);
      case OutputMode.scene:
        return _renderScene();
    }
  }

  GrayImage _renderScene() {
    final image = GrayImage(width, height);
    final scene = _scene;
    if (scene != null) {
      for (final surface in scene.surfaces) {
        if (!surface.visible) continue;
        final mask = BinaryMask.fromPolygon(width, height,
            [for (final v in surface.vertices) Point(v.x, v.y)]);
        final level = grayLevelOf(surface.content);
        final alpha = surface.opacity;
        for (var i = 0; i < mask.data.length; i++) {
          if (mask.data[i] == 0) continue;
          image.data[i] =
              (image.data[i] * (1 - alpha) + level * alpha).round();
        }
      }
    }
    final dot = _dot;
    if (dot != null) {
      const radius = 3;
      final cx = dot.x.round();
      final cy = dot.y.round();
      for (var y = cy - radius; y <= cy + radius; y++) {
        for (var x = cx - radius; x <= cx + radius; x++) {
          if (x < 0 || y < 0 || x >= width || y >= height) continue;
          if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > radius * radius) {
            continue;
          }
          image.set(x, y, 255);
        }
      }
    }
    return image;
  }
}
