import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/app.dart';

void main() {
  testWidgets('the workbench shows both panels and the controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(const PromapApp());
    await tester.pump();

    expect(find.text('Projector output'), findsOneWidget);
    expect(find.text('Camera - tap to light a spot'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Press Scan to calibrate.'), findsOneWidget);

    final findSurfaces = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Find surfaces'));
    expect(findSurfaces.onPressed, isNull,
        reason: 'needs a calibration first');

    await tester.binding.setSurfaceSize(null);
  });
}
