import 'package:calib_core/calib_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/devices/output_controller.dart';
import 'package:promap_app/devices/simulated_camera.dart';
import 'package:promap_app/ui/output_view.dart';
import 'package:promap_app/ui/projector_page.dart';
import 'package:promap_app/workbench.dart';

void main() {
  test('a delayed camera sees the old picture until the delay is over',
      () async {
    final output = OutputController(320, 240)..showWhite();
    final camera = SimulatedCamera(SimScene.standard(), output,
        delay: const Duration(milliseconds: 100));
    output.showBlack();

    final early = meanLevel(camera.captureNow());
    await Future<void>.delayed(const Duration(milliseconds: 160));
    final late = meanLevel(camera.captureNow());
    expect(early - late, greaterThan(20), reason: 'still white, then black');
    camera.dispose();
  });

  test('measuring finds the mirroring delay and stretches the scan wait',
      () async {
    final bench = Workbench(settle: Duration.zero)
      ..setPreset(SimPreset.mirrored);
    expect(await bench.measureDelay(), isTrue);

    final delay = bench.measuredDelay!.inMilliseconds;
    expect(delay, inInclusiveRange(150, 260));
    expect(bench.scanSettle.inMilliseconds, greaterThan(delay));
    expect(bench.status, contains('ms late'));
  });

  test('auto map works through a mirrored projector', () async {
    final bench = Workbench(settle: Duration.zero)
      ..setPreset(SimPreset.mirrored);
    await bench.autoMap();

    expect(bench.measuredDelay, isNotNull);
    expect(bench.report!.verdict, ScanVerdict.ok);
    expect(bench.store.scene.surfaces, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a camera that cannot see the projection fails the measurement',
      () async {
    final bench = Workbench(settle: Duration.zero)
      ..setPreset(SimPreset.aimedAway);
    expect(await bench.measureDelay(), isFalse);
    expect(bench.status, contains("Couldn't see"));
    expect(bench.measuredDelay, isNull);
    expect(bench.busy, isFalse);
  });

  test('wide stripes still calibrate', () async {
    final bench = Workbench(settle: Duration.zero)..setWideStripes(true);
    await bench.startScan();
    expect(bench.report!.verdict, ScanVerdict.ok);

    bench.tapCamera(240, 180);
    final truth = bench.camera.scene.truth(240, 180);
    expect(bench.output.dot!.distanceTo(truth), lessThan(3.0));
  });

  testWidgets('the projector view shows only the output', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ProjectorPage(controller: OutputController(320, 240))));
    expect(find.byType(OutputView), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
