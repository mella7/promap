import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promap_app/cloud/assistant_client.dart';
import 'package:promap_app/workbench.dart';
import 'package:scene_core/scene_core.dart';

String fixture() =>
    File('test/fixtures/assistant_response.json').readAsStringSync();

/// Makes every wall sparkle, whatever was asked.
class _WallsSparkle implements SceneAssistant {
  final prompts = <String>[];

  @override
  String get description => 'test assistant';

  @override
  Future<AssistantReply> ask(Scene scene, String prompt) async {
    prompts.add(prompt);
    return AssistantReply('test', 'Walls sparkle.', [
      for (final s in scene.surfaces)
        if (s.label == 'wall')
          SetContent(s.id, EffectContent('sparkles')),
    ]);
  }
}

class _Failing implements SceneAssistant {
  @override
  String get description => 'failing assistant';

  @override
  Future<AssistantReply> ask(Scene scene, String prompt) async =>
      throw const AssistantException('Backend down');
}

/// Answers with an op for a surface that isn't there.
class _Stale implements SceneAssistant {
  @override
  String get description => 'stale assistant';

  @override
  Future<AssistantReply> ask(Scene scene, String prompt) async =>
      const AssistantReply('test', 'ok', [SetOpacity('gone', 0.5)]);
}

void main() {
  test('a recorded backend reply reads into ops', () {
    final reply = parseAssistantResponse(fixture());
    expect(reply.model, 'rules');
    expect(reply.message, contains('sparkles'));
    expect(reply.ops.length, 4);
    final first = reply.ops.first as SetContent;
    expect(first.surface, 's2');
    expect((first.content as EffectContent).effect, 'sparkles');
    expect(reply.ops.last, isA<SetOpacity>());
  });

  test('a broken reply gives a readable error', () {
    expect(
      () => parseAssistantResponse('{"model": "rules", "ops": [{"op": 1}]}'),
      throwsA(isA<AssistantException>()),
    );
  });

  group('backend assistant', () {
    late HttpServer server;
    late List<Map<String, dynamic>> seen;
    late List<String> headers;

    setUp(() async {
      seen = [];
      headers = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        seen.add(jsonDecode(body) as Map<String, dynamic>);
        headers.add('${request.method} ${request.uri.path} '
            '${request.headers.contentType?.mimeType} '
            '${request.headers.value('x-api-key')}');
        request.response.headers.contentType = ContentType.json;
        request.response.write(fixture());
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('sends the scene and the prompt as JSON', () async {
      final assistant = BackendAssistant(
          Uri.parse('http://127.0.0.1:${server.port}'),
          apiKey: 'k1');
      final scene = Scene(projectorWidth: 320, projectorHeight: 240);
      final reply = await assistant.ask(scene, 'make the walls sparkle');

      expect(reply.ops, isNotEmpty);
      expect(headers, ['POST /v1/assistant application/json k1']);
      expect(seen.single['prompt'], 'make the walls sparkle');
      expect(seen.single['scene'], scene.toJson());
    });
  });

  test('without a backend setting there is no assistant', () {
    expect(SceneAssistant.fromEnvironment(), isNull);
    expect(Workbench(settle: Duration.zero).assistant, isNull);
  });

  group('workbench', () {
    Future<Workbench> ready(SceneAssistant assistant) async {
      final bench = Workbench(settle: Duration.zero, assistant: assistant);
      await bench.startScan();
      await bench.findSurfaces();
      return bench;
    }

    test('applies the reply as one undo step', () async {
      final assistant = _WallsSparkle();
      final bench = await ready(assistant);
      await bench.askAssistant('  make the walls sparkle  ');

      expect(assistant.prompts, ['make the walls sparkle']);
      expect(bench.status, 'Walls sparkle.');
      expect(bench.store.history.last, 'Assistant: make the walls sparkle');
      final walls = [
        for (final s in bench.store.scene.surfaces)
          if (s.label == 'wall') s.content,
      ];
      expect(walls, everyElement(EffectContent('sparkles')));

      bench.undo();
      expect(bench.store.history.last, 'Find surfaces');
    });

    test('an empty prompt does nothing', () async {
      final assistant = _WallsSparkle();
      final bench = await ready(assistant);
      await bench.askAssistant('   ');
      expect(assistant.prompts, isEmpty);
    });

    test('a failing backend shows its message and changes nothing', () async {
      final bench = await ready(_Failing());
      await bench.askAssistant('sparkle');
      expect(bench.status, 'Backend down');
      expect(bench.store.history, ['Find surfaces']);
      expect(bench.busy, isFalse);
    });

    test('ops for a surface that is gone change nothing', () async {
      final bench = await ready(_Stale());
      await bench.askAssistant('dim it');
      expect(bench.status, contains('no longer fit'));
      expect(bench.store.history, ['Find surfaces']);
    });
  });
}
