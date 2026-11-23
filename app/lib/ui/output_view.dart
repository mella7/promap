import 'dart:ui' as ui;

import 'package:calib_core/calib_core.dart';
import 'package:flutter/material.dart';

import '../devices/output_controller.dart';
import 'colors.dart';
import 'gray_image_view.dart';

/// What the projector shows. On the laptop it is a panel; on the phone the
/// same widget goes on the external display.
class OutputView extends StatefulWidget {
  final OutputController controller;

  const OutputView({super.key, required this.controller});

  @override
  State<OutputView> createState() => _OutputViewState();
}

class _OutputViewState extends State<OutputView> {
  ui.Image? _pattern;
  GrayImage? _patternSource;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _onChanged();
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
    widget.controller.removeListener(_onChanged);
    _pattern?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AspectRatio(
      aspectRatio: c.width / c.height,
      child: CustomPaint(
        painter: OutputPainter(controller: c, pattern: _pattern),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class OutputPainter extends CustomPainter {
  final OutputController controller;
  final ui.Image? pattern;

  OutputPainter({required this.controller, this.pattern})
      : super(repaint: controller);

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
            final color = colorOf(surface.content);
            canvas.drawPath(
                path,
                Paint()
                  ..color = color.withValues(alpha: surface.opacity * 0.85));
            final selected = surface.id == c.selected;
            canvas.drawPath(
                path,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = selected ? 3 : 1.5
                  ..color = selected ? Colors.white : color);
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
      oldDelegate.pattern != pattern || oldDelegate.controller != controller;
}
