import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/sound/sound_params.dart';

void main() {
  final keys = {for (final p in allSoundParams) p.key};

  test('preset keys exist and values are in range', () {
    for (final preset in soundPresets) {
      for (final e in preset.values.entries) {
        expect(keys, contains(e.key), reason: '${preset.name}: ${e.key}');
        final p = allSoundParams.firstWhere((p) => p.key == e.key);
        expect(e.value, inInclusiveRange(p.min, p.max), reason: '${preset.name}: ${e.key}');
      }
      expect(preset.allValues.length, allSoundParams.length);
    }
  });

  test('slider position round-trips', () {
    for (final p in allSoundParams) {
      for (final u in [0.0, 0.25, 0.5, 1.0]) {
        final v = p.fromUnit(u);
        expect(v, inInclusiveRange(p.min, p.max), reason: p.key);
        if (p.scale == ParamScale.linear || p.scale == ParamScale.log) {
          expect(p.toUnit(v), closeTo(u, 1e-9), reason: p.key);
        }
      }
      expect(p.def, inInclusiveRange(p.min, p.max), reason: p.key);
    }
  });

  test('ids are unique', () {
    expect({for (final p in allSoundParams) p.id}.length, allSoundParams.length);
  });

  // 同梱のデモ曲が、表にある名前だけを使っている（コアの保存名と食い違っていない）
  test('bundled demo uses known parameter names', () {
    final j = jsonDecode(File('assets/demos/future_bass.json').readAsStringSync()) as Map<String, Object?>;
    final tracks = (j['tracks']! as List<Object?>).cast<Map<String, Object?>>();
    expect(tracks.length, 8);
    for (final t in tracks) {
      final params = ((t['instrument']! as Map<String, Object?>)['params']! as Map<String, Object?>).keys;
      final fx = (t['fx']! as Map<String, Object?>).keys;
      for (final k in [...params, ...fx]) {
        expect(keys, contains(k), reason: '${t['name']}: $k');
      }
    }
  });

  test('format', () {
    final cutoff = allSoundParams.firstWhere((p) => p.key == 'cutoffHz');
    expect(cutoff.format(12000), '12.0 kHz');
    expect(cutoff.format(440), '440 Hz');
    final attack = allSoundParams.firstWhere((p) => p.key == 'attackS');
    expect(attack.format(0.005), '5 ms');
  });
}
