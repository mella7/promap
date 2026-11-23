import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:calib_core/calib_core.dart';

const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

/// Encodes a grey image as an 8-bit greyscale PNG.
///
/// Kept tiny on purpose so the app doesn't need an image package just to
/// upload camera frames. Every row uses filter type 0 (none).
Uint8List encodeGrayPng(GrayImage image) {
  final w = image.width;
  final h = image.height;
  final raw = Uint8List(h * (w + 1));
  for (var y = 0; y < h; y++) {
    raw[y * (w + 1)] = 0;
    raw.setRange(y * (w + 1) + 1, (y + 1) * (w + 1), image.data, y * w);
  }

  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // colour type: greyscale
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter method
    ..setUint8(12, 0); // no interlace

  final out = BytesBuilder(copy: false)..add(pngSignature);
  _chunk(out, 'IHDR', header.buffer.asUint8List());
  _chunk(out, 'IDAT', ZLibCodec(level: 6).encode(raw));
  _chunk(out, 'IEND', const []);
  return out.takeBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  out.add(length.buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  final crc = ByteData(4)..setUint32(0, crc32([...typeBytes, ...data]));
  out.add(crc.buffer.asUint8List());
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// CRC-32 as used by PNG and zip.
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
