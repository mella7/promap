import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scene_core/scene_core.dart';

import 'surface_finder.dart' show backendErrorDetail;

/// What the assistant answered: ops to apply as one undo step, and a line
/// to show the user.
class AssistantReply {
  final String model;
  final String message;
  final List<SceneOp> ops;

  const AssistantReply(this.model, this.message, this.ops);
}

/// Something went wrong asking the assistant. [message] can be shown as is.
class AssistantException implements Exception {
  final String message;

  const AssistantException(this.message);

  @override
  String toString() => message;
}

/// Turns a typed request ("make the walls sparkle") into scene ops.
abstract interface class SceneAssistant {
  /// Shown in the app, for example "backend at http://127.0.0.1:8000".
  String get description;

  Future<AssistantReply> ask(Scene scene, String prompt);

  /// The backend's assistant when the app was started with
  /// `--dart-define=PROMAP_BACKEND=<url>`, otherwise none: the assistant
  /// only runs in the cloud.
  static SceneAssistant? fromEnvironment() {
    const url = String.fromEnvironment('PROMAP_BACKEND');
    const key = String.fromEnvironment('PROMAP_API_KEY');
    if (url.isEmpty) return null;
    return BackendAssistant(Uri.parse(url), apiKey: key.isEmpty ? null : key);
  }
}

/// Sends the scene and the request to the backend's /v1/assistant.
class BackendAssistant implements SceneAssistant {
  final Uri baseUrl;

  /// Sent as X-API-Key when the backend requires one.
  final String? apiKey;

  final Duration timeout;

  const BackendAssistant(this.baseUrl,
      {this.apiKey, this.timeout = const Duration(seconds: 60)});

  @override
  String get description => 'backend at $baseUrl';

  Uri get _url {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return base.resolve('v1/assistant');
  }

  @override
  Future<AssistantReply> ask(Scene scene, String prompt) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(_url).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final key = apiKey;
      if (key != null) request.headers.set('x-api-key', key);
      final body =
          utf8.encode(jsonEncode({'scene': scene.toJson(), 'prompt': prompt}));
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(timeout);
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode != 200) {
        throw AssistantException(
            'The assistant answered ${response.statusCode}: '
            '${backendErrorDetail(text)}');
      }
      return parseAssistantResponse(text);
    } on SocketException catch (error) {
      throw AssistantException(
          'Cannot reach the backend at $baseUrl (${error.message}). '
          'Is it running?');
    } on TimeoutException {
      throw AssistantException('The backend at $baseUrl did not answer within '
          '${timeout.inSeconds} seconds.');
    } finally {
      client.close(force: true);
    }
  }
}

/// Reads a /v1/assistant reply.
AssistantReply parseAssistantResponse(String text) {
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return AssistantReply(
      json['model'] as String,
      json['message'] as String,
      opsFromJson(json['ops']),
    );
  } on Object catch (error) {
    throw AssistantException(
        'The assistant sent a reply the app cannot read ($error).');
  }
}
