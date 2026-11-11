#!/usr/bin/env python3
"""A.I.テクノ系テクノポップのインスト「ネコミミ☆プロトコル」（project.json）を作る。

  python3 tools/demos/nekomimi.py [出力先] [--solo トラック名]

148 BPM / D major（ラストサビで E major へ全音上げ）/ 74小節（約2分）。メロディ・進行は書き下ろし。
ブレイクビーツ寄りのエレクトロ（キックが裏に食う、ゴーストスネア）。最後のサビの2周目だけ4つ打ちになる。
歌は無く、主旋律は明るいのこぎり波のリード（Melody：モノ＋ポルタメント、長い音に遅れて浅いビブラート）。
フック：主旋律の2拍の呼びかけ（D↗A→F#→E）に、矩形波のリード（Lead）が同じ形を1オクターブ上の16分で答える
  （コール＆レスポンス）。2回目は C#ø の上で形を変え、3回目で降りてくる。
  （メロディの音節は歌があった頃の名残で、音の数と区切りの目安）
  小節  0– 3  リフ（リードが呼びかけと答えを両方弾く）
        4–11  Aメロ      GM9 → F#m7 → Em9 → A13（IV–iii–ii–V を下りる）×2
       12–15  Bメロ      Bm9 → B♭M9 → C9（♭VI–♭VII で明るく持ち上げてサビの D へ）
       16–23  サビ       DM9 → C#m7♭5・F#7 → Bm9 → Am7・D7 → GM9 → Gm6 → F#m7・B7 → Em9・E♭M9（半音上から D へ）
       24–27  リフ / 28–35 Aメロ2 / 36–39 Bメロ / 40–47 サビ
       48–51  ブレイク    GM9 → Gm6 → Em9 → B7sus4・B7（主旋律がゆっくりフックの形をなぞる）
       52–67  ラストサビ（+2）×2（2周目は4つ打ち、リードがフックを重ねる）/ 68–71 リフ（+2）/ 72–73 EM9
ベースはのこぎり波を低く絞り（5倍音が出にくい）、1オクターブ下のサインを主にした音。
音はエンジンの合成と同梱の Chiptune キット（自作合成）。キックはシンセで A に合わせる。
"""
import aitechno as A
from aitechno import BAR, note, parse_mel, coin, powerup

TEMPO = 148.0
OUT = "app/assets/demos/nekomimi.json"
MAP = "/tmp/cc/nekomimi_map.json"

