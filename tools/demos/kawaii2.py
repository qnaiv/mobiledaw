#!/usr/bin/env python3
"""kawaii フューチャーベース第2弾のデモ曲（project.json）を作る。

  python3 tools/demos/kawaii2.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/kawaii2.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/kawaii2.json /tmp/kawaii2.wav   # リポジトリの直下で（kits/ を読む）

155 BPM / D major / 56小節（約1分27秒）。既存の kawaii フューチャーベース
（F major・150 BPM・Jersey キック）とは別のキー・進行・メロディ。
エンジン拡張（キートラッキング／グライド＋モノ／テンポ同期 LFO）と
本格 FB プリセット、ドラムキット future-bass-pro を使った曲。
  小節   0– 3  イントロ   パッド（FB Pad Air、音量フェードインのレーン付き）とプラックのアルペジオ
         4–11  Aメロ      ハーフタイムのドラム（3拍目にクラップ、スネアのゴースト入り）、刻むコード、歌うリード、サブベース
        12–15  ビルド     4つ打ち＋スネアロール→タムフィル。最後の1拍はドラムを落として息継ぎ（リバースシンバルの吸い込み）
        16–27  サビ       跳ねるキックで 9th コードが弾む。ワブルベース＋クリーンなサブ。サビ頭にインパクト
        28–35  ブレイク   ドラムは薄いハットとマラカスだけ。冒頭にダウンリフター。クワイアとパッド、プラック、柔らかいリード
        36–39  ビルド2    ビルドと同じ動き＋ライザー短も重ねる
        40–51  ラストサビ サビ＋プラックがメロディを1オクターブ上で重ねる。最後にトーキングリードの掛け合い
        52–55  アウトロ   パッド（音量フェードアウトのレーン付き）とプラック。最後に D の一発
進行（コードは maj9／m9／add9 の広いボイシング。ルートはベース側、3・5・7・9 を上に広げる）
  イントロ/Aメロ/ブレイク  DM9 → Bm9 → GM9 → A9（I–vi–IV–V）
  ビルド                   Em9 → F#m9 → GM9 → A9
  サビ                     GM9 → A9 → F#m9 → Bm9 → Em9 → A9 → DM9 → Dadd9（IV–V–iii–vi–ii–V–I–I）
ドラムは Future Bass Pro キット（kits/future-bass-pro）を使う
音色は本格 FB プリセット（FB Chords 9th / FB Vocal Lead / FB Talking Lead /
FB Pluck / FB Pad Air / FB Wobble Bass / FB Sub Clean）が土台
"""
import json
import sys

from future_bass import Builder, n, steps, PPQ, BAR, S16

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------
# プリセットは app/lib/sound/sound_params.dart の本格 FB プリセットの値をそのまま使う
# （synth と fx に分けて書く。mixer はデモ側のバランス）。

