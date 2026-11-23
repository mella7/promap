import 'package:calib_core/calib_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/devices/output_controller.dart';
import 'package:promap_app/devices/simulated_camera.dart';
import 'package:promap_app/workbench.dart';

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
    bench.findSurfaces();

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
}
