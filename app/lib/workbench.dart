import 'package:calib_core/calib_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';

import 'devices/output_controller.dart';
import 'devices/simulated_camera.dart';
import 'scan/scan_controller.dart';
import 'ui/colors.dart';

/// Everything the laptop simulator needs: a fake camera and projector, the
/// scan, the calibration and the scene.
///
/// In step 0 the simulated camera and the on-screen output get swapped for
/// the phone camera and the external display. Nothing else here changes.
class Workbench extends ChangeNotifier {
  /// Wait after showing each pattern. A real projector needs more.
  final Duration settle;

  final OutputController output = OutputController(320, 240);
  final ScanController scan = ScanController();

  Workbench({this.settle = const Duration(milliseconds: 30)}) {
    _usePreset(SimPreset.normal);
  }

  SimPreset _preset = SimPreset.normal;
  late SimulatedCamera _camera;
  late SceneStore _store;
  GrayImage? _cameraFrame;
  CorrespondenceMap? _map;
  QualityReport? _report;
  String _status = '';

  SimPreset get preset => _preset;
  SimulatedCamera get camera => _camera;
  SceneStore get store => _store;

  /// The latest camera frame, for the camera view.
  GrayImage? get cameraFrame => _cameraFrame;

  /// The calibration, once a usable scan has run.
  CorrespondenceMap? get map => _map;

  QualityReport? get report => _report;
  String get status => _status;
  bool get calibrated => _map != null;

  void setPreset(SimPreset preset) {
    if (scan.busy) return;
    _usePreset(preset);
    notifyListeners();
  }

  void _usePreset(SimPreset preset) {
    _preset = preset;
    _camera = SimulatedCamera(preset.build(), output);
    _store = SceneStore(
        Scene(projectorWidth: output.width, projectorHeight: output.height));
    _store.addListener(_onSceneChanged);
    _map = null;
    _report = null;
    output.setDot(null);
    output.select(null);
    output.showWhite();
    _status = 'Press Scan to calibrate.';
    _refreshCamera();
  }

  /// Lights the whole projection so the camera view shows the room.
  void showWhite() {
    if (scan.busy) return;
    output.showWhite();
    _refreshCamera();
    notifyListeners();
  }

  /// Back to the mapped scene after [showWhite].
  void showScene() {
    if (scan.busy || !calibrated) return;
    output.showScene(_store.scene);
    _refreshCamera();
    notifyListeners();
  }

  Future<void> startScan() async {
    if (scan.busy) return;
    _status = 'Scanning. Keep the phone and projector still.';
    _map = null;
    output.setDot(null);
    notifyListeners();

    final result = await scan.run(
      camera: _camera,
      output: output,
      settle: settle,
      onFrame: (frame) {
        _cameraFrame = frame;
        notifyListeners();
      },
    );
    if (result == null) return;

    _report = result.report;
    _status = result.report.message;
    if (result.report.usable) {
      _map = result.map;
      output.showScene(_store.scene);
    } else {
      output.showWhite();
    }
    _refreshCamera();
    notifyListeners();
  }

  /// Puts a dot on the projector where camera pixel ([x], [y]) is.
  void tapCamera(int x, int y) {
    final map = _map;
    if (map == null) {
      _status = 'Scan first, then tap to light a spot.';
      notifyListeners();
      return;
    }
    final spot = cameraToProjector(map, x, y);
    if (spot == null) {
      output.setDot(null);
      output.select(null);
      _status = 'The projector cannot reach camera pixel ($x, $y).';
    } else {
      output.setDot(spot);
      final surface = _store.scene.surfaceAt(Vec2(spot.x, spot.y));
      output.select(surface?.id);
      _status = 'Camera ($x, $y) lights projector '
          '(${spot.x.toStringAsFixed(1)}, ${spot.y.toStringAsFixed(1)})'
          '${surface == null ? '' : ' on "${surface.name}"'}.';
    }
    if (output.mode != OutputMode.scene) output.showScene(_store.scene);
    _refreshCamera();
    notifyListeners();
  }

  /// Turns the demo masks into surfaces, as one undo step.
  ///
  /// The masks stand in for what segmentation will return in step 4.
  void findSurfaces() {
    final map = _map;
    if (map == null || scan.busy) return;
    final adds = surfaceOpsFromMasks(_store.scene, map, demoMasks(_camera));
    if (adds.isEmpty) {
      _status = 'No surfaces found.';
      notifyListeners();
      return;
    }
    final ops = <SceneOp>[...adds];
    for (var i = 0; i < adds.length; i++) {
      ops.add(SetContent(adds[i].surface.id,
          ColorContent(surfacePalette[i % surfacePalette.length])));
    }
    _store.applyAll(ops, label: 'Find surfaces');
    _status = 'Found ${adds.length} surfaces.';
    notifyListeners();
  }

  void undo() => _store.undo();

  void redo() => _store.redo();

  void _onSceneChanged(Scene scene) {
    if (_map != null) output.showScene(scene);
    _refreshCamera();
    notifyListeners();
  }

  void _refreshCamera() {
    _cameraFrame = _camera.captureNow();
  }
}

/// Camera-space rectangles over the simulated room: the top of the box and
/// two patches of wall.
List<CameraMask> demoMasks(SimulatedCamera camera) {
  BinaryMask rect(int left, int top, int right, int bottom) =>
      BinaryMask.rectangle(
          camera.width, camera.height, left, top, right, bottom);
  return [
    CameraMask(rect(210, 130, 290, 210), name: 'Box top', label: 'box'),
    CameraMask(rect(60, 60, 180, 300), name: 'Left wall', label: 'wall'),
    CameraMask(rect(310, 70, 400, 290), name: 'Right wall', label: 'wall'),
  ];
}