SOUNDS = {
    # サビの主役。FB Chords 9th（スーパーソー9声、keyTrack 0.6、OTT 0.3）
    "Chords": dict(
        color="fff7a8d8",
        synth=dict(unison=9, detuneCents=34, width=0.95, blend=0.7, noise=0.02, drive=0.12,
                   cutoffHz=10000, resonance=0.8, keyTrack=0.6, filterEnv=0.2, filterEnvDecayS=0.3,
                   attackS=0.006, decayS=0.6, sustain=0.78, releaseS=0.4, masterGain=0.55),
        fx=dict(lowCutHz=180, saturation=0.12, chorus=0.3, ott=0.3, reverb=0.3, reverbSize=0.7,
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
    # メロディ。FB Vocal Lead（モノ＋グライド90ms、+12st のスクープ、5.5Hz ビブラート）。
    # レガート区間は melody_legato で音をつなぎ、グライドで歌わせる
    "Lead": dict(
        color="ffe879c6",
        synth=dict(wtTable=3, wtPos=0.5, wtWarp=1, wtWarpAmount=0.25,
                   mono=1, glideS=0.09, pitchEnv=12, pitchEnvDecayS=0.08,
                   wtLfoRate=5.5, lfoPitch=0.18,
                   unison=2, detuneCents=10, width=0.3, blend=0.9,
                   cutoffHz=6000, resonance=1.0, keyTrack=0.5, filterEnv=0.2, filterEnvDecayS=0.2,
                   attackS=0.004, decayS=0.3, sustain=0.7, releaseS=0.15, masterGain=0.7),
        fx=dict(lowCutHz=250, saturation=0.1, ott=0.35, delay=0.35, delayFeedback=0.4,
                reverb=0.3, reverbSize=0.65, sidechain=0.45),
        mixer=dict(gain=0.42, pan=0.05),
    ),
    # ラストサビの掛け合い。FB Talking Lead（フォルマントを LFO で往復、グライド120ms）
    "Talk": dict(
        color="ffd45af2",
        synth=dict(wtTable=3, wtPos=0.45, wtWarp=1, wtWarpAmount=0.35,
                   mono=1, glideS=0.12, wtLfoRate=2.2, wtLfoAmount=0.55,
                   unison=1, width=0.15, blend=1.0,
                   cutoffHz=4200, resonance=1.8, keyTrack=0.35, filterEnv=0.3, filterEnvDecayS=0.25,
                   attackS=0.005, decayS=0.3, sustain=0.7, releaseS=0.12, masterGain=0.6),
        fx=dict(lowCutHz=250, saturation=0.15, ott=0.35, delay=0.3, delayFeedback=0.35,
                reverb=0.28, sidechain=0.45),
        mixer=dict(gain=0.4, pan=-0.08),
    ),
    # アルペジオとサビのチョップ。FB Pluck（keyTrack 0.85 で高音域まで抜ける）
    "Pluck": dict(
        color="ff9a7cf2",
        synth=dict(unison=2, detuneCents=10, width=0.45, blend=0.85,
                   cutoffHz=1600, resonance=1.1, keyTrack=0.85, filterEnv=0.72, filterEnvDecayS=0.09,
                   attackS=0.001, decayS=0.16, sustain=0.0, releaseS=0.12, masterGain=0.68),
        fx=dict(lowCutHz=250, chorus=0.15, ott=0.35, delay=0.32, delayFeedback=0.38, reverb=0.3,
                reverbSize=0.6, sidechain=0.45),
        mixer=dict(gain=0.4, pan=-0.12),
    ),
    # イントロとブレイクとアウトロの土台。FB Pad Air（12声＋1小節同期の微ドリフト）。
    # ブレイクでは Vox（クワイア系）と重ねる
    "Pad": dict(
        color="ff8fd8f2",
        synth=dict(wtTable=5, wtPos=0.3, noise=0.015,
                   unison=12, detuneCents=30, width=1.0, blend=0.75,
                   lfoSync=1, lfoDiv=0, lfoWave=0, lfoCutoff=0.1, wtLfoAmount=0.18,
                   cutoffHz=5200, resonance=0.8, keyTrack=0.45,
                   attackS=0.6, decayS=1.2, sustain=0.85, releaseS=1.8, masterGain=0.30),
        fx=dict(lowCutHz=200, saturation=0.08, chorus=0.45, ott=0.25, reverb=0.6, reverbSize=0.85,
                sidechain=0.5, sidechainReleaseS=0.35),
        mixer=dict(gain=0.55, pan=0),
    ),
    # サビのワブルベース。FB Wobble Bass（付点8分に同期した矩形 LFO がカットオフと wtPos を開閉）。
    # wtPos はレーンでゆっくり寄せて、ワブルの中心を動かす
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(wtTable=5, wtPos=0.6, wtWarp=1, wtWarpAmount=0.4,
                   mono=1, glideS=0.02,
                   lfoSync=1, lfoDiv=2, lfoWave=2, lfoCutoff=0.65, wtLfoAmount=0.45,
                   unison=3, detuneCents=22, width=0.25, blend=0.85, sub=0.5, drive=0.45,
                   cutoffHz=850, resonance=2.8, keyTrack=0.3, filterEnv=0.35, filterEnvDecayS=0.15,
                   attackS=0.003, decayS=0.35, sustain=0.85, releaseS=0.08, masterGain=0.75),
        fx=dict(saturation=0.5, ott=0.5, sidechain=0.8, sidechainReleaseS=0.25),
        mixer=dict(gain=0.3, pan=0),
    ),
    # 低域の土台。FB Sub Clean（サインのみ）に、デモ側でサイドチェインを足す
    # （プリセット側はクリーン維持のため sidechain 0。task20 の推奨どおり 0.85／release 0.25）
    "Sub": dict(
        color="ff4a7de0",
        synth=dict(osc=0, sub=1.0, unison=1, width=0, blend=1.0,
                   mono=1, glideS=0.02,
                   cutoffHz=300, resonance=0.9,
                   attackS=0.004, decayS=0.2, sustain=0.95, releaseS=0.05, masterGain=0.9),
        fx=dict(saturation=0.12, sidechain=0.85, sidechainReleaseS=0.25),
        mixer=dict(gain=0.26, pan=0),
    ),
    # ドラムは Future Bass Pro キット（kits/future-bass-pro）。キックは他のトラックを引っ込める
    "Kick": dict(
        color="fff28c38",
        kit="future-bass-pro",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.26, sustain=0.0, releaseS=0.04,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=30, pitchEnvDecayS=0.03, wave=0, osc=0.5),
        fx=dict(saturation=0.1, sidechainSource=1),
        mixer=dict(gain=0.2, pan=0),
    ),
    # Clap Pro Main＋Snare Pro Main を重ねる（ロールも Snare Pro Main）。ドライでタイトに
    "Clap": dict(
        color="fff2d45a",
        kit="future-bass-pro",
        synth=dict(cutoffHz=2600, resonance=0.9, attackS=0.0005, decayS=0.15, sustain=0.0, releaseS=0.07,
                   detuneCents=0, masterGain=1.0, unison=1, noise=1.0, filterEnv=0.5, filterEnvDecayS=0.05,
                   pitchEnv=12, pitchEnvDecayS=0.02, wave=1, osc=0.25),
        fx=dict(lowCutHz=200, saturation=0.1),  # ドラムはリバーブなし（乾いた音）
        mixer=dict(gain=0.26, pan=0),
    ),
    # 閉じたハット・短い開いたハット・サビ頭のシンバル
    "Hats": dict(
        color="ff5ad6c0",
        kit="future-bass-pro",
        synth=dict(cutoffHz=16000, resonance=0.7, attackS=0.0005, decayS=0.04, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=300, sidechain=0.3, sidechainReleaseS=0.12),
        mixer=dict(gain=0.45, pan=0.2),
    ),
    # 演出ワンショット専用トラック（Pro キットのライザー／リバース／インパクト／ダウンリフター）
    "FX": dict(
        color="ff9fb6c9",
        kit="future-bass-pro",
        synth=dict(cutoffHz=16000, resonance=0.7, attackS=0.0005, decayS=0.04, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=120),
        mixer=dict(gain=0.5, pan=0),
    ),
}

