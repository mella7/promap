import 'dart:typed_data';

import 'correspondence_map.dart';
import 'gray_code.dart';
import 'gray_image.dart';
import 'pattern.dart';
import 'quality.dart';

/// Tuning for [decodeScan]. The defaults suit an 8-bit camera image.
class DecodeOptions {
  /// Smallest white-minus-black difference for a pixel to count as lit.
  final int minContrast;

  /// A bit is "ambiguous" when the pattern and its inverse differ by less
  /// than this share of the pixel's contrast, or by less than
  /// [ambiguityFloor] levels.
  final double ambiguityFraction;
  final int ambiguityFloor;

  /// Pixels with more ambiguous bits than this are rejected. One or two are
  /// normal on stripe edges and cost at most one cell of error.
  final int maxAmbiguousBits;

  /// White-frame level at or above which a pixel counts as clipped.
  final int saturationLevel;

  /// Radius in camera pixels of the smoothing pass that turns cell-sized
  /// steps into sub-pixel positions. 0 turns it off.
  final int refineRadius;

  final QualityThresholds quality;

  const DecodeOptions({
    this.minContrast = 20,
    this.ambiguityFraction = 0.15,
    this.ambiguityFloor = 4,
    this.maxAmbiguousBits = 2,
    this.saturationLevel = 250,
    this.refineRadius = 2,
    this.quality = const QualityThresholds(),
  });
}

class DecodeResult {
  final CorrespondenceMap map;
  final QualityReport report;

  const DecodeResult(this.map, this.report);
}

/// Turns the camera frames of one scan into a camera-to-projector map.
///
/// [frames] must hold one camera image per entry of `patterns.specs`, in the
/// same order, all the same size.
DecodeResult decodeScan(
  PatternSet patterns,
  List<GrayImage> frames, {
  DecodeOptions options = const DecodeOptions(),
}) {
  if (frames.length != patterns.specs.length) {
    throw ArgumentError(
        'Expected ${patterns.specs.length} frames, got ${frames.length}');
  }
  final camW = frames[0].width;
  final camH = frames[0].height;
  for (final frame in frames) {
    if (frame.width != camW || frame.height != camH) {
      throw ArgumentError('All frames must be the same size');
    }
  }
  final n = camW * camH;
  final white = frames[0].data;
  final black = frames[1].data;

  final contrast = Int16List(n);
  var litCount = 0;
  var saturatedCount = 0;
  var blackSum = 0;
  var contrastSum = 0;
  for (var i = 0; i < n; i++) {
    final c = white[i] - black[i];
    contrast[i] = c;
    blackSum += black[i];
    if (c >= options.minContrast) {
      litCount++;
      contrastSum += c;
      if (white[i] >= options.saturationLevel) saturatedCount++;
    }
  }

  final codeX = Int32List(n);
  final codeY = Int32List(n);
  final ambiguous = Uint8List(n);
  var frameIndex = 2;
  frameIndex = _readBits(
      frames, frameIndex, patterns.bitsX, codeX, contrast, ambiguous, options);
  _readBits(
      frames, frameIndex, patterns.bitsY, codeY, contrast, ambiguous, options);

  final cell = patterns.cellSize;
  var projX = Float32List(n);
  var projY = Float32List(n);
  final valid = Uint8List(n);
  for (var i = 0; i < n; i++) {
    if (contrast[i] < options.minContrast) continue;
    if (ambiguous[i] > options.maxAmbiguousBits) continue;
    final cx = fromGray(codeX[i]);
    final cy = fromGray(codeY[i]);
    if (cx >= patterns.cellsX || cy >= patterns.cellsY) continue;
    projX[i] = (cx + 0.5) * cell - 0.5;
    projY[i] = (cy + 0.5) * cell - 0.5;
    valid[i] = 1;
  }

  if (options.refineRadius > 0) {
    final refinedX = Float32List(n);
    final refinedY = Float32List(n);
    _refine(projX, projY, valid, camW, camH, options.refineRadius, 1.5 * cell,
        refinedX, refinedY);
    projX = refinedX;
    projY = refinedY;
  }

  final map = CorrespondenceMap(
    cameraWidth: camW,
    cameraHeight: camH,
    projectorWidth: patterns.projectorWidth,
    projectorHeight: patterns.projectorHeight,
    projX: projX,
    projY: projY,
    valid: valid,
  );

  final report = assessScan(
    cameraCoverage: map.cameraCoverage,
    litFraction: litCount / n,
    projectorCoverage: _projectorCoverage(patterns, projX, projY, valid),
    saturatedFraction: litCount == 0 ? 0.0 : saturatedCount / litCount,
    ambientLevel: blackSum / n,
    meanContrast: litCount == 0 ? 0.0 : contrastSum / litCount,
    minContrast: options.minContrast,
    thresholds: options.quality,
  );

  return DecodeResult(map, report);
}

