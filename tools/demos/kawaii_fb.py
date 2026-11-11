#!/usr/bin/env python3
"""kawaii フューチャーベースのデモ曲「ソーダ色シュガーパレード」（project.json）を作る。

  python3 tools/demos/kawaii_fb.py [出力先] [--solo トラック名]

出力は app/assets/demos/kawaii_fb.json（既定）。リポジトリの直下で
  build/mdaw_render app/assets/demos/kawaii_fb.json /tmp/kawaii_fb.wav
164 BPM / E major → 2回目のドロップで F major に半音転調 / 76小節（約1分51秒）。
メロディ・歌詞・進行は書き下ろし。音はすべてエンジンの合成と同梱キット（自作／CC0）。
  小節  0– 3  イントロ    オルゴールが Aメロの旋律を予告、チップチューンの分散和音
        4– 7  イントロ2   パッド・チョップの合いの手・クラップ
        8–15  Aメロ       合成の歌（擬似歌唱）。跳ねる（16分のスウィング）2ステップ
       16–23  ビルド      4つ打ち→スネアロール、チョップが8分で上がる、最後の拍は無音
       24–39  ドロップ    ハーフタイム（3拍目にクラップ）。3-3-2 のスタブ＋16分で揺れるワブルコード、
                          チップチューンのリードとチョップが掛け合う
       40–47  ブレイク    サビの歌（ねえきいて…）をオルゴールとパッドで
       48–55  ビルド2     最後は C7sus4 で F へ
       56–71  ドロップ2   半音上（F major）。オルゴールが上で重なる
       72–75  アウトロ    オルゴールとピアノ。B♭M7 → FM7 で着地
進行（E major）
  Aメロ   AM7 → G#m7 → F#m7 → Bsus4（IV–iii–ii–V を降りる）
  ビルド  F#m7 → G#m7 → AM7 → B
  ドロップ EM7 → G#m7 → AM7 → B6 → F#m7 → Fm7 → Em7 → B7sus4
          （後半は ii から半音ずつ降りる kawaii FB 定番の動き：ii → ♭ii 相当の Fm7 → 同主短調の i7 → V）
コードのピッチエンベロープはごく小さく（-0.5 半音・15 ms）、揺れは音量とフィルターの LFO（音程は動かさない）。
"""
import copy
import json
import sys

from future_bass import n, steps, PPQ, BAR, S16
from singer import AutoBuilder, sing
import buruaka as base

TEMPO = 164.0
OUT = "app/assets/demos/kawaii_fb.json"
SWING = 0.16  # 裏の16分を S16 の 16% 遅らせる（跳ねる感じ）

S = copy.deepcopy(base.SOUNDS)
SOUNDS = {
    "Stabs": dict(S["Chords"], color="ffff8ad0"),
    "Wobble": dict(
        color="ffc79bff",
        synth=dict(base.CHORD, pitchEnv=0, lfoDiv=4, lfoAmp=0.6, lfoCutoff=0.25, lfoWave=1,
                   attackS=0.01, decayS=0.4, sustain=0.8, releaseS=0.1, masterGain=0.42, cutoffHz=5200),
        fx=dict(lowCutHz=300, chorus=0.2, ott=0.35, eqMidDb=-3, eqMidHz=500, sidechain=0.9,
                sidechainReleaseS=0.25, sidechainCurve=2.2, sendReverb=0.2),
        mixer=dict(gain=0.65, pan=0),
    ),
    "Pad": dict(S["Pad"], synth=dict(S["Pad"]["synth"], releaseS=0.4)),  # 164 BPM なので余韻を短く
    "MusicBox": dict(
        color="fffff3a0",
        synth=dict(osc=0.1, fm=0.25, fmRatio=1.0, unison=1, cutoffHz=9000, keyTrack=0.3,
                   attackS=0.001, decayS=0.45, sustain=0, releaseS=0.5, masterGain=0.6),
        fx=dict(lowCutHz=500, sendDelay=0.25, sendReverb=0.3, sidechain=0.2, sidechainReleaseS=0.15),
        mixer=dict(gain=0.3, pan=0.3),
    ),
    "Chip": dict(  # チップチューンのリード（矩形波・ユニゾンなし・軽いビブラート）
        color="ff7af0ff",
        synth=dict(wave=1, unison=1, mono=1, glideS=0.03, lfoPitch=0.08, wtLfoRate=6.0, cutoffHz=7000,
                   attackS=0.002, decayS=0.15, sustain=0.75, releaseS=0.06, masterGain=0.5),
        fx=dict(lowCutHz=350, eqHighDb=-2, eqHighHz=6000, sendDelay=0.2, sendReverb=0.12,
                sidechain=0.35, sidechainReleaseS=0.15),
        mixer=dict(gain=0.45, pan=0),
    ),
    "ChipArp": dict(
        color="ff9ae6ff",
        synth=dict(wave=1, unison=1, cutoffHz=5000, attackS=0.001, decayS=0.08, sustain=0, releaseS=0.04,
                   masterGain=0.45),
        fx=dict(lowCutHz=600, sendDelay=0.15, sidechain=0.5, sidechainReleaseS=0.15),
        mixer=dict(gain=0.16, pan=-0.3),
    ),
    "Vox": S["Vox"], "Cons": S["Cons"],
    "Chops": S["Chops"], "Chops Oh": S["Chops Oh"], "Piano": S["Piano"],
    "Sub": S["Sub"], "Kick": S["Kick"], "Ghost": S["Ghost"],
    "Clap": S["Clap"], "Hats": S["Hats"], "Riser": S["Riser"],
}
SOUNDS["Vox"]["mixer"] = dict(gain=0.125, pan=0)
SOUNDS["Sub"]["mixer"] = dict(gain=0.45, pan=0)

