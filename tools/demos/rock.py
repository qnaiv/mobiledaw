#!/usr/bin/env python3
"""ロックのデモ曲「オーバードライブ」（project.json）を作る。

  python3 tools/demos/rock.py [出力先] [--solo トラック名]

140 BPM / E minor / 42小節（約1分12秒）
  小節  0– 3  イントロ   歪ませたのこぎり波のパワーコードでリフ、最後にタムのフィル
        4–11  Aメロ      ブリッジミュート風の8分刻み（カットオフを下げたクリップ）。後半にトークボックスの合いの手
       12–15  Bメロ      C5 → D5 → C5 → B5 で溜める。刻みのフィルターが開いていき、スネアが8分 → 16分、ライザー
       16–23  サビ       クラッシュで開ける。開いたパワーコード、オクターブ上のギター、トークボックスの高いフック
                         （リードギターが1オクターブ上で重ねる）
       24–31  ソロ       トークボックスのソロ（「ウ→ア→オ」と母音が開くワウ／トークボックス風）
       32–39  ラストサビ  サビをもう一度（チャイナも足して最大に）
       40–41  エンディング E5 を伸ばして終わる
進行  Aメロ E5 E5 C5 D5 / E5 E5 C5 B5、Bメロ C5 D5 C5 B5、サビ C5 G5 D5 E5
ギターは L/R 2本（デチューンとカットオフを変えて左右に振る）。ドラムは Acoustic Live キット
"""
import json
import sys

from future_bass import n, steps, PPQ, BAR, S16
from singer import AutoBuilder, talkbox

TEMPO = 140.0

GTR = dict(unison=3, detuneCents=14, width=0.3, blend=0.8, cutoffHz=3400, resonance=1.1, drive=0.9,
           sub=0.0, attackS=0.003, decayS=0.4, sustain=0.85, releaseS=0.09, filterEnv=0.15,
           filterEnvDecayS=0.1, masterGain=0.55, keyTrack=0.3)
