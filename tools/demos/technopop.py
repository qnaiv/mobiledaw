#!/usr/bin/env python3
"""テクノポップのボーカル入りデモ曲「ネオン・シグナル」（project.json）を作る。

  python3 tools/demos/technopop.py [出力先] [--solo トラック名]

128 BPM / B♭ major / 38小節（約1分11秒）
  小節  0– 3  イントロ   4つ打ち、オクターブで跳ねるベース、16分のアルペジオ
        4–11  Aメロ      シンセが歌う（Vox＋子音のノイズ Cons）
       12–19  Bメロ      ハーフタイムのキックで溜める。最後の2小節はスネアロールとライザー
       20–27  サビ       クラッシュから全部入り：スーパーソーのコード、1オクターブ上のダブル（Vox Hi）
       28–35  サビ2      さらに3度下のハモり（Vox Harm）。最後は主和音で解決
       36–37  エンディング
進行  イントロ           E♭M7 → F → Dm7 → Gm7（IV–V–iii–vi）
      Aメロ              Gm7 → E♭M7 → F → Dm7
      Bメロ              E♭M7 → F → Dm7 → Gm7 / E♭M7 → F → Cm7 → F
      サビ               E♭M7 → F → Dm7 → Gm7 / E♭M7 → F → B♭ → B♭
歌詞（作詞：デモ用書き下ろし）
  Aメロ  よるの まちに ひかる / ネオンの シグナル / きみの こえが きこえる / デジタルの むこうへ
  Bメロ  ピコピコ ハートが とまらない / ふたりの リズムで おどろうよ
         ピコピコ ハートが とまらない / せかいが ひかるまで ずっと
  サビ   きらきら ネオン シグナル / きみに とどけ いますぐ
         きらきら ネオン シグナル / ふたりの よるは おわらない
歌わせ方は singer.py（音節ごとの母音フォルマント・子音ノイズ・レガート・ビブラート）
"""
import json
import sys

from future_bass import n, steps, PPQ, BAR, S16
from singer import AutoBuilder, sing

TEMPO = 128.0
T = -7  # 曲は F で書いて B♭ に移す（コード -7、歌 -19 で男声の低めの音域＝フォルマント表が一番母音らしく鳴る高さ）
VOX_GAIN = 0.95

