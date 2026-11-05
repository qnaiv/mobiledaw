#!/usr/bin/env python3
"""シティソウル（Just the Two of Us 系のおしゃれでメロディアスな曲）のデモ曲（project.json）を作る。

  python3 tools/demos/city_soul.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/city_soul.json（既定）。
音の確認：build/mdaw_render app/assets/demos/city_soul.json /tmp/cs.wav   # リポジトリの直下で（kits/ を読む）

96 BPM / D minor（平行調 F major）/ 48小節（2分）
  小節   0– 3  イントロ   キーズとビブラフォンが Aメロの動機をそっと
         4–11  Aメロ      サイドスティックの跳ねるグルーヴ。歌うリード
        12–19  サビ       スネアとパッドで広がる。動機を3度ずつ下げていく繰り返し
        20–27  ソロ       リードのアドリブ風（最後は Aメロの動機に戻る）。ライドに替える
        28–35  Aメロ2
        36–43  ラストサビ 最後は高い A まで上がって D に落ち着く。ビブラフォンが1オクターブ上で重ねる
        44–47  アウトロ   B♭M9 → A7(♭9) → Dm9 で終わる
進行
  Aメロ  B♭M9 → A7(♭9) → Dm9 → Cm9・F13      （IVM7 → III7 → vim7 → v7・I7 の定番の流れ）
  サビ   Gm9 → C9 → FM9 → B♭M9 → Em7♭5 → A7(♭9) → Dm9 → Gm7・A7
メロディは書き下ろし（短い動機をくり返し・ずらし・高さを変えて使う）。
ドラムは Acoustic Live キット（kits/acoustic-live）。16分の裏を少し遅らせて跳ねさせる。
"""
import json
import sys

from future_bass import Builder, PPQ, BAR, S16

SWING = 45  # 16分の裏（奇数の16分）を遅らせる量（tick、16分 = 240）


