import 'dart:ui' as ui;

import 'package:effects/effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/devices/output_controller.dart';
import 'package:promap_app/ui/output_view.dart';
import 'package:scene_core/scene_core.dart';

Surface square(String id, double x, double y, Content content) => Surface(
      id: id,
      name: id,
      vertices: [Vec2(x, y), Vec2(x + 60, y), Vec2(x + 60, y + 50), Vec2(x, y + 50)],
      content: content,
    );

void main() {
  test('every effect, colour and empty content paints without errors', () {
    final surfaces = <Surface>[
      for (var i = 0; i < effectLibrary.length; i++)
        square('e$i', 10.0 + (i % 4) * 75, 10.0 + (i ~/ 4) * 60,
            effectLibrary[i].content()),
      square('colour', 10, 150, ColorContent('#FF0000')),
      square('empty', 85, 150, const NoContent()),
      square('image', 160, 150, ImageContent('lava.png')),
      square('unknown', 235, 150, EffectContent('not_in_library')),
    ];
    final output = OutputController(320, 240)
      ..showScene(Scene(
          projectorWidth: 320, projectorHeight: 240, surfaces: surfaces))
      ..select('e0');
    final time = ValueNotifier<double>(0);
    final painter = OutputPainter(controller: output, time: time);

    for (final t in [0.0, 0.37, 1.9, 12.5]) {
      time.value = t;
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const ui.Size(640, 480));
      recorder.endRecording().dispose();
    }
  });

  test('the simulated camera sees an effect by its colour', () {
    final output = OutputController(320, 240)
      ..showScene(Scene(projectorWidth: 320, projectorHeight: 240, surfaces: [
        square('a', 10, 10, effectById('pulse')!.content({'color': '#FFFFFF'})),
        square('b', 100, 10, effectById('pulse')!.content({'color': '#000000'})),
      ]));
    final gray = output.toGray();
    expect(gray.at(40, 35), greaterThan(200));
    expect(gray.at(130, 35), lessThan(20));
  });
}