SOUNDS = {
    "Gtr L": dict(color="ffe85a5a", synth=dict(GTR),
                  fx=dict(lowCutHz=100, saturation=0.55, ott=0.12, reverb=0.05, reverbSize=0.4,
                          eqLowDb=-1, eqMidDb=2.5, eqMidHz=2200, eqHighDb=1, eqHighHz=6500,
                          comp=0.4, compThresholdDb=-16, compRatio=3.5, compAttackMs=8, compMakeupDb=1,
                          sendReverb=0.14),
                  mixer=dict(gain=0.4, pan=-0.72)),
    "Gtr R": dict(color="fff28c38", synth=dict(GTR, detuneCents=18, cutoffHz=3000, wave=1),
                  fx=dict(lowCutHz=100, saturation=0.55, ott=0.12, reverb=0.05, reverbSize=0.4,
                          eqLowDb=-1, eqMidDb=2, eqMidHz=1800, eqHighDb=1.2, eqHighHz=7000,
                          comp=0.4, compThresholdDb=-16, compRatio=3.5, compAttackMs=10, compMakeupDb=1,
                          sendReverb=0.14),
                  mixer=dict(gain=0.36, pan=0.72)),
    "Talkbox": dict(  # 歌うようなリード：フォルマント表＋モノ＋グライド＋歪み
        color="ffff7ab8",
        synth=dict(wtTable=3, wtPos=0.5, unison=2, detuneCents=8, width=0.25, blend=0.9, mono=1, glideS=0.07,
                   wtLfoRate=5.8, cutoffHz=4000, resonance=2.2, keyTrack=0.0, drive=0.55,
                   attackS=0.008, decayS=0.3, sustain=0.85, releaseS=0.12, masterGain=0.7),
        fx=dict(lowCutHz=160, saturation=0.4, chorus=0.08, ott=0.18, delay=0.08, delayFeedback=0.25,
                reverb=0.08, reverbSize=0.55, eqMidDb=2, eqMidHz=1600, eqHighDb=1, eqHighHz=6000,
                comp=0.35, compThresholdDb=-15, compRatio=3, compMakeupDb=1,
                sendReverb=0.18, sendDelay=0.16),
        mixer=dict(gain=0.65, pan=0.05)),
    "Lead Gtr": dict(  # サビでフックを1オクターブ上で重ねるリードギター
        color="ffffa040",
        synth=dict(unison=2, detuneCents=10, width=0.4, blend=0.9, mono=1, glideS=0.04, wtLfoRate=5.5,
                   lfoPitch=0.08, cutoffHz=4200, resonance=1.2, drive=0.8, attackS=0.004, decayS=0.4,
                   sustain=0.8, releaseS=0.15, masterGain=0.5),
        fx=dict(lowCutHz=220, saturation=0.5, delay=0.1, delayFeedback=0.28, reverb=0.08, reverbSize=0.55,
                eqHighDb=1.5, eqHighHz=5500, comp=0.25, compThresholdDb=-16, sendDelay=0.22, sendReverb=0.12),
        mixer=dict(gain=0.3, pan=-0.15)),
    "Gtr Hi": dict(  # サビの厚み：オクターブ上のコード（左右に広く）
        color="ffe8a05a",
        synth=dict(GTR, unison=5, detuneCents=24, width=1.0, cutoffHz=4200),
        fx=dict(lowCutHz=280, saturation=0.4, chorus=0.22, ott=0.15, reverb=0.08, reverbSize=0.55,
                eqHighDb=1, eqHighHz=7000, sendReverb=0.22),
        mixer=dict(gain=0.22, pan=0)),
    "Riser": dict(color="ffdddddd",
                  synth=dict(osc=0, noise=1.0, unison=1, cutoffHz=6000, resonance=1.6, keyTrack=0.0,
                             attackS=6.5, decayS=0.5, sustain=1.0, releaseS=0.2, masterGain=0.6),
                  fx=dict(lowCutHz=500, reverb=0.15, reverbSize=0.7, sendReverb=0.25), mixer=dict(gain=0.38, pan=0)),
    "Bass": dict(color="ff5aa9f2",
                 synth=dict(unison=1, cutoffHz=1100, resonance=1.0, drive=0.45, sub=0.35, filterEnv=0.25,
                            filterEnvDecayS=0.08, attackS=0.002, decayS=0.2, sustain=0.75, releaseS=0.05,
                            masterGain=0.75),
                 fx=dict(saturation=0.3, lowCutHz=35, eqLowDb=2, eqLowHz=80, eqHighDb=-2.5, eqHighHz=2200,
                        comp=0.5, compThresholdDb=-16, compRatio=4, compAttackMs=8, compMakeupDb=1.5),
                 mixer=dict(gain=0.32, pan=0)),
    "Kick": dict(color="fff2d45a", kit="acoustic-live", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(saturation=0.28, eqLowDb=3, eqLowHz=70, eqMidDb=-3, eqMidHz=380,
                        comp=0.5, compThresholdDb=-12, compRatio=4, compAttackMs=5, compMakeupDb=1),
                 mixer=dict(gain=0.4, pan=0)),
    "Snare": dict(color="ffc8f25a", kit="acoustic-live", synth=dict(masterGain=1.0, unison=1),
                  fx=dict(lowCutHz=100, saturation=0.22, reverb=0.06, reverbSize=0.4,
                          eqMidDb=2.5, eqMidHz=2000, eqHighDb=1.5, eqHighHz=7000,
                          comp=0.45, compThresholdDb=-12, compRatio=3.5, compAttackMs=6, compMakeupDb=1,
                          sendReverb=0.2),
                  mixer=dict(gain=0.55, pan=0.02)),
    "Toms": dict(color="ff9a7cf2", kit="acoustic-live", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(lowCutHz=50, reverb=0.05, eqLowDb=1.5, eqLowHz=120, sendReverb=0.16),
                 mixer=dict(gain=0.42, pan=-0.1)),
    "Cymbals": dict(color="ffb0b6c0", kit="acoustic-live", synth=dict(masterGain=1.0, unison=1),
                    fx=dict(lowCutHz=300, reverb=0.04, eqHighDb=1.5, eqHighHz=8000, sendReverb=0.16),
                    mixer=dict(gain=0.26, pan=0.3)),
}

P5 = {"E5": 40, "G5": 43, "A5": 45, "C5": 36 + 12, "D5": 38 + 12, "B5": 35 + 12}
BASS = {"E5": 28, "G5": 31, "A5": 33, "C5": 36, "D5": 38, "B5": 35}


def pc(name, root_only=False):
    r = P5[name]
    return [r, r + 7] if root_only else [r, r + 7, r + 12]