SOUNDS = {
    "Vox": dict(  # 歌うシンセ：フォルマント表＋モノ＋グライド
        color="ffff7ab8",
        synth=dict(wtTable=3, wtPos=0.0, wtWarp=0, unison=2, detuneCents=6, width=0.15, blend=0.9,
                   mono=1, glideS=0.055, wtLfoRate=5.6, lfoPitch=0.0, keyTrack=0.0,
                   cutoffHz=5200, resonance=1.3, drive=0.12, noise=0.015,
                   attackS=0.012, decayS=0.25, sustain=0.85, releaseS=0.07, masterGain=0.75),
        fx=dict(lowCutHz=90, saturation=0.12, chorus=0.1, ott=0.22, delay=0.08, delayFeedback=0.22,
                reverb=0.1, reverbSize=0.5, sidechain=0.1, sidechainReleaseS=0.15,
                eqMidDb=2.0, eqMidHz=2800, eqMidQ=1.1, eqHighDb=1.2, eqHighHz=9000,
                comp=0.4, compThresholdDb=-16, compRatio=3, compAttackMs=8, compReleaseMs=90, compMakeupDb=1.5,
                sendReverb=0.28, sendDelay=0.12),
        mixer=dict(gain=VOX_GAIN, pan=0),
    ),
    "Cons": dict(  # 子音のノイズ（帯域は音節ごとにオートメーション）
        color="ffffc2e0",
        synth=dict(osc=0, noise=1.0, unison=1, cutoffHz=8000, resonance=1.2, keyTrack=0.0,
                   attackS=0.001, decayS=0.06, sustain=0.75, releaseS=0.025, masterGain=0.8),
        fx=dict(lowCutHz=2000, reverb=0.04, eqHighDb=1.5, eqHighHz=8000, sendReverb=0.08),
        mixer=dict(gain=1.4, pan=0),
    ),
    "Vox Hi": dict(  # サビ2：1オクターブ上のダブル（ボコーダー風のきらめき）
        color="ffd88ad0",
        synth=dict(wtTable=3, wtPos=0.0, unison=3, detuneCents=14, width=0.7, blend=0.8,
                   mono=1, glideS=0.055, wtLfoRate=5.6, keyTrack=0.0,
                   cutoffHz=5200, resonance=1.0, drive=0.05,
                   attackS=0.015, decayS=0.25, sustain=0.8, releaseS=0.08, masterGain=0.6),
        fx=dict(lowCutHz=350, chorus=0.35, ott=0.15, delay=0.1, delayFeedback=0.25, reverb=0.12, reverbSize=0.6,
                eqHighDb=1.5, eqHighHz=10000, sendReverb=0.22, sendDelay=0.2),
        mixer=dict(gain=1.2, pan=0.25),
    ),
    "Vox Harm": dict(  # サビ2：3度下のハモり
        color="ffb070c0",
        synth=dict(wtTable=3, wtPos=0.0, unison=2, detuneCents=8, width=0.4, blend=0.9,
                   mono=1, glideS=0.055, wtLfoRate=5.3, keyTrack=0.0,
                   cutoffHz=4500, resonance=1.1, drive=0.08,
                   attackS=0.015, decayS=0.25, sustain=0.8, releaseS=0.08, masterGain=0.6),
        fx=dict(lowCutHz=120, chorus=0.22, ott=0.15, reverb=0.1, reverbSize=0.55,
                eqLowDb=-1, eqMidDb=1, eqMidHz=1800, sendReverb=0.2),
        mixer=dict(gain=0.9, pan=-0.25),
    ),
    "Arp": dict(  # 16分のチップっぽいアルペジオ
        color="ff5ad6c0",
        synth=dict(wave=1, unison=1, cutoffHz=4200, resonance=1.4, filterEnv=0.4, filterEnvDecayS=0.08,
                   attackS=0.001, decayS=0.12, sustain=0.2, releaseS=0.06, masterGain=0.6),
        fx=dict(lowCutHz=400, delay=0.14, delayFeedback=0.3, reverb=0.08, reverbSize=0.45,
                sidechain=0.35, sidechainReleaseS=0.15, eqHighDb=1.5, eqHighHz=8000, sendDelay=0.28),
        mixer=dict(gain=0.28, pan=0.35),
    ),
    "Stab": dict(  # 明るいのこぎりのコードスタブ
        color="ffc8f25a",
        synth=dict(unison=5, detuneCents=22, width=0.85, blend=0.7, cutoffHz=3800, resonance=0.9,
                   filterEnv=0.35, filterEnvDecayS=0.15, attackS=0.002, decayS=0.25, sustain=0.35,
                   releaseS=0.12, masterGain=0.55),
        fx=dict(lowCutHz=260, chorus=0.2, ott=0.22, reverb=0.1, reverbSize=0.55,
                sidechain=0.6, sidechainReleaseS=0.18, eqMidDb=1.5, eqMidHz=2000, comp=0.25,
                compThresholdDb=-18, compRatio=3, sendReverb=0.18),
        mixer=dict(gain=0.3, pan=-0.2),
    ),
    "Pad": dict(  # サビのパッド（ウェーブテーブル Choir で柔らかく）
        color="ff9a7cf2",
        synth=dict(wtTable=7, wtPos=0.6, wtLfoRate=0.3, wtLfoAmount=0.3, unison=6, detuneCents=25,
                   width=0.95, blend=0.8, cutoffHz=4500, resonance=0.8,
                   attackS=0.25, decayS=0.5, sustain=0.85, releaseS=0.5, masterGain=0.5),
        fx=dict(lowCutHz=300, chorus=0.25, reverb=0.18, reverbSize=0.7, sidechain=0.7, sidechainReleaseS=0.25,
                eqLowDb=-1.5, eqHighDb=-1, sendReverb=0.4),
        mixer=dict(gain=0.3, pan=0.1),
    ),
    "Bass": dict(  # オクターブで跳ねるシンセベース
        color="ff5aa9f2",
        synth=dict(wave=1, unison=1, cutoffHz=900, resonance=1.6, filterEnv=0.45, filterEnvDecayS=0.09,
                   sub=0.55, drive=0.25, attackS=0.002, decayS=0.15, sustain=0.5, releaseS=0.04,
                   masterGain=0.75),
        fx=dict(saturation=0.15, sidechain=0.45, sidechainReleaseS=0.12,
                eqLowDb=2.5, eqLowHz=90, eqHighDb=-3, eqHighHz=3200,
                comp=0.5, compThresholdDb=-18, compRatio=4, compAttackMs=6, compReleaseMs=80, compMakeupDb=1),
        mixer=dict(gain=0.32, pan=0),
    ),
    "Saw": dict(  # サビだけのスーパーソー（広く厚く、キックで大きく引っ込む）
        color="ffffe066",
        synth=dict(unison=9, detuneCents=32, width=1.0, blend=0.75, cutoffHz=9000, resonance=0.8,
                   attackS=0.006, decayS=0.6, sustain=0.85, releaseS=0.3, noise=0.02, masterGain=0.5),
        fx=dict(lowCutHz=280, chorus=0.22, ott=0.35, reverb=0.12, reverbSize=0.65, sidechain=0.85,
                sidechainReleaseS=0.2, eqHighDb=1, eqHighHz=8000, comp=0.25, compThresholdDb=-16,
                sendReverb=0.22),
        mixer=dict(gain=0.24, pan=0)),
    "Riser": dict(  # Bメロ終わりのノイズのライザー
        color="ffdddddd",
        synth=dict(osc=0, noise=1.0, unison=1, cutoffHz=7000, resonance=1.6, keyTrack=0.0,
                   attackS=3.6, decayS=0.5, sustain=1.0, releaseS=0.2, masterGain=0.6),
        fx=dict(lowCutHz=400, reverb=0.15, reverbSize=0.7, sendReverb=0.3),
        mixer=dict(gain=0.42, pan=0)),
    "Kick": dict(color="fff28c38", kit="house",
                 synth=dict(masterGain=1.0, unison=1),
                 fx=dict(saturation=0.2, sidechainSource=1, eqLowDb=2, eqLowHz=70, eqMidDb=-2.5, eqMidHz=320,
                        comp=0.45, compThresholdDb=-14, compRatio=4, compAttackMs=4, compMakeupDb=1),
                 mixer=dict(gain=0.2, pan=0)),
    "Clap": dict(color="fff2d45a", kit="house", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(lowCutHz=180, reverb=0.05, eqMidDb=2, eqMidHz=2200, eqHighDb=1, sendReverb=0.14,
                        comp=0.3, compThresholdDb=-14, compRatio=3),
                 mixer=dict(gain=0.2, pan=0)),
    "Hats": dict(color="ffb0b6c0", kit="house", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(lowCutHz=350, sidechain=0.15, sidechainReleaseS=0.1, eqHighDb=2.5, eqHighHz=10000),
                 mixer=dict(gain=0.22, pan=0.25)),
}

