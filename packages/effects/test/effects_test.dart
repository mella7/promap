import 'package:effects/effects.dart';
import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

Surface rect(String id, double w, double h, {String? label}) => Surface(
      id: id,
      name: 'Surface $id',
      label: label,
      vertices: [const Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)],
    );

void main() {
  group('library', () {
    test('ids are unique and every param has a valid default', () {
      final ids = {for (final e in effectLibrary) e.id};
      expect(ids.length, effectLibrary.length);
      for (final effect in effectLibrary) {
        for (final p in effect.params) {
          expect(p.normalise(p.defaultValue), p.defaultValue,
              reason: '${effect.id}.${p.key}');
        }
      }
    });

    test('resolve fills defaults, clamps and drops unknown keys', () {
      final neon = effectById('neon_outline')!;
      final resolved = neon.resolve({
        'speed': 99,
        'color': '#00ff00',
        'width': 'wide',
        'extra': 1,
      });
      expect(resolved, {'color': '#00FF00', 'speed': 4.0, 'width': 4.0});
    });

    test('bad colours and wrong types fall back to the default', () {
      final flood = effectById('color_flood')!;
      expect(flood.resolve({'color': 'red', 'vertical': 'yes'}),
          {'color': '#FF7A1A', 'speed': 1.0, 'vertical': true});
      expect(flood.resolve({'speed': double.nan})['speed'], 1.0);
    });

    test('content is valid scene content that survives JSON', () {
      for (final effect in effectLibrary) {
        final content = effect.content();
        expect(Content.fromJson(content.toJson()), content);
      }
    });

    test('unknown ids give null', () {
      expect(effectById('nope'), isNull);
      expect(themeById('nope'), isNull);
    });
  });

  group('roles', () {
    final scene = Scene(projectorWidth: 100, projectorHeight: 100);

    test('labels decide first', () {
      expect(roleOf(rect('a', 5, 5, label: 'wall'), scene),
          SurfaceRole.background);
      expect(roleOf(rect('a', 90, 90, label: 'box'), scene),
          SurfaceRole.object);
      expect(roleOf(rect('a', 5, 5, label: 'Floor'), scene),
          SurfaceRole.background);
    });

    test('size decides without a label', () {
      expect(roleOf(rect('a', 50, 50), scene), SurfaceRole.background);
      expect(roleOf(rect('a', 30, 30), scene), SurfaceRole.object);
    });
  });

  group('themes', () {
    test('every theme only uses effects that exist', () {
      for (final theme in themes) {
        for (final choice in [...theme.background, ...theme.object]) {
          expect(effectById(choice.effect), isNotNull,
              reason: '${theme.id} uses ${choice.effect}');
        }
      }
    });

    test('a theme gives every visible surface an effect by role', () {
      final scene = Scene(projectorWidth: 100, projectorHeight: 100, surfaces: [
        rect('s1', 100, 100, label: 'wall'),
        rect('s2', 10, 10, label: 'box'),
        rect('s3', 10, 10, label: 'box'),
        rect('s4', 10, 10, label: 'box').copyWith(visible: false),
      ]);
      final ops = themeOps(scene, themeById('neon_night')!);

      expect([for (final op in ops) op.surface], ['s1', 's2', 's3']);
      final effects = [
        for (final op in ops) (op.content as EffectContent).effect
      ];
      expect(effects, ['scanlines', 'neon_outline', 'edge_trace']);

      final after = SceneStore(scene)..applyAll(ops, label: 'Theme');
      expect(after.history, ['Theme']);
      final wall = after.scene.surfaceById('s1')!.content as EffectContent;
      expect(wall.params['color'], '#1F4FFF');
      expect(wall.params['spacing'], 16.0);
    });
  });
}
