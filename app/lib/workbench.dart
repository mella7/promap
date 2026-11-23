import 'package:calib_core/calib_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';

import 'cloud/surface_finder.dart';
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

  /// Where "Find surfaces" gets its masks: the backend or the demo shapes.
  final SurfaceFinder finder;

  Workbench({
    this.settle = const Duration(milliseconds: 30),
    SurfaceFinder? finder,
  }) : finder = finder ?? SurfaceFinder.fromEnvironment() {
    _usePreset(SimPreset.normal);
  }

  SimPreset _preset = SimPreset.normal;
  late SimulatedCamera _camera;
  late SceneStore _store;
  GrayImage? _cameraFrame;
  CorrespondenceMap? _map;
  QualityReport? _report;
  String _status = '';
  bool _finding = false;

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

  /// True while waiting for surfaces.
  bool get finding => _finding;

  /// True while scanning or finding surfaces. Most buttons are off then.
  bool get busy => scan.busy || _finding;

  void setPreset(SimPreset preset) {
    if (busy) return;
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
    if (busy) return;
    output.showWhite();
    _refreshCamera();
    notifyListeners();
  }

  /// Back to the mapped scene after [showWhite].
  void showScene() {
    if (busy || !calibrated) return;
    output.showScene(_store.scene);
    _refreshCamera();
    notifyListeners();
  }

  Future<void> startScan() async {
    if (busy) return;
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

  /// Takes a photo under white light, asks [finder] for surfaces and adds
  /// them to the scene as one undo step.
  Future<void> findSurfaces() async {
    final map = _map;
    if (map == null || busy) return;
    _finding = true;
    _status = 'Taking a photo under white light...';
    notifyListeners();
    try {
      output.showWhite();
      final photo = await _camera.capture();
      output.showScene(_store.scene);
      _refreshCamera();
      _status = 'Looking for surfaces (${finder.description})...';
      notifyListeners();

      final result = await finder.find(photo);
      final adds = surfaceOpsFromMasks(_store.scene, map, result.masks);
      if (adds.isEmpty) {
        _status = 'No surfaces found (model: ${result.model}).';
        return;
      }
      final ops = <SceneOp>[...adds];
      for (var i = 0; i < adds.length; i++) {
        ops.add(SetContent(adds[i].surface.id,
            ColorContent(surfacePalette[i % surfacePalette.length])));
      }
      _store.applyAll(ops, label: 'Find surfaces');
      _status = 'Found ${adds.length} surfaces (model: ${result.model}).';
    } on SurfaceFinderException catch (error) {
      output.showScene(_store.scene);
      _refreshCamera();
      _status = error.message;
    } finally {
      _finding = false;
      notifyListeners();
    }
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
