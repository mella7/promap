// Only plain test() here, no testWidgets: the widget test binding blocks real
// HTTP, and these tests talk to a small local server.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:calib_core/calib_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/cloud/png.dart';
import 'package:promap_app/cloud/rle.dart';
import 'package:promap_app/cloud/surface_finder.dart';

String fixture() =>
    File('test/fixtures/segment_response.json').readAsStringSync();

void main() {
  group('rle', () {
    test('decodes runs that start with background', () {
      final mask = decodeRle([0, 2, 2, 2], 3, 2);
      expect(mask.data, [1, 1, 0, 0, 1, 1]);
      expect(decodeRle([6], 3, 2).count, 0);
    });

    test('rejects runs with the wrong total', () {
      expect(() => decodeRle([1, 2], 2, 2), throwsFormatException);
      expect(() => decodeRle([5, -1], 2, 2), throwsFormatException);
    });
  });

  group('png', () {
    test('writes a valid greyscale PNG', () {
      final pixels = Uint8List.fromList([0, 50, 100, 150, 200, 250]);
      final image = GrayImage(3, 2, pixels);
      final png = encodeGrayPng(image);

      expect(png.sublist(0, 8), pngSignature);
      final data = ByteData.sublistView(png);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
      expect(data.getUint32(16), 3);
      expect(data.getUint32(20), 2);
      expect(png[24], 8);
      expect(png[25], 0);

      // IDAT follows IHDR (8 + 4 + 4 + 13 + 4 = 33 bytes in).
      final idatLength = data.getUint32(33);
      expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
      final idat = png.sublist(41, 41 + idatLength);
      expect(ZLibCodec().decode(idat), [0, 0, 50, 100, 0, 150, 200, 250]);

      final crc = data.getUint32(41 + idatLength);
      expect(crc, crc32(png.sublist(37, 41 + idatLength)));
      expect(String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)),
          'IEND');
    });

    test('crc32 matches the standard check value', () {
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    });
  });

  group('segment response', () {
    test('a real backend reply decodes to three masks', () {
      final result = parseSegmentResponse(fixture(), 480, 360);
      expect(result.model, 'fake');
      expect([for (final m in result.masks) m.name],
          ['Box top', 'Left wall', 'Right wall']);
      expect(result.masks.first.label, 'box');
      expect(result.masks.first.mask.count, 80 * 80);
      expect(result.masks.first.mask.get(210, 130), isTrue);
      expect(result.masks.first.mask.get(290, 130), isFalse);
    });

    test('a reply for another image size is refused', () {
      expect(() => parseSegmentResponse(fixture(), 640, 480),
          throwsA(isA<SurfaceFinderException>()));
    });

    test('a broken reply gives a readable error', () {
      expect(() => parseSegmentResponse('{"masks": 3}', 480, 360),
          throwsA(isA<SurfaceFinderException>()));
      expect(() => parseSegmentResponse('not json', 480, 360),
          throwsA(isA<SurfaceFinderException>()));
    });
  });

  group('backend finder', () {
    late HttpServer server;
    late List<String> seen;
    var status = 200;

    setUp(() async {
      seen = [];
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        seen.add('${request.method} ${request.uri.path} '
            '${request.headers.contentType?.mimeType} '
            '${request.headers.value('x-api-key')} '
            '${body.length >= 8 && _startsWithPng(body)}');
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(status == 200
            ? fixture()
            : jsonEncode({'detail': 'Missing or wrong API key'}));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri base() => Uri.parse('http://127.0.0.1:${server.port}');

    test('sends a PNG and reads the masks back', () async {
      final finder = BackendSurfaceFinder(base(), apiKey: 'k1');
      final result = await finder.find(GrayImage.filled(480, 360, 90));

      expect(result.masks.length, 3);
      expect(seen, ['POST /v1/segment image/png k1 true']);
    });

    test('a path prefix in the URL is kept', () async {
      final finder = BackendSurfaceFinder(base().replace(path: '/promap'));
      try {
        await finder.find(GrayImage.filled(480, 360, 90));
      } on SurfaceFinderException {
        // The test server answers any path; only the path matters here.
      }
      expect(seen.single, startsWith('POST /promap/v1/segment '));
    });

    test('an error status becomes a readable message', () async {
      status = 401;
      final finder = BackendSurfaceFinder(base());
      await expectLater(
        finder.find(GrayImage.filled(480, 360, 90)),
        throwsA(isA<SurfaceFinderException>().having(
            (e) => e.message, 'message', contains('Missing or wrong API key'))),
      );
    });

    test('a backend that is not running gives a clear message', () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);

      final finder = BackendSurfaceFinder(Uri.parse('http://127.0.0.1:$port'),
          timeout: const Duration(seconds: 5));
      await expectLater(
        finder.find(GrayImage.filled(48, 36, 90)),
        throwsA(isA<SurfaceFinderException>()
            .having((e) => e.message, 'message', contains('Cannot reach'))),
      );
    });
  });

  test('without a backend setting the demo shapes are used', () async {
    final finder = SurfaceFinder.fromEnvironment();
    expect(finder, isA<DemoSurfaceFinder>());
    final result = await finder.find(GrayImage(480, 360));
    expect(result.masks.first.mask.count, 80 * 80);
  });
}

bool _startsWithPng(List<int> body) {
  for (var i = 0; i < pngSignature.length; i++) {
    if (body[i] != pngSignature[i]) return false;
  }
  return true;
}
