#!/usr/bin/env python3
"""kawaii フューチャーベースのデモ曲（project.json）を作る。

  python3 tools/demos/future_bass.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/future_bass.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/future_bass.json /tmp/fb.wav   # リポジトリの直下で（kits/ を読む）

150 BPM / F major / 77小節（約2分）
  小節   0– 7  イントロ   ベルのアルペジオ、薄いコード、後半からハイハット
         8–23  Aメロ      ハーフタイムのドラム、刻むコード、チップチューンのリード
        24–31  ビルド     4つ打ち → スネアロール、ノイズのライザー、上がっていく進行
        32–47  サビ       Jersey Club のキック（たんっ、たんっ、たんったんったん）で
                          スーパーソーが跳ねる。ベルのチョップ、サビのメロディ
        48–55  ブレイク   ドラムなし、ベルとコードだけ
        56–59  ビルド2
        60–75  ラストサビ メロディをベルが1オクターブ上で重ねる。最後は F で終わる
        76     終わりの一発
進行
  Aメロ  FM7 → Dm7 → B♭M7 → C（I–vi–IV–V）
  ビルド Gm7 → Am7 → B♭M7 → C
  サビ   B♭M7 → C → Am7 → Dm7 → Gm7 → C7 → FM7 → F7（王道進行から）
"""
import json
import sys

PPQ = 960
BAR = PPQ * 4
S16 = PPQ // 4

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # 明るいスーパーソー。サビはキックごとに大きく引っ込んで跳ねる
    "Chords": dict(
        color="ffc8f25a",
        synth=dict(cutoffHz=12000, resonance=0.8, attackS=0.004, decayS=0.8, sustain=0.8, releaseS=0.25,
                   detuneCents=30, masterGain=0.55, unison=9, width=0.95, blend=0.75, noise=0.03,
                   drive=0.1, filterEnv=0.2, filterEnvDecayS=0.25, wave=0, osc=1),
        fx=dict(lowCutHz=200, saturation=0.1, chorus=0.35, ott=0.5, reverb=0.32, reverbSize=0.7,
                sidechain=0.95, sidechainReleaseS=0.22),
        mixer=dict(gain=0.5, pan=0),
    ),
    # チップチューンっぽい矩形波のリード
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=9000, resonance=0.9, attackS=0.002, decayS=0.2, sustain=0.7, releaseS=0.1,
                   detuneCents=8, masterGain=0.6, unison=2, width=0.3, blend=0.9, filterEnv=0.15,
                   filterEnvDecayS=0.12, wave=1, osc=1),
        fx=dict(lowCutHz=300, saturation=0.1, ott=0.3, delay=0.25, delayFeedback=0.3, reverb=0.25,
                reverbSize=0.6, sidechain=0.3, sidechainReleaseS=0.2),
        mixer=dict(gain=0.42, pan=0.05),
    ),
    # オルゴール／グロッケン風のベル。イントロのアルペジオとサビのチョップ
    "Bell": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=2200, resonance=1.1, attackS=0.001, decayS=0.45, sustain=0.0, releaseS=0.35,
                   detuneCents=6, masterGain=0.7, unison=2, width=0.5, blend=1.0, filterEnv=0.7,
                   filterEnvDecayS=0.15, wave=1, osc=1),
        fx=dict(lowCutHz=500, chorus=0.25, ott=0.3, delay=0.3, delayFeedback=0.35, reverb=0.45,
                reverbSize=0.7, sidechain=0.35, sidechainReleaseS=0.2),
        mixer=dict(gain=0.42, pan=-0.15),
    ),
    # のこぎり＋1オクターブ下のサイン
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=600, resonance=0.9, attackS=0.003, decayS=0.25, sustain=0.8, releaseS=0.05,
                   detuneCents=8, masterGain=0.8, unison=2, width=0.0, blend=1.0, sub=0.7, drive=0.25,
                   filterEnv=0.2, filterEnvDecayS=0.08, wave=0, osc=0.8),
        fx=dict(saturation=0.2, sidechain=0.8, sidechainReleaseS=0.2),
        mixer=dict(gain=0.24, pan=0),
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
    # Clap Wide＋Snare Cute Tight を重ねる（ロールは Snare Cute Tight）
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
    # ビルドで盛り上がるノイズ（4小節かけて大きくなる）
    "Riser": dict(
        color="ffb0b6c0",
        synth=dict(cutoffHz=6000, resonance=1.5, attackS=6.0, decayS=1.0, sustain=1.0, releaseS=0.3,
                   unison=1, noise=1.0, osc=0, masterGain=0.6),
        fx=dict(lowCutHz=500, reverb=0.5, reverbSize=0.8),
        mixer=dict(gain=1.3, pan=0),
    ),
}