def riff_intro():
    pat = [[(0, 6, "E5"), (6, 2, "G5"), (8, 6, "A5"), (14, 2, "G5")],
           [(0, 6, "E5"), (6, 2, "G5"), (8, 4, "D5"), (12, 4, "C5")]] * 2
    out = []
    for b, bar in enumerate(pat):
        for pos, ln, c in bar:
            out += [n(b * BAR + pos * S16, ln * S16 - 30, p, 0.95) for p in pc(c)]
    return out


def palm(prog):
    out = []
    for b, c in enumerate(prog):
        for k in range(8):
            acc = k in (0, 3, 6)
            out += [n(b * BAR + k * PPQ // 2, PPQ // 2 - 170, p, 0.95 if acc else 0.7) for p in pc(c, True)]
    return out


def chug_open(prog):
    out = []
    for b, c in enumerate(prog):
        for k in range(8):
            out += [n(b * BAR + k * PPQ // 2, PPQ // 2 - 25, p, 0.95 if k % 2 == 0 else 0.8) for p in pc(c)]
    return out


def bass8(prog):
    return [n(b * BAR + k * PPQ // 2, PPQ // 2 - 50, BASS[c], 0.95 if k % 2 == 0 else 0.8)
            for b, c in enumerate(prog) for k in range(8)]


def bass_intro():
    m = [("E5", 0), ("E5", 1), ("A5", 2), ("A5", 3)], [("E5", 0), ("E5", 1), ("D5", 2), ("C5", 3)]
    out = []
    for b in range(4):
        for c, beat in m[b % 2]:
            out += [n(b * BAR + beat * PPQ, PPQ // 2 - 40, BASS[c], 0.95), n(b * BAR + beat * PPQ + PPQ // 2, PPQ // 2 - 40, BASS[c], 0.8)]
    return out


KICK, SNARE, HAT_C, HAT_O, CRASH, RIDE, CHINA = 36, 38, 65, 59, 49, 51, 52
TOM_H, TOM_M, TOM_L = 50, 47, 45


def drums_rock(bars, kick_pat=(0, 6, 8, 10), crash=True, ride=False):
    k, s, c = [], [], []
    for b in range(bars):
        k += steps(b, list(kick_pat), S16, [KICK], 1.0)
        s += steps(b, [4, 12], S16, [SNARE], 1.0)
        for e in range(8):
            c.append(n(b * BAR + e * PPQ // 2, S16 * 2, RIDE if ride else HAT_C, 0.85 if e % 2 == 0 else 0.6))
    if crash:
        c.append(n(0, BAR, CRASH, 0.95))
    return k, s, c


def fill(bar):
    # 最後の2拍：スネア→タム高・中・低
    t = [n(bar * BAR + (8 + i) * S16, S16, p, 0.9) for i, p in enumerate([TOM_H, TOM_H, TOM_M, TOM_M, TOM_L, TOM_L, TOM_L, TOM_L])]
    return t


VERSE_ANSWER = [(2, .5, 64), (2.5, .5, 67), (3, 1, 69), (4, 2, 67), (6, 1.5, 64),
                (10, .5, 67), (10.5, .5, 69), (11, 1, 71), (12, 2, 71), (14, 1.5, 66)]
CHORUS_MEL = [(0, 1.5, 67), (1.5, .5, 66), (2, 1, 64), (3, 1, 67), (4, 2, 71), (6, 1, 69), (7, 1, 67),
              (8, 1.5, 66), (9.5, .5, 67), (10, 1, 69), (11, 1, 66), (12, 3, 64), (15, 1, 62),
              (16, 1.5, 67), (17.5, .5, 69), (18, 1, 71), (19, 1, 72), (20, 2, 74), (22, 1, 71), (23, 1, 67),
              (24, 1.5, 69), (25.5, .5, 71), (26, 1, 69), (27, 1, 66), (28, 3.5, 64)]
SOLO = [(0, .5, 72), (.5, .5, 71), (1, .5, 72), (1.5, .5, 74), (2, 2, 76),
        (4, .5, 74), (4.5, .5, 71), (5, 1, 67), (6, 1.5, 71), (7.5, .5, 74),
        (8, 1, 78), (9, 1, 76), (10, 1, 74), (11, 1, 69),
        (12, 2, 71), (14, .5, 69), (14.5, .5, 67), (15, 1, 64),
        (16, .5, 64), (16.5, .5, 67), (17, .5, 71), (17.5, .5, 72), (18, 1, 76), (19, 1, 72),
        (20, .5, 74), (20.5, .5, 76), (21, 1, 79), (22, 2, 74),
        (24, 1, 78), (25, 1, 74), (26, 1, 76), (27, 1, 78), (28, 3.5, 79)]
# サビの新しいフック（高く、同じリズムの動機をくり返す）
HOOK = [(0, .5, 76), (.5, .5, 76), (1, 1, 79), (2, .5, 76), (2.5, 1.5, 72),
        (4, .5, 74), (4.5, .5, 74), (5, 1, 79), (6, .5, 74), (6.5, 1.5, 71),
        (8, .5, 74), (8.5, .5, 74), (9, 1, 78), (10, .5, 76), (10.5, 1.5, 74),
        (12, .5, 71), (12.5, .5, 74), (13, 3, 76),
        (16, .5, 76), (16.5, .5, 76), (17, 1, 79), (18, .5, 76), (18.5, 1.5, 72),
        (20, .5, 74), (20.5, .5, 76), (21, 1, 79), (22, .5, 81), (22.5, 1.5, 79),
        (24, 1, 81), (25, 1, 79), (26, 1, 78), (27, 1, 74), (28, 3.5, 76)]
TB_T = -12  # 1オクターブ下で鳴らす（フォルマント表の母音がはっきりする高さ）


def build(solo=None):
    b = AutoBuilder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    GL, GR, TB, BA = t["Gtr L"], t["Gtr R"], t["Talkbox"], t["Bass"]
    LG, GH, RI = t["Lead Gtr"], t["Gtr Hi"], t["Riser"]
    K, S, TO, CY = t["Kick"], t["Snare"], t["Toms"], t["Cymbals"]

    VA, VB = ["E5", "E5", "C5", "D5"], ["E5", "E5", "C5", "B5"]
    PRE = ["C5", "D5", "C5", "B5"]
    CH = ["C5", "G5", "D5", "E5"]
    L4 = 4 * BAR
    # 刻み（ブリッジミュート）はカットオフを下げて詰まった音に（クリップのオートメーション）
    mute = [dict(param="cutoffHz", points=[[0, 1300], [L4, 1300]]),
            dict(param="decayS", points=[[0, 0.12], [L4, 0.12]]),
            dict(param="sustain", points=[[0, 0.3], [L4, 0.3]])]
    # Bメロ：刻みのフィルターと減衰が開いていく
    opening = lambda cut: [dict(param="cutoffHz", points=[[0, 1300], [L4, cut]]),
                           dict(param="decayS", points=[[0, 0.12], [L4, 0.4]]),
                           dict(param="sustain", points=[[0, 0.3], [L4, 0.85]])]

    # オートメーションは最後の値を保つので、サビのクリップで素の音色へ戻す
    def restore(cut):
        return [dict(param="cutoffHz", points=[[0, cut], [L4, cut]]),
                dict(param="decayS", points=[[0, 0.4], [L4, 0.4]]),
                dict(param="sustain", points=[[0, 0.85], [L4, 0.85]])]
    for g, cut in ((GL, 3400), (GR, 3000)):
        b.clip(g, 4, riff_intro(), [0])
        b.clip(g, 4, palm(VA), [4], automation=mute)
        b.clip(g, 4, palm(VB), [8], automation=mute)
        b.clip(g, 4, palm(PRE), [12], automation=opening(cut))
        b.clip(g, 4, chug_open(CH), [16, 20, 24, 28, 32, 36], automation=restore(cut))
        b.clip(g, 2, [n(0, 2 * BAR - 100, p, 1.0) for p in pc("E5")], [40])
    # サビだけオクターブ上のコード（ハーフノートで伸ばして厚く）
    hi = [n(i * BAR + h * PPQ * 2, PPQ * 2 - 30, p + 12, 0.85) for i, c in enumerate(CH) for h in range(2) for p in pc(c)]
    b.clip(GH, 4, hi, [16, 20, 32, 36])
    b.clip(BA, 4, bass_intro(), [0])
    b.clip(BA, 4, bass8(VA), [4])
    b.clip(BA, 4, bass8(VB), [8])
    b.clip(BA, 4, bass8(PRE), [12])
    b.clip(BA, 4, bass8(CH), [16, 20, 24, 28, 32, 36])
    b.clip(BA, 2, [n(0, 2 * BAR - 100, 28, 1.0)], [40])

    tb = lambda mel, bars: talkbox([(x, l, p + TB_T) for x, l, p in mel], TEMPO, bars * BAR)
    notes, auto = tb(VERSE_ANSWER, 4)
    b.clip(TB, 4, notes, [8], automation=auto)
    notes, auto = tb(CHORUS_MEL[:13], 4)  # Bメロ：旧サビの前半を合いの手に
    b.clip(TB, 4, notes, [12], automation=auto)
    notes, auto = tb(HOOK, 8)
    b.clip(TB, 8, notes, [16, 32], automation=auto)
    notes, auto = tb(SOLO, 8)
    b.clip(TB, 8, notes, [24], automation=auto)
    b.clip(LG, 8, [n(x * PPQ, l * PPQ - 40, p, 0.85) for x, l, p in HOOK], [16, 32])

    # ドラム
    k, s, c = drums_rock(4, kick_pat=(0, 8, 10), crash=True)
    b.clip(K, 4, k, [0])
    b.clip(S, 4, [x for x in s if x[0] < 3 * BAR + 8 * S16], [0])
    b.clip(CY, 4, c, [0])
    b.clip(TO, 1, fill(0), [3, 11, 23, 31, 39])
    k, s, c = drums_rock(4, crash=True)
    b.clip(K, 4, k, [4, 8])
    b.clip(S, 4, s, [4, 8, 24, 28])
    b.clip(CY, 4, c, [4, 8])
    # Bメロ：キックは4分、スネアは3拍目 → 8分 → 16分のロール、ライザー
    b.clip(K, 4, [x for bb in range(4) for x in steps(bb, [0, 4, 8, 12], S16, [KICK], 1.0)], [12])
    sn = [x for bb in range(2) for x in steps(bb, [8], S16, [SNARE], 0.95)]
    sn += [n(2 * BAR + k * PPQ // 2, PPQ // 2 - 20, SNARE, 0.55 + 0.04 * k) for k in range(8)]
    sn += [n(3 * BAR + k * S16, S16 - 10, SNARE, 0.6 + 0.025 * k) for k in range(16)]
    b.clip(S, 4, sn, [12])
    b.clip(CY, 4, [n(bb * BAR + e * PPQ, PPQ, 53, 0.7) for bb in range(4) for e in range(4)] + [n(0, BAR, CRASH, 0.8)], [12])
    b.clip(RI, 4, [n(0, 4 * BAR - 30, 60, 0.9)], [12])
    # サビ：8分で押すキック、クラッシュは毎小節の頭、ライド
    k, s, c = drums_rock(4, kick_pat=(0, 3, 6, 8, 10, 14), crash=True, ride=True)
    c += [n(bb * BAR, BAR, CRASH, 0.75) for bb in (1, 2, 3)]
    b.clip(K, 4, k, [16, 20, 24, 28, 32, 36])
    b.clip(S, 4, s, [16, 20, 32, 36])
    b.clip(CY, 4, c, [16, 20, 32, 36])
    k2, s2, c2 = drums_rock(4, kick_pat=(0, 3, 6, 8, 10, 14), crash=True, ride=True)
    b.clip(CY, 4, c2, [24, 28])
    b.clip(CY, 1, [n(0, BAR, CHINA, 0.8)], [32])
    b.clip(RI, 2, [n(0, 2 * BAR - 30, 60, 0.7)], [30])
    # 終わり
    b.clip(K, 2, [n(0, S16, KICK, 1.0)], [40])
    b.clip(S, 2, [n(0, S16, SNARE, 1.0)], [40])
    b.clip(CY, 2, [n(0, 2 * BAR, CRASH, 1.0), n(0, 2 * BAR, CHINA, 0.7)], [40])

    return dict(format="mobiledaw-project", version=1, title="オーバードライブ", tempo=TEMPO, timeSig=[4, 4],
                key=dict(root=4, scale="minor"),
                master=dict(gain=2.5, glue=0.9, thresholdDb=-12, ratio=1.8, softClip=0.75, ceiling=0.93),
                aux=dict(reverbReturn=0.7, reverbSize=0.48, delayReturn=0.4, delayFeedback=0.28),
                tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/rock.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
