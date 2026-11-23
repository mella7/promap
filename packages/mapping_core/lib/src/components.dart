import 'dart:typed_data';

import 'mask.dart';

/// One connected piece of a mask.
class Component {
  /// Label in [ComponentLabels.labels], starting at 1.
  final int label;
  final int area;
  final int minX;
  final int minY;
  final int maxX;
  final int maxY;

  const Component({
    required this.label,
    required this.area,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  @override
  String toString() =>
      'Component($label, area $area, x $minX..$maxX, y $minY..$maxY)';
}

/// The result of splitting a mask into connected pieces.
class ComponentLabels {
  final int width;
  final int height;

  /// For each pixel, the label of its piece, or 0 for background.
  final Int32List labels;

  /// The pieces in the order they were found (top to bottom, left to right).
  final List<Component> components;

  ComponentLabels(this.width, this.height, this.labels, this.components);

  /// The pixels of one piece as a mask of the original size.
  BinaryMask maskOf(Component component) {
    final mask = BinaryMask(width, height);
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] == component.label) mask.data[i] = 1;
    }
    return mask;
  }

  /// Pieces sorted from largest to smallest.
  List<Component> get bySize =>
      List.of(components)..sort((a, b) => b.area.compareTo(a.area));
}

/// Splits [mask] into pieces whose pixels touch by an edge (4-connected).
ComponentLabels labelComponents(BinaryMask mask) {
  final w = mask.width;
  final h = mask.height;
  final labels = Int32List(w * h);
  final queue = Int32List(w * h);
  final components = <Component>[];
  var next = 0;

  for (var start = 0; start < w * h; start++) {
    if (mask.data[start] == 0 || labels[start] != 0) continue;
    next++;
    labels[start] = next;
    var head = 0;
    var tail = 0;
    queue[tail++] = start;
    var area = 0;
    var minX = w, minY = h, maxX = -1, maxY = -1;

    while (head < tail) {
      final i = queue[head++];
      final x = i % w;
      final y = i ~/ w;
      area++;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      if (x + 1 < w) tail = _visit(mask, labels, queue, tail, i + 1, next);
      if (x > 0) tail = _visit(mask, labels, queue, tail, i - 1, next);
      if (y + 1 < h) tail = _visit(mask, labels, queue, tail, i + w, next);
      if (y > 0) tail = _visit(mask, labels, queue, tail, i - w, next);
    }

    components.add(Component(
      label: next,
      area: area,
      minX: minX,
      minY: minY,
      maxX: maxX,
      maxY: maxY,
    ));
  }
  return ComponentLabels(w, h, labels, components);
}

int _visit(BinaryMask mask, Int32List labels, Int32List queue, int tail,
    int index, int label) {
  if (mask.data[index] == 0 || labels[index] != 0) return tail;
  labels[index] = label;
  queue[tail] = index;
  return tail + 1;
}
