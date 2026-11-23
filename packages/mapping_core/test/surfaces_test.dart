import 'dart:math';

import 'package:calib_core/calib_core.dart';
import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

/// The projector pixels the camera rectangle really lands on, from the
/// simulator's known answer, sampled four times per camera pixel.
BinaryMask truthMask(SimScene scene, int left, int top, int right, int bottom) {
  final mask = BinaryMask(scene.projectorWidth, scene.projectorHeight);
  for (var v = top.toDouble(); v < bottom; v += 0.25) {
    for (var u = left.toDouble(); u < right; u += 0.25) {
      final p = scene.truth(u, v);
      final x = (p.x + 0.5).floor();
      final y = (p.y + 0.5).floor();
      if (x < 0 || y < 0 || x >= mask.width || y >= mask.height) continue;
      mask.set(x, y, true);
    }
  }
  return mask;
}

/// Projector pixels covered by any of the surfaces.
BinaryMask rasterise(List<Surface> surfaces, int width, int height) {
  final mask = BinaryMask(width, height);
  for (final surface in surfaces) {
    final polygon = [for (final v in surface.vertices) Point(v.x, v.y)];
    final filled = BinaryMask.fromPolygon(width, height, polygon);
    for (var i = 0; i < mask.data.length; i++) {
      mask.data[i] |= filled.data[i];
    }
  }
  return mask;
}

double iou(BinaryMask a, BinaryMask b) {
  var both = 0;
  var either = 0;
  for (var i = 0; i < a.data.length; i++) {
    final x = a.data[i] != 0;
    final y = b.data[i] != 0;
    if (x && y) both++;
    if (x || y) either++;
  }
  return either == 0 ? 0 : both / either;
}

void main() {
  late SimScene sim;
  late CorrespondenceMap map;
  late Scene empty;

  setUpAll(() {
    sim = SimScene.standard();
    final patterns = PatternSet(sim.projectorWidth, sim.projectorHeight);
    map = decodeScan(patterns, sim.scan(patterns)).map;
    empty = Scene(
        projectorWidth: sim.projectorWidth,
        projectorHeight: sim.projectorHeight);
  });

  List<Surface> surfacesFor(int left, int top, int right, int bottom,
      {Scene? scene, SurfaceOptions options = const SurfaceOptions()}) {
    final mask = BinaryMask.rectangle(
        sim.cameraWidth, sim.cameraHeight, left, top, right, bottom);
    final ops = surfaceOpsFromMasks(
        scene ?? empty, map, [CameraMask(mask, name: 'Shape', label: 'test')],
        options: options);
    return [for (final op in ops) op.surface];
  }

  test('a box face becomes one surface matching the real shape', () {
    final surfaces = surfacesFor(210, 130, 290, 210);

    expect(surfaces.length, 1);
    expect(surfaces.single.name, 'Shape');
    expect(surfaces.single.label, 'test');
    expect(surfaces.single.vertices.length, lessThanOrEqualTo(10));
    final score = iou(rasterise(surfaces, 320, 240),
        truthMask(sim, 210, 130, 290, 210));
    expect(score, greaterThan(0.95));
  });

  test('a large wall patch at the projector edge stays inside the image', () {
    final surfaces = surfacesFor(60, 60, 180, 300);

    expect(surfaces.length, 1);
    for (final v in surfaces.single.vertices) {
      expect(v.x, inInclusiveRange(-0.5, 319.5));
      expect(v.y, inInclusiveRange(-0.5, 239.5));
    }
    final score =
        iou(rasterise(surfaces, 320, 240), truthMask(sim, 60, 60, 180, 300));
    expect(score, greaterThan(0.95));
  });

  test('a mask across a depth edge splits into two surfaces', () {
    final surfaces = surfacesFor(150, 150, 260, 200);

    expect(surfaces.length, 2);
    expect([for (final s in surfaces) s.name], ['Shape', 'Shape 2']);
    final score = iou(rasterise(surfaces, 320, 240),
        truthMask(sim, 150, 150, 260, 200));
    expect(score, greaterThan(0.9));
  });

  test('largestPieceOnly keeps one surface', () {
    final surfaces = surfacesFor(150, 150, 260, 200,
        options: const SurfaceOptions(largestPieceOnly: true));
    expect(surfaces.length, 1);
  });

  test('tiny masks and masks the projector cannot reach give nothing', () {
    expect(surfacesFor(240, 170, 243, 173), isEmpty);
    // The top-left camera corner looks past the edge of the projection.
    expect(surfacesFor(0, 0, 20, 20), isEmpty);
  });

  test('new ids continue after the ones already in the scene', () {
    final scene = Scene(projectorWidth: 320, projectorHeight: 240, surfaces: [
      Surface(id: 's4', name: 'Old', vertices: const [
        Vec2(0, 0),
        Vec2(10, 0),
        Vec2(0, 10),
      ]),
    ]);
    final surfaces = surfacesFor(150, 150, 260, 200, scene: scene);
    expect([for (final s in surfaces) s.id], ['s5', 's6']);
  });

  test('the operations apply to the scene as one undo step', () {
    final store = SceneStore(empty);
    final masks = [
      CameraMask(BinaryMask.rectangle(480, 360, 210, 130, 290, 210),
          name: 'Box top', label: 'box'),
      CameraMask(BinaryMask.rectangle(480, 360, 60, 60, 180, 300),
          name: 'Wall', label: 'wall'),
    ];
    store.applyAll(surfaceOpsFromMasks(store.scene, map, masks),
        label: 'Find surfaces');

    expect([for (final s in store.scene.surfaces) s.name], ['Box top', 'Wall']);
    expect(store.history, ['Find surfaces']);
    store.undo();
    expect(store.scene.surfaces, isEmpty);
  });

  test('mismatched sizes are rejected', () {
    expect(
        () => surfaceOpsFromMasks(
            Scene(projectorWidth: 1280, projectorHeight: 720), map, const []),
        throwsArgumentError);
    expect(() => projectMask(map, BinaryMask(10, 10)), throwsArgumentError);
  });

  test('a tap on an undecoded pixel falls back to its neighbour', () {
    // Find a decoded pixel next to an undecoded one along the middle row.
    for (var x = 1; x < map.cameraWidth; x++) {
      final here = map.cameraToProjector(x, 180);
      final left = map.cameraToProjector(x - 1, 180);
      if (here != null && left == null) {
        expect(cameraToProjector(map, x - 1, 180), isNotNull);
        expect(cameraToProjector(map, x - 1, 180, searchRadius: 0), isNull);
        return;
      }
    }
    fail('expected an edge between decoded and undecoded pixels');
  });
}