# ---- コード ----------------------------------------------------------------------
# 声部は maj9／m9／add9 の広い配置（下から順に間隔を空ける）。根音はベース用。

V = {
    "DM9": ([62, 66, 69, 73, 76], 38),    # D4 F#4 A4 C#5 E5
    "Bm9": ([59, 62, 66, 69, 73], 47),    # B3 D4 F#4 A4 C#5
    "GM9": ([55, 59, 62, 66, 69], 43),    # G3 B3 D4 F#4 A4
    "A9": ([57, 61, 64, 67, 71], 45),     # A3 C#4 E4 G4 B4
    "Em9": ([59, 62, 66, 67, 71], 40),    # B3 D4 F#4 G4 B4（根音はベース側）
    "F#m9": ([57, 61, 64, 68, 73], 42),   # A3 C#4 E4 G#4 C#5（根音はベース側）
    "Dadd9": ([62, 66, 69, 74, 76], 38),  # D4 F#4 A4 D5 E5
}
VERSE = ["DM9", "Bm9", "GM9", "A9"]
BUILD = ["Em9", "F#m9", "GM9", "A9"]
CHORUS = ["GM9", "A9", "F#m9", "Bm9", "Em9", "A9", "DM9", "Dadd9"]
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
    # サビのワブル：16分のシンコペ。10は5度、14はオクターブ上
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