SOUNDS = A.sounds(
    "Melody", "Lead", "Stab", "Gtr", "Bass", "Arp", "Beep", "Pad", "Kick", "Drums",
    Melody=dict(color="ffff7ac8",  # 主旋律：明るいのこぎり波のリード（モノ＋ポルタメント、遅れて浅いビブラート）
                synth=dict(wave=0, osc=1, unison=2, detuneCents=8, width=0.25, blend=0.85, mono=1, glideS=0.04,
                           cutoffHz=3800, resonance=0.8, filterEnv=0.35, filterEnvDecayS=0.18, keyTrack=0.4,
                           attackS=0.006, decayS=0.3, sustain=0.75, releaseS=0.12, wtLfoRate=5.6, lfoPitch=0.0,
                           masterGain=0.6),
                fx=dict(lowCutHz=220, saturation=0.08, chorus=0.12, ott=0.15, eqHighDb=1, eqHighHz=6000,
                        comp=0.3, compThresholdDb=-16, compRatio=3, sendDelay=0.18, sendReverb=0.2),
                mixer=dict(gain=0.5, pan=0)),
    Stab=dict(color="ffffb15a",
              synth=dict(wave=0, unison=3, detuneCents=9, width=0.6, cutoffHz=3000, resonance=0.9,
                         filterEnv=0.5, filterEnvDecayS=0.08, keyTrack=0.4,
                         attackS=0.002, decayS=0.12, sustain=0.15, releaseS=0.05, masterGain=0.45),
              fx=dict(lowCutHz=250, eqMidDb=-2, eqMidHz=500, chorus=0.15, sendReverb=0.12, sendDelay=0.08),
              mixer=dict(gain=0.6, pan=0.15)),
    # のこぎり波を 380 Hz で絞って、1オクターブ下のサインを主に（上の倍音、とくに5倍音を弱く）
    Bass=dict(synth=dict(wave=0, osc=0.45, sub=0.85, unison=1, mono=1, glideS=0.012, drive=0.0,
                         cutoffHz=380, resonance=0.6, filterEnv=0.25, filterEnvDecayS=0.07, keyTrack=0.15,
                         attackS=0.003, decayS=0.3, sustain=0.65, releaseS=0.05, masterGain=0.75),
              fx=dict(saturation=0.0, eqLowDb=0, comp=0.3, compThresholdDb=-16, compRatio=3),
              mixer=dict(gain=0.38)),
    Lead=dict(mixer=dict(gain=0.5)),
    Gtr=dict(mixer=dict(gain=0.5, pan=-0.3)),
    Arp=dict(mixer=dict(gain=0.8)),
    Kick=dict(color="fff28c38",
              synth=dict(osc=0.7, sub=0.0, unison=1, cutoffHz=900, resonance=0.7, keyTrack=0,
                         pitchEnv=30, pitchEnvDecayS=0.035, filterEnv=0.85, filterEnvDecayS=0.03,
                         attackS=0.0005, decayS=0.24, sustain=0, releaseS=0.04, masterGain=1.0),
              fx=dict(saturation=0.25, eqLowDb=2, eqLowHz=60, eqMidDb=-2.5, eqMidHz=300,
                      comp=0.4, compThresholdDb=-12, compRatio=3.5, sidechainSource=1),
              mixer=dict(gain=0.34, pan=0)),  # 0.6 から 5 dB 下げた（大きすぎたため）
    Drums=dict(color="fff2d45a", kit="chiptune", synth=dict(masterGain=1, unison=1),
               fx=dict(lowCutHz=150, comp=0.25, sendReverb=0.1), mixer=dict(gain=0.32, pan=0)),
)
for k in ("Stab", "Gtr", "Pad", "Bass", "Arp"):
    SOUNDS[k]["fx"].update(sidechain=0.32 if k == "Bass" else 0.2, sidechainReleaseS=0.11)  # キックを下げたぶん揺れも少し浅く

CH = {
    "DM9": ([64, 66, 69, 73], 50), "C#m7b5": ([64, 67, 71, 73], 49), "F#7": ([64, 66, 70, 73], 42),
    "Bm9": ([61, 62, 66, 69], 47), "Am7": ([64, 67, 69, 72], 45), "D7": ([64, 66, 69, 72], 50),
    "GM9": ([62, 66, 69, 71], 43), "Gm6": ([62, 64, 67, 70], 43), "F#m7": ([64, 66, 69, 73], 42),
    "B7": ([63, 66, 69, 71], 47), "Em9": ([62, 66, 67, 71], 40), "A13": ([61, 66, 67, 71], 45),
    "EbM9": ([62, 65, 67, 70], 51), "BbM9": ([62, 65, 69, 72], 46), "C9": ([64, 67, 70, 74], 48),
    "B7sus4": ([64, 66, 69, 71], 47),
}
RIFF = [("DM9", 4), ("C#m7b5", 2), ("F#7", 2), ("Bm9", 4), ("Am7", 2), ("D7", 2)]
CHO = RIFF + [("GM9", 4), ("Gm6", 4), ("F#m7", 2), ("B7", 2), ("Em9", 2), ("EbM9", 2)]
VERSE = [("GM9", 4), ("F#m7", 4), ("Em9", 4), ("A13", 4)] * 2
PRE = [("Bm9", 8), ("BbM9", 4), ("C9", 4)]
BRK = [("GM9", 4), ("Gm6", 4), ("Em9", 4), ("B7sus4", 2), ("B7", 2)]
KICK = 45  # A2（ピッチエンベロープで下がる）
SN, CLAP, RIM, HH, OH, CRASH, SHK = 38, 39, 37, 42, 46, 49, 82

