#!/usr/bin/env python3
"""アンビエント・クラウド： Phase 2（グラニュラー再設計＋シマー＋テープ）のデモ／検証曲。

80 BPM・12小節。FB Pad Air の持続パッドで Cmaj9 → Am9 → Fmaj9 → G6 → Cmaj9 → Am9
（各2小節、隙間なし）。チェーンは fxChain で明示する：
  wet          : グラニュラー（Ambient Cloud）→ ディレイ（4分）→ リバーブ
  dry          : 同じチェーンを全ユニット無効化（比較用の素のパッド）
  shimmer-tape : テープ → シマーリバーブ

使い方:
  python3 tools/demos/ambient_cloud.py            # app/assets/demos/ambient_cloud.json（wet）
  python3 tools/demos/ambient_cloud.py --variants # /tmp に dry / shimmer-tape も出す
レンダリング: mdaw_render <json> <wav> で wav 化し、ffmpeg で mp3 にする。
"""
import json
import sys

PPQ = 960
BAR = PPQ * 4

# FB Pad Air（app/lib/sound/sound_params.dart）のシンセ側パラメータ
PAD = {
    'wtTable': 5, 'wtPos': 0.3, 'noise': 0.015,
    'unison': 12, 'detuneCents': 30, 'width': 1.0, 'blend': 0.75,
    'lfoSync': 1, 'lfoDiv': 0, 'lfoWave': 0, 'lfoCutoff': 0.1, 'wtLfoAmount': 0.18,
    'cutoffHz': 5200, 'resonance': 0.8, 'keyTrack': 0.45,
    'attackS': 0.6, 'decayS': 1.2, 'sustain': 0.85, 'releaseS': 1.8, 'masterGain': 0.30,
}

CHORDS = [
    [48, 52, 55, 59, 62],  # Cmaj9
    [45, 48, 52, 55, 59],  # Am9
    [41, 45, 48, 52, 55],  # Fmaj9
    [43, 47, 50, 52, 55],  # G6
    [48, 52, 55, 59, 62],  # Cmaj9
    [45, 48, 52, 55, 59],  # Am9
]

GRANULAR_CLOUD = {
    'granular': 0.85, 'granularSizeMs': 240, 'granularDensity': 55,
    'granularPositionS': 1.2, 'granularSpray': 0.6, 'granularPitch': 0,
    'granularPitchSpread': 0.4, 'granularTexture': 0.85,
    'granularTimingRandom': 0.7, 'granularSizeRandom': 0.5,
    'granularReverseChance': 0.15, 'granularFeedback': 0.55,
    'granularRoam': 0.4, 'granularRoamSpeed': 0.07, 'granularFreeze': 0,
}
WET_CHAIN = [
    {'type': 'granular', 'enabled': True, 'params': GRANULAR_CLOUD},
    {'type': 'delay', 'enabled': True,
     'params': {'delay': 0.25, 'delayFeedback': 0.45, 'delayDiv': 0, 'delayPingpong': 0}},
    {'type': 'reverb', 'enabled': True, 'params': {'reverb': 0.55, 'reverbSize': 0.85}},
]
SHIMMER_TAPE_CHAIN = [
    {'type': 'tape', 'enabled': True,
     'params': {'tape': 0.5, 'tapeWow': 0.5, 'tapeSat': 0.35, 'tapeHiss': 0.15}},
    {'type': 'shimmer', 'enabled': True,
     'params': {'shimmer': 0.6, 'shimmerSize': 0.8, 'shimmerAmount': 0.6, 'shimmerTone': 0.65}},
]


def build(chain, enable=True):
    notes = []
    nid = 0x10
    for ci, chord in enumerate(CHORDS):
        for pitch in chord:
            notes.append({
                'id': f'{nid:016x}', 'tick': ci * 2 * BAR,
                'length': 2 * BAR - 40, 'pitch': pitch, 'velocity': 0.6,
            })
            nid += 1
    units = [dict(u, enabled=(u['enabled'] and enable)) for u in chain]
    return {
        'format': 'mobiledaw-project',
        'version': 1,
        'title': 'デモ：アンビエント・クラウド',
        'tempo': 80.0,
        'timeSig': [4, 4],
        'key': {'root': 0, 'scale': 'major'},
        'master': {'gain': 1.2, 'glue': 0.3, 'thresholdDb': -15, 'ratio': 2.0,
                   'softClip': 0.4, 'ceiling': 0.93},
        'aux': {'reverbReturn': 1.0, 'reverbSize': 0.7, 'delayReturn': 0.5, 'delayFeedback': 0.4},
        'tracks': [{
            'id': '0000000000000001',
            'name': 'Cloud Pad',
            'color': 'ff7e57c2',
            'instrument': {'type': 'synth', 'params': PAD},
            'fx': {},
            'fxChain': units,
            'mixer': {'gain': 0.9, 'pan': 0, 'mute': False, 'solo': False},
        }],
        'clips': [{
            'id': '0000000000000002', 'trackId': '0000000000000001',
            'lengthTicks': len(CHORDS) * 2 * BAR, 'notes': notes,
        }],
        'placements': [{
            'id': '0000000000000003', 'clipId': '0000000000000002',
            'trackId': '0000000000000001', 'startBar': 0, 'lengthBars': len(CHORDS) * 2,
        }],
    }


def main():
    wet = build(WET_CHAIN)
    with open('app/assets/demos/ambient_cloud.json', 'w') as f:
        json.dump(wet, f, ensure_ascii=False, indent=1)
    print('app/assets/demos/ambient_cloud.json')
    if '--variants' in sys.argv:
        with open('/tmp/ambient-wet.json', 'w') as f:
            json.dump(wet, f, ensure_ascii=False)
        with open('/tmp/ambient-dry.json', 'w') as f:
            json.dump(build(WET_CHAIN, enable=False), f, ensure_ascii=False)
        with open('/tmp/ambient-shimmer-tape.json', 'w') as f:
            json.dump(build(SHIMMER_TAPE_CHAIN), f, ensure_ascii=False)
        print('/tmp/ambient-{wet,dry,shimmer-tape}.json')


if __name__ == '__main__':
    main()