def melody_legato(spec, vel=0.85):
    """モノ＋グライドのリード用。次音まで半拍以内のランは音同士を重ねて
    レガートにし、グライドで滑らかにつなぐ（間が空く音は通常の発音＝スクープが効く）"""
    spec = sorted(spec)
    out = []
    for i, (b, l, p) in enumerate(spec):
        start = int(b * PPQ)
        if i + 1 < len(spec):
            nxt = int(spec[i + 1][0] * PPQ)
            if nxt - (start + l * PPQ) <= PPQ // 2:
                out.append(n(start, nxt - start + 170, p, vel))
                continue
        out.append(n(start, l * PPQ - 30, p, vel))
    return out


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

# ラストサビ最終小節、リードが D を伸ばすところへ返す掛け合い（レガートでつなぐ）
TALK_PHRASE = [(13.5, .5, 76), (14, .5, 78), (14.5, .5, 79), (15, 1, 81)]

# ---- ドラム（1小節 = 16分×16） ------------------------------------------------------

# kits/future-bass-pro の番号（既存 future-bass と互換配置＋演出系）
KICK = 36          # Kick Pro Main
CLAP = [39, 38]    # Clap Pro Main＋Snare Pro Main
SNARE = 38         # Snare Pro Main（単独のバックビート／ゴースト／ロール）
HAT_C, HAT_O = 42, 58  # Hat Closed / Open Short
CRASH = 49         # 808 Cymbal Pro
TOM_H, TOM_M, TOM_L = 50, 47, 45  # Tom High / Mid / Low Pro（フィル用）
MARACAS = 70       # 808 Maracas（シェイカー代わり。ごく薄く敷く）
FINGER = 57        # Perc Finger Cymbal（ラストサビ頭の決めに1発だけ、控えめに）
REVERSE = 52       # Cymbal Reverse（1小節。ピークが末尾＝次のダウンビートに着地）
IMPACT = 53        # Impact Pro（サビ頭用）
RISER_L = 59       # Riser Pro Long（4小節 @155BPM）
RISER_S = 61       # Riser Pro Short（2小節）
DOWNLIFT = 65      # Downlifter Pro（2小節、下降）


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


def four_floor_gap(bars=4):
    # ビルドの4つ打ち。最終小節の4拍目は落として、ドロップ直前に息継ぎを作る
    out = []
    for b in range(bars):
        pos = [0, 4, 8, 12] if b < bars - 1 else [0, 4, 8]
        out += steps(b, pos, S16 * 2, [KICK], 1.0)
    return out


def claps(bars, positions, extra_last=()):
    out = []
    for b in range(bars):
        out += steps(b, positions, S16, CLAP, 0.95)
        if b == bars - 1:
            out += steps(b, list(extra_last), S16, [SNARE], 0.8)
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


def hats_build(bars=4):
    # ビルドのハット：16分で回し、最終小節の4拍目（12以降）は落として息継ぎに合わせる
    out = []
    for b in range(bars):
        last = 12 if b == bars - 1 else 16
        for pos in range(last):
            vel = 0.9 if pos % 4 == 2 else 0.55
            pitch = HAT_O if pos == 14 else HAT_C
            out.append(n(b * BAR + pos * S16, S16, pitch, vel))
    return out


