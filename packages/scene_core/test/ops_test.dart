import 'package:scene_core/scene_core.dart';
import 'package:scene_core/src/json_util.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('every sample operation survives a JSON round trip', () {
    final raw = fixtureJson('sample_ops.json') as List;
    final ops = opsFromJson(raw);
    expect(ops.length, 14);
    for (var i = 0; i < ops.length; i++) {
      expect(deepEquals(ops[i].toJson(), raw[i]), isTrue,
          reason: 'operation $i (${raw[i]['op']}) changed');
      expect(ops[i].description, isNotEmpty);
    }
  });

  test('the sample operations produce the expected scene', () {
    var scene = sampleScene();
    for (final op in opsFromJson(fixtureJson('sample_ops.json'))) {
      scene = op.apply(scene);
    }

    expect([for (final s in scene.surfaces) s.id], ['s1', 's4', 's3']);
    expect(scene.calibration, 'calibration/garage.pmap');
    expect(scene.surfaceById('s1')!.label, isNull);

    final shelf = scene.surfaceById('s4')!;
    expect(shelf.name, 'Shelf edge');
    expect(shelf.label, 'shelf');
    expect(shelf.vertices[2], const Vec2(650, 705));
    expect(shelf.content, ColorContent('#00FF88'));
    expect(shelf.opacity, 0.5);

    final poster = scene.surfaceById('s3')!;
    expect(poster.visible, isTrue);
    expect(poster.vertices[0], const Vec2(710, 195));
    expect(poster.vertices[2], const Vec2(910, 495));
  });

  test('applying an operation leaves the original scene untouched', () {
    final before = sampleScene();
    final after = const NudgeVertex('s2', 0, -2, 1.5).apply(before);

    expect(before.surfaceById('s2')!.vertices[0], const Vec2(100, 100));
    expect(after.surfaceById('s2')!.vertices[0], const Vec2(98, 101.5));
    expect(before, sampleScene());
    // Surfaces that did not change are shared, not copied.
    expect(identical(before.surfaces[0], after.surfaces[0]), isTrue);
  });

  test('add puts the surface on top unless told otherwise', () {
    final scene = sampleScene();
    final onTop = AddSurface(square('new')).apply(scene);
    final atBottom = AddSurface(square('new'), index: 0).apply(scene);

    expect(onTop.surfaces.last.id, 'new');
    expect(atBottom.surfaces.first.id, 'new');
  });

  test('reorder moves a surface within the drawing order', () {
    final scene = const ReorderSurface('s1', 2).apply(sampleScene());
    expect([for (final s in scene.surfaces) s.id], ['s2', 's3', 's1']);
  });

  group('rejected operations', () {
    final scene = sampleScene();

    test('unknown surface', () {
      final ops = <SceneOp>[
        const RemoveSurface('nope'),
        const RenameSurface('nope', 'X'),
        const SetLabel('nope', 'x'),
        const MoveVertex('nope', 0, Vec2(0, 0)),
        const NudgeVertex('nope', 0, 1, 1),
        const SetVertices('nope', [Vec2(0, 0), Vec2(1, 0), Vec2(0, 1)]),
        const TranslateSurface('nope', 1, 1),
        const SetContent('nope', NoContent()),
        const SetOpacity('nope', 0.5),
        const SetVisible('nope', false),
        const ReorderSurface('nope', 0),
      ];
      for (final op in ops) {
        expect(() => op.apply(scene), throwsSceneError,
            reason: op.runtimeType.toString());
      }
    });

    test('duplicate id', () {
      expect(() => AddSurface(square('s1')).apply(scene), throwsSceneError);
    });

    test('positions outside the list', () {
      expect(() => AddSurface(square('n'), index: 4).apply(scene),
          throwsSceneError);
      expect(() => AddSurface(square('n'), index: -1).apply(scene),
          throwsSceneError);
      expect(
          () => const ReorderSurface('s1', 3).apply(scene), throwsSceneError);
    });

    test('corner numbers outside the outline', () {
      expect(() => const MoveVertex('s2', 4, Vec2(0, 0)).apply(scene),
          throwsSceneError);
      expect(() => const NudgeVertex('s2', -1, 1, 1).apply(scene),
          throwsSceneError);
    });

    test('values that break surface rules', () {
      expect(() => const SetOpacity('s1', 2).apply(scene), throwsSceneError);
      expect(
          () => const RenameSurface('s1', '').apply(scene), throwsSceneError);
      expect(
          () => const SetVertices('s1', [Vec2(0, 0), Vec2(1, 1)]).apply(scene),
          throwsSceneError);
      expect(
          () => const MoveVertex('s1', 0, Vec2(double.infinity, 0)).apply(scene),
          throwsSceneError);
    });

    test('malformed JSON', () {
      expect(() => SceneOp.fromJson({'op': 'fly', 'surface': 's1'}),
          throwsFormatException);
      expect(() => SceneOp.fromJson({'op': 'set_opacity', 'surface': 's1'}),
          throwsFormatException);
      expect(() => SceneOp.fromJson({'surface': 's1'}), throwsFormatException);
      expect(
          () => SceneOp.fromJson({
                'op': 'move_vertex',
                'surface': 's1',
                'index': 0,
                'position': [1, 2, 3]
              }),
          throwsFormatException);
      expect(() => opsFromJson({'op': 'remove_surface'}), throwsFormatException);
    });
  });
}
