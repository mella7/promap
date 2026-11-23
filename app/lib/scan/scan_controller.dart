import 'package:calib_core/calib_core.dart';
import 'package:flutter/foundation.dart';

import '../devices/camera_source.dart';
import '../devices/output_controller.dart';

/// Runs one structured-light scan: show each pattern, wait for it to settle,
/// take a frame, then decode everything in a background isolate.
class ScanController extends ChangeNotifier {
  bool _busy = false;
  double _progress = 0;
  String _phase = '';

  bool get busy => _busy;

  /// 0 to 1 while capturing.
  double get progress => _progress;

  /// "Capturing 12 of 32", "Decoding" and so on.
  String get phase => _phase;

  /// Returns null if a scan is already running.
  Future<DecodeResult?> run({
    required CameraSource camera,
    required OutputController output,
    Duration settle = const Duration(milliseconds: 30),
    void Function(GrayImage frame)? onFrame,
  }) async {
    if (_busy) return null;
    _busy = true;
    _progress = 0;
    try {
      final patterns = PatternSet(output.width, output.height);
      final total = patterns.specs.length;
      final frames = <GrayImage>[];
      for (var i = 0; i < total; i++) {
        _phase = 'Capturing ${i + 1} of $total';
        output.showPattern(patterns.render(patterns.specs[i]));
        await Future<void>.delayed(settle);
        final frame = await camera.capture();
        frames.add(frame);
        onFrame?.call(frame);
        _progress = (i + 1) / total;
        notifyListeners();
      }
      _phase = 'Decoding';
      notifyListeners();
      return await compute(_decode, _DecodeJob(patterns, frames));
    } finally {
      _busy = false;
      _phase = '';
      notifyListeners();
    }
  }
}

class _DecodeJob {
  final PatternSet patterns;
  final List<GrayImage> frames;

  const _DecodeJob(this.patterns, this.frames);
}

DecodeResult _decode(_DecodeJob job) => decodeScan(job.patterns, job.frames);
