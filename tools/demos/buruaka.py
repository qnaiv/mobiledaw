#!/usr/bin/env python3
"""透明感のあるフューチャーベース「そら色ステップ」（歌入り／インスト）。

  python3 tools/demos/buruaka.py                 # 歌入りとインストの両方
  python3 tools/demos/buruaka.py vocal|inst [出力先]

146 BPM / A major / 76小節（約2分5秒）。メロディ・歌詞・進行は書き下ろし。
  小節  0– 3  イントロ      ガラスっぽいベルとプラックが 3-3-2 で跳ねる。ドラムはリムとシェイカーだけ
        4–11  イントロドロップ  いきなりハーフタイムのドロップ（サビ進行の予告）。ボーカルチョップのモチーフ
       12–19  Aメロ          ピアノとプラック、軽いキック。D の小節で Dm6（同主短調の iv）に曇らせる
       20–23  Bメロ          ii → iii → IV → Vsus4 と上がる。スネアロール、最後の拍は無音
       24–39  サビ×2         ii–V–iii–vi ／ ii–V–I。スーパーソーは 3-3-2 のスタブ、2・4拍クラップで前へ
       40–47  ドロップ        ハーフタイム。IV–iii–ii–V と降りる進行でチョップが歌う
       48–51  ブリッジ        ドラムなし。ピアノとパッド
       52–55  Bメロ2
       56–71  ラストサビ×2   リードがオクターブ上も重ねる
       72–75  アウトロ        ベルのモチーフに戻って A で終わる
コードは開いた配置（C4 より下で2度を重ねない）。スーパーソーは根音を省いてベースに任せる。
コードのピッチエンベロープはほぼ 0（-0.6 半音・20 ms）。ベルの FM は比率 1・浅め。パッドはクワイア表（wtTable 7）を
やめてスーパーソー表を暗く（クワイア表は長3度の倍音が強く、短調のコードで濁る）。キックは A1 に合わせる。
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16
from singer import AutoBuilder, sing

TEMPO = 146.0
OUT_VOCAL = "app/assets/demos/buruaka.json"
OUT_INST = "app/assets/demos/buruaka_inst.json"

# 未来ベース用の明るいスーパーソー。各スタブが -2 半音から戻る。8分で音量も揺れる
CHORD = dict(
    wtTable=5, wtPos=0.55, unison=7, detuneCents=20, width=0.9, blend=0.72, noise=0.0,
    cutoffHz=6500, resonance=0.75, keyTrack=0.45, filterEnv=0.25, filterEnvDecayS=0.12,
    pitchEnv=-0.6, pitchEnvDecayS=0.02,  # ほんの少しだけ下からすくう（-2/0.09 だと8分のスタブの大半が低いまま鳴る）
    lfoSync=1, lfoRetrig=1, lfoDiv=3, lfoWave=1, lfoAmp=0.45,
    attackS=0.004, decayS=0.22, sustain=0.35, releaseS=0.12, masterGain=0.5,
)
SOUNDS = {
    "Chords": dict(
        color="fff7a8d8",
        synth=dict(CHORD),
        fx=dict(lowCutHz=300, saturation=0.08, chorus=0.22, ott=0.45, eqMidDb=-4, eqMidHz=500, reverb=0.08, reverbSize=0.6,
                eqHighDb=2.5, eqHighHz=4500, sidechain=0.92, sidechainAttackS=0.004, sidechainHoldS=0.03,
                sidechainReleaseS=0.32, sidechainCurve=2.4, sendReverb=0.28),
        mixer=dict(gain=0.8, pan=0),
    ),
    "Pad": dict(
        color="ffd89af2",
        synth=dict(wtTable=5, wtPos=0.35, wtLfoRate=0.25, wtLfoAmount=0.2, unison=6, detuneCents=18,
                   width=0.9, blend=0.75, cutoffHz=1800, attackS=0.45, decayS=0.8, sustain=0.85,
                   releaseS=1.2, masterGain=0.4, lfoPitch=0.04),
        fx=dict(lowCutHz=350, chorus=0.3, reverb=0.15, sendReverb=0.4, sidechain=0.85, sidechainReleaseS=0.32, sidechainCurve=2),
        mixer=dict(gain=0.6, pan=0.05),
    ),
    "Pluck": dict(
        color="ff5ad6c0",
        synth=dict(wtTable=6, wtPos=0.35, unison=2, detuneCents=8, width=0.55, cutoffHz=5200, resonance=1.2,
                   filterEnv=0.55, filterEnvDecayS=0.1, attackS=0.001, decayS=0.18, sustain=0, releaseS=0.16,
                   masterGain=0.55),
        fx=dict(lowCutHz=300, delay=0.12, sendDelay=0.28, sendReverb=0.16, sidechain=0.4, sidechainReleaseS=0.18),
        mixer=dict(gain=0.45, pan=-0.35),
    ),
    "Bell": dict(  # 2オペレーターFM。比率 1・浅めで倍音を素直に（比率 3.5／4 だと部分音がコードとぶつかる）
        color="ffffe066",
        synth=dict(osc=0.15, fm=0.3, fmRatio=1.0, unison=2, detuneCents=6, width=0.4,
                   cutoffHz=8000, resonance=0.7, filterEnv=0.4, filterEnvDecayS=0.08,
                   attackS=0.001, decayS=0.28, sustain=0, releaseS=0.35, masterGain=0.55),
        fx=dict(lowCutHz=400, sendDelay=0.22, sendReverb=0.2, sidechain=0.25, sidechainReleaseS=0.16),
        mixer=dict(gain=0.3, pan=0.4),
    ),
    "Piano": dict(
        color="ffc8f2ea",
        sampler=dict(kit="kawaii-oneshots", sound="Piano", rootNote=60, gain=1.0, start=0),
        synth=dict(masterGain=0.8, unison=1),
        fx=dict(lowCutHz=120, sendReverb=0.35, reverb=0.05),
        mixer=dict(gain=0.14, pan=-0.1),
    ),
    "Chops": dict(
        color="ffff7ab8",
        sampler=dict(kit="kawaii-oneshots", sound="Ah", rootNote=60, gain=1.1, start=0),
        synth=dict(masterGain=0.8, unison=1),
        fx=dict(lowCutHz=200, sendDelay=0.2, sendReverb=0.12, sidechain=0.35, sidechainReleaseS=0.14),
        mixer=dict(gain=0.34, pan=0.15),
    ),
    "Chops Oh": dict(
        color="ffffb0d0",
        sampler=dict(kit="kawaii-oneshots", sound="Oh", rootNote=60, gain=1.0, start=0),
        synth=dict(masterGain=0.7, unison=1),
        fx=dict(lowCutHz=180, sendReverb=0.18, sidechain=0.3, sidechainReleaseS=0.14),
        mixer=dict(gain=0.28, pan=-0.2),
    ),
    "Lead": dict(
        color="ffe879c6",
        synth=dict(wave=1, unison=2, detuneCents=10, width=0.25, mono=1, glideS=0.05,
                   wtLfoRate=5.6, lfoPitch=0.16, cutoffHz=6400, resonance=0.9, filterEnv=0.2,
                   filterEnvDecayS=0.15, attackS=0.004, decayS=0.25, sustain=0.7, releaseS=0.12,
                   masterGain=0.62),
        fx=dict(lowCutHz=280, ott=0.25, sendDelay=0.18, sendReverb=0.2, sidechain=0.4, sidechainReleaseS=0.16),
        mixer=dict(gain=0.36, pan=0.05),
    ),
    "Vox": dict(  # 高い女声域。母音は Hz 固定のフォルマント（音程について上がらない）
        color="ffff9ec8",
        synth=dict(wave=0, osc=1, unison=2, detuneCents=7, width=0.18, blend=0.85,
                   formant=0.92, formantVowel=0, mono=1, glideS=0.055,
                   wtLfoRate=5.5, lfoPitch=0.0, cutoffHz=7500, resonance=0.7, noise=0.02,
                   attackS=0.01, decayS=0.2, sustain=0.82, releaseS=0.08, masterGain=0.72),
        fx=dict(lowCutHz=180, chorus=0.08, ott=0.15, eqMidDb=-2.5, eqMidHz=450, eqHighDb=2, eqHighHz=4000,
                comp=0.35, compThresholdDb=-16, compRatio=3, compMakeupDb=1,
                sendDelay=0.16, sendReverb=0.22, sidechain=0.28, sidechainReleaseS=0.14),
        mixer=dict(gain=0.24, pan=0),
    ),
    "Cons": dict(
        color="ffffd0e6",
        synth=dict(osc=0, noise=1, unison=1, cutoffHz=8000, resonance=1.1,
                   attackS=0.001, decayS=0.05, sustain=0.7, releaseS=0.02, masterGain=0.7),
        fx=dict(lowCutHz=1800, sendReverb=0.08),
        mixer=dict(gain=0.85, pan=0),
    ),
    "Sub": dict(
        color="ff5aa9f2",
        synth=dict(osc=0.4, sub=0.3, unison=1, cutoffHz=300, resonance=0.6,
                   attackS=0.005, decayS=0.2, sustain=0.9, releaseS=0.08, masterGain=0.85),
        fx=dict(eqLowDb=1.5, eqLowHz=70, eqHighDb=-6, eqHighHz=400,
                comp=0.4, compThresholdDb=-18, compRatio=4, sidechain=0.85, sidechainReleaseS=0.22),
        mixer=dict(gain=0.75, pan=0),
    ),
    "Kick": dict(  # ノート 33 = A1。ピッチエンベロープで胴が落ちる
        color="fff28c38",
        synth=dict(osc=0.7, sub=0.0, unison=1, cutoffHz=900, resonance=0.7, keyTrack=0,
                   pitchEnv=30, pitchEnvDecayS=0.04, filterEnv=0.85, filterEnvDecayS=0.03,
                   attackS=0.0005, decayS=0.28, sustain=0, releaseS=0.04, masterGain=1.0),
        fx=dict(saturation=0.3, eqLowDb=2, eqLowHz=70, eqMidDb=-2.5, eqMidHz=300,
                comp=0.4, compThresholdDb=-12, compRatio=3.5),
        mixer=dict(gain=0.5, pan=0),
    ),
    "Ghost": dict(  # 聞こえない4つ打ち。サイドチェインだけを踏む
        color="ff888888",
        synth=dict(osc=0.2, sub=0.4, unison=1, pitchEnv=12, pitchEnvDecayS=0.02,
                   attackS=0.001, decayS=0.05, sustain=0, releaseS=0.02, masterGain=0.4),
        fx=dict(sidechainSource=1),
        mixer=dict(gain=0, pan=0),
    ),
    "Clap": dict(
        color="fff2d45a", kit="future-bass-pro", synth=dict(masterGain=1, unison=1),
        fx=dict(lowCutHz=180, eqMidDb=1.5, eqMidHz=2000, eqHighDb=-3, eqHighHz=7000, comp=0.4, compThresholdDb=-14, compRatio=4,
                sendReverb=0.16),
        mixer=dict(gain=0.22, pan=0.02),
    ),
    "Hats": dict(
        color="ffb0b6c0", kit="future-bass-pro", synth=dict(masterGain=1, unison=1),
        fx=dict(lowCutHz=400, eqHighDb=-1.5, eqHighHz=10000),
        mixer=dict(gain=0.16, pan=0.28),
    ),
    "Riser": dict(
        color="ffeeeeee",
        synth=dict(osc=0, noise=1, unison=1, cutoffHz=8000, resonance=1.4, keyTrack=0,
                   attackS=6.0, decayS=0.4, sustain=1, releaseS=0.15, masterGain=0.55),
        fx=dict(lowCutHz=500, sendReverb=0.3),
        mixer=dict(gain=0.32, pan=0),
    ),
}

V = {  # 開いた配置（A major）
    "AM7": [57, 64, 68, 71, 73], "Aadd9": [57, 64, 69, 71, 76], "C#m7": [61, 68, 71, 76, 80],
    "DM7": [62, 69, 73, 76, 78], "Dm6": [62, 65, 69, 71, 74], "Bm7": [59, 66, 69, 74, 76],  # Bm7 は 11th 入り
    "E7sus4": [64, 69, 71, 74, 76], "Esus4": [64, 69, 71, 76, 81], "F#m7": [66, 69, 73, 76, 81],
}
ROOT = {"AM7": 33, "Aadd9": 33, "C#m7": 37, "DM7": 38, "Dm6": 38, "Bm7": 35, "E7sus4": 40, "Esus4": 40,
        "F#m7": 42}
INTRO = ["DM7", "Dm6", "AM7", "E7sus4"]
VERSE = ["AM7", "C#m7", "DM7", "Dm6"]
PRE = ["Bm7", "C#m7", "DM7", "Esus4"]
CHO = ["Bm7", "E7sus4", "C#m7", "F#m7", "Bm7", "E7sus4", "AM7", "Aadd9"]
DRP = ["DM7", "C#m7", "Bm7", "E7sus4"]
BRG = ["F#m7", "DM7", "Bm7", "Esus4"]
OUTRO = ["DM7", "Dm6", "AM7", "Aadd9"]

CLAP, SNARE, HAT, HAT_O, CRASH, REV, SHAKER, RIM = 39, 38, 42, 58, 51, 52, 82, 37
KICK = 33  # シンセの A1
P332 = (0, 3, 6, 8, 11, 14)  # 付点8分・付点8分・8分 ×2


def stabs(prog, vel=0.82):
    out = []
    for i, c in enumerate(prog):
        for k, pos in enumerate(P332):
            ln = (P332 + (16,))[k + 1] - pos
            out += [n(i * BAR + pos * S16, ln * S16 - 30, p, vel if pos in (0, 8) else vel * 0.86) for p in V[c][1:]]
    return out


def pulses(prog, vel=0.8):
    """ハーフタイム用：4分で刻むコード（サイドチェインで大きく揺れる）"""
    return [n(i * BAR + q * PPQ, PPQ - 40, p, vel) for i, c in enumerate(prog) for q in range(4) for p in V[c][1:]]


def held(prog, vel=0.55):
    return [n(i * BAR, BAR - 40, p, vel) for i, c in enumerate(prog) for p in V[c]]


def bass(prog, pos=(0, 6, 10)):
    out = []
    for i, c in enumerate(prog):
        r = ROOT[c]
        ps = list(pos) + [16]
        out += [n(i * BAR + a * S16, (b_ - a) * S16 - 30, r + (12 if a == 14 else 0), 0.95 if a == 0 else 0.85)
                for a, b_ in zip(ps, ps[1:])]
    return out


def arp332(prog, octave=12, vel=0.6):
    out = []
    for i, c in enumerate(prog):
        tones = V[c][1:]
        order = [0, 2, 3, 1, 3, 2]
        for k, pos in enumerate(P332):
            out.append(n(i * BAR + pos * S16, S16 * 2 - 20, tones[order[k] % len(tones)] + octave, vel))
    return out


def chop_motif(prog):
    """ドロップのチョップ：上の3声を 3-3-2 で歌わせる（全部コードの音）"""
    out = []
    for i, c in enumerate(prog):
        top = V[c][-3:]
        seq = [2, 1, 2, 0, 1, 2] if i % 2 == 0 else [2, 1, 0, 1, 2, 2]
        for k, pos in enumerate(P332):
            out.append(n(i * BAR + pos * S16, S16 * 2 - 30, top[seq[k]], 0.85 if pos in (0, 8) else 0.72))
    return out


def melody(spec, vel=0.88, shift=0):
    return [n(b * PPQ, l * PPQ - 30, p + shift, vel) for b, l, p, *_ in spec]


# 歌（書き下ろし）。(拍, 長さ, 音程, 音節)
A_LYR = [  # AM7 → C#m7 → DM7 → Dm6
    (0, .5, 73, "ki"), (.5, .5, 71, "ra"), (1, .5, 73, "ki"), (1.5, 1, 76, "ra"),
    (2.5, .5, 73, "hi"), (3, .5, 71, "ka"), (3.5, .5, 69, "ri"), (4, .5, 68, "ga"),
    (4.5, .5, 71, "yu"), (5, .5, 73, "re"), (5.5, 2, 76, "te"),
    (8, .5, 69, "ki"), (8.5, .5, 73, "mi"), (9, .5, 76, "to"), (9.5, .5, 73, "to"),
    (10, .5, 69, "mo"), (10.5, .5, 66, "da"), (11, 1, 69, "chi"),
    (12, .5, 69, "ni"), (12.5, .5, 71, "a"), (13, .5, 74, "u"), (13.5, 2, 69, "yo"),
]
B_LYR = [  # Bm7 → C#m7 → DM7 → Esus4
    (0, .5, 66, "ha"), (.5, .5, 69, "ya"), (1, 1, 71, "ku"),
    (2, .5, 69, "ha"), (2.5, .5, 71, "ya"), (3, 1, 74, "ku"),
    (4, .5, 76, "ko"), (4.5, .5, 76, "ko"), (5, .5, 73, "ro"), (5.5, .5, 71, "ga"),
    (6, .5, 73, "to"), (6.5, 1.5, 76, "bu"),
    (8, .5, 78, "so"), (8.5, .5, 76, "ra"), (9, .5, 73, "ma"), (9.5, 1.5, 76, "de"),
    (11, .5, 78, "to"), (11.5, .5, 80, "do"), (12, .5, 81, "ke"), (12.5, 3, 76, "yo"),
]
HOOK_LYR = [  # Bm7 → E7sus4 → C#m7 → F#m7 → Bm7 → E7sus4 → AM7 → Aadd9
    (0, .5, 78, "so"), (.5, .5, 76, "ra"), (1, .5, 74, "i"), (1.5, .5, 76, "ro"),
    (2, .5, 78, "no"), (2.5, .5, 81, "na"), (3, .5, 78, "ka"), (3.5, 1, 76, "de"),
    (5, .5, 74, "te"), (5.5, .5, 76, "o"), (6, .5, 78, "tsu"), (6.5, .5, 76, "na"), (7, .5, 74, "i"),
    (7.5, 1, 73, "de"),
    (9, .5, 73, "to"), (9.5, .5, 76, "N"), (10, .5, 80, "de"), (10.5, .5, 78, "i"), (11, .5, 76, "ko"),
    (11.5, .5, 73, "u"), (12, 1.5, 73, "yo"),
    (16, .5, 78, "ki"), (16.5, .5, 76, "mi"), (17, .5, 74, "to"), (17.5, .5, 76, "na"), (18, 1.5, 78, "ra"),
    (20, .5, 76, "ko"), (20.5, .5, 74, "wa"), (21, .5, 71, "ku"), (21.5, .5, 74, "na"), (22, 1.5, 76, "i"),
    (24, .5, 73, "wa"), (24.5, .5, 76, "ra"), (25, .5, 81, "e"), (25.5, .5, 80, "ru"), (26, 1, 76, "yo"),
    (27, .5, 76, "a"), (27.5, .5, 78, "o"), (28, .5, 80, "zo"), (28.5, 3, 81, "ra"),
]
# サビの合いの手（F#m7 の小節の後半）。チョップ「お」が C#–E–A
ANSWER = [n(13.5 * PPQ, PPQ // 2 - 30, 73, 0.75), n(14 * PPQ, PPQ // 2 - 30, 76, 0.75),
          n(14.5 * PPQ, PPQ * 1.5 - 30, 81, 0.8)]
# イントロ／アウトロのベルのモチーフ（D–Dm–A–E7sus4 の上で、どれもその小節のコードの音）
BELL_MOTIF = [(0, .75, 81), (.75, .75, 78), (1.5, .5, 76), (2, 1, 73), (3, .5, 76), (3.5, .5, 78),
              (4, .75, 81), (4.75, .75, 77), (5.5, .5, 74), (6, 2, 71),
              (8, .75, 80), (8.75, .75, 76), (9.5, .5, 73), (10, 1, 71), (11, .5, 73), (11.5, .5, 76),
              (12, .75, 81), (12.75, .75, 76), (13.5, .5, 74), (14, 2, 71)]


def hats(bars, dense=False, roll_last=False):
    out = []
    for b in range(bars):
        for s in range(16 if dense else 8):
            pos = s if dense else s * 2
            vel = 0.55 if pos % 4 == 0 else 0.3 if dense else 0.4
            out.append(n(b * BAR + pos * S16, S16, HAT, vel))
        if roll_last and b == bars - 1:
            out += [n(b * BAR + 12 * S16 + k * (S16 // 2), S16 // 2 - 6, HAT, 0.35 + 0.03 * k) for k in range(8)]
    return out


def ghost(bars, pos=(0, 4, 8, 12), skip_last_beat=False):
    out = []
    for b in range(bars):
        ps = [p for p in pos if not (skip_last_beat and b == bars - 1 and p >= 12)]
        out += steps(b, ps, S16 * 2, [KICK], 1.0)
    return out


def snare_roll():
    out = []
    for k in range(4):
        out.append(n(k * PPQ, PPQ - 20, SNARE, 0.45 + 0.08 * k))
    for k in range(8):
        out.append(n(BAR + k * PPQ // 2, PPQ // 2 - 15, SNARE, 0.5 + 0.04 * k))
    for k in range(16):
        out.append(n(2 * BAR + k * S16, S16 - 10, SNARE, 0.55 + 0.02 * k))
    for k in range(24):
        out.append(n(3 * BAR + k * (S16 // 2), S16 // 2 - 8, SNARE, 0.6 + 0.012 * k))
    return out


def with_sampler(b, name, sound, solo):
    tid = b.track(name, sound, solo)
    inst = b.tracks[-1]["instrument"]
    inst["type"] = "sampler"
    inst["sampler"] = sound["sampler"]
    return tid


SEC = dict(intro=0, idrop=4, verse=12, pre=20, cho=24, drop=40, bridge=48, pre2=52, last=56, outro=72)


def build(vocal=True, solo=None):
    b = AutoBuilder()
    names = [k for k in SOUNDS if vocal or k not in ("Vox", "Cons")]
    if not vocal:
        SOUNDS["Lead"]["mixer"] = dict(gain=0.5, pan=0)
    t = {}
    for name in names:
        t[name] = with_sampler(b, name, SOUNDS[name], solo) if "sampler" in SOUNDS[name] else b.track(name, SOUNDS[name], solo)
    CHD, PAD, PL, BE, PI, SUB = t["Chords"], t["Pad"], t["Pluck"], t["Bell"], t["Piano"], t["Sub"]
    K, GH, CL, H, RI, LE = t["Kick"], t["Ghost"], t["Clap"], t["Hats"], t["Riser"], t["Lead"]
    CA, CO = t["Chops"], t["Chops Oh"]
    CHO_AT = [24, 32, 56, 64]
    cut = lambda a_, b_, bars=4: [dict(param="cutoffHz", points=[[0, a_], [bars * BAR, b_]])]

    # ---- イントロ：ベルのモチーフとプラック（3-3-2）だけ。パッドは無し
    b.clip(BE, 4, melody(BELL_MOTIF, 0.85), [0, 72])
    b.clip(PL, 4, arp332(INTRO, 0, 0.62), [0])
    b.clip(PI, 4, held(INTRO, 0.4), [0])
    b.clip(H, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [RIM], 0.5)]
           + [x for bb in range(4) for x in steps(bb, range(0, 16, 2), S16, [SHAKER], 0.2)], [0])
    b.clip(H, 1, [n(2 * PPQ, 2 * PPQ, REV, 0.6)], [3])
    # ---- イントロドロップ（ハーフタイム、チョップのモチーフ）
    b.clip(CHD, 8, pulses(CHO, 0.85), [4], automation=cut(5500, 5500, 8))
    b.clip(PAD, 8, held(CHO, 0.5), [4, 24, 32, 56, 64])
    b.clip(CA, 4, chop_motif(CHO[:4]) + [], [4])
    b.clip(CA, 4, chop_motif(CHO[4:]), [8])
    b.clip(SUB, 8, bass(CHO, (0, 10)), [4])
    half_k = [x for bb in range(4) for x in steps(bb, [0, 10] if bb % 2 == 0 else [0, 3, 10], S16 * 2, [KICK], 1.0)]
    b.clip(K, 4, half_k, [4, 8, 40, 44])
    b.clip(GH, 4, ghost(4, (0, 8)), [4, 8, 40, 44])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [8], S16, [CLAP], 0.9)], [4, 8, 40, 44])
    b.clip(H, 4, hats(4, False, roll_last=True), [4, 8, 40, 44])
    b.clip(H, 1, [n(0, BAR, CRASH, 0.8)], [4, 24, 40, 56])
    # ---- Aメロ
    b.clip(PI, 4, held(VERSE, 0.6), [12, 16])
    b.clip(PL, 4, arp332(VERSE, 12, 0.5), [12, 16])
    b.clip(CHD, 4, stabs(VERSE, 0.6), [16], automation=cut(2500, 4500))
    b.clip(SUB, 4, bass(VERSE, (0, 8)), [12, 16])
    b.clip(K, 4, [x for bb in range(4) for x in steps(bb, [0, 8], S16 * 2, [KICK], 0.85)], [12, 16])
    b.clip(GH, 4, ghost(4), [12, 16])
    b.clip(H, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [RIM], 0.55)] + hats(4), [12, 16])
    # ---- Bメロ（ビルド）
    for at in (20, 52):
        b.clip(CHD, 4, stabs(PRE, 0.8), [at], automation=cut(3000, 7000))
    b.clip(PAD, 4, held(PRE, 0.55), [20, 52])
    b.clip(SUB, 4, bass(PRE, (0, 4, 8, 12)), [20, 52])
    b.clip(K, 4, [x for bb in range(3) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 0.95)], [20, 52])
    b.clip(GH, 4, ghost(4, skip_last_beat=True), [20, 52])
    b.clip(CL, 4, snare_roll(), [20, 52])
    b.clip(RI, 4, [n(0, 4 * BAR - PPQ, 60, 0.85)], [20, 52])
    b.clip(H, 4, [n(2 * BAR, 2 * BAR - PPQ, REV, 0.7)], [20, 52])
    # ---- サビ
    b.clip(CHD, 8, stabs(CHO, 0.95), CHO_AT, automation=cut(6500, 6500, 8))
    b.clip(SUB, 8, bass(CHO), CHO_AT)
    b.clip(PL, 8, arp332(CHO, 12, 0.45), [32, 64])
    drive = [x for bb in range(4) for x in steps(bb, [0, 6, 8] if bb < 3 else [0, 6, 8, 11, 14], S16 * 2, [KICK], 1.0)]
    b.clip(K, 4, drive, [24, 28, 32, 36, 56, 60, 64, 68])
    b.clip(GH, 4, ghost(4), [24, 28, 32, 36, 56, 60, 64, 68])
    b.clip(CL, 4, [x for bb in range(4) for x in steps(bb, [4, 12], S16, [CLAP], 0.9)], [24, 28, 32, 36, 56, 60, 64, 68])
    b.clip(H, 4, hats(4, True), [24, 28, 32, 36, 56, 60, 64, 68])
    b.clip(CO, 8, ANSWER, CHO_AT)
    # ---- ドロップ（ハーフタイム、降りる進行）
    b.clip(CHD, 4, pulses(DRP, 0.9), [40, 44], automation=cut(6000, 6000))
    b.clip(PAD, 4, held(DRP, 0.5), [40, 44])
    b.clip(CA, 4, chop_motif(DRP), [40, 44])
    b.clip(BE, 4, arp332(DRP, 12, 0.45), [44])
    b.clip(SUB, 4, bass(DRP, (0, 10)), [40, 44])
    # ---- ブリッジ
    b.clip(PI, 4, held(BRG, 0.6), [48])
    b.clip(PAD, 4, held(BRG, 0.5), [48])
    b.clip(CO, 4, [n(i * BAR, BAR // 2, V[c][-1], 0.6) for i, c in enumerate(BRG)], [48])
    # ---- アウトロ
    b.clip(PI, 4, held(OUTRO, 0.55), [72])
    b.clip(PAD, 4, held(OUTRO, 0.45), [72])
    b.clip(K, 1, [n(0, S16 * 2, KICK, 1)], [72])
    b.clip(H, 1, [n(0, BAR, CRASH, 0.6)], [72])

    # ---- 歌・リード
    gain = SOUNDS["Vox"]["mixer"]["gain"]
    if vocal:
        for lyr, bars, at, vib in ((A_LYR, 4, [12, 16], 0.1), (B_LYR, 4, [20, 52], 0.08), (HOOK_LYR, 8, CHO_AT, 0.14)):
            vox, va, cons, ca = sing(lyr, TEMPO, bars * BAR, fixed_formant=True, compensate=False, vibrato=vib,
                                     base_gain=gain)
            b.clip(t["Vox"], bars, vox, at, automation=va)
            b.clip(t["Cons"], bars, cons, at, automation=ca)
        b.clip(LE, 8, melody(HOOK_LYR, 0.45, -12), [32, 64])
    else:
        b.clip(LE, 8, melody(HOOK_LYR, 0.9), CHO_AT)
        b.clip(LE, 8, melody(HOOK_LYR, 0.5, 12), [64])
        b.clip(LE, 4, melody(A_LYR, 0.75), [12, 16])
        b.clip(LE, 4, melody(B_LYR, 0.8), [20, 52])

    song = dict(format="mobiledaw-project", version=1,
                title="そら色ステップ" if vocal else "そら色ステップ（インスト）",
                tempo=TEMPO, timeSig=[4, 4], key=dict(root=9, scale="major"),
                master=dict(gain=MASTER_GAIN[vocal], glue=0.6, thresholdDb=-10, ratio=1.8, softClip=0.35, ceiling=0.84),
                aux=dict(reverbReturn=0.85, reverbSize=0.6, delayReturn=0.45, delayFeedback=0.3),
                tracks=b.tracks, clips=b.clips, placements=b.placements)
    return song


MASTER_GAIN = {True: 3.3, False: 3.8}


def main():
    args = sys.argv[1:]
    which = "both"
    if args and args[0] in ("vocal", "inst", "both"):
        which = args.pop(0)
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    jobs = []
    if which in ("vocal", "both"):
        jobs.append((True, args[0] if args and which == "vocal" else OUT_VOCAL))
    if which in ("inst", "both"):
        jobs.append((False, args[0] if args and which == "inst" else OUT_INST))
    for vocal, path in jobs:
        # インストはリード音量を戻すため、辞書を汚さないよう都度コピーは SOUNDS を関数内で触っている。
        # 歌入りのあとにインストを作ると Lead の gain が残るので、ここで戻す。
        SOUNDS["Lead"]["mixer"] = dict(gain=0.36, pan=0.05)
        data = build(vocal=vocal, solo=solo)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(path, "tracks", len(data["tracks"]), "bars", max(p["startBar"] + p["lengthBars"] for p in data["placements"]))


if __name__ == "__main__":
    main()
