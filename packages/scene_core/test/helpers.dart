import 'dart:convert';
import 'dart:io';

import 'package:scene_core/scene_core.dart';
import 'package:test/test.dart';

final throwsSceneError = throwsA(isA<SceneError>());

String fixtureText(String name) =>
    File('test/fixtures/$name').readAsStringSync();

Object? fixtureJson(String name) => jsonDecode(fixtureText(name));

Scene sampleScene() => Scene.decode(fixtureText('sample_scene.json'));

Surface square(String id, {double left = 0, double top = 0, double size = 10}) =>
    Surface(
      id: id,
      name: 'Square $id',
      vertices: [
        Vec2(left, top),
        Vec2(left + size, top),
        Vec2(left + size, top + size),
        Vec2(left, top + size),
      ],
    );
