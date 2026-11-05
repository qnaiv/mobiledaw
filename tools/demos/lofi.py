#!/usr/bin/env python3
"""Lo-fi のデモ曲（project.json）を作る。

  python3 tools/demos/lofi.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/lofi.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/lofi.json /tmp/lofi.wav   # リポジトリの直下で（kits/ を読む）

84 BPM / D minor / 24小節（約1分9秒）
  小節   0– 7  A   ローパスをかけたコード、スウィングするドラム、バイナルノイズ
         8–15  B   リードとライドが入る
        16–23  A'  同じループにリードがもう一度（ループ感をそのまま見せる）
進行は Dm9 → B♭M7 → FM7 → A7（ジャズ寄りの ii–VI–III–V…Dマイナー基準）
ドラムは表の16分を少し遅らせるスウィング（+70 tick）で鳴らす。
ドラムは Lo-fi Boom Bap キット（kits/lofi-boombap）を使う
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16

SWING = 70  # 裏の音を遅らせる量（tick）。S16=240 の約3割

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # ローパスを絞ったジャズコード（矩形波＋コーラス＋リバーブ）
    "Chords": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=1700, resonance=0.7, attackS=0.012, decayS=0.6, sustain=0.75, releaseS=0.4,
                   detuneCents=9, masterGain=0.62, unison=2, width=0.55, blend=0.95, drive=0.06,
                   filterEnv=0.12, filterEnvDecayS=0.4, wave=1, osc=1),
        fx=dict(lowCutHz=120, saturation=0.18, chorus=0.4, ott=0.15, reverb=0.42, reverbSize=0.75),
        mixer=dict(gain=0.52, pan=-0.05),
    ),
    # 控えめなリード（絞ったのこぎり、ビブラート代わりのデチューン少なめ）
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=2400, resonance=0.8, attackS=0.01, decayS=0.5, sustain=0.7, releaseS=0.35,
                   detuneCents=5, masterGain=0.55, unison=2, width=0.25, blend=0.9, drive=0.05,
                   filterEnv=0.1, filterEnvDecayS=0.3, wave=0, osc=1),
        fx=dict(lowCutHz=200, saturation=0.12, chorus=0.15, ott=0.15, delay=0.3, delayFeedback=0.3,
                reverb=0.4, reverbSize=0.7),
        mixer=dict(gain=0.4, pan=0.12),
    ),
    # サブ中心のベース
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=420, resonance=0.8, attackS=0.006, decayS=0.4, sustain=0.8, releaseS=0.12,
                   detuneCents=4, masterGain=0.8, unison=1, width=0.0, blend=1.0, sub=0.85, drive=0.12,
                   filterEnv=0.15, filterEnvDecayS=0.12, wave=1, osc=0.55),
        fx=dict(saturation=0.15),
        mixer=dict(gain=0.3, pan=0),
    ),
    # バイナルノイズ（ノイズだけを小さく流し続ける）
    "Vinyl": dict(
        color="ffb0b6c0",
        synth=dict(cutoffHz=750, resonance=0.6, attackS=0.05, decayS=1.0, sustain=1.0, releaseS=0.2,
                   unison=1, noise=1.0, osc=0, masterGain=0.16),
        fx=dict(lowCutHz=60),
        mixer=dict(gain=0.5, pan=0),
    ),
    # ドラムは Lo-fi Boom Bap キット（kits/lofi-boombap）
    "Kick": dict(
        color="fff28c38",
        kit="lofi-boombap",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.26, sustain=0.0, releaseS=0.04,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=24, pitchEnvDecayS=0.03, wave=0, osc=0.5),
        fx=dict(saturation=0.12, sidechainSource=1),
        mixer=dict(gain=0.3, pan=0),
    ),
    "Snare": dict(
        color="fff2d45a",
        kit="lofi-boombap",
        synth=dict(cutoffHz=2400, resonance=0.9, attackS=0.0005, decayS=0.16, sustain=0.0, releaseS=0.08,
                   detuneCents=0, masterGain=1.0, unison=1, noise=1.0, filterEnv=0.4, filterEnvDecayS=0.05,
                   wave=1, osc=0.2),
        fx=dict(lowCutHz=150, saturation=0.12),
        mixer=dict(gain=0.3, pan=0),
    ),
    "Hats": dict(
        color="ff5ad6c0",
        kit="lofi-boombap",
        synth=dict(cutoffHz=9000, resonance=0.7, attackS=0.0005, decayS=0.05, sustain=0.0, releaseS=0.04,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=250),
        mixer=dict(gain=0.36, pan=0.1),
    ),
}

# ---- コード ----------------------------------------------------------------------

V = {  # 声部（ルートレスのジャズボイシング）と根音（ベース用）
    "Dm9": ([53, 57, 60, 64], 38),
    "BbM7": ([58, 62, 65, 69], 34),
    "FM7": ([53, 57, 60, 64], 41),
    "A7": ([57, 61, 64, 67], 45),
}
PROG = ["Dm9", "BbM7", "FM7", "A7"]


def chords(prog):
    # 小節頭に長く、2拍半の所で短くもう一度（キーズの刻み）
    out = []
    for i, c in enumerate(prog):
        out += [n(i * BAR, PPQ * 2 - 40, p, 0.62) for p in V[c][0]]
        out += [n(i * BAR + 10 * S16, S16 * 5 - 40, p, 0.55) for p in V[c][0]]
    return out


def bass_line(prog):
    # 根音 → 5度。裏はスウィングさせる
    out = []
    for i, c in enumerate(prog):
        root = V[c][1]
        out.append(n(i * BAR, PPQ * 2 - 40, root, 0.9))
        out.append(n(i * BAR + 10 * S16 + SWING, PPQ - 40, root + 7, 0.75))
        out.append(n(i * BAR + 14 * S16 + SWING, S16 * 2 - 40, root, 0.7))
    return out


def melody(spec, vel=0.8):
    return [n(b * PPQ, l * PPQ - 40, p, vel) for b, l, p in spec]


LEAD_MELODY = [  # (拍, 長さ, 音程) 8小節。間を多めに空ける
    (0, 2, 69), (3, 1, 65),
    (4, 2, 67), (6, 1, 65), (7, 1, 62),
    (8, 2, 64), (11, 1, 60),
    (12, 3, 62),
    (16, 2, 69), (19, 1, 72),
    (20, 2, 70), (22, 1, 69), (23, 1, 67),
    (24, 2, 65), (27, 1, 64),
    (28, 4, 62),
]

# ---- ドラム（1小節 = 16分×16、裏は +SWING） -----------------------------------------

# kits/lofi-boombap の番号
KICK = 36    # Kick Lofi
SNARE = 38   # Snare Lofi
HAT_C, HAT_O = 42, 46  # Hihat Closed / Open Lofi
CRASH = 49   # Crash Lofi
RIDE = 51    # Ride Lofi


def swung(pos):
    return pos * S16 + (SWING if pos % 2 == 1 else 0)


def kicks(bars=4):
    out = []
    for b in range(bars):
        for pos in (0, 7, 10) + ((14,) if b == bars - 1 else ()):
            out.append(n(b * BAR + swung(pos), S16 * 2 - 20, KICK, 1.0))
    return out


def snares(bars=4):
    return [x for b in range(bars) for x in steps(b, [4, 12], S16, [SNARE], 0.95)]


def hats(bars=4, ride=False, crash=False):
    out = []
    for b in range(bars):
        for pos in range(0, 16, 2):  # 8分。裏（2,6,10,14）はスウィング
            tick = b * BAR + pos * S16 + (SWING if pos % 4 == 2 else 0)
            out.append(n(tick, S16, HAT_C, 0.55 if pos % 4 == 0 else 0.8))
        if ride:
            for pos in (0, 4, 8, 12):
                out.append(n(b * BAR + pos * S16, S16 * 2, RIDE, 0.5))
    out.append(n((bars - 1) * BAR + 14 * S16 + SWING, S16 * 2, HAT_O, 0.7))
    if crash:
        out.append(n(0, BAR, CRASH, 0.75))
    return out


def vinyl(bars=4):
    return [n(0, bars * BAR - 100, 60, 0.9)]


# ---- project.json に組み立てる ----------------------------------------------------

def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    CH, LE, BA, VI = t["Chords"], t["Lead"], t["Bass"], t["Vinyl"]
    K, SN, H = t["Kick"], t["Snare"], t["Hats"]

    for at in ([0, 4, 8, 12, 16, 20],):
        b.clip(CH, 4, chords(PROG), list(at))
        b.clip(BA, 4, bass_line(PROG), list(at))
        b.clip(VI, 4, vinyl(), list(at))
        b.clip(K, 4, kicks(), list(at))
        b.clip(SN, 4, snares(), list(at))
    b.clip(H, 4, hats(), [0, 4])
    b.clip(H, 4, hats(ride=True, crash=True), [8])
    b.clip(H, 4, hats(ride=True), [12, 16, 20])
    b.clip(LE, 8, melody(LEAD_MELODY), [8, 16])

    return dict(format="mobiledaw-project", version=1, tempo=84.0, timeSig=[4, 4],
                key=dict(root=2, scale="minor"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/lofi.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
