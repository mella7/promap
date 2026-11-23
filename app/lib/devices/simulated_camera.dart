import 'package:calib_core/calib_core.dart';

import 'camera_source.dart';
import 'output_controller.dart';

/// Ready-made simulator setups, including the ones a real scan can fail on.
enum SimPreset {
  normal('Normal dim room'),
  brightRoom('Bright room'),
  dimProjector('Weak projector'),
  overexposed('Overexposed camera'),
  aimedAway('Camera aimed away');

  const SimPreset(this.label);

  final String label;

  SimScene build() {
    switch (this) {
      case SimPreset.normal:
        return SimScene.standard();
      case SimPreset.brightRoom:
        return SimScene.standard(ambient: 210, gain: 30);
      case SimPreset.dimProjector:
        return SimScene.standard(gain: 35);
      case SimPreset.overexposed:
        return SimScene.standard(gain: 400);
      case SimPreset.aimedAway:
        return SimScene(
          projectorWidth: 320,
          projectorHeight: 240,
          cameraWidth: 480,
          cameraHeight: 360,
          homography: const [1, 0, 10000, 0, 1, 10000, 0, 0, 1],
        );
    }
  }
}

/// A camera that photographs whatever the [OutputController] is showing,
/// through the simulator's fake room.
class SimulatedCamera implements CameraSource {
  final SimScene scene;
  final OutputController output;

  SimulatedCamera(this.scene, this.output);

  @override
  int get width => scene.cameraWidth;

  @override
  int get height => scene.cameraHeight;

  @override
  Future<GrayImage> capture() async => captureNow();

  /// The same as [capture], without waiting.
  GrayImage captureNow() => scene.capture(output.toGray());
}
