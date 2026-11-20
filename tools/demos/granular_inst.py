#!/usr/bin/env python3
"""グラニュラー楽器（Phase 2.5）の検証デモ生成。

2 つのプロジェクトを出す:
  source.json   : FB Pad Air のコードフレーズ（Cmaj9→Am9→Fmaj9→G6、各2小節、
                  80 BPM・8小節=24秒）。これをレンダーした WAV がバウンス素材になる
  granular.json : その素材をサンプラー（キット bounce-demo / 音 "Phrase"）で受け、
                  グラニュラーモードでゆっくりしたコードメロディを鳴らす曲（12小節）

使い方:
  python3 tools/demos/granular_inst.py [出力フォルダ]
  # 出力フォルダ（既定 ~/workspace/mobiledaw-pending/task35/granular-demo）に
  # source.json / granular.json / kit.json の雛形を書く。レンダー手順は
  # PHASE25-HANDOFF.md を参照。
アプリのデモ曲としては登録しない（素材キットがダウンロード式でないため）。
"""
import json
import os
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

SOURCE_CHORDS = [
    [48, 52, 55, 59, 62],  # Cmaj9
    [45, 48, 52, 55, 59],  # Am9
    [41, 45, 48, 52, 55],  # Fmaj9
    [43, 47, 50, 52, 55],  # G6
]

# メロディ側のコード（ルート音）。素材の進行と揃えてある
MELODY_ROOTS = [48, 45, 41, 43, 48, 45]

GRANULAR = {
    'enabled': 1, 'sizeMs': 240, 'density': 50, 'position': 0,
    'spray': 0.6, 'texture': 0.85, 'pitchSpread': 0.4,
    'timingRandom': 0.7, 'sizeRandom': 0.5, 'reverseChance': 0.1,
    'positionMode': 0, 'roam': 0.3, 'roamSpeed': 0.07,
    'feedback': 0.45, 'freeze': 0, 'pitchQuantize': 1, 'pitchDrift': 1.5,
}

MASTER = {'gain': 1.2, 'glue': 0.3, 'thresholdDb': -15, 'ratio': 2.0,
          'softClip': 0.4, 'ceiling': 0.93}
AUX = {'reverbReturn': 1.0, 'reverbSize': 0.7, 'delayReturn': 0.5, 'delayFeedback': 0.4}


def project(title, track, notes, bars):
    return {
        'format': 'mobiledaw-project', 'version': 1, 'title': title,
        'tempo': 80.0, 'timeSig': [4, 4], 'key': {'root': 0, 'scale': 'major'},
        'master': MASTER, 'aux': AUX,
        'tracks': [track],
        'clips': [{
            'id': '0000000000000002', 'trackId': '0000000000000001',
            'lengthTicks': bars * BAR, 'notes': notes,
        }],
        'placements': [{
            'id': '0000000000000003', 'clipId': '0000000000000002',
            'trackId': '0000000000000001', 'startBar': 0, 'lengthBars': bars,
        }],
    }


def build_source():
    notes = []
    nid = 0x10
    for ci, chord in enumerate(SOURCE_CHORDS):
        for pitch in chord:
            notes.append({'id': f'{nid:016x}', 'tick': ci * 2 * BAR,
                          'length': 2 * BAR - 40, 'pitch': pitch, 'velocity': 0.6})
            nid += 1
    track = {
        'id': '0000000000000001', 'name': 'Pad Phrase', 'color': 'ff7e57c2',
        'instrument': {'type': 'synth', 'params': PAD},
        'fx': {}, 'fxChain': [],
        'mixer': {'gain': 0.9, 'pan': 0, 'mute': False, 'solo': False},
    }
    return project('検証：バウンス素材', track, notes, 8)


def build_granular():
    notes = []
    nid = 0x10
    for ci, root in enumerate(MELODY_ROOTS):
        notes.append({'id': f'{nid:016x}', 'tick': ci * 2 * BAR,
                      'length': 2 * BAR - 40, 'pitch': root, 'velocity': 0.85})
        nid += 1
        # 2 小節目の頭にオクターブ上を静かに重ねる
        notes.append({'id': f'{nid:016x}', 'tick': (ci * 2 + 1) * BAR,
                      'length': BAR - 40, 'pitch': root + 12, 'velocity': 0.45})
        nid += 1
    track = {
        'id': '0000000000000001', 'name': 'Granular Cloud', 'color': 'ff4fc3f7',
        'instrument': {
            'type': 'sampler',
            'sampler': {'kit': 'bounce-demo', 'sound': 'Phrase', 'rootNote': 60,
                        'gain': 1.0, 'start': 0.0, 'granular': GRANULAR},
            'params': {},
        },
        'fx': {},
        'fxChain': [
            {'type': 'reverb', 'enabled': True,
             'params': {'reverb': 0.35, 'reverbSize': 0.8}},
        ],
        'mixer': {'gain': 1.0, 'pan': 0, 'mute': False, 'solo': False},
    }
    return project('検証：グラニュラー楽器', track, notes, 12)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        '~/workspace/mobiledaw-pending/task35/granular-demo')
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'source.json'), 'w') as f:
        json.dump(build_source(), f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, 'granular.json'), 'w') as f:
        json.dump(build_granular(), f, ensure_ascii=False, indent=1)
    with open(os.path.join(out, 'kit.json'), 'w') as f:
        json.dump({'name': 'Bounce Demo', 'version': 1, 'sounds': [
            {'name': 'Phrase', 'file': 'phrase.wav', 'note': 60, 'gain': 1.0},
        ]}, f, ensure_ascii=False, indent=1)
    print(out)


if __name__ == '__main__':
    main()
