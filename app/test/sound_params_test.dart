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
  test('bundled demos use known parameter names', () {
    final dir = Directory('assets/demos');
    expect(dir.existsSync(), isTrue);
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files.length, greaterThanOrEqualTo(9));
    for (final f in files) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      final tracks = (j['tracks']! as List<Object?>).cast<Map<String, Object?>>();
      expect(tracks, isNotEmpty, reason: f.path);
      for (final t in tracks) {
        final params = ((t['instrument']! as Map<String, Object?>)['params']! as Map<String, Object?>).keys;
        final fx = (t['fx']! as Map<String, Object?>).keys;
        for (final k in [...params, ...fx]) {
          expect(keys, contains(k), reason: '${f.path} ${t['name']}: $k');
        }
      }
    }
  });

  // エンジン拡張（キートラッキング／グライド／モノ／LFO拡張）：既定値は全て「従来挙動」
  test('engine expansion params exist with legacy defaults', () {
    final byKey = {for (final p in allSoundParams) p.key: p};
    for (final (key, def) in [
      ('keyTrack', 0.0),
      ('glideS', 0.0),
      ('mono', 0.0),
      ('lfoWave', 0.0),
      ('lfoSync', 0.0),
      ('lfoDiv', 1.0),
      ('lfoCutoff', 0.0),
      ('lfoPitch', 0.0),
    ]) {
      expect(byKey, contains(key));
      expect(byKey[key]!.def, def, reason: key);
    }
    // コア（mdaw.h）と番号がずれていないこと：FX は 40 番台に移っている
    expect(byKey['lowCutHz']!.id, 40);
    expect(byKey['sidechainSource']!.id, 50);
    expect(byKey['lfoPitch']!.id, 33);
    // ミックス拡張は既定で素通し（古い曲の音は変わらない）
    for (final (key, def) in [
      ('eqLowDb', 0.0),
      ('eqMidDb', 0.0),
      ('eqHighDb', 0.0),
      ('comp', 0.0),
      ('sendReverb', 0.0),
      ('sendDelay', 0.0),
      ('bitcrush', 0.0),
      ('stutter', 0.0),
    ]) {
      expect(byKey[key]!.def, def, reason: key);
    }
    // 音色画面の節分けに新しい節が入っている
    expect(filterParams.map((p) => p.key), contains('keyTrack'));
    expect(playParams.map((p) => p.key), ['glideS', 'mono']);
    expect(lfoParams.map((p) => p.key), ['lfoWave', 'lfoSync', 'lfoDiv', 'lfoCutoff', 'lfoPitch']);
  });

  // 本格フューチャーベース・プリセット：エンジン拡張パラメータの使い方が設計どおりか
  test('future bass pro presets use the engine expansion as designed', () {
    final byName = {for (final p in soundPresets) p.name: p};
    double v(String preset, String key) => byName[preset]!.values[key] ?? 0;

    for (final name in [
      'FB Chords 9th', 'FB Vocal Lead', 'FB Wobble Bass', 'FB Reese Bass', 'FB Pluck',
      'FB Pad Air', 'FB Sparkle Arp', 'FB Talking Lead', 'FB Sub Clean',
    ]) {
      expect(byName, contains(name), reason: name);
    }

    // コード主力： 9声、OTT は定番の 20〜30% 帯、キートラッキング中量
    expect(v('FB Chords 9th', 'unison'), 9);
    expect(v('FB Chords 9th', 'ott'), inInclusiveRange(0.2, 0.3));
    expect(v('FB Chords 9th', 'keyTrack'), inInclusiveRange(0.5, 0.7));

    // ボーカルリード： モノ＋グライド 80〜120ms、スクープ +12 半音、ビブラート小量
    expect(v('FB Vocal Lead', 'mono'), 1);
    expect(v('FB Vocal Lead', 'glideS'), inInclusiveRange(0.08, 0.12));
    expect(v('FB Vocal Lead', 'pitchEnv'), 12);
    expect(v('FB Vocal Lead', 'lfoPitch'), inInclusiveRange(0.1, 0.3));

    // ワブル： 付点8分（lfoDiv=2）に同期し、カットオフを大きく揺らす
    expect(v('FB Wobble Bass', 'lfoSync'), 1);
    expect(v('FB Wobble Bass', 'lfoDiv'), 2);
    expect(v('FB Wobble Bass', 'lfoCutoff'), greaterThanOrEqualTo(0.5));

    // リース： 1小節同期の微量ドリフト、サブは別建て（サイン加算）
    expect(v('FB Reese Bass', 'lfoSync'), 1);
    expect(v('FB Reese Bass', 'lfoDiv'), 0);
    expect(v('FB Reese Bass', 'lfoCutoff'), inInclusiveRange(0.05, 0.2));
    expect(v('FB Reese Bass', 'sub'), greaterThan(0));

    // サブ専用： オシレーター無し・サインのみ・モノ
    expect(v('FB Sub Clean', 'osc'), 0);
    expect(v('FB Sub Clean', 'sub'), 1);
    expect(v('FB Sub Clean', 'mono'), 1);

    // 喋るリードは wtPos の動き主体（ビブラートに頼らない）
    expect(v('FB Talking Lead', 'wtLfoAmount'), greaterThanOrEqualTo(0.5));
    expect(v('FB Talking Lead', 'lfoPitch'), 0);
  });

  test('format', () {
    final cutoff = allSoundParams.firstWhere((p) => p.key == 'cutoffHz');
    expect(cutoff.format(12000), '12.0 kHz');
    expect(cutoff.format(440), '440 Hz');
    final attack = allSoundParams.firstWhere((p) => p.key == 'attackS');
    expect(attack.format(0.005), '5 ms');
  });
}
