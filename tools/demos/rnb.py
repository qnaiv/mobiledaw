#!/usr/bin/env python3
"""R&B のデモ曲（project.json）を作る。

  python3 tools/demos/rnb.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/rnb.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/rnb.json /tmp/rnb.wav   # リポジトリの直下で（kits/ を読む）

92 BPM / E♭ major / 32小節（約1分23秒）
  小節   0– 3  イントロ   パッドとキーズだけ
         4–11  Aメロ      サイドスティックのグルーヴ、跳ねるベース
        12–19  サビ       リードとライド。フィンガーシンバルのアクセント
        20–27  Aメロ2     ドラムとキーズに戻る
        28–31  アウトロ   パッドとキーズだけ。最後は E♭ で終わる
進行は通して E♭M7 → Cm9 → A♭M7 → B♭7。
R&B 専用キットは無いので、生ドラムの Acoustic Live キット（kits/acoustic-live）を使う。
サイドスティックの裏拍とライドの滑らかさがスローな R&B に一番合うため。
キックは実機のキック（36）、裏拍はサイドスティック（37）、ハットは生の閉じたハット（65）。
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16

SWING = 40  # 16分の裏をほんの少し遅らせる（tick）

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # ゆっくり開くパッド（持続コード用）
    "Pad": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=1500, resonance=0.6, attackS=0.4, decayS=1.2, sustain=0.8, releaseS=0.9,
                   detuneCents=14, masterGain=0.5, unison=4, width=0.9, blend=0.8, drive=0.03,
                   filterEnv=0.1, filterEnvDecayS=0.8, wave=0, osc=1),
        fx=dict(lowCutHz=150, saturation=0.06, chorus=0.45, ott=0.15, reverb=0.45, reverbSize=0.8),
        mixer=dict(gain=0.42, pan=0),
    ),
    # ローズ風キーズ（矩形波を絞って、頭だけ少し開く）
    "Keys": dict(
        color="ff5ad6c0",
        synth=dict(cutoffHz=1300, resonance=0.7, attackS=0.004, decayS=0.9, sustain=0.45, releaseS=0.4,
                   detuneCents=7, masterGain=0.62, unison=2, width=0.4, blend=0.95, drive=0.04,
                   filterEnv=0.3, filterEnvDecayS=0.35, wave=1, osc=1),
        fx=dict(lowCutHz=180, saturation=0.08, chorus=0.35, ott=0.2, delay=0.22, delayFeedback=0.28,
                reverb=0.38, reverbSize=0.7),
        mixer=dict(gain=0.5, pan=-0.08),
    ),
    # 滑らかなリード（レガート気味に長めの音で）
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=2800, resonance=0.8, attackS=0.03, decayS=0.6, sustain=0.75, releaseS=0.45,
                   detuneCents=6, masterGain=0.55, unison=2, width=0.3, blend=0.9, drive=0.05,
                   filterEnv=0.12, filterEnvDecayS=0.4, wave=0, osc=1),
        fx=dict(lowCutHz=250, saturation=0.1, chorus=0.2, ott=0.2, delay=0.3, delayFeedback=0.32,
                reverb=0.42, reverbSize=0.75),
        mixer=dict(gain=0.42, pan=0.1),
    ),
    # サブと跳ねるベース
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=500, resonance=0.8, attackS=0.005, decayS=0.35, sustain=0.75, releaseS=0.1,
                   detuneCents=4, masterGain=0.8, unison=1, width=0.0, blend=1.0, sub=0.8, drive=0.15,
                   filterEnv=0.2, filterEnvDecayS=0.1, wave=1, osc=0.6),
        fx=dict(saturation=0.15),
        mixer=dict(gain=0.3, pan=0),
    ),
    # ドラムは Acoustic Live キット（kits/acoustic-live）
    "Kick": dict(
        color="fff28c38",
        kit="acoustic-live",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.26, sustain=0.0, releaseS=0.04,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=24, pitchEnvDecayS=0.03, wave=0, osc=0.5),
        fx=dict(saturation=0.08, sidechainSource=1),
        mixer=dict(gain=0.3, pan=0),
    ),
    # 裏拍はサイドスティック、ゴーストは本物のスネアを小さく
    "Stick": dict(
        color="fff2d45a",
        kit="acoustic-live",
        synth=dict(cutoffHz=2600, resonance=0.9, attackS=0.0005, decayS=0.12, sustain=0.0, releaseS=0.06,
                   detuneCents=0, masterGain=1.0, unison=1, noise=0.8, filterEnv=0.4, filterEnvDecayS=0.04,
                   wave=1, osc=0.2),
        fx=dict(lowCutHz=200, saturation=0.08),
        mixer=dict(gain=0.28, pan=0),
    ),
    "Hats": dict(
        color="ff5ad6c0",
        kit="acoustic-live",
        synth=dict(cutoffHz=12000, resonance=0.7, attackS=0.0005, decayS=0.04, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=300),
        mixer=dict(gain=0.34, pan=0.12),
    ),
    # ライドとフィンガーシンバル
    "Ride": dict(
        color="ffb0b6c0",
        kit="acoustic-live",
        synth=dict(cutoffHz=10000, resonance=0.7, attackS=0.0005, decayS=0.3, sustain=0.0, releaseS=0.2,
                   unison=1, noise=0.7, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=300),
        mixer=dict(gain=0.3, pan=-0.12),
    ),
}

# ---- コード ----------------------------------------------------------------------

V = {  # 声部と根音（ベース用）
    "EbM7": ([58, 63, 67, 70, 74], 39),
    "Cm9": ([60, 63, 67, 70, 74], 36),
    "AbM7": ([56, 60, 63, 67, 72], 44),
    "Bb7": ([58, 62, 65, 68, 72], 46),
}
PROG = ["EbM7", "Cm9", "AbM7", "Bb7"]


def held(prog, vel=0.55):
    return [n(i * BAR, BAR - 60, p, vel) for i, c in enumerate(prog) for p in V[c][0]]


def keys_groove(prog):
    # 小節頭に長く、裏のシンコペで短く2回
    out = []
    for i, c in enumerate(prog):
        out += [n(i * BAR, PPQ * 2 - 40, p, 0.66) for p in V[c][0]]
        for pos in (7, 10):
            out += [n(i * BAR + pos * S16 + (SWING if pos % 2 == 1 else 0), S16 * 2 - 30, p, 0.55) for p in V[c][0]]
    return out


def keys_long(prog):
    return [n(i * BAR, BAR - 80, p, 0.5) for i, c in enumerate(prog) for p in V[c][0]]


def bass_line(prog):
    out = []
    for i, c in enumerate(prog):
        root = V[c][1]
        out.append(n(i * BAR, PPQ - 30, root, 0.92))
        out.append(n(i * BAR + 7 * S16 + SWING, S16 * 2 - 30, root, 0.8))
        out.append(n(i * BAR + 10 * S16, PPQ - 30, root + 7, 0.78))
        out.append(n(i * BAR + 14 * S16, S16 * 2 - 30, root + 12, 0.7))
    return out


def melody(spec, vel=0.85):
    return [n(b * PPQ, l * PPQ - 40, p, vel) for b, l, p in spec]


LEAD_MELODY = [  # (拍, 長さ, 音程) 8小節。E♭メジャーの滑らかな歌
    (0, 2, 75), (2, 1, 74), (3, 1, 72),
    (4, 3, 70), (7, 1, 72),
    (8, 2, 74), (10, 2, 75),
    (12, 3, 77), (15, 1, 75),
    (16, 2, 74), (18, 1, 72), (19, 1, 70),
    (20, 3, 68), (23, 1, 70),
    (24, 2, 72), (26, 2, 74),
    (28, 4, 75),
]

# ---- ドラム（1小節 = 16分×16） ------------------------------------------------------

# kits/acoustic-live の番号
KICK = 36        # Kick Real
STICK = 37       # Sidestick
SNARE = 38       # Snare Real（ゴースト）
HAT_C = 65       # Hihat Closed Real
HAT_HALF = 46    # Hihat Halfopen
RIDE = 51        # Ride Bow
FINGER = 71      # Perc Finger Cymbal


def swung(pos):
    return pos * S16 + (SWING if pos % 2 == 1 else 0)


def kicks(bars=4):
    out = []
    for b in range(bars):
        for pos in (0, 7, 10) + ((14,) if b == bars - 1 else ()):
            out.append(n(b * BAR + swung(pos), S16 * 2 - 20, KICK, 0.95))
    return out


def sticks(bars=4):
    out = []
    for b in range(bars):
        out += steps(b, [4, 12], S16, [STICK], 0.95)
        if b % 2 == 1:
            out.append(n(b * BAR + 15 * S16 + SWING, S16, SNARE, 0.3))  # ゴースト
    return out


def hats(bars=4):
    out = []
    for b in range(bars):
        for pos in range(16):
            out.append(n(b * BAR + swung(pos), S16, HAT_C, 0.62 if pos % 4 == 0 else 0.42))
        if b == bars - 1:
            out.append(n(b * BAR + 14 * S16, S16 * 2, HAT_HALF, 0.6))
    return out


def ride(bars=4, accent=False):
    out = []
    for b in range(bars):
        for pos in (0, 4, 8, 12, 14):
            out.append(n(b * BAR + pos * S16, S16 * 2, RIDE, 0.55 if pos % 4 == 0 else 0.45))
    if accent:
        out.append(n(0, BAR, FINGER, 0.7))
    return out


# ---- project.json に組み立てる ----------------------------------------------------

def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    PA, KE, LE, BA = t["Pad"], t["Keys"], t["Lead"], t["Bass"]
    K, ST, H, RI = t["Kick"], t["Stick"], t["Hats"], t["Ride"]

    # イントロ／アウトロ
    b.clip(PA, 4, held(PROG), [0, 28])
    b.clip(KE, 4, keys_long(PROG), [0, 28])

    # Aメロ／サビ／Aメロ2
    b.clip(KE, 4, keys_groove(PROG), [4, 8, 12, 16, 20, 24])
    b.clip(BA, 4, bass_line(PROG), [4, 8, 12, 16, 20, 24])
    b.clip(K, 4, kicks(), [4, 8, 12, 16, 20, 24])
    b.clip(ST, 4, sticks(), [4, 8, 12, 16, 20, 24])
    b.clip(H, 4, hats(), [4, 8, 12, 16, 20, 24])
    b.clip(RI, 4, ride(accent=True), [12])
    b.clip(RI, 4, ride(), [16, 20, 24])
    b.clip(LE, 8, melody(LEAD_MELODY), [12, 20])

    return dict(format="mobiledaw-project", version=1, tempo=92.0, timeSig=[4, 4],
                key=dict(root=3, scale="major"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/rnb.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
