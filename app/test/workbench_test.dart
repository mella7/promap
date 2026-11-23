import 'package:calib_core/calib_core.dart';
import 'package:effects/effects.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/cloud/surface_finder.dart';
import 'package:promap_app/devices/output_controller.dart';
import 'package:promap_app/devices/simulated_camera.dart';
import 'package:promap_app/workbench.dart';
import 'package:scene_core/scene_core.dart';

void main() {
  test('a scan in the normal room calibrates', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.startScan();

    expect(bench.report!.verdict, ScanVerdict.ok);
    expect(bench.calibrated, isTrue);
    expect(bench.output.mode, OutputMode.scene);
  });

  test('a tap lands where the simulator says it should', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.startScan();
    bench.tapCamera(240, 180);

    final dot = bench.output.dot!;
    final truth = bench.camera.scene.truth(240, 180);
    expect(dot.distanceTo(truth), lessThan(1.0));
  });

  test('find surfaces adds coloured surfaces as one undo step', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.startScan();
    await bench.findSurfaces();

    final names = [for (final s in bench.store.scene.surfaces) s.name];
    expect(names, containsAll(['Box top', 'Left wall', 'Right wall']));
    expect(bench.store.history, ['Find surfaces']);

    bench.undo();
    expect(bench.store.scene.surfaces, isEmpty);
  });

  test('a tap before scanning asks for a scan', () {
    final bench = Workbench(settle: Duration.zero);
    bench.tapCamera(10, 10);
    expect(bench.status, contains('Scan first'));
    expect(bench.output.dot, isNull);
  });

  test('a bright room fails with a clear message and no calibration',
      () async {
    final bench = Workbench(settle: Duration.zero);
    bench.setPreset(SimPreset.brightRoom);
    await bench.startScan();

    expect(bench.report!.verdict, ScanVerdict.tooBright);
    expect(bench.calibrated, isFalse);
    expect(bench.status, contains('Dim the lights'));
  });

  test('the simulated camera sees what the output shows', () {
    final bench = Workbench(settle: Duration.zero);
    bench.output.showBlack();
    final dark = bench.camera.captureNow();
    bench.output.showWhite();
    final lit = bench.camera.captureNow();

    int sum(GrayImage image) => image.data.fold(0, (a, b) => a + b);
    expect(sum(lit), greaterThan(sum(dark) * 2));
  });

  test('a theme gives every surface an effect, as one undo step', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.startScan();
    await bench.findSurfaces();
    bench.applyTheme(themeById('neon_night')!);

    final contents = [for (final s in bench.store.scene.surfaces) s.content];
    expect(contents, everyElement(isA<EffectContent>()));
    expect(bench.store.undoLabel, 'Theme: Neon night');

    bench.undo();
    expect(bench.store.scene.surfaces.first.content, isA<ColorContent>());
  });

  test('a theme with no surfaces asks for surfaces first', () {
    final bench = Workbench(settle: Duration.zero);
    bench.applyTheme(themes.first);
    expect(bench.status, contains('Find surfaces first'));
  });

  test('tapping a surface selects it and its effect can be changed', () async {
    final bench = Workbench(settle: Duration.zero);
    await bench.startScan();
    await bench.findSurfaces();
    // The middle of the box top in the camera image.
    bench.tapCamera(250, 170);
    expect(bench.selectedSurface?.name, 'Box top');

    bench.setSurfaceEffect(bench.selectedSurface!.id, 'sparkles');
    final content = bench.selectedSurface!.content as EffectContent;
    expect(content.effect, 'sparkles');
    expect(content.params['density'], 1.0);

    bench.setSurfaceEffect(bench.selectedSurface!.id, null);
    expect(bench.selectedSurface!.content, isA<ColorContent>());
  });

  test('a finder error shows its message and changes nothing', () async {
    final bench = Workbench(settle: Duration.zero, finder: _FailingFinder());
    await bench.startScan();
    await bench.findSurfaces();

    expect(bench.status, 'Backend down');
    expect(bench.store.scene.surfaces, isEmpty);
    expect(bench.finding, isFalse);
  });
}

class _FailingFinder implements SurfaceFinder {
  @override
  String get description => 'failing test finder';

  @override
  Future<SurfaceFinderResult> find(GrayImage photo) async =>
      throw const SurfaceFinderException('Backend down');
}