def verse_backbeat(bars=4):
    # Aメロ：ハーフタイムの3拍目にクラップ（39＋38のレイヤー）。
    # 38単独のゴースト（14拍目）と、4小節目終わりの小さな拾いで「スネア」を聞かせる
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
    # ビルド後半：8分ロール→16分ロール→タムフィル（高→低）。
    # 最終小節の4拍目は全部落として、ドロップ直前の息継ぎにする
    out = []
    for k in range(8):
        out.append(n(k * PPQ // 2, PPQ // 2 - 10, SNARE, 0.45 + 0.25 * k / 7))
    for k in range(8):
        out.append(n(BAR + k * S16, S16 - 10, SNARE, 0.7 + 0.25 * k / 7))
    for pos, pitch, vel in [(8, TOM_H, 0.75), (9, TOM_H, 0.8), (10, TOM_M, 0.85), (11, TOM_L, 0.95)]:
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
# ビルドのコード：ローカットも一緒に開く（700 → 180 Hz。薄く始めてドロップで全開）
BUILD_LOWCUT = [{"param": "lowCutHz", "points": [[0, 700], [11520, 320], [15360, 180]]}]
# サビ前半のワブル：wtPos の中心がゆっくり寄れる（同期 LFO のワブルに重ねる）
GROWL_WT_A = [{"param": "wtPos", "points": [[0, 0.4], [1920, 0.62], [3840, 0.38], [5760, 0.65],
                                             [7680, 0.35], [9600, 0.6], [11520, 0.42], [13440, 0.62],
                                             [15360, 0.4]]}]
# サビ後半のワブル：寄れの形を変える
GROWL_WT_B = [{"param": "wtPos", "points": [[0, 0.6], [3840, 0.42], [7680, 0.58], [11520, 0.38],
                                             [15360, 0.55]]}]


def build(solo=None):
    b = AutoBuilder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    C, VX, L, TK, PL, PD = t["Chords"], t["Vox"], t["Lead"], t["Talk"], t["Pluck"], t["Pad"]
    BA, SU = t["Bass"], t["Sub"]
    K, CL, H, FX = t["Kick"], t["Clap"], t["Hats"], t["FX"]

    # イントロ（0–3）：パッドは音量フェードインのレーン付き専用クリップ
    b.clip(PD, 4, held(VERSE, 0.5), [0],
           automation=[{"param": "gain", "points": [[0, 0.0], [15360, 0.55]]}])
    b.clip(PL, 4, pluck_arp(VERSE), [0, 52])
    b.clip(H, 2, hats(2, False), [2])

    # Aメロ（4–11）
    b.clip(C, 4, stabs(VERSE), [4, 8])
    b.clip(L, 8, melody_legato(VERSE_MELODY, vel=0.8), [4])
    b.clip(SU, 4, sub_line(VERSE), [4, 8])
    b.clip(K, 4, halftime_kicks(), [4, 8])
    b.clip(CL, 4, verse_backbeat(), [4, 8])
    b.clip(H, 4, hats_verse(), [4, 8])

    # ビルド（12–15）とビルド2（36–39）：コードはカットオフ＋ローカットのレーン付き
    b.clip(C, 4, held(BUILD, 0.7), [12], automation=BUILD_CUTOFF + BUILD_LOWCUT)
    b.clip(C, 4, held(BUILD, 0.72), [36], automation=BUILD_CUTOFF + BUILD_LOWCUT)
    b.clip(SU, 4, sub_line(BUILD), [12, 36])
    b.clip(K, 4, four_floor_gap(), [12, 36])
    b.clip(H, 4, hats_build(), [12, 36])
    b.clip(CL, 2, build_snare(2), [12, 36])
    b.clip(CL, 2, build_roll_fill(), [14, 38])
    # 演出：ライザー長はビルド全体、ビルド2は後半にライザー短も重ねる
    b.clip(FX, 4, [n(0, BAR * 4 - 200, RISER_L, 0.9)], [12])
    b.clip(FX, 4, [n(0, BAR * 4 - 200, RISER_L, 0.9), n(BAR * 2, BAR * 2 - 200, RISER_S, 0.85)], [36])
    # リバースシンバル：ドロップ（とサビ後半の頭）に着地させる
    b.clip(FX, 1, [n(0, BAR, REVERSE, 0.9)], [15, 23, 39, 47])
    # インパクト：サビ頭
    b.clip(FX, 1, [n(0, BAR, IMPACT, 0.95)], [16, 40])

    # サビ（16–27）とラストサビ（40–51）：8小節＋4小節の2クリップ構成
    b.clip(C, 8, held(CHORUS, 0.88), [16, 40])
    b.clip(L, 8, melody_legato(CHORUS_MELODY), [16])
    b.clip(L, 8, melody_legato(CHORUS_MELODY_END), [40])
    b.clip(L, 4, melody_legato(CHORUS_MELODY_B), [24])
    b.clip(L, 4, melody_legato(CHORUS_MELODY_B_END), [48])
    b.clip(TK, 4, melody_legato(TALK_PHRASE, vel=0.75), [48])
    b.clip(PL, 8, pluck_chops(CHORUS), [16])
    b.clip(PL, 8, melody(CHORUS_MELODY, transpose=12, vel=0.65), [40])
    b.clip(PL, 4, pluck_chops(CHORUS_B), [24, 48])
    b.clip(BA, 4, growl_line(CHORUS_A), [16, 40], automation=GROWL_WT_A)
    b.clip(BA, 4, growl_line(CHORUS_B), [24, 48], automation=GROWL_WT_B)
    # サビの低域の土台：クリーンなサブを別トラックで（キックで引っ込むサイドチェイン付き）
    b.clip(SU, 4, sub_line(CHORUS_A), [16, 40])
    b.clip(SU, 4, sub_line(CHORUS_B), [24, 48])
    b.clip(K, 4, bounce_kicks(), [16, 20, 24, 40, 44, 48])
    b.clip(CL, 4, claps(4, [4, 12], extra_last=[15]), [16, 20, 24, 40, 44, 48])
    b.clip(H, 4, hats(4, True, crash=True), [16, 20, 24, 44, 48])
    # ラストサビ頭だけ、フィンガーシンバルを1発重ねた別クリップにする
    b.clip(H, 4, hats(4, True, crash=True) + [n(0, S16 * 2, FINGER, 0.35)], [40])

    # ブレイク（28–35）：冒頭にダウンリフター。ドラムは薄いハット＋マラカスだけ。
    # パッド（Pad Air）とクワイア系（Vox）の重ね、プラック、柔らかいリード
    b.clip(FX, 2, [n(0, BAR * 2, DOWNLIFT, 0.85)], [28])
    b.clip(H, 4, break_hats(), [28, 32])
    b.clip(CL, 1, break_fill(), [35])
    b.clip(PD, 4, held(VERSE, 0.5), [28, 32])
    b.clip(VX, 4, held(VERSE, 0.45), [28, 32])
    b.clip(PL, 4, pluck_arp(VERSE), [28, 32])
    b.clip(L, 8, melody_legato(VERSE_MELODY, vel=0.55), [28])

    # アウトロ（52–55）：パッドは音量フェードアウトのレーン付き。最後に D の一発
    b.clip(PD, 4, held(VERSE, 0.45), [52],
           automation=[{"param": "gain", "points": [[0, 0.55], [15360, 0.0]]}])
    b.clip(C, 1, [n(0, BAR - 60, p, 0.85) for p in V["Dadd9"][0]], [55])
    b.clip(SU, 1, [n(0, PPQ * 2, V["Dadd9"][1], 0.9)], [55])
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