# ---- 主旋律（もとは歌のメロディ。音節は区切りの目安） ----
VPOS = [(0, .5), (.5, .5), (1.5, .5), (2, .5), (2.5, .5), (3, 1), (4, .5), (4.5, .5), (5.5, .5), (6, .5), (6.5, 1.5)]
VMEL = ["D5 D5 B4 D5 E5 F#5 E5 C#5 A4 C#5 E5", "D5 D5 B4 D5 E5 G5 F#5 E5 C#5 E5 G5",
        "D5 D5 B4 D5 E5 F#5 E5 C#5 A4 C#5 E5", "D5 D5 B4 D5 E5 G5 A5 F#5 E5 C#5 E5"]


def verse(lines):
    out = []
    for i, (m, t) in enumerate(zip(VMEL, lines)):
        out += parse_mel(8 * i, " ".join(f"{b}/{l}/{p}" for (b, l), p in zip(VPOS, m.split())), t)
    return out


VERSE1 = verse(["pi po pa po de ki do u shi ta yo", "ne ko mi mi mo tsu ke te mi ta yo",
                "ka wa i i ka na ki ni na ru no", "ki mi no e ga o o yo mi ko mu"])
VERSE2 = verse(["yo zo ra ni ho shi no a i ko N", "ne ga i go to o ka ki ko mu yo",
                "ba gu ga de te mo da i jo u bu", "ki mi ga i re ba sa i ki do u"])
PRE_MEL = (parse_mel(0, "0/.5/B4 .5/.5/D5 1/.5/B4 1.5/.5/D5 2/.5/F#5 2.5/.5/E5 3/.5/D5 3.5/4.5/C#5",
                     "do ki do ki shi su te mu")
           + parse_mel(8, "0/1/D5 1/1/F5 2/.5/A5 2.5/.5/G5 3/1/F5 4/1/E5 5/3/G5", "ha ji ma ru yo i ma"))
HOOK = parse_mel(0, "0/.5/D5 .5/.5/A5 1/.5/F#5 1.5/1/E5"
                    " 4/.5/C#5 4.5/.5/G5 5/.5/E5 5.5/1/C#5"
                    " 8/.5/F#5 8.5/.5/E5 9/.5/D5 9.5/.5/C#5 10/.5/D5 10.5/.5/A5 11/.5/F#5 11.5/2/E5"
                    " 16/.5/D5 16.5/.5/D5 17/.5/F#5 17.5/.5/F#5 18/.5/A5 18.5/1/G5"
                    " 20/.5/Bb4 20.5/.5/D5 21/.5/E5 21.5/.5/G5 22/.5/E5 22.5/1.5/D5"
                    " 24/.5/C#5 24.5/.5/E5 25/.5/A5 25.5/.5/F#5 26/.5/F#5 26.5/.5/D#5 27/.5/F#5 27.5/.5/A5 28/3/G5",
                 "ro gu i N ro gu i N ha a to ni ro gu i N pa su wa a do wa ki mi no na ma e"
                 " ne ko mi mi pu ro to ko ru")
ANSWER = parse_mel(0, "2.5/.25/D6 2.75/.25/A6 3/.25/F#6 3.25/.75/E6"
                      " 6.5/.25/A#5 6.75/.25/C#6 7/.25/E6 7.25/.75/F#6"
                      " 14/.25/F#5 14.25/.25/A5 14.5/.25/C6 14.75/1/D6"
                      " 30/.25/F5 30.25/.25/G5 30.5/.25/Bb5 30.75/1/D6", None)
CALLS = [x for x in HOOK if x[0] < 16]
# ブレイク：主旋律がゆっくりフックの形（上がって降りる）をなぞる
BRK_MEL = parse_mel(0, "0/1/D5 1/1/F#5 2/2/A5 4/1/D5 5/1/E5 6/2/G5 8/1/B4 9/1/D5 10/2/F#5 12/2/E5 14/2/F#5", None)


# ---- リズム ----
def hits(bars, pos, pitch, vel, ln=1):
    return [note(b * 4 + p / 4, ln / 4, pitch, vel(p) if callable(vel) else vel, 0) for b in range(bars) for p in pos]