def at(beat):
    """拍（0始まり、小数可）→ tick。16分の裏ならスイングで少し遅らせる"""
    t = round(beat * PPQ)
    if (t // S16) % 2 == 1 and t % S16 == 0:
        t += SWING
    return t


def note(beat, beats, pitch, vel=0.8):
    t = at(beat)
    end = at(beat + beats)
    return (t, max(30, end - t - 25), pitch, vel)


# ---- 音色 ------------------------------------------------------------------------

SOUNDS = {
    # ローズ風のキーズ（矩形波を絞って、弾いた瞬間だけ少し開く。コーラスで揺らす）
    "Keys": dict(
        color="ff5ad6c0",
        synth=dict(cutoffHz=1400, resonance=0.7, attackS=0.003, decayS=1.1, sustain=0.4, releaseS=0.45,
                   detuneCents=8, masterGain=0.62, unison=2, width=0.45, blend=0.95, drive=0.06,
                   filterEnv=0.32, filterEnvDecayS=0.3, wave=1, osc=1, keyTrack=0.4),
        fx=dict(lowCutHz=220, saturation=0.12, chorus=0.45, ott=0.15, reverb=0.3, reverbSize=0.65),
        mixer=dict(gain=0.4, pan=-0.12),
    ),
    # 歌うリード：モノで音どうしを少しすべらせる（レガート）。ディレイとリバーブで奥行き
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=3800, resonance=0.9, attackS=0.025, decayS=0.7, sustain=0.78, releaseS=0.3,
                   detuneCents=7, masterGain=0.6, unison=2, width=0.25, blend=0.9, drive=0.08,
                   filterEnv=0.14, filterEnvDecayS=0.35, wave=0, osc=1, mono=1, glideS=0.05, keyTrack=0.5),
        fx=dict(lowCutHz=260, saturation=0.12, chorus=0.18, ott=0.2, delay=0.24, delayFeedback=0.3,
                reverb=0.36, reverbSize=0.72),
        mixer=dict(gain=0.58, pan=0.06),
    ),
    # ビブラフォン風（矩形波を絞り、頭で開いてすぐ閉じる。長めの余韻）
    "Vibes": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=1800, resonance=1.0, attackS=0.001, decayS=1.3, sustain=0.0, releaseS=0.8,
                   detuneCents=5, masterGain=0.6, unison=2, width=0.5, blend=1.0, filterEnv=0.55,
                   filterEnvDecayS=0.12, wave=1, osc=1),
        fx=dict(lowCutHz=400, chorus=0.3, delay=0.2, delayFeedback=0.25, reverb=0.45, reverbSize=0.75),
        mixer=dict(gain=0.36, pan=0.22),
    ),
    # 弦っぽいパッド（ゆっくり立ち上がる）。サビとソロだけ
    "Pad": dict(
        color="ffb0b6c0",
        synth=dict(cutoffHz=2200, resonance=0.6, attackS=0.6, decayS=1.5, sustain=0.85, releaseS=1.2,
                   detuneCents=16, masterGain=0.5, unison=5, width=0.95, blend=0.8, filterEnv=0.05,
                   filterEnvDecayS=1.0, wave=0, osc=1),
        fx=dict(lowCutHz=300, chorus=0.5, reverb=0.5, reverbSize=0.85),
        mixer=dict(gain=0.26, pan=0),
    ),
    # 丸いベース（矩形を絞った上の音＋1オクターブ下のサイン）
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=650, resonance=0.8, attackS=0.004, decayS=0.4, sustain=0.7, releaseS=0.08,
                   detuneCents=4, masterGain=0.8, unison=1, width=0.0, blend=1.0, sub=0.75, drive=0.18,
                   filterEnv=0.22, filterEnvDecayS=0.09, wave=1, osc=0.6, mono=1, glideS=0.02),
        fx=dict(saturation=0.15),
        mixer=dict(gain=0.28, pan=0),
    ),
    "Kick": dict(color="fff28c38", kit="acoustic-live", synth={}, fx=dict(saturation=0.05),
                 mixer=dict(gain=0.36, pan=0)),
    # サイドスティック・スネア・ゴースト
    "Snare": dict(color="fff2d45a", kit="acoustic-live", synth={}, fx=dict(lowCutHz=150),
                  mixer=dict(gain=0.36, pan=0.04)),
    # ハット・ライド・クラッシュ
    "Cymbals": dict(color="ffd0d6e0", kit="acoustic-live", synth={}, fx=dict(lowCutHz=300),
                    mixer=dict(gain=0.34, pan=-0.14)),
}

# acoustic-live の番号
KICK, STICK, SNARE = 36, 37, 38
HAT, HAT_OPEN, RIDE, CRASH, FINGER = 65, 59, 51, 49, 71

# ---- コード（声部はキーズ用の根音なしボイシング。なめらかにつながる高さで並べてある） ---------------

V = {  # 声部, ベースの根音
    "BbM9": ([60, 62, 65, 69], 46),
    "A7b9": ([61, 64, 67, 70], 45),
    "A7b9lo": ([58, 61, 64, 67], 45),
    "Dm9": ([60, 64, 65, 69], 50),
    "Dm9lo": ([57, 60, 64, 65], 50),
    "Cm9": ([58, 62, 63, 67], 48),
    "F13": ([57, 62, 63, 67], 41),
    "Gm9": ([58, 62, 65, 69], 43),
    "Gm7": ([57, 58, 62, 65], 43),
    "C9": ([58, 62, 64, 67], 48),
    "FM9": ([57, 60, 64, 67], 41),
    "BbM9lo": ([57, 60, 62, 65], 46),
    "Em7b5": ([58, 62, 64, 67], 40),
}
# (コード, 拍)
VERSE = [("BbM9", 4), ("A7b9", 4), ("Dm9", 4), ("Cm9", 2), ("F13", 2)]
CHORUS = [("Gm9", 4), ("C9", 4), ("FM9", 4), ("BbM9lo", 4), ("Em7b5", 4), ("A7b9lo", 4), ("Dm9lo", 4),
          ("Gm7", 2), ("A7b9lo", 2)]
OUTRO = [("BbM9", 4), ("A7b9", 4), ("Dm9", 8)]


def timeline(prog):
    """(コード, 始まりの拍, 長さ)"""
    out, b = [], 0
    for c, beats in prog:
        out.append((c, b, beats))
        b += beats
    return out


