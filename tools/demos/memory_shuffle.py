#!/usr/bin/env python3
"""A.I.テクノ系テクノポップのインスト「メモリー☆シャッフル」（project.json）を作る。

  python3 tools/demos/memory_shuffle.py [出力先] [--solo トラック名]

120 BPM / E major（ラストサビで F major へ半音上げ）/ 66小節（約2分12秒）。メロディ・進行は書き下ろし。
16分が跳ねるシャッフル（裏の16分を 60 tick 遅らせる）。ローズ風エレピとカッティングでシティポップ／渋谷系寄り。
歌は無く、主旋律はあたたかいのこぎり波のシンセブラス風リード（Melody：モノ＋ポルタメント、遅れてビブラート）。
フック：（もとは「メモリー メモリー」） C#↗G#（5度の跳躍）→F#→E と降りる動機を、2回目は B13sus4 の上で A→F# に変える。
  3行目も同じ跳躍で始まる。矩形波のリード（Lead）が合間に1オクターブ上で答え、イントロ・間奏・アウトロのリフもフックをなぞる。
  小節  0– 3  イントロ    リードがフックを弾く
        4–11  Aメロ      AM9 → G#m7 → F#m9 → EM9 → AM9 → G#m7・G9（半音で降りる）→ F#m9 → B13sus4・B7
       12–15  Bメロ      C#m9 → G#m7 → Bm9・E9（IV へのツーファイブ）→ B13sus4
       16–23  サビ       AM9 → B13sus4・B7 → G#m7 → C#m9 → F#m9 → G#m7・G°7（経過の減七）→ F#m9 → B13sus4・B7（王道進行）
       24–27  リフ / 28–35 Aメロ2 / 36–39 Bメロ / 40–47 サビ
       48–51  ブレイク    AM9 → Am6（同主短調の iv）→ G#m7 → C7（F の V）。主旋律がゆっくり和音をなぞる
       52–59  ラストサビ（+1）/ 60–63 リフ（+1）/ 64–65 FM9
（メロディの音節は歌があった頃の名残で、音の数と区切りの目安）
ベースは低く絞ったのこぎり波＋1オクターブ下のサイン（5倍音を弱く）。
音はエンジンの合成と同梱の Future Bass Pro キット（ドラム）。
"""
import aitechno as A
from aitechno import BAR, note, parse_mel, coin, powerup

A.SWING = 60
TEMPO = 120.0
OUT = "app/assets/demos/memory_shuffle.json"
MAP = "/tmp/cc/memory_shuffle_map.json"

SOUNDS = A.sounds(
    "Melody", "EP", "Gtr", "Bass", "Lead", "Arp", "Beep", "Pad", "Kick", "Drums",
    Melody=dict(color="ffff9a7a",  # 主旋律：あたたかいのこぎり波のシンセブラス風（モノ＋ポルタメント、遅れてビブラート）
                synth=dict(wave=0, osc=1, unison=3, detuneCents=10, width=0.35, blend=0.85, mono=1, glideS=0.06,
                           cutoffHz=2600, resonance=0.7, filterEnv=0.4, filterEnvDecayS=0.25, keyTrack=0.4,
                           attackS=0.012, decayS=0.4, sustain=0.72, releaseS=0.2, wtLfoRate=5.2, lfoPitch=0.0,
                           masterGain=0.6),
                fx=dict(lowCutHz=200, saturation=0.06, chorus=0.25, ott=0.12, comp=0.3, compThresholdDb=-16,
                        compRatio=3, sendDelay=0.2, sendReverb=0.28),
                mixer=dict(gain=0.58, pan=0)),
    EP=dict(mixer=dict(gain=0.45)),
    Gtr=dict(mixer=dict(gain=0.65)),
    Bass=dict(synth=dict(wave=0, osc=0.45, sub=0.85, unison=1, mono=1, glideS=0.015, drive=0.0,
                         cutoffHz=380, resonance=0.6, filterEnv=0.3, filterEnvDecayS=0.08, keyTrack=0.15,
                         attackS=0.003, decayS=0.35, sustain=0.6, releaseS=0.06, masterGain=0.75),
              fx=dict(saturation=0.0, eqLowDb=0, comp=0.3, compThresholdDb=-16, compRatio=3),
              mixer=dict(gain=0.38)),
    Lead=dict(synth=dict(cutoffHz=3600, attackS=0.004, decayS=0.25, sustain=0.5, releaseS=0.12),
              fx=dict(chorus=0.2), mixer=dict(gain=0.55)),
    Arp=dict(mixer=dict(gain=1.0)),
    Pad=dict(mixer=dict(gain=0.3)),
    Kick=dict(color="fff28c38", kit="future-bass-pro", synth=dict(masterGain=1, unison=1),
              fx=dict(sidechainSource=1), mixer=dict(gain=0.13, pan=0)),
    Drums=dict(color="fff2d45a", kit="future-bass-pro", synth=dict(masterGain=1, unison=1),
               fx=dict(lowCutHz=150, comp=0.2, sendReverb=0.08), mixer=dict(gain=0.3, pan=0)),
)
for k in ("EP", "Gtr", "Pad", "Bass", "Arp"):
    SOUNDS[k]["fx"].update(sidechain=0.3 if k == "Bass" else 0.18, sidechainReleaseS=0.12)

