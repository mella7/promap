import 'dart:io';

import 'package:calib_core/calib_core.dart';
import 'package:effects/effects.dart';
import 'package:flutter/foundation.dart';
import 'package:mapping_core/mapping_core.dart';
import 'package:scene_core/scene_core.dart';

import 'cloud/assistant_client.dart';
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

  /// Folder that Save writes to and Open reads from.
  final Directory projectDir;

  /// Turns typed requests into scene changes. Null without a backend.
  final SceneAssistant? assistant;

  Workbench({
    this.settle = const Duration(milliseconds: 30),
    SurfaceFinder? finder,
    Directory? projectDir,
    SceneAssistant? assistant,
  })  : finder = finder ?? SurfaceFinder.fromEnvironment(),
        projectDir = projectDir ?? defaultProjectDir(),
        assistant = assistant ?? SceneAssistant.fromEnvironment() {
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
  bool _asking = false;

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

  /// True while waiting for the assistant.
  bool get asking => _asking;

  /// True while scanning, finding surfaces or asking the assistant. Most
  /// buttons are off then.
  bool get busy => scan.busy || _finding || _asking;

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

  /// The surface last tapped, if it still exists.
  Surface? get selectedSurface {
    final id = output.selected;
    return id == null ? null : _store.scene.surfaceById(id);
  }

  /// Scan, find surfaces and dress them with [theme], in one go. Surfaces
  /// already in the scene are cleared first. Each stage is its own undo step,
  /// so Undo peels the result back a stage at a time.
  Future<void> autoMap([EffectTheme? theme]) async {
    if (busy) return;
    await startScan();
    if (!calibrated) return; // the scan's message says what went wrong
    final old = _store.scene.surfaces;
    if (old.isNotEmpty) {
      _store.applyAll([for (final s in old) RemoveSurface(s.id)],
          label: 'Clear surfaces');
      output.select(null);
    }
    await findSurfaces();
    if (_store.scene.surfaces.isEmpty) return;
    final look = theme ?? themes.first;
    applyTheme(look);
    _status = 'Mapped ${_store.scene.surfaces.length} surfaces with '
        '"${look.name}". Tap a surface to change it.';
    notifyListeners();
  }

  /// Gives a surface a new name. Blank names are ignored.
  void renameSurface(String surfaceId, String name) {
    final clean = name.trim();
    final surface = _store.scene.surfaceById(surfaceId);
    if (busy || surface == null || clean.isEmpty || clean == surface.name) {
      return;
    }
    _store.apply(RenameSurface(surfaceId, clean));
    _status = 'Renamed "${surface.name}" to "$clean".';
    notifyListeners();
  }

  /// Hides a surface, or shows it again.
  void toggleVisible(String surfaceId) {
    final surface = _store.scene.surfaceById(surfaceId);
    if (busy || surface == null) return;
    _store.apply(SetVisible(surfaceId, !surface.visible));
    _status = surface.visible
        ? '"${surface.name}" is hidden.'
        : '"${surface.name}" is showing again.';
    notifyListeners();
  }

  /// Removes a surface from the scene. Undo brings it back.
  void deleteSurface(String surfaceId) {
    final surface = _store.scene.surfaceById(surfaceId);
    if (busy || surface == null) return;
    _store.apply(RemoveSurface(surfaceId));
    if (output.selected == surfaceId) output.select(null);
    _status = 'Deleted "${surface.name}". Undo brings it back.';
    notifyListeners();
  }

  /// Joins [otherId] into [keepId]: one outline around both, [keepId]'s
  /// name and look, [otherId] removed. One undo step. Refused when the two
  /// don't touch.
  void mergeSurfaces(String keepId, String otherId) {
    final scene = _store.scene;
    final keep = scene.surfaceById(keepId);
    final other = scene.surfaceById(otherId);
    if (busy || keep == null || other == null || keepId == otherId) return;
    final outline = mergeOutlines(keep.vertices, other.vertices,
        scene.projectorWidth, scene.projectorHeight);
    if (outline == null) {
      _status = '"${keep.name}" and "${other.name}" don\'t touch, '
          'so they can\'t be one surface.';
      notifyListeners();
      return;
    }
    _store.applyAll([SetVertices(keepId, outline), RemoveSurface(otherId)],
        label: 'Merge "${other.name}" into "${keep.name}"');
    output.select(keepId);
    _status = 'Merged "${other.name}" into "${keep.name}".';
    notifyListeners();
  }

  /// Sends [prompt] and the scene to the assistant and applies what comes
  /// back as one undo step.
  Future<void> askAssistant(String prompt) async {
    final assistant = this.assistant;
    final text = prompt.trim();
    if (assistant == null || busy || text.isEmpty) return;
    _asking = true;
    _status = 'Asking the assistant...';
    notifyListeners();
    try {
      final reply = await assistant.ask(_store.scene, text);
      if (reply.ops.isNotEmpty) {
        final label = text.length > 40 ? '${text.substring(0, 40)}...' : text;
        _store.applyAll(reply.ops, label: 'Assistant: $label');
      }
      _status = reply.message;
    } on AssistantException catch (error) {
      _status = error.message;
    } on SceneError catch (error) {
      // The scene changed while waiting, for example a surface was removed.
      _status = "The assistant's changes no longer fit the scene "
          '(${error.message}). Nothing was changed.';
    } finally {
      _asking = false;
      notifyListeners();
    }
  }

  /// Dresses every surface with [theme], as one undo step.
  void applyTheme(EffectTheme theme) {
    if (busy) return;
    final ops = themeOps(_store.scene, theme);
    if (ops.isEmpty) {
      _status = 'Find surfaces first, then pick a theme.';
      notifyListeners();
      return;
    }
    _store.applyAll(ops, label: 'Theme: ${theme.name}');
    _status = 'Applied "${theme.name}" to ${ops.length} surfaces.';
    notifyListeners();
  }

  /// Puts effect [effectId] on one surface, or a plain colour when null.
  void setSurfaceEffect(String surfaceId, String? effectId) {
    if (busy) return;
    final surface = _store.scene.surfaceById(surfaceId);
    if (surface == null) return;
    final Content content;
    if (effectId == null) {
      final index = _store.scene.indexOf(surfaceId);
      content = ColorContent(surfacePalette[index % surfacePalette.length]);
    } else {
      final spec = effectById(effectId);
      if (spec == null) return;
      content = spec.content();
    }
    _store.apply(SetContent(surfaceId, content));
    _status = effectId == null
        ? '"${surface.name}" is a plain colour now.'
        : '"${surface.name}" now shows ${effectById(effectId)!.name}.';
    notifyListeners();
  }

  /// Shows [params] on a surface's effect without adding an undo step, for
  /// live preview while a slider moves. [commitSurfaceParams] makes it stick.
  void previewSurfaceParams(String surfaceId, Map<String, Object?> params) {
    final content = _effectContent(surfaceId, params);
    if (content == null || !calibrated) return;
    final scene = _store.scene;
    output.showScene(scene.withSurfaces([
      for (final s in scene.surfaces)
        s.id == surfaceId ? s.copyWith(content: content) : s,
    ]));
  }

  /// Saves new settings for a surface's effect as one undo step.
  void commitSurfaceParams(String surfaceId, Map<String, Object?> params) {
    if (busy) return;
    final content = _effectContent(surfaceId, params);
    if (content == null) return;
    _store.apply(SetContent(surfaceId, content));
  }

  EffectContent? _effectContent(String surfaceId, Map<String, Object?> params) {
    final current = _store.scene.surfaceById(surfaceId)?.content;
    if (current is! EffectContent) return null;
    return effectById(current.effect)?.content(params);
  }

  /// Writes the scene and the calibration to [projectDir].
  Future<void> saveProject() async {
    final map = _map;
    if (map == null || busy) {
      _status = 'Scan first, there is nothing to save yet.';
      notifyListeners();
      return;
    }
    try {
      await projectDir.create(recursive: true);
      final scene = _store.scene.withCalibration(_calibrationFile);
      await File('${projectDir.path}/$_calibrationFile')
          .writeAsBytes(map.toBytes(), flush: true);
      await File('${projectDir.path}/$_sceneFile')
          .writeAsString(scene.encode(), flush: true);
      _status = 'Saved ${scene.surfaces.length} surfaces to ${projectDir.path}.';
    } on FileSystemException catch (error) {
      _status = 'Could not save: ${error.message} (${error.path}).';
    }
    notifyListeners();
  }

  /// Loads the scene and calibration last saved to [projectDir].
  Future<void> openProject() async {
    if (busy) return;
    try {
      final sceneFile = File('${projectDir.path}/$_sceneFile');
      if (!await sceneFile.exists()) {
        _status = 'Nothing saved in ${projectDir.path} yet.';
        notifyListeners();
        return;
      }
      final scene = Scene.decode(await sceneFile.readAsString());
      final name = scene.calibration ?? _calibrationFile;
      if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
        throw FormatException('Calibration file name "$name" is not allowed');
      }
      final map = CorrespondenceMap.fromBytes(
          await File('${projectDir.path}/$name').readAsBytes());
      if (map.projectorWidth != scene.projectorWidth ||
          map.projectorHeight != scene.projectorHeight) {
        throw const FormatException(
            'The scene and the calibration are for different projectors');
      }
      if (map.cameraWidth != _camera.width ||
          map.cameraHeight != _camera.height) {
        throw const FormatException(
            'The calibration was made with a different camera');
      }
      _map = map;
      _report = null;
      output.setDot(null);
      output.select(null);
      _store.replaceScene(scene);
      _status = 'Opened ${scene.surfaces.length} surfaces from '
          '${projectDir.path}.';
    } on FormatException catch (error) {
      _status = 'Could not open the project: ${error.message}';
    } on SceneError catch (error) {
      _status = 'Could not open the project: ${error.message}';
    } on FileSystemException catch (error) {
      _status = 'Could not open the project: ${error.message} (${error.path}).';
    }
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

const _sceneFile = 'scene.json';
const _calibrationFile = 'calibration.pmap';

/// Where projects go on the laptop: ~/promap-projects/last.
Directory defaultProjectDir() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return Directory('$home/promap-projects/last');
}
