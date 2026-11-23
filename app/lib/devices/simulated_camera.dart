import 'package:calib_core/calib_core.dart';

import 'camera_source.dart';
import 'output_controller.dart';

/// Ready-made simulator setups, including the ones a real scan can fail on.
enum SimPreset {
  normal('Normal dim room'),
  brightRoom('Bright room'),
  dimProjector('Weak projector'),
  overexposed('Overexposed camera'),
  aimedAway('Camera aimed away'),
  mirrored('Mirrored projector (150 ms late)', delay: Duration(milliseconds: 150));

  const SimPreset(this.label, {this.delay = Duration.zero});

  final String label;

  /// How late the projector shows what the app draws, like with wireless
  /// screen mirroring.
  final Duration delay;

  SimScene build() {
    switch (this) {
      case SimPreset.normal:
      case SimPreset.mirrored:
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
/// through the simulator's fake room. With a [delay] it sees what the output
/// showed that long ago, like a projector fed by screen mirroring.
class SimulatedCamera implements CameraSource {
  final SimScene scene;
  final OutputController output;
  final Duration delay;

  /// What the output showed and since when, oldest first. Only kept when
  /// there's a delay.
  final _history = <(DateTime, GrayImage)>[];

  SimulatedCamera(this.scene, this.output, {this.delay = Duration.zero}) {
    if (delay > Duration.zero) {
      _record();
      output.addListener(_record);
    }
  }

  /// Stops following the output. Call before dropping the camera.
  void dispose() {
    if (delay > Duration.zero) output.removeListener(_record);
  }

  void _record() {
    final now = DateTime.now();
    _history.add((now, output.toGray()));
    // Keep everything newer than the delay, plus the last frame before it.
    final cutoff = now.subtract(delay);
    while (_history.length > 1 && !_history[1].$1.isAfter(cutoff)) {
      _history.removeAt(0);
    }
  }

  /// What the projector is actually showing now.
  GrayImage _shown() {
    if (delay == Duration.zero) return output.toGray();
    final cutoff = DateTime.now().subtract(delay);
    var shown = _history.first.$2;
    for (final (since, frame) in _history) {
      if (since.isAfter(cutoff)) break;
      shown = frame;
    }
    return shown;
  }

  @override
  int get width => scene.cameraWidth;

  @override
  int get height => scene.cameraHeight;

  @override
  Future<GrayImage> capture() async => captureNow();

  /// The same as [capture], without waiting.
  GrayImage captureNow() => scene.capture(_shown());
}