# ---- コード ----------------------------------------------------------------------

V = {  # 声部（明るめの高さ）と根音（ベース用）
    "FM7": ([57, 60, 64, 65, 72], 41),
    "Dm7": ([57, 60, 62, 65, 69], 50),
    "BbM7": ([58, 62, 65, 69, 74], 46),
    "C": ([60, 64, 67, 72, 74], 48),
    "Gm7": ([58, 62, 65, 67, 70], 43),
    "Am7": ([57, 60, 64, 67, 72], 45),
    "C7": ([58, 60, 64, 67, 72], 48),
    "F7": ([57, 60, 63, 65, 69], 41),
    "Fadd9": ([57, 60, 65, 67, 72], 41),
}
VERSE = ["FM7", "Dm7", "BbM7", "C"]
BUILD = ["Gm7", "Am7", "BbM7", "C"]
BUILD2 = ["Gm7", "Am7", "BbM7", "C7"]
CHORUS = ["BbM7", "C", "Am7", "Dm7", "Gm7", "C7", "FM7", "F7"]
CHORUS_END = ["BbM7", "C", "Am7", "Dm7", "Gm7", "C7", "FM7", "Fadd9"]


def n(tick, length, pitch, vel=0.8):
    return (int(tick), max(1, int(length)), pitch, vel)


def steps(bar, positions, length, pitches, vel):
    """16分の位置で、同じ高さの組を鳴らす"""
    return [n(bar * BAR + p * S16, length, x, vel(p) if callable(vel) else vel) for p in positions for x in pitches]


def held(prog, vel=0.6):
    return [n(i * BAR, BAR - 60, p, vel) for i, c in enumerate(prog) for p in V[c][0]]


def stabs(prog):
    # Aメロ：跳ねる刻み（16分の位置, 長さ）
    rhythm = [(0, 2), (3, 2), (6, 2), (10, 2), (12, 3)]
    out = []
    for i, c in enumerate(prog):
        for pos, ln in rhythm:
            out += [n(i * BAR + pos * S16, ln * S16 - 40, p, 0.72 if pos in (0, 6, 12) else 0.62) for p in V[c][0]]
    return out


def chorus_chords(prog):
    # 伸ばしたコードを、キック（Jersey Club のリズム）のサイドチェインで跳ねさせる
    return [n(i * BAR, BAR - 30, p, 0.9) for i, c in enumerate(prog) for p in V[c][0]]


def bass_line(prog, positions, length):
    return [n(i * BAR + s * S16, length, V[c][1], 0.9) for i, c in enumerate(prog) for s in positions]