V = {
    "EM7": [52, 63, 68, 71, 75], "G#m7": [56, 63, 66, 71, 75], "AM7": [57, 64, 68, 73, 76],
    "B6": [59, 66, 68, 71, 75], "F#m7": [54, 61, 64, 69, 73], "Fm7": [53, 60, 63, 68, 72],
    "Em7": [52, 59, 62, 67, 71], "B7sus4": [59, 64, 66, 69, 76], "Bsus4": [59, 64, 66, 71, 76],
    "B": [59, 63, 66, 71, 75], "C7sus4": [60, 65, 67, 70, 77],
}
ROOT = {"EM7": 40, "G#m7": 44, "AM7": 33, "B6": 35, "F#m7": 42, "Fm7": 41, "Em7": 40, "B7sus4": 35,
        "Bsus4": 35, "B": 35, "C7sus4": 36}
VERSE = ["AM7", "G#m7", "F#m7", "Bsus4"]
BUILD = ["F#m7", "G#m7", "AM7", "B"]
BUILD2 = ["F#m7", "G#m7", "AM7", "C7sus4"]
DROP = ["EM7", "G#m7", "AM7", "B6", "F#m7", "Fm7", "Em7", "B7sus4"]
OUTRO = ["AM7", "AM7", "EM7", "EM7"]  # +1 で B♭M7 → FM7（IV → I で終わる）

CLAP, SNARE, HAT, HAT_O, CRASH, REV, BUBBLE, CHIME = 39, 38, 42, 58, 51, 52, 60, 63
KICK = 40  # シンセの E2
P332 = (0, 3, 6, 8, 11, 14)


def sw(pos):
    """16分の位置 → tick（裏の16分だけ少し遅らせる）"""
    return int(pos * S16 + (SWING * S16 if pos % 2 == 1 else 0))


def stabs(prog, sh=0, vel=0.85):
    out = []
    for i, c in enumerate(prog):
        for k, pos in enumerate(P332):
            ln = (P332 + (16,))[k + 1] - pos
            out += [n(i * BAR + sw(pos), ln * S16 - 40, p + sh, vel if pos in (0, 8) else vel * 0.85) for p in V[c][1:]]
    return out


def held(prog, sh=0, vel=0.55, top=False):
    return [n(i * BAR, BAR - 40, p + sh, vel) for i, c in enumerate(prog) for p in (V[c][1:] if top else V[c])]


def bass(prog, pos, sh=0):
    out = []
    ps = list(pos) + [16]
    for i, c in enumerate(prog):
        out += [n(i * BAR + sw(a), (b - a) * S16 - 30, ROOT[c] + sh, 0.95 if a == 0 else 0.85) for a, b in zip(ps, ps[1:])]
    return out


def chip_arp(prog, sh=0, vel=0.5):
    """16分の分散和音（上2オクターブ、上がって下がる）"""
    out = []
    for i, c in enumerate(prog):
        tones = [p + 12 for p in V[c][1:]]
        seq = tones + tones[-2:0:-1]
        out += [n(i * BAR + sw(k), S16 - 20, seq[k % len(seq)] + sh, vel if k % 4 == 0 else vel * 0.8) for k in range(16)]
    return out