def kicks(bars, kind):
    if kind == "four":
        return hits(bars, (0, 4, 8, 12), KICK, 1.0, 2)
    out = []
    for b in range(bars):
        pos = (0, 6, 10) if b % 2 == 0 else (0, 3, 10, 14)
        out += [note(b * 4 + p / 4, .5, KICK, 1.0 if p == 0 else 0.9, 0) for p in pos]
    return out


def drums(bars, kind):
    out = []
    if kind in ("break", "four", "verse"):
        out += hits(bars, (4, 12), SN, 0.85) + hits(bars, (7, 15), SN, 0.25)
        out += hits(bars, range(0, 16, 2), HH, lambda p: 0.5 if p % 4 == 2 else 0.32)
    if kind in ("break", "four"):
        out += hits(bars, (4, 12), CLAP, 0.6) + hits(bars, (14,), OH, 0.4, 2) + hits(bars, (1, 5, 9, 13), HH, 0.22)
    if kind == "four":
        out += hits(bars, (2, 6, 10), OH, 0.35, 2)
    if kind == "light":
        out += hits(bars, range(0, 16, 2), HH, 0.38) + hits(bars, range(16), SHK, 0.2)
    return out


def fill(bar):
    return [note(bar * 4 + 2 + k / 4, 0.25, SN, 0.45 + 0.05 * k, 0) for k in range(8)]


BASS_CHO = "R-.R..O.R-.R.OR."
BASS_VERSE = "R-..R-.O..R-.R.."
STAB = (2, 6, 10, 14)
GTR = "x.gxg.x.gxg.xg.x"