# ---- コード（F で書いて T で移調） -----------------------------------------------
V = {
    "Dm7": ([57, 60, 62, 65, 69], 38), "BbM7": ([58, 62, 65, 69, 70], 34), "C": ([60, 64, 67, 72], 36),
    "Am7": ([57, 60, 64, 67, 72], 33), "F": ([57, 60, 65, 69, 72], 29), "Gm7": ([58, 62, 65, 67, 70], 31),
    "Fadd9": ([57, 60, 65, 67, 72], 29),
}
BMELO2 = ["BbM7", "C", "Gm7", "C"]
SABI = ["BbM7", "C", "Am7", "Dm7"]
SABI2 = ["BbM7", "C", "F", "Fadd9"]
INTRO = ["BbM7", "C", "Am7", "Dm7"]
VERSE = ["Dm7", "BbM7", "C", "Am7"]
CHORUS = ["BbM7", "C", "Am7", "Dm7"]
CHORUS_END = ["BbM7", "C", "Am7", "Dm7", "BbM7", "C", "Gm7", "C"]


def ch(name):
    tones, root = V[name]
    return [p + T for p in tones], root + T


# ---- 歌（拍・長さ・音程は F の譜面。音節はローマ字） ------------------------------
def line(start, spec, syls):
    s = syls.split()
    assert len(s) == len(spec), (syls, len(s), len(spec))
    return [(start + b, l, p, x) for (b, l, p), x in zip(spec, s)]


