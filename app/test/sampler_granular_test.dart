import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/engine/mdaw_ffi.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/sound/sound_params.dart';

// Phase 2.5（グラニュラー楽器）の Dart 側: sampler.granular の読み込みと
// パラメータ表（コアの kGranularSamplerParamSpecs との整合）を見る。
TrackData _trackOf(String json) {
  final p = ProjectData.fromJson(jsonDecode(json) as Map<String, Object?>);
  return p.tracks.single;
}

const _withGranular = '''
{
  "format": "mobiledaw-project", "version": 1, "tempo": 80.0,
  "timeSig": [4, 4], "key": {"root": 0, "scale": "major"},
  "tracks": [
    {
      "id": "0000000000000001", "name": "Cloud", "color": "ffc8f25a",
      "instrument": {
        "type": "sampler",
        "sampler": {
          "kit": "bounce-demo", "sound": "Phrase", "rootNote": 60, "gain": 1.0, "start": 0.0,
          "granular": {
            "enabled": 1.0, "sizeMs": 300.0, "density": 55.0, "position": 0.25,
            "spray": 0.6, "texture": 0.85, "pitchSpread": 0.4, "timingRandom": 0.5,
            "sizeRandom": 0.5, "reverseChance": 0.15, "positionMode": 1.0,
            "roam": 0.4, "roamSpeed": 0.1, "feedback": 0.55, "freeze": 1.0,
            "pitchQuantize": 1.0, "pitchDrift": 1.5
          }
        },
        "params": {}
      },
      "fx": {}, "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
    }
  ],
  "clips": [], "placements": []
}
''';

const _withoutGranular = '''
{
  "format": "mobiledaw-project", "version": 1, "tempo": 120.0,
  "timeSig": [4, 4], "key": {"root": 0, "scale": "minor"},
  "tracks": [
    {
      "id": "0000000000000001", "name": "Plain", "color": "ffc8f25a",
      "instrument": {
        "type": "sampler",
        "sampler": {"kit": "some-kit", "sound": "Tone", "rootNote": 60, "gain": 1.0, "start": 0.0},
        "params": {}
      },
      "fx": {}, "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
    }
  ],
  "clips": [], "placements": []
}
''';

void main() {
  test('sampler.granular を読み込む', () {
    final t = _trackOf(_withGranular);
    expect(t.isSampler, isTrue);
    expect(t.samplerGranularEnabled, isTrue);
    expect(t.samplerGranularSizeMs, 300.0);
    expect(t.samplerGranularDensity, 55.0);
    expect(t.samplerGranularPosition, 0.25);
    expect(t.samplerGranularPositionMode, 1);
    expect(t.samplerGranularFeedback, 0.55);
    expect(t.samplerGranularFreeze, isTrue);
    expect(t.samplerGranularPitchQuantize, isTrue);
    expect(t.samplerGranularPitchDrift, 1.5);
  });

  test('granular が無いサンプラーは既定値（モード OFF）', () {
    final t = _trackOf(_withoutGranular);
    expect(t.samplerGranularEnabled, isFalse);
    expect(t.samplerGranularSizeMs, 240.0);
    expect(t.samplerGranularDensity, 40.0);
    expect(t.samplerGranularTexture, 0.7);
    expect(t.samplerGranularPositionMode, 0);
    expect(t.samplerGranularFeedback, 0.3);
    expect(t.samplerGranularFreeze, isFalse);
  });

  test('パラメータ表がコアの仕様と揃っている', () {
    // ID は 105〜121 の連続帯（mdaw.h の MDAW_SAMPLER_GRANULAR_*）
    expect(MdawParam.samplerGranular, 105);
    expect(MdawParam.samplerGranularPitchDrift, 121);
    final ids = samplerGranularParams.map((p) => p.id).toSet();
    expect(ids.length, samplerGranularParams.length); // 重複なし
    for (final p in samplerGranularParams) {
      expect(p.id, greaterThan(MdawParam.samplerGranular));
      expect(p.id, lessThanOrEqualTo(MdawParam.samplerGranularPitchDrift));
      expect(p.min, lessThan(p.max));
      expect(p.def, inInclusiveRange(p.min, p.max));
    }
  });

  test('samplerGranularValueOf が TrackData の値を返す', () {
    final t = _trackOf(_withGranular);
    expect(samplerGranularValueOf(t, MdawParam.samplerGranular), 1);
    expect(samplerGranularValueOf(t, MdawParam.samplerGranularSizeMs), 300.0);
    expect(samplerGranularValueOf(t, MdawParam.samplerGranularPositionMode), 1);
    expect(samplerGranularValueOf(t, MdawParam.samplerGranularFreeze), 1);
    expect(samplerGranularValueOf(t, MdawParam.samplerGranularPitchDrift), 1.5);
  });
}