def chops(prog, sh=0, pattern=(0, 3, 6, 10, 12, 14)):
    """チョップ「あ」：上の3声を跳ねるリズムで（全部コードの音）"""
    out = []
    for i, c in enumerate(prog):
        top = V[c][-3:]
        seq = [2, 1, 0, 1, 2, 1]
        out += [n(i * BAR + sw(p), S16 * 2 - 40, top[seq[k % 6]] + sh, 0.85 if p in (0, 8) else 0.7) for k, p in enumerate(pattern)]
    return out


def mel(spec, sh=0, vel=0.85):
    return [n(b * PPQ, l * PPQ - 30, p + sh, vel) for b, l, p, *_ in spec]


# ドロップのフック（チップチューン）。各小節その和音の音から始め、同じ型を進行に合わせてずらす
HOOK = [
    (0, .75, 83), (.75, .75, 80), (1.5, .5, 76), (2, 1, 80), (3, .5, 78), (3.5, .5, 76),
    (4, .75, 78), (4.75, .75, 75), (5.5, .5, 71), (6, 1, 75), (7, .5, 78), (7.5, .5, 80),
    (8, .75, 81), (8.75, .75, 80), (9.5, .5, 76), (10, 1, 73), (11, .5, 76), (11.5, .5, 80),
    (12, .75, 83), (12.75, .75, 80), (13.5, .5, 78), (14, 2, 75),
    (16, .75, 81), (16.75, .75, 78), (17.5, .5, 76), (18, 1, 73), (19, .5, 76), (19.5, .5, 78),
    (20, .75, 80), (20.75, .75, 77), (21.5, .5, 75), (22, 1, 72), (23, .5, 75), (23.5, .5, 77),
    (24, .75, 79), (24.75, .75, 76), (25.5, .5, 74), (26, 1, 71), (27, .5, 74), (27.5, .5, 76),
    (28, .75, 78), (28.75, .75, 76), (29.5, .5, 71), (30, 2, 78),
]
# ブレイクの歌：フックの各小節の頭4音を歌う（ねえきいて きみがすきだよ ぱちぱち ほしがひかるそら ふたりでとぼうよ）
HOOK_SYL = "ne e ki i te ki mi ga su ki da yo pa chi pa chi ho shi ga hi ka ru so ra fu ta ri de to bo u yo".split()
SUNG = [x for x in HOOK if (x[0] % 4) in (0, .75, 1.5, 2)]
SUNG = [(b, (1.5 if b % 4 == 2 else l), p, s) for (b, l, p), s in zip(SUNG, HOOK_SYL)]

# Aメロの歌（AM7 → G#m7 → F#m7 → Bsus4）。2行ずつ2回
V_MEL = [(0, .5, 76), (.5, .5, 73), (1, .5, 76), (1.5, .5, 73), (2, .5, 80), (2.5, 1.5, 81),
         (4, .5, 78), (4.5, .5, 75), (5, .5, 71), (5.5, .5, 75), (6, .5, 78), (6.5, 1.5, 80)]
V_MEL2 = [(8, .5, 73), (8.5, .5, 76), (9, .5, 78), (9.5, .5, 80), (10, 1, 81), (11, .5, 78),
          (12, .5, 76), (12.5, .5, 78), (13, .5, 83), (13.5, .5, 78), (14, 2, 76)]


def lyr(spec, text):
    s = text.split()
    assert len(s) == len(spec), (text, len(s), len(spec))
    return [(b, l, p, x) for (b, l, p), x in zip(spec, s)]


VERSE_A = lyr(V_MEL, "fu wa fu wa so o da ga ha ji ke te") + lyr(V_MEL2, "ki mi no te no hi ra ni ki ra ri")
VERSE_B = lyr(V_MEL, "ma do no so to wa pa su te ru i ro") + lyr(V_MEL2, "fu ta ri no ji ka N ka ke da su")
assert len(SUNG) == len(HOOK_SYL)