VERSE_LYRIC = (
    line(0, [(.5, .5, 69), (1, .5, 69), (1.5, .5, 67), (2, .5, 69), (2.5, .5, 72), (3, 1, 69),
             (4.5, .5, 67), (5, .5, 65), (5.5, 1.5, 67)], "yo ru no ma chi ni hi ka ru")
    + line(8, [(.5, .5, 67), (1, .5, 69), (1.5, .5, 69), (2, .5, 67), (2.5, .5, 65), (3, .5, 64),
               (3.5, .5, 65), (4, 2, 64)], "ne o N no shi gu na ru")
    + line(16, [(.5, .5, 69), (1, .5, 69), (1.5, .5, 67), (2, .5, 69), (2.5, .5, 72), (3, 1, 74),
                (4.5, .5, 72), (5, .5, 70), (5.5, .5, 69), (6, 1.5, 70)], "ki mi no ko e ga ki ko e ru")
    + line(24, [(.5, .5, 72), (1, .5, 72), (1.5, .5, 74), (2, .5, 72), (2.5, .5, 70), (3, .5, 69),
                (3.5, .5, 67), (4, .5, 67), (4.5, 2.5, 69)], "de ji ta ru no mu ko u e")
)
PIKO = [(0, .5, 72), (.5, .5, 72), (1, .5, 74), (1.5, .5, 72), (2, 1, 77), (3, .5, 76), (3.5, .5, 74),
        (4, .5, 72), (4.5, .5, 72), (5, .5, 74), (5.5, .5, 76), (6, 1.5, 72)]
CHORUS_LYRIC = (
    line(0, PIKO, "pi ko pi ko ha to ga to ma ra na i")
    + line(8, [(0, .5, 69), (.5, .5, 72), (1, .5, 72), (1.5, .5, 72), (2, .5, 74), (2.5, .5, 72),
               (3, .5, 69), (3.5, .5, 72), (4, .5, 74), (4.5, .5, 74), (5, 1, 72), (6, 1.5, 69)],
           "fu ta ri no ri zu mu de o do ro yo")
    + line(16, PIKO, "pi ko pi ko ha to ga to ma ra na i")
    + line(24, [(0, .5, 77), (.5, .5, 76), (1, .5, 74), (1.5, .5, 72), (2, .5, 74), (2.5, .5, 72),
                (3, .5, 69), (3.5, .5, 72), (4, 1, 72), (5, .5, 74), (6, 1.75, 77)],
           "se ka i ga hi ka ru ma de zu to")
)
# サビ：Bメロより高く、短い動機（きらきら ネオン シグナル）をくり返すフック
KIRA = [(0, .5, 77), (.5, .5, 77), (1, .5, 79), (1.5, .5, 77), (2, .5, 76), (2.5, .5, 74), (3, 1, 72),
        (4, .5, 72), (4.5, .5, 74), (5, .5, 76), (5.5, 2, 76)]
SABI_LYRIC = (
    line(0, KIRA, "ki ra ki ra ne o N shi gu na ru")
    + line(8, [(0, .5, 76), (.5, .5, 77), (1, 1, 76), (2, .5, 72), (2.5, .5, 74), (3, 1, 76),
               (4, .5, 77), (4.5, .5, 76), (5, .5, 74), (5.5, 2.5, 74)], "ki mi ni to do ke i ma su gu")
    + line(16, KIRA, "ki ra ki ra ne o N shi gu na ru")
    + line(24, [(0, .5, 72), (.5, .5, 74), (1, .5, 76), (1.5, .5, 77), (2, .5, 79), (2.5, .5, 77), (3, 1, 76),
                (4, .5, 74), (4.5, .5, 76), (5, .5, 77), (5.5, .5, 76), (6, 1.75, 77)],
           "fu ta ri no yo ru wa o wa ra na i")
)
SCALE_F = [65, 67, 69, 70, 72, 74, 76]  # F major