CH = {
    "AM9": ([61, 64, 68, 71], 45), "B13sus4": ([57, 64, 68, 73], 47), "B7": ([63, 66, 69, 73], 47),
    "G#m7": ([63, 66, 68, 71], 44), "C#m9": ([63, 64, 68, 71], 49), "F#m9": ([64, 68, 69, 73], 42),
    "Gdim7": ([64, 67, 70, 73], 43), "EM9": ([63, 66, 68, 71], 40), "G9": ([65, 69, 71, 74], 43),
    "Bm9": ([61, 62, 66, 69], 47), "E9": ([62, 66, 68, 71], 40), "Am6": ([60, 64, 66, 69], 45),
    "C7": ([64, 67, 70, 74], 48),
}
RIFF = [("AM9", 4), ("B13sus4", 2), ("B7", 2), ("G#m7", 4), ("C#m9", 4)]
CHO = RIFF + [("F#m9", 4), ("G#m7", 2), ("Gdim7", 2), ("F#m9", 4), ("B13sus4", 2), ("B7", 2)]
VERSE = [("AM9", 4), ("G#m7", 4), ("F#m9", 4), ("EM9", 4), ("AM9", 4), ("G#m7", 2), ("G9", 2),
         ("F#m9", 4), ("B13sus4", 2), ("B7", 2)]
PRE = [("C#m9", 4), ("G#m7", 4), ("Bm9", 2), ("E9", 2), ("B13sus4", 4)]
BRK = [("AM9", 4), ("Am6", 4), ("G#m7", 4), ("C7", 4)]
KICK, SN, GHOST, RIM, CLAP, HH, HHS, OH, CRASH, SHK, CLAV = 36, 38, 31, 37, 39, 42, 44, 58, 51, 82, 75

# ---- 主旋律（もとは歌のメロディ。音節は区切りの目安） ----
VPOS = [(0, .75), (.75, .75), (1.5, .5), (2, 1.5), (4, .5), (4.5, .5), (5, .75), (5.75, .75), (6.5, 1.5)]
VMEL = ["B4 C#5 E5 C#5 B4 B4 D#5 F#5 D#5", "A4 B4 C#5 A4 G#4 G#4 B4 D#5 B4",
        "B4 C#5 E5 C#5 B4 B4 D#5 B4 D5", "A4 B4 C#5 E5 E5 F#5 G#5 A5 F#5"]


def verse(lines):
    out = []
    for i, (m, t) in enumerate(zip(VMEL, lines)):
        out += parse_mel(8 * i, " ".join(f"{b}/{l}/{p}" for (b, l), p in zip(VPOS, m.split())), t)
    return out


VERSE1 = verse(["a ru ba mu hi ra i te ru", "a no hi no yu u ya ke ga",
                "ki ra ki ra ni ji N de ru", "ko ko ro ga a ta ta ka i"])
VERSE2 = verse(["sa ku ra mo na tsu no ho shi", "mo mi ji mo fu yu no yu ki",
                "ka ra fu ru na ki o ku ga", "ki ra me ku ta ka ra mo no"])
PRE_MEL = (parse_mel(0, "0/1/E5 1/1/D#5 2/.75/E5 2.75/1.25/G#5 4/.75/F#5 4.75/.75/D#5 5.5/.5/B4 6/2/D#5",
                     "ki o ku ga ki e te mo")
           + parse_mel(8, "0/.5/D5 .5/.5/F#5 1/1/A5 2/.75/G#5 2.75/.75/F#5 3.5/.5/D5 4/1/E5 5/1/F#5 6/2/G#5",
                       "ki mi no ko e wa no ko ru"))
