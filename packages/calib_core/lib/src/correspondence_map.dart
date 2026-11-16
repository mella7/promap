import 'dart:math';
import 'dart:typed_data';

/// For every camera pixel, the projector pixel that lights it.
///
/// Coordinates are pixel centres: projector pixel 0 has its centre at 0.0.
class CorrespondenceMap {
  static const int _magic = 0x50414D50; // 'PMAP', little endian
  static const int _version = 1;
  static const int _headerBytes = 24;

  final int cameraWidth;
  final int cameraHeight;
  final int projectorWidth;
  final int projectorHeight;

  /// Projector x and y per camera pixel. Only meaningful where [valid] is 1.
  final Float32List projX;
  final Float32List projY;
  final Uint8List valid;

  CorrespondenceMap({
    required this.cameraWidth,
    required this.cameraHeight,
    required this.projectorWidth,
    required this.projectorHeight,
    required this.projX,
    required this.projY,
    required this.valid,
  }) {
    final n = cameraWidth * cameraHeight;
    if (projX.length != n || projY.length != n || valid.length != n) {
      throw ArgumentError('Map arrays must hold one value per camera pixel');
    }
  }

  int get validCount {
    var count = 0;
    for (var i = 0; i < valid.length; i++) {
      count += valid[i];
    }
    return count;
  }

  /// Share of camera pixels that decoded to a projector position.
  double get cameraCoverage => validCount / valid.length;

  /// Projector position seen by camera pixel ([cx], [cy]), or null when that
  /// pixel is outside the image or was not decoded.
  Point<double>? cameraToProjector(int cx, int cy) {
    if (cx < 0 || cy < 0 || cx >= cameraWidth || cy >= cameraHeight) {
      return null;
    }
    final i = cy * cameraWidth + cx;
    if (valid[i] == 0) return null;
    return Point<double>(projX[i], projY[i]);
  }