def third_below(p):
    # F major の中で3度下（2音階下）
    pc = [x % 12 for x in SCALE_F]
    i = pc.index(p % 12)
    j = i - 2
    oct_shift = -12 if j < 0 else 0
    return SCALE_F[j % 7] + (p // 12 - 5) * 12 + oct_shift


VOX_T = -19


# ---- 伴奏 -------------------------------------------------------------------------
def bass_oct(prog):
    out = []
    for i, c in enumerate(prog):
        root = ch(c)[1]
        for k in range(8):
            out.append(n(i * BAR + k * PPQ // 2, PPQ // 2 - 60, root + (12 if k % 2 else 0), 0.9 if k % 2 == 0 else 0.75))
    return out


def arp(prog):
    out = []
    for i, c in enumerate(prog):
        t = sorted(ch(c)[0])
        seq = [t[0], t[1], t[2], t[-1], t[2] + 12, t[-1], t[2], t[1]] * 2
        for k, p in enumerate(seq):
            out.append(n(i * BAR + k * S16, S16 - 30, p + 12, 0.85 if k % 4 == 0 else 0.62))
    return out


def stabs(prog, scale=1.0):
    out = []
    for i, c in enumerate(prog):
        for pos, ln in [(0, 3), (3, 3), (6, 2), (10, 2), (12, 3)]:
            out += [n(i * BAR + pos * S16, ln * S16 - 40, p, (0.8 if pos in (0, 6) else 0.68) * scale) for p in ch(c)[0]]
    return out


def pad(prog):
    return [n(i * BAR, BAR - 40, p, 0.6) for i, c in enumerate(prog) for p in ch(c)[0]]


KICK, CLAP, HAT_C, HAT_O, CYM = 35, [39, 28], 42, 46, 49


def kicks(bars=4):
    return [x for b in range(bars) for x in steps(b, [0, 4, 8, 12], S16 * 2, [KICK], 1.0)]


def claps(bars=4):
    return [x for b in range(bars) for x in steps(b, [4, 12], S16, CLAP, 0.9)]


def hats(bars=4, crash=False):
    out = []
    for b in range(bars):
        for k in range(16):
            out.append(n(b * BAR + k * S16, S16, HAT_C, 0.75 if k % 4 == 2 else 0.45))
        out += steps(b, [2, 6, 10, 14], S16 * 2, [HAT_O], 0.6)
    if crash:
        out.append(n(0, BAR, CYM, 0.8))
    return out


def half_kicks(bars=4):
    return [x for b in range(bars) for x in steps(b, [0, 8], S16 * 2, [KICK], 1.0)]


def snare_roll():
    # 2小節：8分 → 16分、だんだん強く（House キットの Snare Tight Dry）
    out = [n(k * PPQ // 2, PPQ // 2 - 20, 38, 0.4 + 0.02 * k) for k in range(8)]
    out += [n(BAR + k * S16, S16 - 10, 38, 0.55 + 0.028 * k) for k in range(16)]
    return out


def saw_chords(prog):
    return [n(i * BAR, BAR - 30, p + 12, 0.9) for i, c in enumerate(prog) for p in ch(c)[0]]


def build(solo=None):
    b = AutoBuilder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    VO, CO, VH, VM = t["Vox"], t["Cons"], t["Vox Hi"], t["Vox Harm"]
    AR, ST, PA, BA, K, CL, H = t["Arp"], t["Stab"], t["Pad"], t["Bass"], t["Kick"], t["Clap"], t["Hats"]
    SW, RI = t["Saw"], t["Riser"]

    # 歌：Aメロ・Bメロ・サビ×2
    for lyric, at in ((VERSE_LYRIC, [4]), (CHORUS_LYRIC, [12]), (SABI_LYRIC, [20, 28])):
        vox, va, cons, ca = sing(lyric, TEMPO, 8 * BAR, transpose=VOX_T, base_gain=VOX_GAIN)
        b.clip(VO, 8, vox, at, automation=va)
        b.clip(CO, 8, cons, at, automation=ca)
    hi = sing(SABI_LYRIC, TEMPO, 8 * BAR, transpose=VOX_T + 12, base_gain=1.2, consonants=False)
    b.clip(VH, 8, hi[0], [20, 28], automation=hi[1])
    harm_lyric = [(bt, l, third_below(p), s) for bt, l, p, s in SABI_LYRIC]
    hm = sing(harm_lyric, TEMPO, 8 * BAR, transpose=VOX_T, base_gain=0.9, consonants=False)
    b.clip(VM, 8, hm[0], [28], automation=hm[1])

    # イントロ・Aメロ
    b.clip(AR, 4, arp(INTRO), [0])
    b.clip(AR, 4, arp(VERSE), [8])
    b.clip(BA, 4, bass_oct(INTRO), [0])
    b.clip(BA, 4, bass_oct(VERSE), [4, 8])
    # Aメロは控えめ（スタブは弱く、ハットは8分の閉じだけ、クラップは後半から）
    b.clip(ST, 4, stabs(VERSE, 0.6), [4, 8])
    b.clip(K, 4, kicks(), [0, 4, 8])
    b.clip(CL, 4, claps(), [8])
    b.clip(H, 4, [n(b_ * BAR + k * S16 * 2, S16, HAT_C, 0.6 if k % 2 else 0.4) for b_ in range(4) for k in range(8)], [2, 4])
    b.clip(H, 4, hats(4), [8])

    # Bメロ：ハーフタイムで溜める。パッドが入り、最後はスネアロールとライザー
    b.clip(PA, 4, pad(CHORUS), [12])
    b.clip(PA, 4, pad(BMELO2), [16])
    b.clip(BA, 4, [n(i * BAR, BAR - 80, ch(c)[1], 0.9) for i, c in enumerate(CHORUS)], [12])
    b.clip(BA, 4, bass_oct(BMELO2), [16])
    b.clip(AR, 4, arp(CHORUS), [12])
    b.clip(AR, 4, arp(BMELO2), [16])
    b.clip(K, 4, half_kicks(), [12])
    b.clip(K, 2, half_kicks(2), [16])
    b.clip(K, 2, kicks(2), [18])
    b.clip(CL, 4, [x for b_ in range(4) for x in steps(b_, [8], S16, CLAP, 0.85)], [12])
    b.clip(CL, 2, claps(2), [16])
    b.clip(CL, 2, snare_roll(), [18])
    b.clip(H, 4, [n(b_ * BAR + k * S16 * 2, S16, HAT_C, 0.5 if k % 2 else 0.35) for b_ in range(4) for k in range(8)], [12, 16])
    b.clip(RI, 2, [n(0, 2 * BAR - 30, 60, 0.9)], [18])

    # サビ×2：クラッシュから全部入り
    for at in (20, 28):
        b.clip(SW, 4, saw_chords(SABI), [at])
        b.clip(SW, 4, saw_chords(SABI2), [at + 4])
        b.clip(ST, 4, stabs(SABI), [at])
        b.clip(ST, 4, stabs(SABI2), [at + 4])
        b.clip(PA, 4, pad(SABI), [at])
        b.clip(PA, 4, pad(SABI2), [at + 4])
        b.clip(AR, 4, arp(SABI), [at])
        b.clip(AR, 4, arp(SABI2), [at + 4])
        b.clip(BA, 4, bass_oct(SABI), [at])
        b.clip(BA, 4, bass_oct(SABI2), [at + 4])
        b.clip(K, 4, kicks(), [at, at + 4])
        b.clip(CL, 4, claps(), [at, at + 4])
        b.clip(H, 4, hats(4, crash=True), [at, at + 4])
    b.clip(RI, 1, [n(0, BAR - 30, 60, 0.7)], [27])  # サビ2への小さな持ち上げ

    # エンディング：B♭（F の譜面で F）で終わる
    endc = [p + T for p in [57, 60, 65, 69, 72, 79]]
    b.clip(PA, 2, [n(0, 2 * BAR - 60, p, 0.6) for p in endc], [36])
    b.clip(SW, 2, [n(0, 2 * BAR - 60, p + 12, 0.8) for p in endc], [36])
    b.clip(ST, 2, [n(0, PPQ * 2, p, 0.85) for p in endc], [36])
    b.clip(BA, 2, [n(0, PPQ * 2, 29 + T, 0.9)], [36])
    b.clip(K, 2, [n(0, S16 * 2, KICK, 1.0)], [36])
    b.clip(H, 2, [n(0, BAR, CYM, 0.8)], [36])
    b.clip(AR, 2, [n(k * S16, S16 - 30, sorted(endc)[k % 6] + 12, 0.7 - k * 0.03) for k in range(16)], [36])

    return dict(format="mobiledaw-project", version=1, title="ネオン・シグナル", tempo=TEMPO, timeSig=[4, 4],
                key=dict(root=10, scale="major"),
                master=dict(gain=2.9, glue=0.75, thresholdDb=-14, ratio=2.0, softClip=0.6, ceiling=0.93),
                aux=dict(reverbReturn=0.9, reverbSize=0.58, delayReturn=0.48, delayFeedback=0.28),
                tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/technopop.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