HOOK = parse_mel(0, "0/.75/C#5 .75/.75/G#5 1.5/.5/F#5 2/1.5/E5"
                    " 4/.75/C#5 4.75/.75/G#5 5.5/.5/A5 6/1.5/F#5"
                    " 8/.75/D#5 8.75/.75/F#5 9.5/.5/D#5 10/1/B4 11/.5/D#5 11.5/.5/F#5 12/2.5/G#5"
                    " 16/.75/C#5 16.75/.75/G#5 17.5/.5/F#5 18/.5/E5 18.5/.5/C#5 19/.5/E5 19.5/.5/F#5 20/1/G#5"
                    " 21/.5/F#5 21.5/.5/D#5 22/.5/C#5 22.5/.5/E5 23/1/A#4"
                    " 24/.5/C#5 24.5/.5/E5 25/.75/A5 25.75/.75/G#5 26.5/1/F#5 27.5/.5/E5 28/.5/G#5 28.5/.5/A5 29/1/F#5",
                 "me mo ri i me mo ri i ki mi to no hi bi o shi a wa se fo ru da ni ho zo N shi te"
                 " na N ka i mo sa i se i")
ANSWER = parse_mel(0, "3/.5/B5 3.5/.5/C#6 7/.5/F#5 7.5/.5/A5 14.5/.5/G#5 15/.5/B5 15.5/.5/C#6"
                      " 30/.5/D#6 30.5/.5/F#6 31/1/A6", None)
RIFF_LEAD = [x for x in HOOK if x[0] < 16]
# ブレイク：主旋律がゆっくり和音をなぞる
BRK_MEL = parse_mel(0, "0/1/C#5 1/1/E5 2/2/G#5 4/1/C5 5/1/E5 6/2/F#5 8/1/B4 9/1/D#5 10/2/F#5 12/2/E5 14/2/G5", None)


# ---- リズム ----
def hits(bars, pos, pitch, vel, ln=1):
    return [note(b * 4 + p / 4, ln / 4, pitch, vel(p) if callable(vel) else vel, 0) for b in range(bars) for p in pos]


def kicks(bars):
    out = []
    for b in range(bars):
        pos = (0, 7, 10) if b % 2 == 0 else (0, 8, 10, 15)
        out += [note(b * 4 + p / 4, .5, KICK, 1.0 if p in (0, 8) else 0.85, 0) for p in pos]
    return out


def drums(bars, kind):
    out = []
    if kind in ("cho", "verse"):
        out += hits(bars, range(16), HHS, lambda p: 0.5 if p % 4 == 2 else (0.36 if p % 2 == 0 else 0.26))
        out += hits(bars, (3, 6, 9, 14), GHOST, 0.22)
    if kind == "cho":
        out += hits(bars, (4, 12), SN, 0.85) + hits(bars, (4, 12), CLAP, 0.45)
        out += hits(bars, (14,), OH, 0.4, 2) + hits(bars, range(16), SHK, 0.25)
    if kind == "verse":
        out += hits(bars, (4, 12), SN, 0.7) + hits(bars, (2, 11), RIM, 0.3)
    if kind == "light":
        out += hits(bars, range(0, 16, 2), HHS, 0.35) + hits(bars, range(16), SHK, 0.22) + hits(bars, (3, 10), CLAV, 0.3)
    return out


def fill(bar):
    return [note(bar * 4 + 2 + k / 4, 0.25, SN if k % 2 == 0 else GHOST, 0.4 + 0.06 * k, 0) for k in range(8)]


BASS_CHO = "R-.gR-.O.gR-.O5."
BASS_VERSE = "R-..R-gO..R-.Og."
EP_VERSE = (0, 3, 8, 11, 14)
EP_CHO = (0, 6, 10, 14)
GTR_VERSE = "..x.g.x...x.gx.."
GTR_CHO = "x.gxg.x.gxg.x.gx"


