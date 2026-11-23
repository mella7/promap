import 'package:effects/effects.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/workbench.dart';
import 'package:scene_core/scene_core.dart';

/// Pixels [left]..[right) x [top]..[bottom) as a surface outline.
List<Vec2> box(int left, int top, int right, int bottom) => [
      Vec2(left - 0.5, top - 0.5),
      Vec2(right - 0.5, top - 0.5),
      Vec2(right - 0.5, bottom - 0.5),
      Vec2(left - 0.5, bottom - 0.5),
    ];

Future<Workbench> mapped() async {
  final bench = Workbench(settle: Duration.zero);
  await bench.startScan();
  await bench.findSurfaces();
  return bench;
}

String idOf(Workbench bench, String name) =>
    bench.store.scene.surfaces.firstWhere((s) => s.name == name).id;

void main() {
  test('auto map scans, finds surfaces and applies a theme', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.autoMap();

    expect(bench.calibrated, isTrue);
    final surfaces = bench.store.scene.surfaces;
    expect([for (final s in surfaces) s.name],
        containsAll(['Box top', 'Left wall', 'Right wall']));
    expect(surfaces.every((s) => s.content is EffectContent), isTrue);
    expect(bench.store.history, ['Find surfaces', 'Theme: ${themes.first.name}']);
    expect(bench.status, contains('Mapped ${surfaces.length} surfaces'));
  });

  test('auto map again replaces the surfaces instead of doubling them',
      () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.autoMap();
    final count = bench.store.scene.surfaces.length;
    await bench.autoMap(themeById('starry'));

    expect(bench.store.scene.surfaces.length, count);
    expect(bench.store.history, contains('Clear surfaces'));
    expect(bench.store.history.last, 'Theme: Starry');
  });

  test('rename, and blank names are ignored', () async {
    final bench = await mapped();
    final id = idOf(bench, 'Box top');
    bench.renameSurface(id, '  Speaker  ');
    expect(bench.store.scene.surfaceById(id)!.name, 'Speaker');
    bench.renameSurface(id, '   ');
    expect(bench.store.scene.surfaceById(id)!.name, 'Speaker');
    expect(bench.store.history.last, isNot(contains('Find')));
  });

  test('hide and show again', () async {
    final bench = await mapped();
    final id = idOf(bench, 'Left wall');
    bench.toggleVisible(id);
    expect(bench.store.scene.surfaceById(id)!.visible, isFalse);
    bench.toggleVisible(id);
    expect(bench.store.scene.surfaceById(id)!.visible, isTrue);
  });

  test('delete, and undo brings it back', () async {
    final bench = await mapped();
    final id = idOf(bench, 'Right wall');
    bench.deleteSurface(id);
    expect(bench.store.scene.surfaceById(id), isNull);
    bench.undo();
    expect(bench.store.scene.surfaceById(id), isNotNull);
  });

  test('two touching surfaces merge into one, as one undo step', () async {
    final bench = await mapped();
    bench.store.applyAll([
      AddSurface(Surface(id: 'a', name: 'Left half', vertices: box(20, 20, 60, 60))),
      AddSurface(Surface(id: 'b', name: 'Right half', vertices: box(60, 20, 100, 60))),
    ]);
    final before = bench.store.scene.surfaces.length;

    bench.mergeSurfaces('a', 'b');

    final scene = bench.store.scene;
    expect(scene.surfaces.length, before - 1);
    expect(scene.surfaceById('b'), isNull);
    final merged = scene.surfaceById('a')!;
    expect(merged.name, 'Left half');
    expect(merged.area, closeTo(80 * 40, 1));
    expect(bench.output.selected, 'a');

    bench.undo();
    expect(bench.store.scene.surfaceById('b'), isNotNull);
  });

  test('surfaces that do not touch are not merged', () async {
    final bench = await mapped();
    final steps = bench.store.history.length;
    final count = bench.store.scene.surfaces.length;
    bench.mergeSurfaces(idOf(bench, 'Box top'), idOf(bench, 'Left wall'));
    expect(bench.store.scene.surfaces.length, count);
    expect(bench.store.history.length, steps);
    expect(bench.status, contains("don't touch"));
  });

  test('split: two taps cut a surface in two, as one undo step', () async {
    final bench = await mapped();
    final id = idOf(bench, 'Left wall');
    final before = bench.store.scene.surfaces.length;
    final area = bench.store.scene.surfaceById(id)!.area;

    bench.startSplit(id);
    expect(bench.splitting, id);
    bench.tapCamera(120, 80);
    expect(bench.status, contains('second point'));
    bench.tapCamera(120, 280);

    final scene = bench.store.scene;
    expect(bench.splitting, isNull);
    expect(scene.surfaces.length, before + 1);
    final halves = [scene.surfaceById(id)!, scene.surfaces[scene.indexOf(id) + 1]];
    expect(halves[1].name, 'Left wall 2');
    expect(halves[1].label, 'wall');
    expect(halves[0].area + halves[1].area, closeTo(area, area * 0.05));
    expect(bench.store.history.last, 'Split "Left wall"');

    bench.undo();
    expect(bench.store.scene.surfaces.length, before);
  });

  test('split: a cut that misses keeps waiting, cancel leaves it alone',
      () async {
    final bench = await mapped();
    final steps = bench.store.history.length;
    bench.startSplit(idOf(bench, 'Left wall'));
    bench.tapCamera(350, 100); // both taps on the right wall
    bench.tapCamera(350, 250);

    expect(bench.status, contains("doesn't cut"));
    expect(bench.splitting, isNotNull);
    bench.cancelSplit();
    expect(bench.splitting, isNull);
    expect(bench.store.history.length, steps);
  });
}
