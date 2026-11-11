#!/usr/bin/env python3
"""ブルアカ風かわいいフューチャーベース「そら色ステップ」。

  python3 tools/demos/buruaka.py                 # 歌入りとインストの両方
  python3 tools/demos/buruaka.py vocal|inst [出力先]

150 BPM / E♭ major / 64小節（約1分42秒）。
既存の future_bass（F・150）や kawaii2（D・155、GM9→A9→F#m9→Bm9）とは
キーも進行もメロディも別。歌は固定Hzのフォルマントで高い音域のまま母音を保つ。
ドラムのキックはシンセで E♭ に合わせる（キットの E チューンのキックは使わない）。
音程のあるパーカッション（Bubble / Chime / Impact）は使わない。
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16
from singer import AutoBuilder, sing

TEMPO = 150.0
OUT_VOCAL = "app/assets/demos/buruaka.json"
OUT_INST = "app/assets/demos/buruaka_inst.json"

# 未来ベース用の明るいスーパーソー。各スタブが -2 半音から戻る。8分で音量も揺れる
CHORD = dict(
    wtTable=5, wtPos=0.62, unison=8, detuneCents=28, width=1.0, blend=0.72, noise=0.02,
    cutoffHz=9000, resonance=0.75, keyTrack=0.45, filterEnv=0.25, filterEnvDecayS=0.12,
    pitchEnv=-2, pitchEnvDecayS=0.09,
    lfoSync=1, lfoRetrig=1, lfoDiv=3, lfoWave=1, lfoAmp=0.45,
    attackS=0.004, decayS=0.22, sustain=0.35, releaseS=0.12, masterGain=0.5,
)
SOUNDS = {
    "Chords": dict(
        color="fff7a8d8",
        synth=dict(CHORD),
        fx=dict(lowCutHz=250, saturation=0.08, chorus=0.22, ott=0.45, reverb=0.08, reverbSize=0.6,
                eqHighDb=2, eqHighHz=8000, sidechain=0.92, sidechainAttackS=0.004, sidechainHoldS=0.03,
                sidechainReleaseS=0.2, sidechainCurve=2.4, sendReverb=0.28),
        mixer=dict(gain=0.42, pan=0),
    ),
    "Pad": dict(
        color="ffd89af2",
        synth=dict(wtTable=7, wtPos=0.35, wtLfoRate=0.25, wtLfoAmount=0.2, unison=6, detuneCents=18,
                   width=0.9, blend=0.75, cutoffHz=4200, attackS=0.45, decayS=0.8, sustain=0.85,
                   releaseS=1.2, masterGain=0.4, lfoPitch=0.04),
        fx=dict(lowCutHz=200, chorus=0.3, reverb=0.15, sendReverb=0.4, sidechain=0.55, sidechainReleaseS=0.28),
        mixer=dict(gain=0.34, pan=0.05),
    ),
    "Pluck": dict(
        color="ff5ad6c0",
        synth=dict(wtTable=6, wtPos=0.35, unison=2, detuneCents=8, width=0.55, cutoffHz=5200, resonance=1.2,
                   filterEnv=0.55, filterEnvDecayS=0.1, attackS=0.001, decayS=0.18, sustain=0, releaseS=0.16,
                   masterGain=0.55),
        fx=dict(lowCutHz=300, delay=0.12, sendDelay=0.28, sendReverb=0.16, sidechain=0.4, sidechainReleaseS=0.18),
        mixer=dict(gain=0.32, pan=-0.35),
    ),
    "Bell": dict(  # 2オペレーターFM。比率 3.5 で鉄琴っぽい部分音
        color="ffffe066",
        synth=dict(osc=0.15, fm=0.85, fmRatio=3.5, unison=2, detuneCents=6, width=0.4,
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
        mixer=dict(gain=0.32, pan=-0.1),
    ),
    "Chops": dict(
        color="ffff7ab8",
        sampler=dict(kit="kawaii-oneshots", sound="Ah", rootNote=60, gain=1.1, start=0),
        synth=dict(masterGain=0.8, unison=1),
        fx=dict(lowCutHz=200, sendDelay=0.2, sendReverb=0.12, sidechain=0.35, sidechainReleaseS=0.14),
        mixer=dict(gain=0.48, pan=0.15),
    ),
    "Chops Oh": dict(
        color="ffffb0d0",
        sampler=dict(kit="kawaii-oneshots", sound="Oh", rootNote=60, gain=1.0, start=0),
        synth=dict(masterGain=0.7, unison=1),
        fx=dict(lowCutHz=180, sendReverb=0.18, sidechain=0.3, sidechainReleaseS=0.14),
        mixer=dict(gain=0.36, pan=-0.2),
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
        fx=dict(lowCutHz=180, chorus=0.08, ott=0.15, eqHighDb=1.5, eqHighHz=7000,
                comp=0.35, compThresholdDb=-16, compRatio=3, compMakeupDb=1,
                sendDelay=0.16, sendReverb=0.22, sidechain=0.28, sidechainReleaseS=0.14),
        mixer=dict(gain=0.42, pan=0),
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
        synth=dict(osc=0.15, sub=1.0, unison=1, cutoffHz=220, resonance=0.6,
                   attackS=0.005, decayS=0.2, sustain=0.9, releaseS=0.08, masterGain=0.85),
        fx=dict(eqLowDb=1.5, eqLowHz=70, eqHighDb=-6, eqHighHz=400,
                comp=0.4, compThresholdDb=-18, compRatio=4, sidechain=0.7, sidechainReleaseS=0.18),
        mixer=dict(gain=0.34, pan=0),
    ),
    "Kick": dict(  # ノート 39 = E♭2。ピッチエンベロープで胴が落ちる
        color="fff28c38",
        synth=dict(osc=0.35, sub=1.0, unison=1, cutoffHz=900, resonance=0.7, keyTrack=0,
                   pitchEnv=30, pitchEnvDecayS=0.04, filterEnv=0.85, filterEnvDecayS=0.03,
                   attackS=0.0005, decayS=0.28, sustain=0, releaseS=0.04, masterGain=1.0),
        fx=dict(saturation=0.3, eqLowDb=2, eqLowHz=70, eqMidDb=-2.5, eqMidHz=300,
                comp=0.4, compThresholdDb=-12, compRatio=3.5),
        mixer=dict(gain=0.4, pan=0),
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
        fx=dict(lowCutHz=180, eqMidDb=1.5, eqMidHz=2000, comp=0.25, sendReverb=0.16),
        mixer=dict(gain=0.32, pan=0.02),
    ),
    "Hats": dict(
        color="ffb0b6c0", kit="future-bass-pro", synth=dict(masterGain=1, unison=1),
        fx=dict(lowCutHz=400, eqHighDb=2, eqHighHz=9000),
        mixer=dict(gain=0.22, pan=0.28),
    ),
    "Riser": dict(
        color="ffeeeeee",
        synth=dict(osc=0, noise=1, unison=1, cutoffHz=8000, resonance=1.4, keyTrack=0,
                   attackS=6.0, decayS=0.4, sustain=1, releaseS=0.15, masterGain=0.55),
        fx=dict(lowCutHz=500, sendReverb=0.3),
        mixer=dict(gain=0.32, pan=0),
    ),
}

V = {
    "AbM9": [56, 60, 63, 67, 70], "Bb": [58, 62, 65, 70], "Gm7": [55, 58, 62, 65],
    "Cm9": [60, 63, 67, 70, 74], "Fm9": [53, 56, 60, 63, 67], "Bbsus": [58, 63, 65],
    "Bb7": [58, 62, 65, 68], "EbM9": [63, 67, 70, 74, 77], "Eb7": [63, 67, 70, 73],
    "Ebadd9": [63, 67, 70, 74, 77],
}
ROOT = {"AbM9": 44, "Bb": 46, "Gm7": 43, "Cm9": 48, "Fm9": 41, "Bbsus": 46,
        "Bb7": 46, "EbM9": 39, "Eb7": 39, "Ebadd9": 39}
VERSE = ["AbM9", "Bb", "Gm7", "Cm9"]
BUILD = ["Fm9", "Gm7", "AbM9", "Bbsus"]
DROP = ["AbM9", "Bb", "Gm7", "Cm9", "Fm9", "Bb7", "EbM9", "Eb7"]
LAST = ["AbM9", "Bb", "Gm7", "Cm9", "Fm9", "Bb7", "EbM9", "Ebadd9"]

CLAP, SNARE, HAT, HAT_O, CRASH, REV, SHAKER = 39, 38, 42, 58, 51, 52, 82
KICK = 39  # シンセの E♭2


def stabs(prog, vel=0.82):
    out = []
    for i, c in enumerate(prog):
        for pos in (0, 3, 6, 10, 14):
            out += [n(i * BAR + pos * S16, S16 * 2 - 20, p, vel if pos in (0, 10) else vel * 0.85) for p in V[c]]
    return out


def held(prog, vel=0.55):
    return [n(i * BAR, BAR - 40, p, vel) for i, c in enumerate(prog) for p in V[c]]


def bass(prog):
    out = []
    for i, c in enumerate(prog):
        r = ROOT[c]
        out += [n(i * BAR, S16 * 6, r, 0.95), n(i * BAR + 8 * S16, S16 * 6, r, 0.85),
                n(i * BAR + 14 * S16, S16 * 2 - 20, r + 12, 0.7)]
    return out


def arp(prog):
    out = []
    for i, c in enumerate(prog):
        tones = V[c]
        for k in range(8):
            out.append(n(i * BAR + k * S16 * 2, S16 * 2 - 30, tones[k % len(tones)] + 12, 0.6))
    return out


def melody(spec, vel=0.88):
    return [n(b * PPQ, l * PPQ - 30, p, vel) for b, l, p in spec]


# サビのフック。6度の跳躍のあと階段で降り、6小節目で一番高い音。音域は10度
HOOK = [
    (0, .7, 70), (.7, .7, 79), (1.5, .5, 77), (2, 1, 75), (3, .5, 74), (3.5, .5, 72),
    (4, .5, 72), (4.5, .5, 72), (5, .75, 70), (5.75, .75, 68), (6.5, 1.5, 67),
    (8, .7, 70), (8.7, .7, 79), (9.5, .5, 77), (10, .5, 75), (10.5, .5, 74), (11, 1, 72),
    (12, 1, 74), (13, .5, 75), (13.5, .5, 77), (14, 2, 79),
    (16, .7, 72), (16.7, .7, 81), (17.5, .5, 79), (18, 1, 77), (19, .5, 75), (19.5, .5, 74),
    (20, .5, 74), (20.5, .5, 74), (21, .75, 72), (21.75, .75, 70), (22.5, 1.5, 67),
    (24, .75, 75), (24.75, .75, 79), (25.5, .5, 77), (26, 1, 75), (27, 1, 74),
    (28, 1.5, 72), (29.5, .5, 70), (30, 2, 67),
]


def line(start, spec, syls):
    s = syls.split()
    assert len(s) == len(spec), (syls, len(s), len(spec))
    return [(start + b, l, p, x) for (b, l, p), x in zip(spec, s)]


# 歌（書き下ろし。放課後の光と友だち。キャラクター名や既存曲の文句は使わない）
A1 = [(0, .5, 70), (.5, .5, 72), (1, .5, 75), (1.5, .5, 72),
      (2.5, .75, 70), (3.25, .75, 67), (4, 1, 68), (5, .5, 70),
      (6, 1, 72), (7, .5, 70), (7.5, .5, 67)]
A2 = [(0, .5, 72), (.5, .5, 74), (1, .75, 75), (2, .5, 70), (2.5, .5, 72),
      (3, .5, 74), (3.5, .5, 75), (4, .75, 72), (5, .75, 70), (6, .5, 67), (6.5, 1.5, 75)]
B1 = [(0, .5, 74), (.5, .5, 75), (1, .5, 77), (1.5, .5, 75), (2, .5, 74), (2.5, .5, 72),
      (3, .5, 70), (3.5, .5, 72), (4, .75, 74), (5, .5, 75), (5.5, 1, 79), (6.5, 1, 77)]
B2 = [(0, .75, 75), (1, .5, 74), (1.5, .75, 72), (2.5, .5, 70), (3, .5, 72),
      (3.5, .75, 74), (4.5, 1, 75), (6, 2, 79)]
SABI_SYL = "so ra i ro su te p pu to n de i ko u".split()
# フックの音の数に歌詞を合わせる（32音は長いので、フックの前半16音＋後半は繰り返しの変形）
SABI_A = HOOK[:16]
SABI_B = HOOK[16:]


def lyric_hook(spec, text):
    syls = text.split()
    assert len(syls) == len(spec), (len(syls), len(spec), text)
    return [(b, l, p, s) for (b, l, p), s in zip(spec, syls)]


def chops_of(spec, every=2):
    return [n(b * PPQ, min(l, 0.35) * PPQ, p, 0.8) for i, (b, l, p) in enumerate(spec) if i % every == 0]


def hats(bars, dense=False):
    out = []
    for b in range(bars):
        for s in range(16 if dense else 8):
            pos = s if dense else s * 2
            vel = 0.55 if pos % 4 == 0 else 0.32
            out.append(n(b * BAR + pos * S16, S16, HAT, vel))
        if dense:
            for pos in (2, 6, 10, 14):
                out.append(n(b * BAR + pos * S16, S16 * 2, HAT_O, 0.4))
    return out


def kick_half(bars, jersey_last=False):
    out = []
    for b in range(bars):
        pat = [0, 8, 10, 12, 14] if jersey_last and b == bars - 1 else [0, 10]
        out += steps(b, pat, S16 * 2, [KICK], 1.0)
    return out


def ghost(bars, skip_last_beat=False):
    out = []
    for b in range(bars):
        pos = [0, 4, 8] if skip_last_beat and b == bars - 1 else [0, 4, 8, 12]
        out += steps(b, pos, S16 * 2, [KICK], 1.0)
    return out


def snare_roll():
    out = []
    # 4分 → 8分 → 16分 → 32分。最後の拍は空ける
    for k in range(4):
        out.append(n(k * PPQ, PPQ - 20, SNARE, 0.45 + 0.08 * k))
    for k in range(8):
        out.append(n(BAR + k * PPQ // 2, PPQ // 2 - 15, SNARE, 0.5 + 0.04 * k))
    for k in range(16):
        out.append(n(2 * BAR + k * S16, S16 - 10, SNARE, 0.55 + 0.02 * k))
    for k in range(24):  # 32分だが最後の8つ（1拍）は置かない
        out.append(n(3 * BAR + k * (S16 // 2), S16 // 2 - 8, SNARE, 0.6 + 0.012 * k))
    return out


def with_sampler(b, name, sound, solo):
    tid = b.track(name, sound, solo)
    inst = b.tracks[-1]["instrument"]
    inst["type"] = "sampler"
    inst["sampler"] = sound["sampler"]
    return tid


def build(vocal=True, solo=None):
    b = AutoBuilder()
    names = [k for k in SOUNDS if vocal or k not in ("Vox", "Cons")]
    if not vocal:
        SOUNDS["Lead"]["mixer"] = dict(gain=0.55, pan=0)
    t = {}
    for name in names:
        if "sampler" in SOUNDS[name]:
            t[name] = with_sampler(b, name, SOUNDS[name], solo)
        else:
            t[name] = b.track(name, SOUNDS[name], solo)

    L4 = 4 * BAR
    b.clip(t["Pad"], 4, held(VERSE, 0.5), [0, 4, 8, 12, 16, 20, 48, 52])
    b.clip(t["Pad"], 4, held(DROP[:4], 0.55), [32, 36, 40, 44, 56, 60])
    b.clip(t["Chords"], 4, stabs(VERSE, 0.7), [0, 4], automation=[
        dict(param="cutoffHz", points=[[0, 1800], [4 * BAR, 5200]])])
    b.clip(t["Chords"], 4, stabs(VERSE), [8, 12, 16, 20])
    b.clip(t["Chords"], 4, stabs(BUILD, 0.9), [24, 28])
    b.clip(t["Chords"], 4, stabs(DROP[:4], 0.95), [32, 36, 40, 44])
    b.clip(t["Chords"], 4, stabs(DROP[4:], 0.95), [32 + 4, 40 + 4])  # 各8小節の後半は別クリップで置き直す
    # 上の配置は 4小節クリップを 32 と 36 に置くと 32-39 が DROP前半の繰り返しになる。
    # 後半進行は 36 を上書きできない（同じ小節に2つ置けるが重なる）。
    # 8小節クリップでドロップ進行を置く。
    b.clips = [c for c in b.clips if not (c["trackId"] == t["Chords"] and c["lengthTicks"] == 4 * BAR and any(
        p["clipId"] == c["id"] and p["startBar"] >= 32 for p in b.placements))]
    b.placements = [p for p in b.placements if not (p["trackId"] == t["Chords"] and p["startBar"] >= 32)]
    b.clip(t["Chords"], 8, stabs(DROP, 0.95), [32, 40])
    b.clip(t["Chords"], 8, stabs(LAST, 0.95), [56])
    b.clip(t["Chords"], 4, held(VERSE, 0.6), [48, 52])

    b.clip(t["Pluck"], 4, arp(VERSE), [0, 4, 48, 52])
    b.clip(t["Bell"], 4, arp(VERSE), [0, 48])
    b.clip(t["Sub"], 4, bass(VERSE), [8, 12, 16, 20, 32, 36, 40, 44, 56, 60])
    b.clip(t["Sub"], 4, bass(BUILD), [24, 28])

    b.clip(t["Piano"], 4, held(VERSE, 0.7), [48, 52])
    b.clip(t["Piano"], 2, [n(0, 2 * BAR - 80, p, 0.75) for p in V["Ebadd9"]], [62])

    # リード：インストはサビのメロディが主役。歌入りはサビで3度下を薄く重ねる
    lead_hook = [(b, l, p - 3, ) for b, l, p in HOOK] if vocal else [(b, l, p) for b, l, p in HOOK]
    # melody() expects triples
    b.clip(t["Lead"], 8, melody(lead_hook, 0.7 if vocal else 0.9), [32, 56] if vocal else [32, 40, 56])
    if not vocal:
        b.clip(t["Lead"], 8, melody([(b, l, p + 12) for b, l, p in HOOK], 0.55), [40])

    if vocal:
        a_lyr = line(0, A1, "ki ra ki ra hi ka ri ga yu re te") + line(8, A2, "ki mi to to mo da chi ni a u yo")
        vox, va, cons, ca = sing(a_lyr, TEMPO, 4 * BAR, fixed_formant=True, compensate=False, vibrato=0.1)
        b.clip(t["Vox"], 4, vox, [8, 12, 16, 20], automation=va)
        b.clip(t["Cons"], 4, cons, [8, 12, 16, 20], automation=ca)
        b_lyr = line(0, B1, "ha ya ku ha ya ku ko ko ro ga to bu") + line(8, B2, "so ra ma de to do ke yo")
        # B1 は11、B2 は8。line() が数を確かめる
        vox, va, cons, ca = sing(b_lyr, TEMPO, 4 * BAR, fixed_formant=True, compensate=False, vibrato=0.08)
        b.clip(t["Vox"], 4, vox, [24], automation=va)
        b.clip(t["Cons"], 4, cons, [24], automation=ca)
        hook_syl = (
            "so ra i ro no na ka de "
            "te o tsu na i de "
            "to N de i ko u yo "
            "ki mi to na ra "
            "ko wa ku na i "
            "wa ra e ru yo "
            "a o zo ra"
        ).split()
        assert len(hook_syl) == len(HOOK), (len(hook_syl), len(HOOK))
        hook_lyr = [(b, l, p, s) for (b, l, p), s in zip(HOOK, hook_syl)]
        vox, va, cons, ca = sing(hook_lyr, TEMPO, 8 * BAR, fixed_formant=True, compensate=False, vibrato=0.14)
        b.clip(t["Vox"], 8, vox, [32, 40, 56], automation=va)
        b.clip(t["Cons"], 8, cons, [32, 40, 56], automation=ca)

    b.clip(t["Chops"], 8, chops_of(HOOK, 2), [32, 40, 56])
    b.clip(t["Chops Oh"], 8, chops_of(HOOK[1:], 2), [32, 40])

    # ドラム
    b.clip(t["Kick"], 4, kick_half(4), [8, 12, 16, 20])
    b.clip(t["Kick"], 4, [x for bb in range(3) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 0.95)], [24])
    b.clip(t["Kick"], 4, kick_half(4, jersey_last=True), [32, 36, 40, 44, 56, 60])
    b.clip(t["Ghost"], 4, ghost(4), [8, 12, 16, 20, 32, 36, 40, 44, 56, 60])
    b.clip(t["Ghost"], 4, ghost(4, skip_last_beat=True), [24, 28])
    b.clip(t["Clap"], 4, [x for bb in range(4) for x in steps(bb, [8], S16, [CLAP], 0.9)], [8, 12, 16, 20, 32, 36, 40, 44, 56, 60])
    b.clip(t["Clap"], 4, snare_roll(), [28])
    b.clip(t["Hats"], 4, hats(4, False), [4, 8, 12, 16, 20])
    b.clip(t["Hats"], 4, hats(4, True), [32, 36, 40, 44, 56, 60])
    b.clip(t["Hats"], 1, [n(0, BAR, CRASH, 0.85)], [32, 40, 56])
    b.clip(t["Hats"], 4, [n(2 * BAR, 2 * BAR, REV, 0.75)], [48])
    b.clip(t["Hats"], 4, [n(bb * BAR + (3 if bb % 2 == 0 else 11) * S16, S16, SHAKER, 0.45) for bb in range(4)], [8, 16])
    b.clip(t["Riser"], 4, [n(0, 4 * BAR - PPQ, 60, 0.85)], [28])
    # 終わりの一発
    b.clip(t["Kick"], 1, [n(0, S16 * 2, KICK, 1)], [63])
    b.clip(t["Chords"], 1, [n(0, BAR - 40, p, 0.8) for p in V["Ebadd9"]], [63])

    song = dict(format="mobiledaw-project", version=1,
                title="そら色ステップ" if vocal else "そら色ステップ（インスト）",
                tempo=TEMPO, timeSig=[4, 4], key=dict(root=3, scale="major"),
                master=dict(gain=2.5 if vocal else 3.3, glue=0.8, thresholdDb=-13, ratio=1.8, softClip=0.55, ceiling=0.93),
                aux=dict(reverbReturn=0.85, reverbSize=0.62, delayReturn=0.5, delayFeedback=0.32),
                tracks=b.tracks, clips=b.clips, placements=b.placements)
    return song


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
