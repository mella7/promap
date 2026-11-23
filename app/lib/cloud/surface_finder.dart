import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calib_core/calib_core.dart';
import 'package:mapping_core/mapping_core.dart';

import 'png.dart';
import 'rle.dart';

/// What a finder found in one photo.
class SurfaceFinderResult {
  /// Which model produced the masks, as reported by whoever ran it.
  final String model;
  final List<CameraMask> masks;

  const SurfaceFinderResult(this.model, this.masks);
}

/// Something went wrong finding surfaces. [message] can be shown as is.
class SurfaceFinderException implements Exception {
  final String message;

  const SurfaceFinderException(this.message);

  @override
  String toString() => message;
}

/// Finds surfaces in a camera photo taken under white projector light.
abstract interface class SurfaceFinder {
  /// Shown in the app, for example "backend at http://127.0.0.1:8000".
  String get description;

  Future<SurfaceFinderResult> find(GrayImage photo);

  /// The backend when the app was started with
  /// `--dart-define=PROMAP_BACKEND=<url>`, the built-in demo shapes otherwise.
  static SurfaceFinder fromEnvironment() {
    const url = String.fromEnvironment('PROMAP_BACKEND');
    const key = String.fromEnvironment('PROMAP_API_KEY');
    if (url.isEmpty) return const DemoSurfaceFinder();
    return BackendSurfaceFinder(Uri.parse(url), apiKey: key.isEmpty ? null : key);
  }
}

/// (name, label, left, top, right, bottom) as fractions of the photo. They
/// match the box and wall in the simulator, and the backend's fake model.
const _demoShapes = [
  ('Box top', 'box', 210 / 480, 130 / 360, 290 / 480, 210 / 360),
  ('Left wall', 'wall', 60 / 480, 60 / 360, 180 / 480, 300 / 360),
  ('Right wall', 'wall', 310 / 480, 70 / 360, 400 / 480, 290 / 360),
];

/// Fixed shapes, no network. Used when no backend is configured.
class DemoSurfaceFinder implements SurfaceFinder {
  const DemoSurfaceFinder();

  @override
  String get description => 'built-in demo shapes';

  @override
  Future<SurfaceFinderResult> find(GrayImage photo) async {
    final w = photo.width;
    final h = photo.height;
    return SurfaceFinderResult('demo', [
      for (final (name, label, left, top, right, bottom) in _demoShapes)
        CameraMask(
          BinaryMask.rectangle(w, h, (left * w).round(), (top * h).round(),
              (right * w).round(), (bottom * h).round()),
          name: name,
          label: label,
        ),
    ]);
  }
}

/// Sends the photo to the promap backend and reads back its masks.
class BackendSurfaceFinder implements SurfaceFinder {
  final Uri baseUrl;

  /// Sent as X-API-Key when the backend requires one.
  final String? apiKey;

  final Duration timeout;

  const BackendSurfaceFinder(this.baseUrl,
      {this.apiKey, this.timeout = const Duration(seconds: 120)});

  @override
  String get description => 'backend at $baseUrl';

  Uri get _segmentUrl {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return base.resolve('v1/segment');
  }

  @override
  Future<SurfaceFinderResult> find(GrayImage photo) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(_segmentUrl).timeout(timeout);
      request.headers.contentType = ContentType('image', 'png');
      final key = apiKey;
      if (key != null) request.headers.set('x-api-key', key);
      final body = encodeGrayPng(photo);
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        throw SurfaceFinderException(
            'The backend answered ${response.statusCode}: ${backendErrorDetail(text)}');
      }
      return parseSegmentResponse(text, photo.width, photo.height);
    } on SocketException catch (error) {
      throw SurfaceFinderException(
          'Cannot reach the backend at $baseUrl (${error.message}). '
          'Is it running?');
    } on TimeoutException {
      throw SurfaceFinderException(
          'The backend at $baseUrl did not answer within '
          '${timeout.inSeconds} seconds.');
    } finally {
      client.close(force: true);
    }
  }
}

/// Reads a /v1/segment reply for a photo of [width] x [height] pixels.
SurfaceFinderResult parseSegmentResponse(String text, int width, int height) {
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['width'] != width || json['height'] != height) {
      throw SurfaceFinderException(
          'The backend answered for a ${json['width']}x${json['height']} '
          'image, but the photo is ${width}x$height.');
    }
    final masks = <CameraMask>[];
    for (final entry in json['masks'] as List<dynamic>) {
      final mask = entry as Map<String, dynamic>;
      final rle = mask['rle'] as Map<String, dynamic>;
      final counts = [for (final c in rle['counts'] as List<dynamic>) c as int];
      masks.add(CameraMask(
        decodeRle(counts, width, height),
        name: mask['name'] as String,
        label: mask['label'] as String?,
      ));
    }
    return SurfaceFinderResult(json['model'] as String, masks);
  } on SurfaceFinderException {
    rethrow;
  } on Object catch (error) {
    throw SurfaceFinderException(
        'The backend sent a reply the app cannot read ($error).');
  }
}

/// The `detail` of a FastAPI error reply, or the start of the raw text.
String backendErrorDetail(String text) {
  try {
    final json = jsonDecode(text);
    if (json is Map && json['detail'] is String) return json['detail'] as String;
  } on FormatException {
    // Not JSON, fall through.
  }
  return text.length > 200 ? '${text.substring(0, 200)}...' : text;
}
