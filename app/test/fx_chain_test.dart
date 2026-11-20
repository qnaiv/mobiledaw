import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/engine/mdaw_ffi.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/sound/sound_params.dart';

// Phase 1（FX チェーン）の Dart 側: モデルの読み込みとユニット表の整合を見る。
// コアの projectToJson が書く形（fx はトラック直属だけ、チェーン項目は fxChain 側）
const _jsonWithChain = '''
{
  "format": "mobiledaw-project",
  "version": 1,
  "tempo": 120.0,
  "timeSig": [4, 4],
  "key": {"root": 0, "scale": "minor"},
  "tracks": [
    {
      "id": "0000000000000001",
      "name": "Pad",
      "color": "ffc8f25a",
      "instrument": {"type": "synth", "params": {}},
      "fx": {"sidechain": 0.5, "sendReverb": 0.3},
      "fxChain": [
        {"type": "reverb", "enabled": true, "params": {"reverb": 0.4, "reverbSize": 0.7}},
        {"type": "granular", "enabled": false, "params": {"granular": 0.6, "granularFreeze": 1.0}},
        {"type": "granular", "enabled": true, "params": {"granular": 0.2}}
      ],
      "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
    }
  ],
  "clips": [],
  "placements": []
}
''';

// 旧形式（fxChain 無し・フラット fx）
const _jsonLegacy = '''
{
  "format": "mobiledaw-project",
  "version": 1,
  "tempo": 120.0,
  "timeSig": [4, 4],
  "key": {"root": 0, "scale": "minor"},
  "tracks": [
    {
      "id": "0000000000000001",
      "name": "Pad",
      "color": "ffc8f25a",
      "instrument": {"type": "synth", "params": {}},
      "fx": {"reverb": 0.4, "sidechain": 0.5, "granular": 0.7},
      "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
    }
  ],
  "clips": [],
  "placements": []
}
''';

