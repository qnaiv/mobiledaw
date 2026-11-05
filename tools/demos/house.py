#!/usr/bin/env python3
"""ハウスのデモ曲（project.json）を作る。

  python3 tools/demos/house.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/house.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/house.json /tmp/house.wav   # リポジトリの直下で（kits/ を読む）

124 BPM / A minor / 32小節（約1分）
  小節   0– 3  イントロ   4つ打ちキックと閉じたハットだけ
         4– 7  イントロ2  オフビートのコードスタブが入る
         8–15  グルーヴ   オフビートベース、2・4拍のクラップ、開いたハット
        16–23  ブレイク   キックが抜けてコードとベースだけ → 後半でドラムが戻る
        24–31  グルーヴ2  リードのフックが乗る。最後はキックとコードで終わる
進行は通して Am7 → Fmaj7 → Cmaj7 → G（vi–IV–I–V、フューチャーベースのデモとは別）
ドラムは House キット（kits/house）を使う
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # オフビートで刻むキーズ（矩形波を絞って柔らかく）
    "Keys": dict(
        color="ff5ad6c0",
        synth=dict(cutoffHz=2600, resonance=0.8, attackS=0.003, decayS=0.3, sustain=0.5, releaseS=0.12,
                   detuneCents=10, masterGain=0.6, unison=3, width=0.6, blend=0.9, drive=0.05,
                   filterEnv=0.35, filterEnvDecayS=0.15, wave=1, osc=1),
        fx=dict(lowCutHz=250, saturation=0.1, chorus=0.2, ott=0.3, delay=0.2, delayFeedback=0.25,
                reverb=0.25, reverbSize=0.6, sidechain=0.55, sidechainReleaseS=0.18),
        mixer=dict(gain=0.5, pan=0),
    ),
    # オフビートベース（拍の裏で跳ねる）
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=700, resonance=1.0, attackS=0.003, decayS=0.22, sustain=0.6, releaseS=0.05,
                   detuneCents=6, masterGain=0.8, unison=2, width=0.0, blend=1.0, sub=0.6, drive=0.3,
                   filterEnv=0.3, filterEnvDecayS=0.07, wave=0, osc=0.85),
        fx=dict(saturation=0.2, sidechain=0.5, sidechainReleaseS=0.15),
        mixer=dict(gain=0.3, pan=0),
    ),
    # 後半のフック（細いのこぎり、ディレイで流す）
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=5200, resonance=0.9, attackS=0.004, decayS=0.3, sustain=0.6, releaseS=0.15,
                   detuneCents=12, masterGain=0.55, unison=3, width=0.5, blend=0.85, drive=0.08,
                   filterEnv=0.25, filterEnvDecayS=0.2, wave=0, osc=1),
        fx=dict(lowCutHz=300, saturation=0.1, ott=0.3, delay=0.35, delayFeedback=0.35, reverb=0.3,
                reverbSize=0.65, sidechain=0.4, sidechainReleaseS=0.18),
        mixer=dict(gain=0.4, pan=0.08),
    ),
    # ドラムは House キット（kits/house）。キックは他のトラックを軽く引っ込める
    "Kick": dict(
        color="fff28c38",
        kit="house",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.26, sustain=0.0, releaseS=0.04,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=28, pitchEnvDecayS=0.03, wave=0, osc=0.5),
        fx=dict(saturation=0.1, sidechainSource=1),
        mixer=dict(gain=0.3, pan=0),
    ),
    # 2・4拍：Clap Wide＋808 Clap を重ねる
    "Clap": dict(
        color="fff2d45a",
        kit="house",
        synth=dict(cutoffHz=2600, resonance=0.9, attackS=0.0005, decayS=0.15, sustain=0.0, releaseS=0.07,
                   detuneCents=0, masterGain=1.0, unison=1, noise=1.0, filterEnv=0.5, filterEnvDecayS=0.05,
                   pitchEnv=12, pitchEnvDecayS=0.02, wave=1, osc=0.25),
        fx=dict(lowCutHz=200, saturation=0.1),
        mixer=dict(gain=0.26, pan=0),
    ),
    # 閉じたハット（16分）と裏拍の開いたハット（チョークで止まる）
    "Hats": dict(
        color="ff9a7cf2",
        kit="house",
        synth=dict(cutoffHz=16000, resonance=0.7, attackS=0.0005, decayS=0.04, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=300, sidechain=0.25, sidechainReleaseS=0.1),
        mixer=dict(gain=0.42, pan=0.15),
    ),
    # シェイカーとクラベス
    "Perc": dict(
        color="ffb0b6c0",
        kit="house",
        synth=dict(cutoffHz=9000, resonance=0.7, attackS=0.0005, decayS=0.05, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=400),
        mixer=dict(gain=0.3, pan=-0.2),
    ),
}

# ---- コード ----------------------------------------------------------------------

V = {  # 声部と根音（ベース用）
    "Am7": ([57, 60, 64, 67, 72], 45),
    "Fmaj7": ([57, 60, 65, 69, 72], 41),
    "Cmaj7": ([55, 60, 64, 67, 71], 48),
    "G": ([55, 59, 62, 67, 71], 43),
}
PROG = ["Am7", "Fmaj7", "Cmaj7", "G"]


def keys_stabs(prog):
    # オフビート（各拍の裏）のスタブ
    out = []
    for i, c in enumerate(prog):
        for pos in (2, 6, 10, 14):
            out += [n(i * BAR + pos * S16, S16 * 2 - 40, p, 0.78 if pos in (2, 10) else 0.66) for p in V[c][0]]
    return out


def keys_held(prog, vel=0.55):
    return [n(i * BAR, BAR - 60, p, vel) for i, c in enumerate(prog) for p in V[c][0]]


def bass_offbeat(prog):
    # キックの裏（オフビート）で跳ねる。4拍目の裏は1オクターブ上
    out = []
    for i, c in enumerate(prog):
        root = V[c][1]
        for pos in (2, 6, 10):
            out.append(n(i * BAR + pos * S16, S16 * 2 - 30, root, 0.92))
        out.append(n(i * BAR + 14 * S16, S16 * 2 - 30, root + 12, 0.8))
    return out


def bass_held(prog):
    return [n(i * BAR, BAR - 80, V[c][1], 0.85) for i, c in enumerate(prog)]


def melody(spec, vel=0.85):
    return [n(b * PPQ, l * PPQ - 30, p, vel) for b, l, p in spec]


LEAD_HOOK = [  # (拍, 長さ, 音程) 8小節。Aマイナーのペンタトニック
    (0, 1, 81), (1, 1, 79), (2, 2, 76),
    (4, 1, 77), (5, 1, 81), (6, 2, 79),
    (8, 1, 79), (9, 1, 76), (10, 2, 72),
    (12, 1, 74), (13, 1, 76), (14, 2, 79),
    (16, 1, 81), (17, 1, 84), (18, 2, 81),
    (20, 1, 79), (21, 1, 77), (22, 2, 76),
    (24, 1, 74), (25, 1, 76), (26, 1, 77), (27, 1, 79),
    (28, 2, 81), (30, 2, 76),
]

# ---- ドラム（1小節 = 16分×16） ------------------------------------------------------

# kits/house の番号
KICK = 36        # Kick House
CLAP = [28, 39]  # Clap Wide＋808 Clap
HAT_C, HAT_O = 42, 46  # 808 Hihat Closed / Open Long
CYMBAL = 49      # 808 Cymbal
SHAKER, CLAVES = 82, 75


def four_floor(bars=4):
    return [x for b in range(bars) for x in steps(b, [0, 4, 8, 12], S16 * 2, [KICK], 1.0)]


def claps(bars=4):
    return [x for b in range(bars) for x in steps(b, [4, 12], S16, CLAP, 0.95)]


def hats_quiet(bars=4):
    # 8分の閉じたハットだけ
    out = []
    for b in range(bars):
        for k in range(8):
            out.append(n(b * BAR + k * 2 * S16, S16, HAT_C, 0.55 if k % 2 == 0 else 0.75))
    return out


def hats_full(bars=4, crash=False):
    # 16分の閉じたハット＋裏拍の開いたハット
    out = []
    for b in range(bars):
        for pos in range(16):
            vel = 0.5 + (0.25 if pos % 4 == 0 else 0.0) + (0.15 if pos % 2 == 1 else 0.0)
            out.append(n(b * BAR + pos * S16, S16, HAT_C, vel))
        for pos in (2, 6, 10, 14):
            out.append(n(b * BAR + pos * S16, S16 * 2, HAT_O, 0.8))
    if crash:
        out.append(n(0, BAR, CYMBAL, 0.8))
    return out


def perc(bars=4):
    out = []
    for b in range(bars):
        for pos in range(16):
            out.append(n(b * BAR + pos * S16, S16, SHAKER, 0.35 if pos % 2 == 0 else 0.55))
        out += steps(b, [7, 14], S16, [CLAVES], 0.6)
    return out


# ---- project.json に組み立てる ----------------------------------------------------

def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    KE, BA, LE = t["Keys"], t["Bass"], t["Lead"]
    K, CL, H, PE = t["Kick"], t["Clap"], t["Hats"], t["Perc"]

    # イントロ
    b.clip(K, 4, four_floor(), [0, 4, 8, 12, 20, 24, 28])
    b.clip(H, 4, hats_quiet(), [0, 16])
    b.clip(KE, 4, keys_stabs(PROG), [4, 8, 12, 24, 28])

    # グルーヴ
    b.clip(BA, 4, bass_offbeat(PROG), [8, 12, 24, 28])
    b.clip(CL, 4, claps(), [8, 12, 20, 24, 28])
    b.clip(H, 4, hats_full(), [8, 12])
    b.clip(H, 4, hats_full(crash=True), [20, 24])
    b.clip(H, 4, hats_full(), [28])
    b.clip(PE, 4, perc(), [8, 12, 20, 24, 28])

    # ブレイク（キックなし → 後半で戻る）
    b.clip(KE, 4, keys_held(PROG), [16, 20])
    b.clip(BA, 4, bass_held(PROG), [16])

    # グルーヴ2のリード
    b.clip(LE, 8, melody(LEAD_HOOK), [24])

    return dict(format="mobiledaw-project", version=1, tempo=124.0, timeSig=[4, 4],
                key=dict(root=9, scale="minor"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/house.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
