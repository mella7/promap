// schema/effects.json is the backend's copy of this library: its assistant
// picks effects and settings from it. This test keeps the two the same.
import 'dart:convert';
import 'dart:io';

import 'package:effects/effects.dart';
import 'package:test/test.dart';

void main() {
  final json = jsonDecode(File('../../schema/effects.json').readAsStringSync())
      as Map<String, dynamic>;

  test('effects match, in order, with the same settings', () {
    final effects = (json['effects'] as List).cast<Map<String, dynamic>>();
    expect(effects.map((e) => e['id']), effectLibrary.map((e) => e.id));
    for (final (index, spec) in effectLibrary.indexed) {
      final e = effects[index];
      expect(e['name'], spec.name, reason: spec.id);
      expect(e['description'], spec.description, reason: spec.id);
      final params = (e['params'] as List).cast<Map<String, dynamic>>();
      expect(params.map((p) => p['key']), spec.params.map((p) => p.key),
          reason: spec.id);
      for (final (i, p) in spec.params.indexed) {
        final j = params[i];
        final where = '${spec.id}.${p.key}';
        expect(j['label'], p.label, reason: where);
        expect(j['kind'], p.kind.name, reason: where);
        expect(j['default'], p.defaultValue, reason: where);
        if (p.kind == ParamKind.number) {
          expect(j['min'], p.min, reason: where);
          expect(j['max'], p.max, reason: where);
        }
      }
    }
  });

  test('themes match', () {
    final raw = (json['themes'] as List).cast<Map<String, dynamic>>();
    expect(raw.map((t) => t['id']), themes.map((t) => t.id));
    for (final (index, theme) in themes.indexed) {
      final t = raw[index];
      expect(t['name'], theme.name);
      for (final role in SurfaceRole.values) {
        final choices = (t[role.name] as List).cast<Map<String, dynamic>>();
        final ours = theme.choicesFor(role);
        expect(choices.length, ours.length, reason: '${theme.id} ${role.name}');
        for (final (i, choice) in ours.indexed) {
          expect(choices[i]['effect'], choice.effect);
          expect(choices[i]['params'], choice.params);
        }
      }
    }
  });

  test('roles use the same rule', () {
    expect((json['backgroundLabels'] as List).toSet(), backgroundLabels);
    expect(json['backgroundAreaShare'], backgroundAreaShare);
  });
}