  /// Builds the opposite lookup: for every projector pixel, where the camera
  /// sees it. Projector pixels no camera pixel landed on are filled from their
  /// neighbours for up to [holeFillPasses] rounds.
  InverseMap buildInverse({int holeFillPasses = 4}) {
    final pw = projectorWidth;
    final ph = projectorHeight;
    final sumX = Float64List(pw * ph);
    final sumY = Float64List(pw * ph);
    final hits = Int32List(pw * ph);

    for (var cy = 0; cy < cameraHeight; cy++) {
      for (var cx = 0; cx < cameraWidth; cx++) {
        final i = cy * cameraWidth + cx;
        if (valid[i] == 0) continue;
        final px = projX[i].round();
        final py = projY[i].round();
        if (px < 0 || py < 0 || px >= pw || py >= ph) continue;
        final j = py * pw + px;
        sumX[j] += cx;
        sumY[j] += cy;
        hits[j]++;
      }
    }

    final camX = Float32List(pw * ph);
    final camY = Float32List(pw * ph);
    var filled = Uint8List(pw * ph);
    final measured = Uint8List(pw * ph);
    for (var j = 0; j < pw * ph; j++) {
      if (hits[j] > 0) {
        camX[j] = sumX[j] / hits[j];
        camY[j] = sumY[j] / hits[j];
        filled[j] = 1;
        measured[j] = 1;
      }
    }

    for (var pass = 0; pass < holeFillPasses; pass++) {
      final next = Uint8List.fromList(filled);
      var changed = false;
      for (var y = 0; y < ph; y++) {
        for (var x = 0; x < pw; x++) {
          final j = y * pw + x;
          if (filled[j] == 1) continue;
          var sx = 0.0;
          var sy = 0.0;
          var count = 0;
          for (var dy = -1; dy <= 1; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= ph) continue;
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              if (nx < 0 || nx >= pw) continue;
              final k = ny * pw + nx;
              if (filled[k] == 0) continue;
              sx += camX[k];
              sy += camY[k];
              count++;
            }
          }
          if (count >= 2) {
            camX[j] = sx / count;
            camY[j] = sy / count;
            next[j] = 1;
            changed = true;
          }
        }
      }
      filled = next;
      if (!changed) break;
    }

    return InverseMap(
      projectorWidth: pw,
      projectorHeight: ph,
      camX: camX,
      camY: camY,
      valid: filled,
      measured: measured,
    );
  }

  /// Packs the map into bytes for saving to a file.
  ///
  /// Layout: 24-byte header (magic, version, four sizes, all uint32 little
  /// endian), projX, projY as float32, then one validity byte per pixel.
  Uint8List toBytes() {
    final n = cameraWidth * cameraHeight;
    final bytes = Uint8List(_headerBytes + n * 9);
    final header = ByteData.sublistView(bytes, 0, _headerBytes);
    header.setUint32(0, _magic, Endian.little);
    header.setUint32(4, _version, Endian.little);
    header.setUint32(8, cameraWidth, Endian.little);
    header.setUint32(12, cameraHeight, Endian.little);
    header.setUint32(16, projectorWidth, Endian.little);
    header.setUint32(20, projectorHeight, Endian.little);

    final body = ByteData.sublistView(bytes, _headerBytes);
    for (var i = 0; i < n; i++) {
      body.setFloat32(i * 4, projX[i], Endian.little);
      body.setFloat32(n * 4 + i * 4, projY[i], Endian.little);
    }
    bytes.setRange(_headerBytes + n * 8, _headerBytes + n * 9, valid);
    return bytes;
  }

  /// Reads a map written by [toBytes]. Throws [FormatException] on bad data.
  static CorrespondenceMap fromBytes(Uint8List bytes) {
    if (bytes.length < _headerBytes) {
      throw const FormatException('Calibration file is too short');
    }
    final header = ByteData.sublistView(bytes, 0, _headerBytes);
    if (header.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('Not a calibration map file');
    }
    final version = header.getUint32(4, Endian.little);
    if (version != _version) {
      throw FormatException('Unsupported calibration map version $version');
    }
    final cw = header.getUint32(8, Endian.little);
    final ch = header.getUint32(12, Endian.little);
    final pw = header.getUint32(16, Endian.little);
    final ph = header.getUint32(20, Endian.little);
    final n = cw * ch;
    if (bytes.length != _headerBytes + n * 9) {
      throw const FormatException('Calibration file size does not match');
    }

    final body = ByteData.sublistView(bytes, _headerBytes);
    final px = Float32List(n);
    final py = Float32List(n);
    for (var i = 0; i < n; i++) {
      px[i] = body.getFloat32(i * 4, Endian.little);
      py[i] = body.getFloat32(n * 4 + i * 4, Endian.little);
    }
    final valid = Uint8List.fromList(
        bytes.sublist(_headerBytes + n * 8, _headerBytes + n * 9));

    return CorrespondenceMap(
      cameraWidth: cw,
      cameraHeight: ch,
      projectorWidth: pw,
      projectorHeight: ph,
      projX: px,
      projY: py,
      valid: valid,
    );
  }
}

/// For every projector pixel, the camera position that sees it.
class InverseMap {
  final int projectorWidth;
  final int projectorHeight;
  final Float32List camX;
  final Float32List camY;

  /// 1 where a camera position is known, measured or filled.
  final Uint8List valid;

  /// 1 only where at least one camera pixel landed directly.
  final Uint8List measured;

  InverseMap({
    required this.projectorWidth,
    required this.projectorHeight,
    required this.camX,
    required this.camY,
    required this.valid,
    required this.measured,
  });

  /// Share of projector pixels the camera saw directly.
  double get measuredCoverage {
    var count = 0;
    for (var i = 0; i < measured.length; i++) {
      count += measured[i];
    }
    return count / measured.length;
  }

  Point<double>? projectorToCamera(int px, int py) {
    if (px < 0 || py < 0 || px >= projectorWidth || py >= projectorHeight) {
      return null;
    }
    final i = py * projectorWidth + px;
    if (valid[i] == 0) return null;
    return Point<double>(camX[i], camY[i]);
  }
}
