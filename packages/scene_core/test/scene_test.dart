import 'dart:convert';

import 'package:scene_core/scene_core.dart';
import 'package:scene_core/src/json_util.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('JSON', () {
    test('the sample scene loads with every field', () {
      final scene = sampleScene();

      expect(scene.projectorWidth, 1280);
      expect(scene.projectorHeight, 720);
      expect(scene.calibration, 'calibration/living-room.pmap');
      expect([for (final s in scene.surfaces) s.id], ['s1', 's2', 's3']);

      final box = scene.surfaceById('s2')!;
      expect(box.name, 'Box top');
      expect(box.label, 'box');
      expect(box.opacity, 0.8);
      expect(box.vertices[1], const Vec2(400, 120));
      final effect = box.content as EffectContent;
      expect(effect.effect, 'neon_outline');
      expect(effect.params['speed'], 1.5);
      expect(effect.params['sound'], true);

      final poster = scene.surfaceById('s3')!;
      expect(poster.label, isNull);
      expect(poster.visible, isFalse);
      expect(poster.content, ImageContent('textures/lava.png'));
    });

    test('writing the sample scene gives back the same JSON', () {
      final written = sampleScene().toJson();
      expect(deepEquals(written, fixtureJson('sample_scene.json')), isTrue);
    });

    test('encode then decode gives an equal scene', () {
      final scene = sampleScene();
      final copy = Scene.decode(scene.encode());
      expect(copy, scene);
      expect(copy.hashCode, scene.hashCode);
    });

    test('optional fields fall back to defaults', () {
      final scene = Scene.fromJson({
        'version': 1,
        'projector': {'width': 640, 'height': 480},
        'surfaces': [
          {
            'id': 'a',
            'name': 'Bare',
            'vertices': [
              [0, 0],
              [10, 0],
              [0, 10]
            ]
          }
        ]
      });
      final bare = scene.surfaces.single;
      expect(scene.calibration, isNull);
      expect(bare.content, const NoContent());
      expect(bare.opacity, 1.0);
      expect(bare.visible, isTrue);
      expect(bare.label, isNull);
    });

    test('bad files are rejected with a FormatException', () {
      expect(() => Scene.decode('not json'), throwsFormatException);
      expect(() => Scene.decode('[]'), throwsFormatException);
      expect(() => Scene.decode('{"version": 1}'), throwsFormatException);

      final future = jsonDecode(fixtureText('sample_scene.json')) as Map;
      future['version'] = 2;
      expect(() => Scene.fromJson(future), throwsFormatException);

      final wrongType = jsonDecode(fixtureText('sample_scene.json')) as Map;
      (wrongType['surfaces'] as List)[0]['content'] = {'type': 'hologram'};
      expect(() => Scene.fromJson(wrongType), throwsFormatException);
    });
  });

  group('rules', () {
    test('a surface needs three finite corners', () {
      expect(
          () => Surface(
              id: 'a', name: 'A', vertices: const [Vec2(0, 0), Vec2(1, 1)]),
          throwsSceneError);
      expect(
          () => Surface(id: 'a', name: 'A', vertices: const [
                Vec2(0, 0),
                Vec2(1, 1),
                Vec2(double.nan, 0),
              ]),
          throwsSceneError);
    });

    test('a surface needs an id and a name', () {
      expect(() => square(''), throwsSceneError);
      expect(
          () => Surface(id: 'a', name: '  ', vertices: square('x').vertices),
          throwsSceneError);
    });

    test('opacity stays between 0 and 1', () {
      expect(() => square('a').copyWith(opacity: 1.5), throwsSceneError);
      expect(() => square('a').copyWith(opacity: -0.1), throwsSceneError);
      expect(() => square('a').copyWith(opacity: double.nan), throwsSceneError);
      expect(square('a').copyWith(opacity: 0).opacity, 0);
    });

    test('surface ids are unique within a scene', () {
      expect(
          () => Scene(
              projectorWidth: 100,
              projectorHeight: 100,
              surfaces: [square('a'), square('a')]),
          throwsSceneError);
    });

    test('colours are checked and normalised', () {
      expect(ColorContent('#ff3300').color, '#FF3300');
      expect(ColorContent('#80ff3300').color, '#80FF3300');
      expect(() => ColorContent('red'), throwsSceneError);
      expect(() => ColorContent('#12345'), throwsSceneError);
    });

    test('effect params must be plain JSON values', () {
      expect(() => EffectContent('glow', params: {'when': DateTime(2026)}),
          throwsSceneError);
      expect(() => EffectContent(' '), throwsSceneError);
      expect(
          EffectContent('glow', params: {
            'a': [1, 2]
          }),
          EffectContent('glow', params: {
            'a': [1, 2]
          }));
    });
  });

  group('geometry', () {
    test('area of a square', () {
      expect(square('a', size: 10).area, 100);
    });

    test('contains tells inside from outside', () {
      final s = square('a', left: 10, top: 10, size: 20);
      expect(s.contains(const Vec2(20, 20)), isTrue);
      expect(s.contains(const Vec2(5, 20)), isFalse);
      expect(s.contains(const Vec2(20, 35)), isFalse);
    });

    test('surfaceAt returns the topmost visible surface', () {
      final scene = sampleScene();
      expect(scene.surfaceAt(const Vec2(200, 200))!.id, 's2');
      // The poster covers this point but is hidden, so the wall is hit.
      expect(scene.surfaceAt(const Vec2(800, 300))!.id, 's1');
      expect(scene.surfaceAt(const Vec2(-5, -5)), isNull);
    });

    test('nextSurfaceId skips ids already in use', () {
      expect(sampleScene().nextSurfaceId(), 's4');
      final scene = Scene(
          projectorWidth: 100,
          projectorHeight: 100,
          surfaces: [square('top'), square('s10')]);
      expect(scene.nextSurfaceId(), 's11');
      expect(Scene(projectorWidth: 1, projectorHeight: 1).nextSurfaceId(), 's1');
    });
  });
}