def build(solo=None):
    s = A.Song(SOUNDS, TEMPO, solo)
    cut = lambda a, z, bars=4: [dict(param="cutoffHz", points=[[0, a], [bars * BAR, z]])]

    def riff(at, tr=0, first=False):
        s.chords(at, CH, RIFF, tr)
        s.clip("Lead", 4, A.lead(CALLS, tr, 0.85) + A.lead(ANSWER[:12], tr, 0.8), [at])
        s.clip("Gtr", 4, A.gtr(CH, RIFF, GTR, tr), [at], automation=cut(700, 2200) if first else None)
        s.clip("Stab", 4, A.comp(CH, RIFF, STAB, 1, 0.6, tr, 12), [at])
        s.clip("Bass", 4, A.bassline(CH, RIFF, BASS_CHO, tr), [at])
        s.clip("Pad", 4, A.held(CH, RIFF, 0.4, tr), [at])
        s.clip("Kick", 4, kicks(4, "break"), [at])
        s.clip("Drums", 4, drums(4, "break") + [note(0, 4, CRASH, 0.6)], [at])

    riff(0, 0, True)
    riff(24)
    s.clip("Beep", 1, coin(3, (74, 78, 81)), [3])
    # Aメロ
    for at, mel in ((4, VERSE1), (28, VERSE2)):
        s.chords(at, CH, VERSE)
        s.melody(mel, 8, [at], 0.06)
        print("verse", A.check_melody("A", mel, CH, VERSE))
    s.clip("Stab", 8, A.comp(CH, VERSE, STAB, 1, 0.65, 0, 12), [4, 28])
    s.clip("Gtr", 8, A.gtr(CH, VERSE, "..x.g.x...x.g.xg"), [4, 28])
    s.clip("Bass", 8, A.bassline(CH, VERSE, BASS_VERSE), [4, 28])
    s.clip("Kick", 8, kicks(8, "break"), [4, 28])
    s.clip("Drums", 8, drums(8, "verse"), [4, 28])
    tl = A.timeline(VERSE)
    s.clip("Beep", 8, [x for b in range(1, 8, 2) for x in
                       [note(b * 4 + 3.5, .25, CH[A.chord_at(tl, b * 4 + 3.5)[0]][0][-1] + 12, 0.5, 0),
                        note(b * 4 + 3.75, .25, CH[A.chord_at(tl, b * 4 + 3.5)[0]][0][-2] + 24, 0.45, 0)]], [4, 28])
    # Bメロ
    for at in (12, 36):
        s.chords(at, CH, PRE)
    print("pre", A.check_melody("B", PRE_MEL, CH, PRE))
    s.melody(PRE_MEL, 4, [12, 36], 0.06)
    s.clip("Stab", 4, A.held(CH, PRE, 0.45, 0, 12), [12, 36])
    s.clip("Pad", 4, A.held(CH, PRE, 0.45), [12, 36])
    s.clip("Arp", 4, A.arp(CH, PRE, 0, 12, 0.45), [12, 36], automation=cut(1200, 4500))
    s.clip("Bass", 4, A.bassline(CH, PRE, "R-.R..R.R-.R..R."), [12, 36])
    s.clip("Kick", 4, [x for x in hits(4, (0, 4, 8, 12), KICK, 0.95, 2) if x[0] < 3 * BAR + 2 * A.PPQ], [12, 36])
    s.clip("Drums", 4, drums(3, "verse") + fill(3), [12, 36])
    s.clip("Beep", 4, powerup(14.0, (60, 64, 67, 70, 72, 76, 79, 82)), [12, 36])
    # サビ
    for at, tr, four in ((16, 0, False), (40, 0, False), (52, 2, False), (60, 2, True)):
        s.chords(at, CH, CHO, tr)
        s.melody(HOOK, 8, [at], 0.08, tr)
        s.clip("Lead", 8, A.lead(ANSWER, tr, 0.8) + (A.lead(HOOK, tr + 12, 0.35) if four else []), [at])
        s.clip("Stab", 8, A.comp(CH, CHO, STAB, 1, 0.7, tr, 12), [at])
        s.clip("Gtr", 8, A.gtr(CH, CHO, GTR, tr), [at])
        s.clip("Pad", 8, A.held(CH, CHO, 0.45, tr), [at])
        s.clip("Bass", 8, A.bassline(CH, CHO, BASS_CHO if not four else "R-.OR-.OR-.OR-.O", tr), [at])
        s.clip("Arp", 8, A.arp(CH, CHO, tr, 24, 0.35), [at])
        s.clip("Kick", 8, kicks(8, "four" if four else "break"), [at])
        s.clip("Drums", 8, drums(8, "four" if four else "break") + [note(0, 4, CRASH, 0.7)], [at])
    print("hook", A.check_melody("S", HOOK, CH, CHO), A.check_melody("ans", ANSWER, CH, CHO))
    # ブレイク
    s.chords(48, CH, BRK)
    s.clip("Pad", 4, A.held(CH, BRK, 0.5), [48])
    s.clip("Stab", 4, A.comp(CH, BRK, (0, 6, 12), 2, 0.45, 0, 12), [48])
    s.clip("Bass", 4, [note(s_, l, CH[c][1], 0.7) for c, s_, l in A.timeline(BRK)], [48])
    s.clip("Drums", 4, drums(3, "light") + fill(3), [48])
    s.melody(BRK_MEL, 4, [48], 0.08, vel=0.62)
    print("break", A.check_melody("Br", BRK_MEL, CH, BRK))
    s.clip("Arp", 4, A.arp(CH, BRK, 0, 12, 0.3, 2), [48])
    s.clip("Beep", 4, powerup(14.0, (59, 63, 66, 69, 71, 75, 78, 81)), [48])
    # アウトロ
    riff(68, 2)
    s.chords(72, CH, [("DM9", 8)], 2)
    s.clip("Pad", 2, A.held(CH, [("DM9", 8)], 0.45, 2), [72])
    s.clip("Stab", 1, A.held(CH, [("DM9", 4)], 0.55, 2, 12), [72])
    s.clip("Bass", 2, [note(0, 4, 52, 0.8)], [72])
    s.clip("Kick", 1, [note(0, .5, KICK, 1)], [72])
    s.clip("Drums", 1, [note(0, 4, CRASH, 0.6)], [72])
    s.clip("Beep", 1, coin(0.5, (76, 80, 83)), [72])
    data = s.project("ネコミミ☆プロトコル", 2, dict(gain=MASTER_GAIN, glue=0.6, thresholdDb=-10, ratio=1.8,
                                                   softClip=0.35, ceiling=0.72))
    return s, data


MASTER_GAIN = 5.4

if __name__ == "__main__":
    A.main(build, OUT, MAP)