def keys_comp(prog, vel=0.6):
    """キーズの刻み：頭で長く、2拍目の裏で短く、4拍目で軽く（2拍のコードは頭と裏）"""
    out = []
    for c, b, beats in timeline(prog):
        voices = V[c][0]
        hits = [(0, 1.4, vel), (1.5, 0.45, vel * 0.75), (3, 0.9, vel * 0.8)] if beats >= 4 else [(0, 1.4, vel)]
        if beats >= 8:
            hits = [(0, 3.8, vel), (4, 3.8, vel * 0.8)]
        for off, ln, v in hits:
            out += [note(b + off, ln, p, v) for p in voices]
    return out


def keys_held(prog, vel=0.5):
    return [note(b, beats - 0.1, p, vel) for c, b, beats in timeline(prog) for p in V[c][0]]


def pad(prog, vel=0.45):
    # 声部の上2つを1オクターブ上に（キーズとぶつからないように薄く）
    return [note(b, beats - 0.05, p + 12, vel) for c, b, beats in timeline(prog) for p in sorted(V[c][0])[-2:]]


def bass(prog):
    """R&B の跳ねるベース：根音を長く、5度、次のコードへ半音で近づく"""
    out = []
    tl = timeline(prog)
    for i, (c, b, beats) in enumerate(tl):
        r = V[c][1]
        nxt = V[tl[(i + 1) % len(tl)][0]][1]
        approach = nxt - 1 if nxt > r else nxt + 1
        if beats >= 8:
            out += [note(b, 3.5, r, 0.85), note(b + 4, 3.5, r, 0.7)]
        elif beats >= 4:
            out += [note(b, 1.0, r, 0.9), note(b + 1.5, 0.45, r, 0.6), note(b + 2.5, 0.45, r + 7, 0.75),
                    note(b + 3, 0.45, r + 12, 0.6), note(b + 3.5, 0.45, approach, 0.7)]
        else:
            out += [note(b, 0.75, r, 0.9), note(b + 1, 0.45, r + 7, 0.7), note(b + 1.5, 0.45, approach, 0.7)]
    return out


def mel(spec, transpose=0, vel=0.85, offset=0):
    return [note(offset + b, l, p + transpose, vel * (1.0 if l >= 1 else 0.92)) for b, l, p in spec]


# ---- メロディ（書き下ろし） ---------------------------------------------------------
# 動機 M：「D-C-A〜, C-D」。Aメロの小節頭のたびに戻ってくる

M1 = [(0.5, .5, 74), (1, .5, 72), (1.5, 1, 69), (2.5, .5, 72), (3, 1, 74)]                 # B♭M9
M2 = [(4.5, .5, 76), (5, .5, 74), (5.5, 1, 73), (6.5, 1.5, 69)]                            # A7(♭9)：C♯で色
VERSE_MEL = (
    M1 + M2
    + [(8.5, .5, 74), (9, .5, 72), (9.5, 1, 69), (10.5, .5, 65), (11, 1, 67)]                # Dm9：同じ出だし、終わりを変える
    + [(12.5, .5, 67), (13, .5, 70), (13.5, .5, 72), (14, .5, 75), (14.5, 1.5, 74)]          # Cm9・F13：上がって答える
    + [(b + 16, l, p) for b, l, p in M1 + M2]                                                 # くり返し
    + [(24.5, .5, 74), (25, .5, 72), (25.5, .5, 69), (26, .5, 72), (26.5, 1.5, 77)]          # Dm9：高い F へ
    + [(28.5, .5, 75), (29, .5, 74), (29.5, .5, 72), (30, 2, 70)]                             # 下りて B♭（サビの Gm へ）
)

