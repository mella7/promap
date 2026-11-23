import 'dart:ui' as ui;

import 'package:calib_core/calib_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../devices/output_controller.dart';
import 'effect_painter.dart';
import 'gray_image_view.dart';

/// What the projector shows. On the laptop it is a panel; on the phone the
/// same widget goes on the external display.
///
/// It redraws every frame so effects animate, and shows the frame rate in
/// the corner.
class OutputView extends StatefulWidget {
  final OutputController controller;

  /// Show the frames-per-second counter.
  final bool showFps;

  const OutputView({super.key, required this.controller, this.showFps = true});

  @override
  State<OutputView> createState() => _OutputViewState();
}

class _OutputViewState extends State<OutputView>
    with SingleTickerProviderStateMixin {
  ui.Image? _pattern;
  GrayImage? _patternSource;

  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final ValueNotifier<int> _fps = ValueNotifier(0);
  int _framesThisSecond = 0;
  Duration _secondStart = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _onChanged();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    _time.value = elapsed.inMicroseconds / 1e6;
    _framesThisSecond++;
    if (elapsed - _secondStart >= const Duration(seconds: 1)) {
      _fps.value = _framesThisSecond;
      _framesThisSecond = 0;
      _secondStart = elapsed;
    }
  }

  @override
  void didUpdateWidget(OutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    final source = widget.controller.pattern;
    if (widget.controller.mode != OutputMode.pattern ||
        source == null ||
        identical(source, _patternSource)) {
      return;
    }
    _patternSource = source;
    grayToUiImage(source).then((image) {
      if (!mounted || !identical(source, _patternSource)) {
        image.dispose();
        return;
      }
      setState(() {
        _pattern?.dispose();
        _pattern = image;
      });
    });
  }

  @override
  void dispose() {
    _ticker
      ..stop()
      ..dispose();
    widget.controller.removeListener(_onChanged);
    _pattern?.dispose();
    _time.dispose();
    _fps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AspectRatio(
      aspectRatio: c.width / c.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: OutputPainter(controller: c, time: _time, pattern: _pattern),
          ),
          if (widget.showFps)
            Positioned(
              right: 6,
              top: 4,
              child: ValueListenableBuilder<int>(
                valueListenable: _fps,
                builder: (context, fps, _) => Text(
                  '$fps fps',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontFeatures: [ui.FontFeature.tabularFigures()]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class OutputPainter extends CustomPainter {
  final OutputController controller;

  /// Seconds since the view started, for animation.
  final ValueListenable<double> time;
  final ui.Image? pattern;

  OutputPainter({required this.controller, required this.time, this.pattern})
      : super(repaint: Listenable.merge([controller, time]));

  @override
  void paint(Canvas canvas, Size size) {
    final c = controller;
    final sx = size.width / c.width;
    final sy = size.height / c.height;
    final bounds = Offset.zero & size;

    canvas.drawRect(bounds, Paint()..color = Colors.black);

    switch (c.mode) {
      case OutputMode.black:
        break;
      case OutputMode.white:
        canvas.drawRect(bounds, Paint()..color = Colors.white);
      case OutputMode.pattern:
        final image = pattern;
        if (image != null) {
          paintImage(
            canvas: canvas,
            rect: bounds,
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          );
        }
      case OutputMode.scene:
        final scene = c.scene;
        if (scene != null) {
          for (final surface in scene.surfaces) {
            if (!surface.visible) continue;
            final path = Path();
            for (var i = 0; i < surface.vertices.length; i++) {
              final v = surface.vertices[i];
              final p = Offset((v.x + 0.5) * sx, (v.y + 0.5) * sy);
              if (i == 0) {
                path.moveTo(p.dx, p.dy);
              } else {
                path.lineTo(p.dx, p.dy);
              }
            }
            path.close();
            paintSurfaceContent(canvas, path, surface, time.value);
            if (surface.id == c.selected) {
              canvas.drawPath(
                  path,
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 2
                    ..color = Colors.white);
            }
          }
        }
    }

    final dot = c.dot;
    if (dot != null && c.mode == OutputMode.scene) {
      final centre = Offset((dot.x + 0.5) * sx, (dot.y + 0.5) * sy);
      canvas.drawCircle(centre, 3.5 * sx, Paint()..color = Colors.white);
      canvas.drawCircle(
          centre,
          7 * sx,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = Colors.white70);
    }
  }

  @override
  bool shouldRepaint(OutputPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.controller != controller ||
      oldDelegate.time != time;
}
