import 'dart:math';
import 'dart:ui';

import 'package:effects/effects.dart';
import 'package:scene_core/scene_core.dart';

import 'colors.dart';

/// Draws one surface's content into [path] at time [t] (seconds).
///
/// Effects read the surface's own outline and size, so the same effect fits
/// every surface. Sizes such as line widths are in screen pixels.
void paintSurfaceContent(Canvas canvas, Path path, Surface surface, double t) {
  final content = surface.content;
  final opacity = surface.opacity;
  if (content is EffectContent) {
    final spec = effectById(content.effect);
    if (spec != null) {
      _paintEffect(canvas, path, surface, spec, spec.resolve(content.params),
          t, opacity);
      return;
    }
  }
  final alpha = content is NoContent ? 0.35 : 0.9;
  canvas.drawPath(
      path,
      Paint()
        ..color = colorOf(content).withValues(alpha: alpha * opacity));
}

void _paintEffect(Canvas canvas, Path path, Surface surface, EffectSpec spec,
    Map<String, Object> p, double t, double opacity) {
  final color = Color(argbFromHex(p['color'] as String) ?? 0xFFFFFFFF);
  final speed = p['speed'] as double;
  final bounds = path.getBounds();
  if (bounds.isEmpty) return;

  switch (spec.id) {
    case 'neon_outline':
      final width = p['width'] as double;
      final breathe = 0.65 + 0.35 * sin(2 * pi * t * speed * 0.5);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width * 3
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, width)
            ..color = color.withValues(alpha: 0.6 * breathe * opacity));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: breathe * opacity));

    case 'color_flood':
      final vertical = p['vertical'] as bool;
      final phase = (t * speed * 0.4) % 1.0;
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
          bounds, Paint()..color = color.withValues(alpha: 0.12 * opacity));
      final filled = vertical
          ? Rect.fromLTRB(bounds.left, bounds.bottom - phase * bounds.height,
              bounds.right, bounds.bottom)
          : Rect.fromLTRB(bounds.left, bounds.top,
              bounds.left + phase * bounds.width, bounds.bottom);
      canvas.drawRect(
          filled, Paint()..color = color.withValues(alpha: 0.9 * opacity));
      canvas.restore();

    case 'pulse':
      final depth = p['depth'] as double;
      final level = 1 - depth * (0.5 + 0.5 * cos(2 * pi * t * speed * 0.5));
      canvas.drawPath(
          path, Paint()..color = color.withValues(alpha: level * opacity));

    case 'scanlines':
      final spacing = p['spacing'] as double;
      final offset = (t * speed * spacing * 2) % spacing;
      final stripe = Paint()..color = color.withValues(alpha: 0.85 * opacity);
      canvas.save();
      canvas.clipPath(path);
      for (var y = bounds.top - spacing + offset;
          y < bounds.bottom;
          y += spacing) {
        canvas.drawRect(
            Rect.fromLTWH(bounds.left, y, bounds.width, spacing * 0.4), stripe);
      }
      canvas.restore();

    case 'sparkles':
      final density = p['density'] as double;
      final count =
          (bounds.width * bounds.height / 400 * density).round().clamp(1, 600);
      final random = Random(surface.id.hashCode);
      final dot = Paint();
      for (var i = 0; i < count; i++) {
        final point = Offset(bounds.left + random.nextDouble() * bounds.width,
            bounds.top + random.nextDouble() * bounds.height);
        final phase = random.nextDouble();
        if (!path.contains(point)) continue;
        final wave = 0.5 + 0.5 * sin(2 * pi * (t * speed * 0.7 + phase));
        final glow = wave * wave * wave;
        dot.color = color.withValues(alpha: glow * opacity);
        canvas.drawCircle(point, 1 + 2 * glow, dot);
      }

    case 'edge_trace':
      final tail = p['tail'] as double;
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.2 * opacity));
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) return;
      final metric = metrics.first;
      final total = metric.length;
      if (total <= 0) return;
      final head = (t * speed * 0.25 % 1.0) * total;
      const steps = 24;
      final tailLength = tail * total;
      for (var k = 0; k < steps; k++) {
        final end = head - tailLength * k / steps;
        final start = head - tailLength * (k + 1) / steps;
        final fade = 1 - k / steps;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: fade * opacity);
        for (final piece in _wrapped(start, end, total)) {
          canvas.drawPath(metric.extractPath(piece.$1, piece.$2), paint);
        }
      }

    default:
      canvas.drawPath(
          path, Paint()..color = color.withValues(alpha: 0.9 * opacity));
  }
}

/// The stretch from [start] to [end] along a closed outline of length
/// [total], split in two where it crosses the starting point.
List<(double, double)> _wrapped(double start, double end, double total) {
  if (start >= 0) return [(start, end)];
  if (end <= 0) return [(start + total, end + total)];
  return [(start + total, total), (0, end)];
}