# サビ：「長く → 跳ねて上がる → 段で下りる」の形を、3度ずつ下げてくり返す
CHORUS_MEL = (
    [(0, 1.5, 74), (1.5, .5, 77), (2, 1, 81), (3, .5, 79), (3.5, .5, 77)]                    # Gm9
    + [(4, 1.5, 72), (5.5, .5, 76), (6, 1, 79), (7, .5, 77), (7.5, .5, 76)]                  # C9
    + [(8, 1.5, 69), (9.5, .5, 72), (10, 1, 76), (11, .5, 74), (11.5, .5, 72)]               # FM9
    + [(12, 1, 74), (13, 1, 72), (14, 2, 69)]                                                 # B♭M9：息つぎ
    + [(16.5, .5, 70), (17, .5, 72), (17.5, 1, 74), (18.5, .5, 76), (19, 1, 79)]             # Em7♭5：上っていく
    + [(20, 1.5, 81), (21.5, .5, 79), (22, 1, 76), (23, 1, 73)]                               # A7(♭9)：一番高い所から
    + [(24, 1.5, 74), (25.5, .5, 76), (26, 2, 77)]                                            # Dm9
)
CHORUS_END1 = [(28, 1, 79), (29, 1, 77), (30, .5, 76), (30.5, 1.5, 73)]                      # → ソロ（B♭M9）へ
CHORUS_END2 = [(24, 1.5, 74), (25.5, .5, 76), (26, 1, 77), (27, 1, 81),                      # 最後は高い A まで
               (28, 1, 79), (29, .5, 77), (29.5, .5, 76), (30, 2, 74)]                         # D に落ち着く

# ソロ：動機を細かくしたアドリブ風。最後の2小節は Aメロの動機に戻る
SOLO_MEL = [
    (0, .5, 69), (.5, .25, 72), (.75, .25, 74), (1, 1, 77), (2, .5, 76), (2.5, .5, 74), (3, 1, 72),
    (4, .5, 73), (4.5, .5, 76), (5, .5, 79), (5.5, .5, 82), (6, 1, 81), (7, 1, 76),
    (8.5, .5, 77), (9, .5, 76), (9.5, .5, 74), (10, .5, 72), (10.5, .5, 69), (11, 1, 72),
    (12, .5, 70), (12.5, .5, 74), (13, 1, 75), (14, .5, 77), (14.5, .5, 75), (15, 1, 74),
    (16.5, .5, 81), (17, 1.5, 79), (18.5, .5, 77), (19, 1, 74),
    (20, .25, 76), (20.25, .25, 77), (20.5, .5, 76), (21, .5, 73), (21.5, .5, 70), (22, 2, 69),
    (24.5, .5, 74), (25, .5, 72), (25.5, 1, 69), (26.5, .5, 72), (27, 1, 74),
    (28.5, .5, 75), (29, .5, 74), (29.5, .5, 72), (30, 2, 70),
]

# ---- ドラム（16分の位置） -----------------------------------------------------------


def hits(bars, pattern, pitch, vel):
    """pattern: 1小節の (16分の位置, 強さの倍率)"""
    return [note(bar * 4 + pos / 4, 0.25, pitch, vel * v) for bar in range(bars) for pos, v in pattern]


def groove(bars, chorus=False, ride=False, fill_last=True):
    kick = hits(bars, [(0, 1.0), (7, 0.7), (10, 0.9)], KICK, 0.95)
    back = hits(bars, [(4, 1.0), (12, 1.0)], SNARE if chorus else STICK, 0.9)
    ghosts = hits(bars, [(6, 0.22), (15, 0.25)], SNARE, 0.9)
    if ride:
        cym = hits(bars, [(p, 0.9 if p % 4 == 0 else 0.65) for p in range(0, 16, 2)], RIDE, 0.8)
    else:
        cym = hits(bars, [(p, 0.85 if p % 4 == 2 else 0.6) for p in range(0, 16, 2)], HAT, 0.8)
        cym += hits(bars, [(p, 0.35) for p in (3, 11)], HAT, 0.8)  # 16分の裏をうすく
    if fill_last:
        # 最後の小節はハットを開いて次へ。スネアのゴーストを足す
        last = (bars - 1) * 4
        cym = [c for c in cym if c[0] < at(last + 3.5)] + [note(last + 3.5, 0.5, HAT_OPEN, 0.7)]
        ghosts += [note(last + 3.25, 0.25, SNARE, 0.35), note(last + 3.75, 0.25, SNARE, 0.45)]
    return kick, back + ghosts, cym


# ---- 組み立て -----------------------------------------------------------------------