def build(solo=None):
    s = A.Song(SOUNDS, TEMPO, solo)
    cut = lambda a, z, bars=4: [dict(param="cutoffHz", points=[[0, a], [bars * BAR, z]])]

    def band(at, prog, bars, tr=0, kind="cho", ep=EP_CHO, gtr=GTR_CHO, bass=BASS_CHO):
        s.chords(at, CH, prog, tr)
        s.clip("EP", bars, A.comp(CH, prog, ep, 2.5 if kind == "cho" else 1.6, 0.6, tr), [at])
        s.clip("Gtr", bars, A.gtr(CH, prog, gtr, tr), [at])
        s.clip("Bass", bars, A.bassline(CH, prog, bass, tr), [at])
        s.clip("Kick", bars, kicks(bars), [at])
        s.clip("Drums", bars, drums(bars, kind) + ([note(0, 4, CRASH, 0.55)] if kind == "cho" else []), [at])

    # イントロ・リフ
    for at, tr in ((0, 0), (24, 0), (60, 1)):
        band(at, RIFF, 4, tr)
        s.clip("Pad", 4, A.held(CH, RIFF, 0.4, tr), [at])
        s.clip("Lead", 4, A.lead(RIFF_LEAD, tr, 0.85) + A.lead(ANSWER[4:7], tr, 0.7), [at])
    s.clip("Beep", 1, coin(3, (75, 80, 83)), [3])
    # Aメロ
    for at, mel in ((4, VERSE1), (28, VERSE2)):
        band(at, VERSE, 8, 0, "verse", EP_VERSE, GTR_VERSE, BASS_VERSE)
        s.melody(mel, 8, [at], 0.07)
        print("verse", A.check_melody("A", mel, CH, VERSE))
    tl = A.timeline(VERSE)
    s.clip("Lead", 8, [note(b * 4 + 3.5, .5, CH[A.chord_at(tl, b * 4 + 3.5)[0]][0][-1] + 12, 0.45) for b in (1, 3, 5)], [4, 28])
    # Bメロ
    for at in (12, 36):
        s.chords(at, CH, PRE)
    print("pre", A.check_melody("B", PRE_MEL, CH, PRE))
    s.melody(PRE_MEL, 4, [12, 36], 0.07)
    s.clip("EP", 4, A.comp(CH, PRE, (0, 6, 10), 3, 0.55), [12, 36])
    s.clip("Pad", 4, A.held(CH, PRE, 0.42), [12, 36])
    s.clip("Arp", 4, A.arp(CH, PRE, 0, 12, 0.45, 2), [12, 36], automation=cut(1200, 3500))
    s.clip("Gtr", 4, A.gtr(CH, PRE, "..x...x...x...x."), [12, 36])
    s.clip("Bass", 4, A.bassline(CH, PRE, "R--.R-.R.-R-.R.."), [12, 36])
    s.clip("Kick", 4, [x for x in kicks(4) if x[0] < 3 * BAR + 2 * A.PPQ], [12, 36])
    s.clip("Drums", 4, drums(3, "verse") + fill(3), [12, 36])
    s.clip("Beep", 4, powerup(14.0, (59, 64, 66, 68, 71, 76, 78, 80)), [12, 36])
    # サビ
    for at, tr in ((16, 0), (40, 0), (52, 1)):
        band(at, CHO, 8, tr)
        s.melody(HOOK, 8, [at], 0.09, tr)
        s.clip("Lead", 8, A.lead(ANSWER, tr, 0.75) + (A.lead(HOOK, tr + 12, 0.3) if tr else []), [at])
        s.clip("Pad", 8, A.held(CH, CHO, 0.45, tr), [at])
        s.clip("Arp", 8, A.arp(CH, CHO, tr, 24, 0.3, 4), [at])
    print("hook", A.check_melody("S", HOOK, CH, CHO), A.check_melody("ans", ANSWER, CH, CHO))
    # ブレイク
    s.chords(48, CH, BRK)
    s.clip("Pad", 4, A.held(CH, BRK, 0.5), [48])
    s.clip("EP", 4, A.comp(CH, BRK, (0, 6, 10), 3, 0.5), [48])
    s.clip("Bass", 4, [note(s_, l, CH[c][1], 0.7) for c, s_, l in A.timeline(BRK)], [48])
    s.clip("Drums", 4, drums(3, "light") + fill(3), [48])
    s.melody(BRK_MEL, 4, [48], 0.09, vel=0.62)
    print("break", A.check_melody("Br", BRK_MEL, CH, BRK))
    s.clip("Arp", 4, A.arp(CH, BRK, 0, 12, 0.3, 2), [48])
    s.clip("Beep", 4, powerup(14.0, (60, 64, 67, 70, 72, 76, 79, 82)), [48])
    # エンディング
    s.chords(64, CH, [("EM9", 8)], 1)
    s.clip("Pad", 2, A.held(CH, [("EM9", 8)], 0.45, 1), [64])
    s.clip("EP", 2, A.held(CH, [("EM9", 4)], 0.55, 1), [64])
    s.clip("Bass", 2, [note(0, 4, 41, 0.8)], [64])
    s.clip("Kick", 1, [note(0, .5, KICK, 1)], [64])
    s.clip("Drums", 1, [note(0, 4, CRASH, 0.6)], [64])
    s.clip("Beep", 1, coin(0.5, (76, 81, 84)), [64])
    data = s.project("メモリー☆シャッフル", 4, dict(gain=MASTER_GAIN, glue=0.6, thresholdDb=-10, ratio=1.8,
                                                   softClip=0.35, ceiling=0.72))
    return s, data


MASTER_GAIN = 4.7

if __name__ == "__main__":
    A.main(build, OUT, MAP)