/// Share of projector cells that at least one camera pixel decoded to.
double _projectorCoverage(
  PatternSet patterns,
  Float32List projX,
  Float32List projY,
  Uint8List valid,
) {
  final cellsX = patterns.cellsX;
  final cellsY = patterns.cellsY;
  final cell = patterns.cellSize;
  final seen = Uint8List(cellsX * cellsY);
  for (var i = 0; i < valid.length; i++) {
    if (valid[i] == 0) continue;
    var cx = ((projX[i] + 0.5) / cell).floor();
    var cy = ((projY[i] + 0.5) / cell).floor();
    if (cx < 0) cx = 0;
    if (cy < 0) cy = 0;
    if (cx >= cellsX) cx = cellsX - 1;
    if (cy >= cellsY) cy = cellsY - 1;
    seen[cy * cellsX + cx] = 1;
  }
  var count = 0;
  for (var i = 0; i < seen.length; i++) {
    count += seen[i];
  }
  return count / seen.length;
}

/// Reads [bitCount] pattern/inverse pairs starting at [frameIndex] into
/// [code], coarse bit first. Returns the index of the next unread frame.
int _readBits(
  List<GrayImage> frames,
  int frameIndex,
  int bitCount,
  Int32List code,
  Int16List contrast,
  Uint8List ambiguous,
  DecodeOptions options,
) {
  final n = code.length;
  var index = frameIndex;
  for (var bit = bitCount - 1; bit >= 0; bit--) {
    final normal = frames[index].data;
    final inverse = frames[index + 1].data;
    index += 2;
    final mask = 1 << bit;
    for (var i = 0; i < n; i++) {
      final a = normal[i];
      final b = inverse[i];
      if (a > b) code[i] |= mask;
      final c = contrast[i];
      if (c < options.minContrast) continue;
      var threshold = (options.ambiguityFraction * c).round();
      if (threshold < options.ambiguityFloor) {
        threshold = options.ambiguityFloor;
      }
      final diff = a > b ? a - b : b - a;
      if (diff < threshold) ambiguous[i]++;
    }
  }
  return index;
}

/// Averages each valid pixel with the valid neighbours on the same surface.
///
/// A neighbour counts only when both of its raw coordinates are within
/// [tolerance] of the centre pixel's, so the average never mixes two objects
/// at different depths. This turns the cell-sized steps of the raw decode
/// into sub-pixel positions.
void _refine(
  Float32List rawX,
  Float32List rawY,
  Uint8List valid,
  int width,
  int height,
  int radius,
  double tolerance,
  Float32List outX,
  Float32List outY,
) {
  for (var y = 0; y < height; y++) {
    final y0 = y - radius < 0 ? 0 : y - radius;
    final y1 = y + radius >= height ? height - 1 : y + radius;
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (valid[i] == 0) continue;
      final centreX = rawX[i];
      final centreY = rawY[i];
      final x0 = x - radius < 0 ? 0 : x - radius;
      final x1 = x + radius >= width ? width - 1 : x + radius;
      var sumX = 0.0;
      var sumY = 0.0;
      var count = 0;
      for (var ny = y0; ny <= y1; ny++) {
        final row = ny * width;
        for (var nx = x0; nx <= x1; nx++) {
          final k = row + nx;
          if (valid[k] == 0) continue;
          final dx = rawX[k] - centreX;
          if (dx > tolerance || dx < -tolerance) continue;
          final dy = rawY[k] - centreY;
          if (dy > tolerance || dy < -tolerance) continue;
          sumX += rawX[k];
          sumY += rawY[k];
          count++;
        }
      }
      outX[i] = sumX / count;
      outY[i] = sumY / count;
    }
  }
}
