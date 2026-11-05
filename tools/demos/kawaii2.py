#!/usr/bin/env python3
"""kawaii フューチャーベース第2弾のデモ曲（project.json）を作る。

  python3 tools/demos/kawaii2.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/kawaii2.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/kawaii2.json /tmp/kawaii2.wav   # リポジトリの直下で（kits/ を読む）

155 BPM / D major / 56小節（約1分27秒）。既存の kawaii フューチャーベース
（F major・150 BPM・Jersey キック）とは別のキー・進行・メロディ。
ウェーブテーブル強化（テーブル5/6/7、wtPos の LFO）とクリップの
オートメーション（"automation" のレーン）を使った曲。
  小節   0– 3  イントロ   クワイアパッド（音量フェードインのレーン付き）とプラックのアルペジオ
         4–11  Aメロ      ハーフタイムのドラム（3拍目にクラップ、スネアのゴースト入り）、刻むコード、フォルマントリード、サブベース
        12–15  ビルド     4つ打ち＋スネアの2・4拍 → スネアロール＋タムフィル、ライザー。コードの cutoff が開いていくレーン
        16–27  サビ       跳ねるキックでスーパーソーが弾む。グロウルベースは wtPos のレーンでうねる
        28–35  ブレイク   ドラムは薄いハットとマラカスだけ（最後に小さいフィル）。クワイアとボーカルコード、プラック、柔らかいリード
        36–39  ビルド2    ビルドと同じ（カットオフのレーンも同じ動き）
        40–51  ラストサビ サビ＋ベルがメロディを1オクターブ上で重ねる
        52–55  アウトロ   パッド（音量フェードアウトのレーン付き）とプラック。最後に D の一発
進行
  イントロ/Aメロ/ブレイク  DM7 → Bm7 → GM7 → A（I–vi–IV–V）
  ビルド                   Em7 → F#m7 → GM7 → A
  サビ                     GM7 → A → F#m7 → Bm7 → Em7 → A → DM7 → D（IV–V–iii–vi–ii–V–I–I）
ドラムは Future Bass キット（kits/future-bass）を使う
音色はウェーブテーブルのプリセット（FB WT Chords / FB Formant Lead /
Spectral Pluck / Choir Pad / FB Vocal Chords / FB Growl Bass / FB Sub Bass）が土台
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # サビの主役。テーブル5（Spectral Saw）の厚いスーパーソー（FB WT Chords が土台）
    "Chords": dict(
        color="fff7a8d8",
        synth=dict(cutoffHz=8500, resonance=0.8, attackS=0.008, decayS=0.6, sustain=0.75, releaseS=0.22,
                   detuneCents=45, masterGain=0.55, unison=9, width=1.0, blend=0.7, noise=0.03,
                   drive=0.12, filterEnv=0.25, filterEnvDecayS=0.25,
                   wtTable=5, wtPos=0.55, wtLfoRate=0.4, wtLfoAmount=0.12),
        fx=dict(lowCutHz=180, chorus=0.3, ott=0.55, reverb=0.3, reverbSize=0.7,
                sidechain=0.9, sidechainReleaseS=0.3),
        mixer=dict(gain=0.5, pan=0),
    ),
    # ブレイクの柔らかいコード。テーブル3（フォルマント）を LFO で歌わせる（FB Vocal Chords が土台）
    "Vox": dict(
        color="ffd89af2",
        synth=dict(cutoffHz=6000, resonance=0.9, attackS=0.01, decayS=0.6, sustain=0.8, releaseS=0.25,
                   detuneCents=30, masterGain=0.55, unison=5, width=0.9, blend=0.75,
                   filterEnv=0.2, filterEnvDecayS=0.3,
                   wtTable=3, wtPos=0.45, wtLfoRate=1.8, wtLfoAmount=0.5),
        fx=dict(lowCutHz=180, chorus=0.35, ott=0.4, reverb=0.4, reverbSize=0.75,
                sidechain=0.8, sidechainReleaseS=0.3),
        mixer=dict(gain=0.45, pan=-0.06),
    ),
    # メロディ。テーブル3のフォルマントリード（FB Formant Lead が土台）
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=6500, resonance=1.0, attackS=0.004, decayS=0.3, sustain=0.65, releaseS=0.15,
                   detuneCents=14, masterGain=0.6, unison=3, width=0.5, blend=0.85,
                   filterEnv=0.25, filterEnvDecayS=0.2,
                   wtTable=3, wtPos=0.6, wtWarp=1, wtWarpAmount=0.35, wtLfoRate=3.5, wtLfoAmount=0.3),
        fx=dict(lowCutHz=250, chorus=0.2, ott=0.4, delay=0.35, delayFeedback=0.4, reverb=0.3,
                sidechain=0.45, sidechainReleaseS=0.22),
        mixer=dict(gain=0.42, pan=0.05),
    ),
    # キラキラしたプラック。テーブル5（Spectral Pluck が土台）。アルペジオとサビのチョップ用
    "Pluck": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=2400, resonance=1.1, attackS=0.001, decayS=0.22, sustain=0.0, releaseS=0.18,
                   detuneCents=8, masterGain=0.65, unison=2, width=0.4, blend=0.9,
                   filterEnv=0.65, filterEnvDecayS=0.12,
                   wtTable=5, wtPos=0.8, wtWarp=1, wtWarpAmount=0.2),
        fx=dict(lowCutHz=250, chorus=0.15, ott=0.35, delay=0.3, delayFeedback=0.35, reverb=0.35,
                sidechain=0.4, sidechainReleaseS=0.2),
        mixer=dict(gain=0.4, pan=-0.12),
    ),
    # イントロとブレイクの土台。テーブル7（クワイア）のパッド（Choir Pad が土台）
    "Pad": dict(
        color="ff8fd8f2",
        synth=dict(cutoffHz=4200, resonance=0.9, attackS=0.5, decayS=1.0, sustain=0.85, releaseS=1.4,
                   detuneCents=35, masterGain=0.5, unison=7, width=1.0, blend=0.8,
                   wtTable=7, wtPos=0.4, wtLfoRate=0.25, wtLfoAmount=0.2),
        fx=dict(lowCutHz=200, chorus=0.5, reverb=0.65, reverbSize=0.85,
                sidechain=0.4, sidechainReleaseS=0.35),
        mixer=dict(gain=0.55, pan=0),
    ),
    # サビのうねるベース。テーブル5＋強めの LFO（FB Growl Bass が土台）。wtPos はレーンでも動かす
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=900, resonance=3.2, attackS=0.003, decayS=0.4, sustain=0.8, releaseS=0.09,
                   detuneCents=25, masterGain=0.75, unison=3, width=0.3, blend=0.85, sub=0.55,
                   drive=0.55, filterEnv=0.5, filterEnvDecayS=0.16,
                   wtTable=5, wtPos=0.75, wtWarp=1, wtWarpAmount=0.45, wtLfoRate=8, wtLfoAmount=0.35),
        fx=dict(saturation=0.5, ott=0.6, sidechain=0.85, sidechainReleaseS=0.28),
        mixer=dict(gain=0.3, pan=0),
    ),
    # Aメロの静かな土台。テーブル1のサブ（FB Sub Bass が土台）
    "Sub": dict(
        color="ff4a7de0",
        synth=dict(cutoffHz=500, resonance=0.9, attackS=0.003, decayS=0.3, sustain=0.9, releaseS=0.06,
                   detuneCents=0, masterGain=0.85, unison=1, sub=0.8, osc=0.8,
                   filterEnv=0.15, filterEnvDecayS=0.1,
                   wtTable=1, wtPos=0.15),
        fx=dict(saturation=0.2, sidechain=0.9, sidechainReleaseS=0.28),
        mixer=dict(gain=0.26, pan=0),
    ),
    # ドラムは Future Bass キット（kits/future-bass）。キックは他のトラックを引っ込める
    "Kick": dict(
        color="fff28c38",
        kit="future-bass",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.26, sustain=0.0, releaseS=0.04,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=30, pitchEnvDecayS=0.03, wave=0, osc=0.5),
        fx=dict(saturation=0.1, sidechainSource=1),
        mixer=dict(gain=0.2, pan=0),
    ),
    # Clap Wide＋Snare Cute Tight を重ねる（ロールは Snare Cute Tight）。ドライでタイトに
    "Clap": dict(
        color="fff2d45a",
        kit="future-bass",
        synth=dict(cutoffHz=2600, resonance=0.9, attackS=0.0005, decayS=0.15, sustain=0.0, releaseS=0.07,
                   detuneCents=0, masterGain=1.0, unison=1, noise=1.0, filterEnv=0.5, filterEnvDecayS=0.05,
                   pitchEnv=12, pitchEnvDecayS=0.02, wave=1, osc=0.25),
        fx=dict(lowCutHz=200, saturation=0.1),  # ドラムはリバーブなし（乾いた音）
        mixer=dict(gain=0.26, pan=0),
    ),
    # 閉じたハット・短い開いたハット・サビ頭のシンバル
    "Hats": dict(
        color="ff5ad6c0",
        kit="future-bass",
        synth=dict(cutoffHz=16000, resonance=0.7, attackS=0.0005, decayS=0.04, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=300, sidechain=0.3, sidechainReleaseS=0.12),
        mixer=dict(gain=0.45, pan=0.2),
    ),
    # ビルドで盛り上がるノイズ（attack は長めにして4小節かけて開く）
    "Riser": dict(
        color="ffb0b6c0",
        synth=dict(cutoffHz=6000, resonance=1.5, attackS=8.0, decayS=1.0, sustain=1.0, releaseS=0.3,
                   unison=1, noise=1.0, osc=0, masterGain=0.6),
        fx=dict(lowCutHz=500, reverb=0.5, reverbSize=0.8),
        mixer=dict(gain=1.3, pan=0),
    ),
}

# ---- コード ----------------------------------------------------------------------

V = {  # 声部（明るめの高さ）と根音（ベース用）
    "DM7": ([62, 66, 69, 73, 76], 38),
    "Bm7": ([59, 62, 66, 69, 74], 47),
    "GM7": ([55, 59, 62, 66, 71], 43),
    "A": ([57, 61, 64, 69, 73], 45),
    "Em7": ([59, 62, 64, 67, 71], 40),
    "F#m7": ([57, 61, 64, 66, 69], 42),
    "D": ([62, 66, 69, 74, 76], 38),
    "A7": ([57, 61, 64, 67, 71], 45),
}
VERSE = ["DM7", "Bm7", "GM7", "A"]
BUILD = ["Em7", "F#m7", "GM7", "A"]
BUILD2 = ["Em7", "F#m7", "GM7", "A7"]
CHORUS = ["GM7", "A", "F#m7", "Bm7", "Em7", "A", "DM7", "D"]
CHORUS_A = CHORUS[:4]
CHORUS_B = CHORUS[4:]


def held(prog, vel=0.6):
    return [n(i * BAR, BAR - 60, p, vel) for i, c in enumerate(prog) for p in V[c][0]]


def stabs(prog):
    # Aメロ：拍頭＋シンコペの刻み（16分の位置, 長さ）
    rhythm = [(0, 3), (3, 2), (6, 3), (10, 2), (12, 2)]
    out = []
    for i, c in enumerate(prog):
        for pos, ln in rhythm:
            out += [n(i * BAR + pos * S16, ln * S16 - 40, p, 0.7 if pos in (0, 6) else 0.6) for p in V[c][0]]
    return out


def growl_line(prog):
    # サビのグロウル：16分のシンコペ。10は5度、14はオクターブ上
    out = []
    for i, c in enumerate(prog):
        root = V[c][1]
        for pos, dp in [(0, 0), (3, 0), (6, 0), (10, 7), (12, 0), (14, 12)]:
            out.append(n(i * BAR + pos * S16, S16 * 2 - 30, root + dp, 0.92 if pos == 0 else 0.82))
    return out


def sub_line(prog):
    # 1・3拍に根音を長く、終わりにオクターブの跳ね
    out = []
    for i, c in enumerate(prog):
        root = V[c][1]
        out.append(n(i * BAR, S16 * 6, root, 0.9))
        out.append(n(i * BAR + 8 * S16, S16 * 5, root, 0.9))
        out.append(n(i * BAR + 14 * S16, S16 * 2 - 30, root + 12, 0.7))
    return out


def pluck_arp(prog):
    # 8分のアルペジオ（コード音を1オクターブ上で往復）
    out = []
    for i, c in enumerate(prog):
        tones = sorted(set(V[c][0]))
        seq = [tones[j] for j in (0, 1, 2, 3, 4, 3, 2, 4)]
        for k, p in enumerate(seq):
            out.append(n(i * BAR + k * PPQ // 2, PPQ // 2 - 40, p + 12, 0.75 if k % 2 == 0 else 0.6))
    return out


def pluck_chops(prog):
    # サビのチョップ：コードの上の3音を16分のシンコペで
    pattern = [0, 3, 6, 8, 11, 14]
    out = []
    for i, c in enumerate(prog):
        top = sorted(V[c][0])[-3:]
        for k, s in enumerate(pattern):
            out.append(n(i * BAR + s * S16, S16 * 2 - 40, top[k % 3] + 12, 0.72))
    return out


def melody(spec, transpose=0, vel=0.85):
    return [n(b * PPQ, l * PPQ - 30, p + transpose, vel) for b, l, p in spec]


VERSE_MELODY = [  # (拍, 長さ, 音程) 8小節
    (0, .5, 78), (.5, .5, 81), (1, 1, 81), (2, .5, 79), (2.5, .5, 78), (3, 1, 76),
    (4, .5, 74), (4.5, .5, 76), (5, 1, 78), (6, 1.5, 81), (7.5, .5, 79),
    (8, .5, 71), (8.5, .5, 74), (9, 1, 78), (10, .5, 76), (10.5, .5, 74), (11, 1, 71),
    (12, .5, 74), (12.5, .5, 76), (13, 1, 78), (14, 2, 81),
    (16, .5, 79), (16.5, .5, 79), (17, .5, 81), (17.5, .5, 79), (18, 1, 76), (19, 1, 74),
    (20, .5, 71), (20.5, .5, 74), (21, 1, 79), (22, 1, 78), (23, 1, 76),
    (24, .5, 76), (24.5, .5, 78), (25, 1, 81), (26, .5, 79), (26.5, .5, 78), (27, 1, 76),
    (28, 1, 74), (29, .5, 76), (29.5, .5, 78), (30, 2, 74),
]

CHORUS_MELODY = [  # 8小節
    (0, 1, 81), (1, .5, 83), (1.5, .5, 81), (2, 1, 78), (3, .5, 76), (3.5, .5, 78),
    (4, 1, 79), (5, .5, 81), (5.5, .5, 83), (6, 1, 86), (7, 1, 83),
    (8, .5, 81), (8.5, .5, 79), (9, 1, 78), (10, .5, 76), (10.5, .5, 74), (11, 1, 76),
    (12, 1.5, 78), (13.5, .5, 76), (14, 1, 74), (15, 1, 71),
    (16, .5, 76), (16.5, .5, 78), (17, 1, 79), (18, .5, 81), (18.5, .5, 79), (19, 1, 78),
    (20, 1, 81), (21, .5, 83), (21.5, .5, 81), (22, 1, 79), (23, 1, 78),
    (24, 1.5, 81), (25.5, .5, 79), (26, 1, 78), (27, 1, 76),
    (28, 1, 74), (29, .5, 76), (29.5, .5, 78), (30, 2, 81),
]
# ラストサビの終わりは D に落ち着く
CHORUS_MELODY_END = CHORUS_MELODY[:-4] + [(28, 1, 78), (29, .5, 76), (29.5, .5, 74), (30, 2, 74)]
CHORUS_MELODY_A = [x for x in CHORUS_MELODY if x[0] < 16]
CHORUS_MELODY_B = [(b - 16, l, p) for b, l, p in CHORUS_MELODY if b >= 16]
CHORUS_MELODY_B_END = [(b - 16, l, p) for b, l, p in CHORUS_MELODY_END if b >= 16]

# ---- ドラム（1小節 = 16分×16） ------------------------------------------------------

# kits/future-bass の番号（future_bass.py と同じ）
KICK = 36          # Kick Punchy
CLAP = [28, 41]    # Clap Wide＋Snare Cute Tight
SNARE = 41         # Snare Cute Tight（単独のバックビート／ゴースト／ロール）
HAT_C, HAT_O = 42, 58  # 808 Hihat Closed / Open Short
CRASH = 49         # 808 Cymbal
TOM_H, TOM_M, TOM_L = 50, 47, 45  # 808 Tom High / Mid / Low（フィル用）
MARACAS = 70       # 808 Maracas（シェイカー代わり。ごく薄く敷く）
FINGER = 57        # Perc Finger Cymbal（ラストサビ頭の決めに1発だけ、控えめに）


def bounce_kicks(bars=4):
    # 既存曲の Jersey（0,4,8,11,14）とは違う跳ね：0, 4, 8, 10, 13。4小節目は詰める
    out = []
    for b in range(bars):
        pos = [0, 4, 8, 10, 13] if b % 4 != 3 else [0, 4, 8, 10, 12, 14, 15]
        out += steps(b, pos, S16 * 2 - 20, [KICK], 1.0)
    return out


def halftime_kicks(bars=4):
    out = []
    for b in range(bars):
        out += steps(b, [0, 7, 10] if b % 2 == 0 else [0, 7, 9, 14], S16 * 2, [KICK], 1.0)
    return out


def four_floor(bars=4):
    return [x for b in range(bars) for x in steps(b, [0, 4, 8, 12], S16 * 2, [KICK], 1.0)]


def claps(bars, positions, extra_last=()):
    out = []
    for b in range(bars):
        out += steps(b, positions, S16, CLAP, 0.95)
        if b == bars - 1:
            out += steps(b, list(extra_last), S16, [SNARE], 0.8)
    return out


def snare_roll(bars=2):
    # 8分 → 16分で、だんだん強く（ビルドの後半2小節）
    out = []
    for b, d in enumerate([8, 16]):
        step = BAR // d
        for k in range(d):
            out.append(n(b * BAR + k * step, max(step - 10, 30), SNARE, 0.45 + 0.5 * (b * d + k) / (bars * d)))
    return out


def hats(bars, sixteenths, crash=False):
    out = []
    for b in range(bars):
        for k in range(16 if sixteenths else 8):
            pos = k if sixteenths else k * 2
            vel = (0.9 if pos % 4 == 2 else 0.55) if sixteenths else (0.85 if k % 2 == 1 else 0.5)
            pitch = HAT_O if sixteenths and pos == 14 else HAT_C
            out.append(n(b * BAR + pos * S16, S16, pitch, vel))
    if crash:
        out.append(n(0, BAR, CRASH, 0.85))
    return out


def verse_backbeat(bars=4):
    # Aメロ：ハーフタイムの3拍目にクラップ（28＋41のレイヤー）。
    # 41単独のゴースト（14拍目）と、4小節目終わりの小さな拾いで「スネア」を聞かせる
    out = []
    for b in range(bars):
        out += steps(b, [8], S16, CLAP, 0.95)
        if b % 2 == 1:
            out += steps(b, [14], S16, [SNARE], 0.5)
        if b == bars - 1:
            out += steps(b, [12], S16, [SNARE], 0.6)
            out += steps(b, [15], S16, [SNARE], 0.65)
    return out


def build_snare(bars=2):
    # ビルド前半（ロールの前）：スネア単独で2・4拍の基本パターンを刻む
    out = []
    for b in range(bars):
        out += steps(b, [4, 12], S16, [SNARE], 0.85)
    return out


def build_roll_fill():
    # ビルド後半：スネアロール＋最終小節の後半にタムフィル（高→低）でサビへ落とす
    out = snare_roll(2)
    for pos, pitch, vel in [(8, TOM_H, 0.7), (10, TOM_H, 0.7), (12, TOM_M, 0.8),
                            (13, TOM_M, 0.8), (14, TOM_L, 0.9), (15, TOM_L, 0.9)]:
        out.append(n(BAR + pos * S16, S16, pitch, vel))
    return out


def break_fill():
    # ブレイク明けの小さなフィル：スネアの8分を少しずつ強く、最後に低いタム
    out = [n(pos * S16, S16, SNARE, 0.4 + 0.08 * k) for k, pos in enumerate([8, 10, 12, 14])]
    out.append(n(15 * S16, S16, TOM_L, 0.6))
    return out


def hats_verse(bars=4):
    # Aメロのハット：8分を土台に厚みを足す（小節終わりで短く開く＋裏の拾い）
    out = []
    for b in range(bars):
        for k in range(8):
            out.append(n(b * BAR + k * 2 * S16, S16, HAT_C, 0.85 if k % 2 == 1 else 0.5))
        out.append(n(b * BAR + 14 * S16, S16, HAT_O, 0.6))
        if b % 2 == 1:
            out.append(n(b * BAR + 15 * S16, S16, HAT_C, 0.4))
    return out


def break_hats(bars=4):
    # ブレイク：完全無音にせず、4分の閉ハットとごく薄いマラカスで脈だけ残す
    out = []
    for b in range(bars):
        out += steps(b, [0, 4, 8, 12], S16, [HAT_C], 0.3)
        for k in range(8):
            out.append(n(b * BAR + k * 2 * S16, S16, MARACAS, 0.18))
        out.append(n(b * BAR + 14 * S16, S16, HAT_O, 0.22))
    return out


# ---- project.json に組み立てる ----------------------------------------------------

class AutoBuilder(Builder):
    """Builder にクリップのオートメーション（"automation" のレーン）を足したもの。

    automation は [{"param": "cutoffHz", "points": [[tick, 値], ...]}] の形。
    tick はクリップ先頭からの相対 tick。レーンはクリップ専用になるので、
    オートメーション付きのクリップは使い回さず、置く場所ごとに意味を持たせる。
    """
    def clip(self, track, bars, notes, at, automation=None):
        super().clip(track, bars, notes, at)
        if automation:
            self.clips[-1]["automation"] = automation
        return self.clips[-1]


# ビルドのコード：カットオフが4小節かけて開く（1200 → 11000 Hz）
BUILD_CUTOFF = [{"param": "cutoffHz", "points": [[0, 1200], [7680, 4500], [15360, 11000]]}]
# サビ前半のグロウル：wtPos が2拍ごとにうねる
GROWL_WT_A = [{"param": "wtPos", "points": [[0, 0.25], [1920, 0.8], [3840, 0.3], [5760, 0.85],
                                             [7680, 0.2], [9600, 0.75], [11520, 0.35], [13440, 0.8],
                                             [15360, 0.3]]}]
# サビ後半のグロウル：うねりの形を変える
GROWL_WT_B = [{"param": "wtPos", "points": [[0, 0.7], [3840, 0.3], [7680, 0.65], [11520, 0.25],
                                             [15360, 0.6]]}]


def build(solo=None):
    b = AutoBuilder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    C, VX, L, PL, PD = t["Chords"], t["Vox"], t["Lead"], t["Pluck"], t["Pad"]
    BA, SU = t["Bass"], t["Sub"]
    K, CL, H, R = t["Kick"], t["Clap"], t["Hats"], t["Riser"]

    # イントロ（0–3）：パッドは音量フェードインのレーン付き専用クリップ
    b.clip(PD, 4, held(VERSE, 0.5), [0],
           automation=[{"param": "gain", "points": [[0, 0.0], [15360, 0.55]]}])
    b.clip(PL, 4, pluck_arp(VERSE), [0, 52])
    b.clip(H, 2, hats(2, False), [2])

    # Aメロ（4–11）
    b.clip(C, 4, stabs(VERSE), [4, 8])
    b.clip(L, 8, melody(VERSE_MELODY, vel=0.8), [4])
    b.clip(SU, 4, sub_line(VERSE), [4, 8])
    b.clip(K, 4, halftime_kicks(), [4, 8])
    b.clip(CL, 4, verse_backbeat(), [4, 8])
    b.clip(H, 4, hats_verse(), [4, 8])

    # ビルド（12–15）とビルド2（36–39）：コードはカットオフのレーン付き
    b.clip(C, 4, held(BUILD, 0.7), [12], automation=BUILD_CUTOFF)
    b.clip(C, 4, held(BUILD2, 0.72), [36], automation=BUILD_CUTOFF)
    b.clip(SU, 4, sub_line(BUILD), [12, 36])
    b.clip(K, 4, four_floor(), [12, 36])
    b.clip(H, 4, hats(4, True), [12, 36])
    b.clip(CL, 2, build_snare(2), [12, 36])
    b.clip(CL, 2, build_roll_fill(), [14, 38])
    b.clip(R, 4, [n(0, BAR * 4 - 200, 60, 0.9)], [12, 36])

    # サビ（16–27）とラストサビ（40–51）：8小節＋4小節の2クリップ構成
    b.clip(C, 8, held(CHORUS, 0.88), [16, 40])
    b.clip(L, 8, melody(CHORUS_MELODY), [16])
    b.clip(L, 8, melody(CHORUS_MELODY_END), [40])
    b.clip(L, 4, melody(CHORUS_MELODY_B), [24])
    b.clip(L, 4, melody(CHORUS_MELODY_B_END), [48])
    b.clip(PL, 8, pluck_chops(CHORUS), [16])
    b.clip(PL, 8, melody(CHORUS_MELODY, transpose=12, vel=0.65), [40])
    b.clip(PL, 4, pluck_chops(CHORUS_B), [24, 48])
    b.clip(BA, 4, growl_line(CHORUS_A), [16, 40], automation=GROWL_WT_A)
    b.clip(BA, 4, growl_line(CHORUS_B), [24, 48], automation=GROWL_WT_B)
    b.clip(K, 4, bounce_kicks(), [16, 20, 24, 40, 44, 48])
    b.clip(CL, 4, claps(4, [4, 12], extra_last=[15]), [16, 20, 24, 40, 44, 48])
    b.clip(H, 4, hats(4, True, crash=True), [16, 20, 24, 44, 48])
    # ラストサビ頭だけ、フィンガーシンバルを1発重ねた別クリップにする
    b.clip(H, 4, hats(4, True, crash=True) + [n(0, S16 * 2, FINGER, 0.35)], [40])

    # ブレイク（28–35）：ドラムは薄いハット＋マラカスだけ。パッド（レーンなし）とボーカルコードとプラック
    b.clip(H, 4, break_hats(), [28, 32])
    b.clip(CL, 1, break_fill(), [35])
    b.clip(PD, 4, held(VERSE, 0.5), [28, 32])
    b.clip(VX, 4, held(VERSE, 0.45), [28, 32])
    b.clip(PL, 4, pluck_arp(VERSE), [28, 32])
    b.clip(L, 8, melody(VERSE_MELODY, vel=0.55), [28])

    # アウトロ（52–55）：パッドは音量フェードアウトのレーン付き。最後に D の一発
    b.clip(PD, 4, held(VERSE, 0.45), [52],
           automation=[{"param": "gain", "points": [[0, 0.55], [15360, 0.0]]}])
    b.clip(C, 1, [n(0, BAR - 60, p, 0.85) for p in V["D"][0]], [55])
    b.clip(SU, 1, [n(0, PPQ * 2, V["D"][1], 0.9)], [55])
    b.clip(K, 1, [n(0, S16 * 2, KICK, 1.0)], [55])
    b.clip(H, 1, [n(0, BAR, CRASH, 0.8)], [55])  # 最後の一発にシンバルを重ねる

    return dict(format="mobiledaw-project", version=1, tempo=155.0, timeSig=[4, 4],
                key=dict(root=2, scale="major"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/kawaii2.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