def bell_arp(prog):
    # オルゴールのような8分のアルペジオ（1オクターブ上）
    out = []
    for i, c in enumerate(prog):
        tones = sorted(set(V[c][0]))
        seq = [tones[0], tones[2], tones[4], tones[3], tones[1] + 12, tones[3], tones[2], tones[4]]
        for k, p in enumerate(seq):
            out.append(n(i * BAR + k * PPQ // 2, PPQ // 2 - 40, p + 12, 0.8 if k % 2 == 0 else 0.65))
    return out


def bell_chops(prog):
    # サビのチョップ：コードの上の音を16分のシンコペで
    pattern = [0, 3, 6, 8, 10, 13, 14]
    out = []
    for i, c in enumerate(prog):
        top = sorted(V[c][0])[-3:]
        for k, s in enumerate(pattern):
            out.append(n(i * BAR + s * S16, S16 * 2 - 40, top[k % 3] + 12, 0.75))
    return out


def melody(spec, transpose=0, vel=0.85):
    return [n(b * PPQ, l * PPQ - 30, p + transpose, vel) for b, l, p in spec]


VERSE_MELODY = [  # (拍, 長さ, 音程) 8小節
    (0, .5, 72), (.5, .5, 72), (1, .5, 74), (1.5, .5, 76), (2, 1, 77), (3, .5, 76), (3.5, .5, 74),
    (4, .5, 72), (4.5, .5, 74), (5, 1, 69), (6, .5, 72), (6.5, .5, 74), (7, 1, 77),
    (8, .5, 74), (8.5, .5, 74), (9, .5, 76), (9.5, .5, 77), (10, 1, 79), (11, .5, 77), (11.5, .5, 76),
    (12, 1, 74), (13, .5, 76), (13.5, .5, 72), (14, 2, 79),
    (16, .5, 72), (16.5, .5, 72), (17, .5, 74), (17.5, .5, 76), (18, 1, 77), (19, .5, 79), (19.5, .5, 81),
    (20, .5, 81), (20.5, .5, 79), (21, 1, 77), (22, .5, 74), (22.5, .5, 76), (23, 1, 77),
    (24, .5, 74), (24.5, .5, 76), (25, .5, 77), (25.5, .5, 79), (26, 1, 81), (27, .5, 79), (27.5, .5, 77),
    (28, 1, 76), (29, .5, 77), (29.5, .5, 79), (30, 2, 72),
]

CHORUS_MELODY = [  # 8小節
    (0, .75, 81), (.75, .75, 79), (1.5, .5, 77), (2, .5, 79), (2.5, .5, 81), (3, 1, 82),
    (4, .75, 84), (4.75, .75, 82), (5.5, .5, 81), (6, 1, 79), (7, .5, 76), (7.5, .5, 77),
    (8, .75, 79), (8.75, .75, 77), (9.5, .5, 76), (10, .5, 77), (10.5, .5, 79), (11, 1, 81),
    (12, 1.5, 77), (13.5, .5, 76), (14, 1, 74), (15, .5, 72), (15.5, .5, 74),
    (16, .75, 77), (16.75, .75, 79), (17.5, .5, 81), (18, .5, 82), (18.5, .5, 81), (19, 1, 79),
    (20, .75, 79), (20.75, .75, 81), (21.5, .5, 82), (22, 1, 84), (23, .5, 82), (23.5, .5, 81),
    (24, 1.5, 81), (25.5, .5, 79), (26, 1, 77), (27, 1, 76),
    (28, 1, 77), (29, .5, 75), (29.5, .5, 77), (30, 2, 81),
]
# 最後のサビの終わりは F に落ち着く
CHORUS_MELODY_END = CHORUS_MELODY[:-4] + [(28, 1, 77), (29, .5, 76), (29.5, .5, 79), (30, 2, 77)]

# ---- ドラム（1小節 = 16分×16） ------------------------------------------------------

# kits/future-bass の番号
KICK = 36          # Kick Punchy
CLAP = [28, 41]    # Clap Wide＋Snare Cute Tight
SNARE = 41         # Snare Cute Tight（ロール）
HAT_C, HAT_O = 42, 58  # 808 Hihat Closed / Open Short
CRASH = 49         # 808 Cymbal


def jersey_kicks(bars=4):
    # たんっ、たんっ、たんったんったん（0, 4, 8, 11, 14）。4小節目は詰めて次へ
    out = []
    for b in range(bars):
        pos = [0, 4, 8, 11, 14] if b % 4 != 3 else [0, 4, 8, 10, 12, 13, 14, 15]
        out += steps(b, pos, S16 * 2 - 20, [KICK], 1.0)
    return out


def halftime_kicks(bars=4):
    out = []
    for b in range(bars):
        out += steps(b, [0, 6, 10] if b % 2 == 0 else [0, 6, 9, 14], S16 * 2, [KICK], 1.0)
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


def snare_roll(bars=4):
    # 4分 → 8分 → 16分 → 32分で、だんだん強く
    out = []
    divs = [4, 8, 16, 32] if bars == 4 else [8, 16]
    for b, d in enumerate(divs):
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
            # 16分のときは各拍の裏の裏（14）だけ開いたハット
            pitch = HAT_O if sixteenths and pos == 14 else HAT_C
            out.append(n(b * BAR + pos * S16, S16, pitch, vel))
    if crash:
        out.append(n(0, BAR, CRASH, 0.85))
    return out


# ---- project.json に組み立てる ----------------------------------------------------

class Builder:
    def __init__(self):
        self.next_id = 1
        self.tracks, self.clips, self.placements = [], [], []

    def nid(self):
        i = self.next_id
        self.next_id += 1
        return f"{i:016x}"

    def track(self, name, sound, solo=None):
        tid = self.nid()
        mixer = dict(gain=0.8, pan=0.0, mute=False, solo=False)
        mixer.update(sound["mixer"])
        if solo is not None:
            mixer["solo"] = name == solo
        instrument = dict(type="synth", params=sound["synth"])
        if "kit" in sound:
            instrument = dict(type="kit", kit=sound["kit"], params=sound["synth"])
        self.tracks.append(dict(id=tid, name=name, color=sound["color"],
                                instrument=instrument,
                                fx=sound["fx"], mixer=mixer))
        return tid

    def clip(self, track, bars, notes, at):
        """at の各小節に同じクリップを置く（複製なので、1か所直すと全部変わる）"""
        assert all(0 <= t < bars * BAR for t, _, _, _ in notes), "クリップからはみ出すノート"
        cid = self.nid()
        self.clips.append(dict(id=cid, trackId=track, lengthTicks=bars * BAR, notes=[
            dict(id=self.nid(), tick=t, length=min(l, bars * BAR - t), pitch=p, velocity=round(v, 3))
            for t, l, p, v in sorted(notes)]))
        for start in at:
            self.placements.append(dict(id=self.nid(), clipId=cid, trackId=track, startBar=start, lengthBars=bars))


def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    C, L, BE, BA = t["Chords"], t["Lead"], t["Bell"], t["Bass"]
    K, CL, H, R = t["Kick"], t["Clap"], t["Hats"], t["Riser"]

    # イントロ・ブレイク（同じ素材）
    b.clip(C, 4, held(VERSE, 0.5), [0, 4, 48, 52])
    b.clip(BE, 4, bell_arp(VERSE), [0, 4, 48, 52])
    b.clip(H, 4, hats(4, False), [4])

    # Aメロ
    b.clip(C, 4, stabs(VERSE), [8, 12, 16, 20])
    b.clip(L, 8, melody(VERSE_MELODY, vel=0.8), [8, 16])
    b.clip(BA, 4, bass_line(VERSE, [0, 6, 10], S16 * 3), [8, 12, 16, 20])
    b.clip(K, 4, halftime_kicks(), [8, 12, 16, 20])
    # クラップはサビだけ（Aメロ・ビルドは鳴らさない）
    b.clip(H, 4, hats(4, False), [8, 12, 16, 20])

    # ビルド（8小節）とビルド2（4小節）
    b.clip(C, 4, held(BUILD, 0.7), [24, 28])
    b.clip(BA, 4, bass_line(BUILD, [0], BAR - 60), [24])
    b.clip(K, 4, four_floor(), [24])
    b.clip(H, 4, hats(4, True), [24])
    b.clip(CL, 4, snare_roll(4), [28, 56])
    b.clip(R, 4, [n(0, BAR * 4 - 200, 60, 0.9)], [28, 56])
    b.clip(C, 4, held(BUILD2, 0.72), [56])

    # サビ（8小節を2回）とラストサビ
    b.clip(C, 8, chorus_chords(CHORUS), [32, 40, 60])
    b.clip(C, 8, chorus_chords(CHORUS_END), [68])
    b.clip(L, 8, melody(CHORUS_MELODY), [32, 40, 60])
    b.clip(L, 8, melody(CHORUS_MELODY_END), [68])
    b.clip(BE, 8, bell_chops(CHORUS), [32, 40])
    b.clip(BE, 8, melody(CHORUS_MELODY, transpose=12, vel=0.7), [60])
    b.clip(BE, 8, melody(CHORUS_MELODY_END, transpose=12, vel=0.7), [68])
    b.clip(BA, 8, bass_line(CHORUS, [0, 4, 8, 11, 14], S16 * 2 - 30), [32, 40, 60])
    b.clip(BA, 8, bass_line(CHORUS_END, [0, 4, 8, 11, 14], S16 * 2 - 30), [68])
    b.clip(K, 4, jersey_kicks(), [32, 36, 40, 44, 60, 64, 68, 72])
    b.clip(CL, 4, claps(4, [4, 12], extra_last=[15]), [32, 36, 40, 44, 60, 64, 68, 72])
    b.clip(H, 4, hats(4, True, crash=True), [32, 36, 40, 44, 60, 64, 68, 72])

    # 終わりの一発
    b.clip(C, 1, [n(0, BAR - 60, p, 0.9) for p in V["Fadd9"][0]], [76])
    b.clip(BA, 1, [n(0, PPQ * 2, V["Fadd9"][1], 0.9)], [76])
    b.clip(K, 1, [n(0, S16 * 2, KICK, 1.0)], [76])
    b.clip(BE, 1, [n(0, PPQ * 2, p + 12, 0.7) for p in [65, 69, 72]], [76])

    return dict(format="mobiledaw-project", version=1, tempo=150.0, timeSig=[4, 4],
                key=dict(root=5, scale="major"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/future_bass.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
