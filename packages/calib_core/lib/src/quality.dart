/// Outcome of a scan, worst problem first.
enum ScanVerdict {
  ok,

  /// The camera saw no difference between the white and black frames.
  noSignal,

  /// Room light drowns out the projector.
  tooBright,

  /// The projection is visible but weak.
  tooDim,

  /// Large parts of the lit area are clipped to white.
  overexposed,

  /// The scan worked but the camera sees only part of the projection.
  partialCoverage,
}

/// Numbers and a plain-language verdict for one decoded scan.
class QualityReport {
  final ScanVerdict verdict;

  /// A sentence the app can show to the user as is.
  final String message;

  /// Share of camera pixels that decoded to a projector position.
  final double cameraCoverage;

  /// Share of camera pixels where the projector made a visible difference.
  final double litFraction;

  /// Share of the projector image the camera saw.
  final double projectorCoverage;

  /// Share of lit camera pixels that are clipped in the white frame.
  final double saturatedFraction;

  /// Mean camera brightness with the projector showing black (0-255).
  final double ambientLevel;

  /// Mean white-minus-black difference over lit pixels (0-255).
  final double meanContrast;

  const QualityReport({
    required this.verdict,
    required this.message,
    required this.cameraCoverage,
    required this.litFraction,
    required this.projectorCoverage,
    required this.saturatedFraction,
    required this.ambientLevel,
    required this.meanContrast,
  });

  /// Whether the map is good enough to project with.
  bool get usable =>
      verdict == ScanVerdict.ok ||
      verdict == ScanVerdict.partialCoverage ||
      verdict == ScanVerdict.overexposed;

  @override
  String toString() => '${verdict.name}: $message '
      '(camera ${(cameraCoverage * 100).toStringAsFixed(1)}%, '
      'projector ${(projectorCoverage * 100).toStringAsFixed(1)}%, '
      'saturated ${(saturatedFraction * 100).toStringAsFixed(1)}%, '
      'ambient ${ambientLevel.toStringAsFixed(0)}, '
      'contrast ${meanContrast.toStringAsFixed(0)})';
}

/// Thresholds behind the verdict.
class QualityThresholds {
  final double minLitFraction;
  final double brightAmbientLevel;
  final double maxSaturatedFraction;
  final double minProjectorCoverage;

  const QualityThresholds({
    this.minLitFraction = 0.01,
    this.brightAmbientLevel = 128,
    this.maxSaturatedFraction = 0.25,
    this.minProjectorCoverage = 0.6,
  });
}

QualityReport assessScan({
  required double cameraCoverage,
  required double litFraction,
  required double projectorCoverage,
  required double saturatedFraction,
  required double ambientLevel,
  required double meanContrast,
  required int minContrast,
  QualityThresholds thresholds = const QualityThresholds(),
}) {
  ScanVerdict verdict;
  String message;
  final brightRoom = ambientLevel > thresholds.brightAmbientLevel;

  if (litFraction < thresholds.minLitFraction) {
    if (brightRoom) {
      verdict = ScanVerdict.tooBright;
      message = 'The room is too bright for the camera to see the projection. '
          'Dim the lights or lower the camera exposure.';
    } else {
      verdict = ScanVerdict.noSignal;
      message = 'The camera cannot see the projection. '
          'Point the camera at the projected area and check the projector is on.';
    }
  } else if (meanContrast < 2 * minContrast) {
    if (brightRoom) {
      verdict = ScanVerdict.tooBright;
      message = 'Room light is washing out the projection. '
          'Dim the lights or lower the camera exposure.';
    } else {
      verdict = ScanVerdict.tooDim;
      message = 'The projection looks too dim to the camera. '
          'Move the projector closer or raise the camera exposure.';
    }
  } else if (saturatedFraction > thresholds.maxSaturatedFraction) {
    verdict = ScanVerdict.overexposed;
    message = 'The camera is overexposed on the projection. '
        'Lower the exposure and scan again for a cleaner result.';
  } else if (projectorCoverage < thresholds.minProjectorCoverage) {
    verdict = ScanVerdict.partialCoverage;
    message = 'The camera sees only part of the projection. '
        'Move the camera back or aim it at the whole projected area.';
  } else {
    verdict = ScanVerdict.ok;
    message = 'Scan complete.';
  }

  return QualityReport(
    verdict: verdict,
    message: message,
    cameraCoverage: cameraCoverage,
    litFraction: litFraction,
    projectorCoverage: projectorCoverage,
    saturatedFraction: saturatedFraction,
    ambientLevel: ambientLevel,
    meanContrast: meanContrast,
  );
}