def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    K, L, VI, P, BA = t["Keys"], t["Lead"], t["Vibes"], t["Pad"], t["Bass"]
    KI, SN, CY = t["Kick"], t["Snare"], t["Cymbals"]

    # イントロ（0–3）：キーズは伸ばし、ビブラフォンが動機を予告。3小節目からベースとハット
    b.clip(K, 4, keys_held(VERSE, 0.5), [0])
    b.clip(VI, 4, mel(M1 + M2, vel=0.7) + mel([(8.5, .5, 74), (9, .5, 72), (9.5, 2.5, 69)], vel=0.65), [0])
    b.clip(BA, 2, [(x[0] - 2 * BAR, *x[1:]) for x in bass(VERSE) if 2 * BAR <= x[0] < 4 * BAR], [2])
    b.clip(CY, 2, hits(2, [(p, 0.5) for p in range(0, 16, 2)], HAT, 0.7) + [note(7.5, .5, HAT_OPEN, .6)], [2])

    # Aメロ（4–11、28–35）：同じクリップを使い回す
    b.clip(K, 4, keys_comp(VERSE), [4, 8, 20, 24, 28, 32])
    b.clip(BA, 4, bass(VERSE), [4, 8, 20, 24, 28, 32])
    kick, snare, hat = groove(4)
    b.clip(KI, 4, kick, [4, 8, 28, 32])
    b.clip(SN, 4, snare, [4, 8, 28, 32])
    b.clip(CY, 4, hat, [4, 8, 28, 32])
    b.clip(L, 8, mel(VERSE_MEL), [4, 28])

    # サビ（12–19、36–43）
    b.clip(K, 8, keys_comp(CHORUS, 0.62), [12, 36])
    b.clip(P, 8, pad(CHORUS), [12, 36])
    b.clip(BA, 8, bass(CHORUS), [12, 36])
    kick, snare, hat = groove(8, chorus=True)
    hat = [note(0, 2, CRASH, 0.75)] + [h for h in hat if h[0] >= at(0.5)]
    b.clip(KI, 8, kick, [12, 36])
    b.clip(SN, 8, snare, [12, 36])
    b.clip(CY, 8, hat, [12, 36])
    b.clip(L, 8, mel(CHORUS_MEL + CHORUS_END1), [12])
    b.clip(L, 8, mel(CHORUS_MEL[:-3] + CHORUS_END2), [36])
    b.clip(VI, 8, mel(CHORUS_MEL[:-3] + CHORUS_END2, transpose=12, vel=0.5), [36])  # ラストは1オクターブ上で重ねる

    # ソロ（20–27）：ライドに替えて、パッドを薄く
    kick, snare, ride = groove(8, ride=True)
    ride = [note(0, 1, FINGER, 0.6)] + ride
    b.clip(KI, 8, kick, [20])
    b.clip(SN, 8, snare, [20])
    b.clip(CY, 8, ride, [20])
    b.clip(P, 8, pad(VERSE + VERSE, 0.35), [20])
    b.clip(L, 8, mel(SOLO_MEL, vel=0.82), [20])

    # アウトロ（44–47）：キーズを伸ばし、ビブラフォンが動機で締める。最後は Dm9
    b.clip(K, 4, keys_held(OUTRO, 0.5), [44])
    b.clip(P, 4, pad(OUTRO, 0.32), [44])
    b.clip(BA, 4, [note(0, 3.8, 46, .8), note(4, 3.8, 45, .75), note(8, 7.5, 50, .8)], [44])
    b.clip(VI, 4, mel(M1 + M2, vel=0.6) + [note(8.5, .5, 74, .6), note(9, .5, 72, .55), note(9.5, 6, 69, .6)], [44])
    b.clip(KI, 4, [note(0, .25, KICK, .8), note(8, .25, KICK, .8)], [44])
    b.clip(CY, 4, [note(0, 1, FINGER, .5), note(8, 4, CRASH, .45)], [44])

    return dict(format="mobiledaw-project", version=1, title="デモ：シティソウル", tempo=96.0, timeSig=[4, 4],
                key=dict(root=2, scale="minor"), tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/city_soul.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")


if __name__ == "__main__":
    main()