void main() {
  test('fxChain is parsed in order with enabled and params', () {
    final t = ProjectData.parse(_jsonWithChain).tracks.single;
    expect(t.fxChain.length, 3);
    expect(t.fxChain[0].type, 'reverb');
    expect(t.fxChain[0].enabled, isTrue);
    expect(t.fxChain[0].params['reverb'], 0.4);
    expect(t.fxChain[1].type, 'granular');
    expect(t.fxChain[1].enabled, isFalse);
    expect(t.fxChain[2].type, 'granular'); // 同じ種別が複数あってもよい
  });

  test('flat fx view merges track-level keys and first-unit values', () {
    final t = ProjectData.parse(_jsonWithChain).tracks.single;
    expect(t.fx['sidechain'], 0.5); // トラック直属は fx から
    expect(t.fx['sendReverb'], 0.3);
    expect(t.fx['reverb'], 0.4); // チェーン項目は最初のユニットから
    expect(t.fx['reverbSize'], 0.7);
    expect(t.fx['granular'], 0.6); // 2個目のグラニュラー（0.2）ではなく最初のもの
    expect(t.fx['granularFreeze'], 1.0);
  });

  test('legacy project without fxChain keeps the flat fx as-is', () {
    final t = ProjectData.parse(_jsonLegacy).tracks.single;
    expect(t.fxChain, isEmpty);
    expect(t.fx['reverb'], 0.4);
    expect(t.fx['granular'], 0.7);
    expect(t.fx['sidechain'], 0.5);
  });

  test('unit meta covers every type in core order', () {
    expect(
      fxUnitMetas.map((m) => m.type).toList(),
      [
        'lowcut', 'eq', 'saturation', 'chorus', 'comp', 'ott', 'bitcrush', 'stutter', 'granular', 'delay', 'reverb',
        'shimmer', 'tape',
      ],
    );
    for (final m in fxUnitMetas) {
      expect(m.name, isNotEmpty, reason: m.type);
      expect(m.paramKeys, isNotEmpty, reason: m.type);
      expect(fxUnitTypeIndex(m.type), fxUnitMetas.indexOf(m), reason: m.type);
      expect(fxUnitMetaOf(m.type), same(m));
    }
    expect(fxUnitMetaOf('no-such-unit'), isNull);
    expect(kMaxFxUnits, 16);
  });

  test('every fx param is owned by exactly one unit or is track-level', () {
    final owned = <String, int>{};
    for (final m in fxUnitMetas) {
      for (final k in m.paramKeys) {
        owned[k] = (owned[k] ?? 0) + 1;
      }
    }
    final trackLevel = trackLevelFxParams.map((p) => p.key).toSet();
    for (final p in fxParams) {
      final inUnit = owned[p.key] ?? 0;
      final inTrack = trackLevel.contains(p.key) ? 1 : 0;
      expect(inUnit + inTrack, 1, reason: '${p.key} はユニットかトラック直属のどちらか1つ');
    }
    // ユニット表のキーはすべて実在するパラメータ
    final keys = {for (final p in allSoundParams) p.key};
    for (final k in owned.keys) {
      expect(keys, contains(k), reason: k);
    }
  });

  test('granular freeze and feedback params match the core ids and defaults', () {
    final byKey = {for (final p in allSoundParams) p.key: p};
    final freeze = byKey['granularFreeze']!;
    expect(freeze.id, MdawParam.fxGranularFreeze);
    expect(freeze.id, 87);
    expect(freeze.scale, ParamScale.toggle);
    expect(freeze.def, 0);
    final feedback = byKey['granularFeedback']!;
    expect(feedback.id, MdawParam.fxGranularFeedback);
    expect(feedback.id, 88);
    expect(feedback.min, 0);
    expect(feedback.max, 0.9);
    expect(feedback.def, 0.25);
    // グラニュラーの詳細に出る
    final granular = fxUnitMetaOf('granular')!;
    expect(granular.paramKeys, containsAll(['granularFreeze', 'granularFeedback']));
    // フラットな valueOf でも読める（互換ビューのキー）
    expect(freeze.isFx, isTrue);
    expect(feedback.isFx, isTrue);
  });

  test('phase 2 params match the core ids, ranges and defaults', () {
    final byKey = {for (final p in allSoundParams) p.key: p};
    void check(String key, int id, double min, double max, double def) {
      final p = byKey[key]!;
      expect(p.id, id, reason: key);
      expect(p.min, min, reason: key);
      expect(p.max, max, reason: key);
      expect(p.def, def, reason: key);
      expect(p.isFx, isTrue, reason: key);
    }

    check('granularTexture', MdawParam.fxGranularTexture, 0, 1, 0.6);
    expect(MdawParam.fxGranularTexture, 89);
    check('granularTimingRandom', MdawParam.fxGranularTimingRandom, 0, 1, 0.7);
    check('granularSizeRandom', MdawParam.fxGranularSizeRandom, 0, 1, 0.3);
    check('granularReverseChance', MdawParam.fxGranularReverseChance, 0, 1, 0);
    check('granularRoam', MdawParam.fxGranularRoam, 0, 1, 0);
    check('granularRoamSpeed', MdawParam.fxGranularRoamSpeed, 0.01, 0.5, 0.07);
    check('granularPositionS', MdawParam.fxGranularPositionS, 0, 3.9, 0.35);
    check('shimmer', MdawParam.fxShimmer, 0, 1, 0);
    expect(MdawParam.fxShimmer, 95);
    check('shimmerSize', MdawParam.fxShimmerSize, 0, 1, 0.65);
    check('shimmerAmount', MdawParam.fxShimmerAmount, 0, 1, 0.5);
    check('shimmerTone', MdawParam.fxShimmerTone, 0, 1, 0.6);
    check('tape', MdawParam.fxTape, 0, 1, 0);
    expect(MdawParam.fxTape, 99);
    check('tapeWow', MdawParam.fxTapeWow, 0, 1, 0.4);
    check('tapeSat', MdawParam.fxTapeSat, 0, 1, 0.3);
    check('tapeHiss', MdawParam.fxTapeHiss, 0, 1, 0);
    check('delayDiv', MdawParam.fxDelayDiv, 0, 4, 1);
    check('delayPingpong', MdawParam.fxDelayPingpong, 0, 1, 0);
    expect(byKey['delayDiv']!.scale, ParamScale.integer);
    expect(byKey['delayPingpong']!.scale, ParamScale.toggle);

    // 新ユニットの表示情報（名前・色は Phase 2 の指定どおり）
    final shimmer = fxUnitMetaOf('shimmer')!;
    expect(shimmer.name, 'シマーリバーブ');
    expect(shimmer.color, const Color(0xFF3B82F6));
    expect(shimmer.paramKeys, ['shimmer', 'shimmerSize', 'shimmerAmount', 'shimmerTone']);
    final tape = fxUnitMetaOf('tape')!;
    expect(tape.name, 'テープ');
    expect(tape.color, const Color(0xFFF59E0B));
    expect(tape.paramKeys, ['tape', 'tapeWow', 'tapeSat', 'tapeHiss']);
    // グラニュラーの詳細に新しい質感パラメータが出る
    expect(
      fxUnitMetaOf('granular')!.paramKeys,
      containsAll([
        'granularTexture', 'granularTimingRandom', 'granularSizeRandom',
        'granularReverseChance', 'granularRoam', 'granularRoamSpeed',
      ]),
    );
    // ディレイの詳細に長さとピンポンが出る
    expect(fxUnitMetaOf('delay')!.paramKeys, containsAll(['delayDiv', 'delayPingpong']));
  });
}