def hats(bars, dense=True):
    out = []
    for b in range(bars):
        for pos in range(16 if dense else 8):
            p = pos if dense else pos * 2
            out.append(n(b * BAR + sw(p), S16, HAT, 0.5 if p % 4 == 0 else 0.3))
        if dense and b % 2 == 1:  # 3連のロール
            out += [n(b * BAR + 12 * S16 + k * (PPQ // 3), PPQ // 3 - 10, HAT, 0.4) for k in range(3)]
            out += [n(b * BAR + 14 * S16 + k * (PPQ // 6), PPQ // 6 - 8, HAT, 0.35 + 0.04 * k) for k in range(3)]
    return out


def snare_roll():
    out = [n(k * PPQ, PPQ - 20, SNARE, 0.45 + 0.06 * k) for k in range(8)]
    out += [n(2 * BAR + k * PPQ // 2, PPQ // 2 - 15, SNARE, 0.5 + 0.03 * k) for k in range(8)]
    out += [n(3 * BAR + k * (S16 // 2), S16 // 2 - 8, SNARE, 0.6 + 0.012 * k) for k in range(24)]
    return out


def with_sampler(b, name, sound, solo):
    tid = b.track(name, sound, solo)
    inst = b.tracks[-1]["instrument"]
    inst["type"] = "sampler"
    inst["sampler"] = sound["sampler"]
    return tid


def build(solo=None):
    b = AutoBuilder()
    t = {k: (with_sampler(b, k, v, solo) if "sampler" in v else b.track(k, v, solo)) for k, v in SOUNDS.items()}
    ST, WO, PAD, MB, CH, CA = t["Stabs"], t["Wobble"], t["Pad"], t["MusicBox"], t["Chip"], t["ChipArp"]
    VO, CO_, AH, OH, PI = t["Vox"], t["Cons"], t["Chops"], t["Chops Oh"], t["Piano"]
    SUB, K, GH, CL, H, RI = t["Sub"], t["Kick"], t["Ghost"], t["Clap"], t["Hats"], t["Riser"]
    cut = lambda a, z, bars=4: [dict(param="cutoffHz", points=[[0, a], [bars * BAR, z]])]

    # イントロ：オルゴールが Aメロの旋律、チップの分散和音（フィルターが開く）
    b.clip(MB, 4, mel(V_MEL + V_MEL2, 12, 0.8), [0, 4])
    b.clip(CA, 4, chip_arp(VERSE, 0, 0.45), [0, 4], automation=cut(1200, 5000))
    b.clip(PAD, 4, held(VERSE, 0, 0.45), [4, 8, 12])
    b.clip(PAD, 8, held(DROP, 0, 0.4), [40])
    b.clip(OH, 4, [n(i * BAR + sw(14), S16 * 2, V[c][-1], 0.7) for i, c in enumerate(VERSE)], [4])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [CLAP], 0.6)], [4])
    b.clip(H, 4, [n(bb * BAR + 15 * S16, S16, CHIME, 0.5) for bb in range(4)], [4])
    # Aメロ
    for at, ly in ((8, VERSE_A), (12, VERSE_B)):
        vox, va, cons, ca = sing(ly, TEMPO, 4 * BAR, fixed_formant=True, compensate=False, vibrato=0.1,
                                 base_gain=SOUNDS["Vox"]["mixer"]["gain"])
        b.clip(VO, 4, vox, [at], automation=va)
        b.clip(CO_, 4, cons, [at], automation=ca)
    b.clip(PI, 4, held(VERSE, 0, 0.32), [8, 12])
    b.clip(CA, 4, chip_arp(VERSE, 0, 0.35), [12], automation=cut(3000, 3000))
    b.clip(SUB, 4, bass(VERSE, (0, 6, 10)), [8, 12])
    two = [x for bb in range(4) for x in steps(bb, [0, 6, 10], S16 * 2, [KICK], 0.75)]
    b.clip(K, 4, two, [8, 12])
    b.clip(GH, 4, [x for bb in range(4) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 1)], [8, 12, 16])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [CLAP], 0.8)], [8, 12])
    b.clip(H, 4, hats(4, False) + [n(bb * BAR + sw(7), S16, BUBBLE, 0.4) for bb in range(4)], [8, 12])
    # ビルド
    for at, prog in ((16, BUILD), (20, BUILD), (48, BUILD), (52, BUILD2)):
        b.clip(ST, 4, stabs(prog, 0, 0.75), [at], automation=cut(2500, 6500))
        b.clip(SUB, 4, bass(prog, (0, 4, 8, 12)), [at])
        b.clip(AH, 4, [n(i * BAR + q * PPQ // 2, PPQ // 2 - 30, V[c][-1 - (q % 3)], 0.6 + 0.04 * q)
                       for i, c in enumerate(prog) for q in range(8)], [at])
    b.clip(PAD, 4, held(BUILD, 0, 0.5), [16, 20, 48])
    b.clip(PAD, 4, held(BUILD2, 0, 0.5), [52])
    b.clip(K, 4, [x for bb in range(4) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 0.95)], [16, 48])
    b.clip(K, 4, [x for bb in range(3) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 0.95)], [20, 52])
    b.clip(GH, 4, [x for bb in range(4) for x in steps(bb, [0, 4, 8, 12] if bb < 3 else [0, 4, 8], S16, [KICK], 1)], [20, 48, 52])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [CLAP], 0.75)], [16, 48])
    b.clip(CL, 4, snare_roll(), [20, 52])
    b.clip(RI, 4, [n(0, 4 * BAR - PPQ, 60, 0.85)], [20, 52])
    b.clip(H, 4, [n(2 * BAR, 2 * BAR - PPQ, REV, 0.7)], [20, 52])
    # ドロップ（E）とドロップ2（F）
    for at, sh in ((24, 0), (56, 1)):
        b.clip(ST, 8, stabs(DROP, sh, 0.9), [at, at + 8], automation=cut(6500, 6500, 8))
        b.clip(WO, 8, held(DROP, sh, 0.6, top=True), [at, at + 8])
        b.clip(PAD, 8, held(DROP, sh, 0.4), [at, at + 8])
        b.clip(SUB, 8, bass(DROP, (0, 10), sh), [at, at + 8])
        b.clip(CH, 8, mel(HOOK, sh, 0.85), [at, at + 8])
        b.clip(AH, 8, chops(DROP, sh, (0, 3, 6)) + [], [at + 8])
        b.clip(OH, 8, [n(i * BAR + sw(p), S16 * 2 - 40, V[c][-1] + sh, 0.7) for i, c in enumerate(DROP)
                       for p in (12, 14)], [at])
        hk = [x for bb in range(4) for x in steps(bb, [0, 10] if bb % 2 == 0 else [0, 3, 10], S16 * 2, [KICK + sh], 1.0)]
        b.clip(K, 4, hk, [at, at + 4, at + 8, at + 12])
        b.clip(GH, 4, [x for bb in range(4) for x in steps(bb, [0, 8, 10], S16, [KICK], 1)], [at, at + 4, at + 8, at + 12])
        b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [8], S16, [CLAP], 0.95)], [at, at + 4, at + 8, at + 12])
        b.clip(H, 4, hats(4, True), [at, at + 4, at + 8, at + 12])
        b.clip(H, 1, [n(0, BAR, CRASH, 0.8)], [at, at + 8])
    b.clip(MB, 8, [n(i * BAR + sw(p), S16 * 2, V[c][-1 - k] + 12 + 1, 0.55) for i, c in enumerate(DROP)
                   for k, p in enumerate((0, 6, 10))], [56, 64])
    b.clip(CA, 8, chip_arp(DROP, 1, 0.3), [64])
    # ブレイク：サビの歌
    vox, va, cons, ca = sing(SUNG, TEMPO, 8 * BAR, fixed_formant=True, compensate=False, vibrato=0.14,
                             base_gain=SOUNDS["Vox"]["mixer"]["gain"])
    b.clip(VO, 8, vox, [40], automation=va)
    b.clip(CO_, 8, cons, [40], automation=ca)
    b.clip(MB, 8, [n(i * BAR + sw(p), S16 * 2, V[c][k + 1] + 12, 0.5) for i, c in enumerate(DROP)
                   for k, p in enumerate((0, 3, 6, 8))], [40])
    b.clip(PI, 8, held(DROP, 0, 0.45), [40])
    b.clip(SUB, 8, [n(i * BAR, BAR - 60, ROOT[c], 0.6) for i, c in enumerate(DROP)], [40])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [8], S16, [CLAP], 0.5)], [44])
    b.clip(H, 4, hats(4, False), [44])
    b.clip(H, 1, [n(0, BAR, CRASH, 0.6)], [40])
    # アウトロ（F）
    b.clip(MB, 4, mel(V_MEL[:6] + [(4, 4, 76)], 13, 0.75), [72])
    b.clip(PAD, 4, held(OUTRO, 1, 0.45), [72])
    b.clip(PI, 4, held(OUTRO, 1, 0.45), [72])
    b.clip(K, 1, [n(0, S16 * 2, KICK + 1, 1)], [72])
    b.clip(H, 1, [n(0, BAR, CRASH, 0.6)], [72])

    return dict(format="mobiledaw-project", version=1, title="ソーダ色シュガーパレード",
                tempo=TEMPO, timeSig=[4, 4], key=dict(root=4, scale="major"),
                master=dict(gain=MASTER_GAIN, glue=0.6, thresholdDb=-10, ratio=1.8, softClip=0.35, ceiling=0.84),
                aux=dict(reverbReturn=0.8, reverbSize=0.55, delayReturn=0.45, delayFeedback=0.28),
                tracks=b.tracks, clips=b.clips, placements=b.placements)


MASTER_GAIN = 4.0


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    path = args[0] if args else OUT
    data = build(solo)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(path, "tracks", len(data["tracks"]), "bars", max(p["startBar"] + p["lengthBars"] for p in data["placements"]))


if __name__ == "__main__":
    main()
