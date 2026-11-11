#!/usr/bin/env python3
"""エレクトロニカのデモ曲「グラス・ガーデン」（project.json）を作る。

  python3 tools/demos/electronica.py [出力先] [--solo トラック名]

112 BPM / D minor / 38小節（約1分21秒）
  小節  0– 3  イントロ   クワイア（Choir テーブル）のパッドが「ウー」→「アー」と開く。フィルターの閉じたアルペジオ
        4–11  ビートA    崩したキック、乾いたクラップ、ゆれる16分ハットと32分のグリッチロール、サブベース
       12–19  ビートB    ボーカルチョップ（フォルマント表の母音 e/i/o を音ごとに切り替える声ネタ風）
       20–23  ブレイク   ドラムが抜けて、パッドとチョップ
       24–27  ビルド     4分 → 8分のキック、クラップのロール（4分→8分→16分→32分）、ライザー、
                         アルペジオのフィルターとクワイアの母音が開いていく。最後の拍は無音
       28–35  ドロップ   クライマックス：スーパーソーのフック（Spectral Saw テーブル）と
                         キックで大きく揺れるコード、チョップ、全部のドラム
       36–37  エンディング クワイアが「アー」→「ウー」と閉じて終わる
進行  Dm9 → B♭M9 → FM7 → Csus2
ドラムは Future Bass Pro キット（kits/future-bass-pro）。キックは音程のあるサンプル（E）がキー（D）と
ぶつかるのでシンセで D に合わせたキック。音程のはっきりしたパーカッション（Bubble＝B、Sparkle Chime＝B、
Water Drop＝C 付近）は使わない
"""
import json
import sys

from future_bass import n, steps, PPQ, BAR, S16
from singer import AutoBuilder, sing

TEMPO = 112.0

SOUNDS = {
    "Choir": dict(  # 声っぽいパッド：Choir テーブル、WT_POS のオートメーションで「ウー」→「アー」
        color="ffd89af2",
        synth=dict(wtTable=7, wtPos=0.1, wtLfoRate=0.25, wtLfoAmount=0.15, unison=7, detuneCents=22,
                   width=0.95, blend=0.8, cutoffHz=5000, resonance=0.8, lfoPitch=0.03,
                   attackS=0.7, decayS=1.0, sustain=0.9, releaseS=1.6, masterGain=0.5),
        fx=dict(lowCutHz=160, chorus=0.28, ott=0.1, reverb=0.2, reverbSize=0.8, sidechain=0.4,
                sidechainReleaseS=0.35, eqLowDb=-1, eqHighDb=-1, eqHighHz=8000,
                comp=0.15, compThresholdDb=-20, compRatio=2, sendReverb=0.45),
        mixer=dict(gain=0.72, pan=0)),
    "Chops": dict(  # 声ネタ風チョップ（音ごとに母音を切り替える）
        color="ffff7ab8",
        synth=dict(wtTable=3, wtPos=0.25, unison=2, detuneCents=5, width=0.4, blend=0.9,
                   wtLfoRate=6.0, cutoffHz=3200, resonance=0.9, keyTrack=0.0,
                   attackS=0.004, decayS=0.12, sustain=0.6, releaseS=0.06, masterGain=0.7),
        fx=dict(lowCutHz=220, chorus=0.15, ott=0.15, delay=0.08, delayFeedback=0.2, reverb=0.08, reverbSize=0.6,
                sidechain=0.25, sidechainReleaseS=0.15, eqMidDb=1.5, eqMidHz=2000,
                sendReverb=0.18, sendDelay=0.28),
        mixer=dict(gain=1.3, pan=0.1)),
    "Arp": dict(  # パルスモーフのプラック。フィルターのオートメーションで開いていく
        color="ff5ad6c0",
        synth=dict(wtTable=6, wtPos=0.3, wtLfoRate=0.2, wtLfoAmount=0.4, unison=2, detuneCents=8, width=0.6,
                   cutoffHz=2500, resonance=1.6, filterEnv=0.5, filterEnvDecayS=0.09,
                   attackS=0.001, decayS=0.18, sustain=0.0, releaseS=0.15, masterGain=0.6),
        fx=dict(lowCutHz=280, delay=0.18, delayFeedback=0.4, reverb=0.1, reverbSize=0.65,
                sidechain=0.35, sidechainReleaseS=0.2, eqHighDb=1, sendDelay=0.32),
        mixer=dict(gain=0.75, pan=-0.3)),
    "Sub": dict(color="ff5aa9f2",
                synth=dict(unison=1, cutoffHz=260, resonance=0.7, sub=0.8, osc=0.5, drive=0.1,
                           attackS=0.005, decayS=0.3, sustain=0.85, releaseS=0.12, masterGain=0.8),
                fx=dict(sidechain=0.5, sidechainReleaseS=0.2, eqLowDb=2, eqLowHz=60, eqHighDb=-4, eqHighHz=400,
                        comp=0.5, compThresholdDb=-18, compRatio=4, compAttackMs=10, compMakeupDb=1),
                mixer=dict(gain=0.3, pan=0)),
    "Kick": dict(  # シンセのキック（ノート 50 = D、サブは1オクターブ下の D）
        color="fff28c38",
        synth=dict(osc=0.25, sub=1.0, unison=1, cutoffHz=900, resonance=0.7, keyTrack=0.0,
                   pitchEnv=26, pitchEnvDecayS=0.035, filterEnv=0.8, filterEnvDecayS=0.03,
                   attackS=0.0005, decayS=0.32, sustain=0.0, releaseS=0.05, masterGain=1.0),
        fx=dict(sidechainSource=1, saturation=0.32, eqLowDb=2.5, eqLowHz=70, eqMidDb=-3, eqMidHz=280,
                comp=0.55, compThresholdDb=-12, compRatio=4, compAttackMs=3, compMakeupDb=1),
        mixer=dict(gain=0.38, pan=0)),
    "Lead": dict(  # ドロップのフック：Spectral Saw のスーパーソー
        color="ffffe066",
        synth=dict(wtTable=5, wtPos=0.7, unison=7, detuneCents=18, width=0.8, blend=0.75,
                   cutoffHz=7000, resonance=0.9, filterEnv=0.2, filterEnvDecayS=0.15, lfoPitch=0.0,
                   attackS=0.004, decayS=0.4, sustain=0.8, releaseS=0.2, masterGain=0.55),
        fx=dict(lowCutHz=220, chorus=0.15, ott=0.3, delay=0.08, delayFeedback=0.2, reverb=0.1, reverbSize=0.65,
                sidechain=0.4, sidechainReleaseS=0.18, eqHighDb=1.2, eqHighHz=7000,
                comp=0.25, compThresholdDb=-16, sendDelay=0.18, sendReverb=0.12),
        mixer=dict(gain=0.48, pan=0)),
    "Saw": dict(  # ドロップのコード：キックで大きく引っ込んで揺れる
        color="ffc8f25a",
        synth=dict(wtTable=5, wtPos=0.55, unison=9, detuneCents=20, width=1.0, blend=0.7, cutoffHz=6000,
                   resonance=0.8, attackS=0.01, decayS=0.6, sustain=0.85, releaseS=0.3, masterGain=0.5),
        fx=dict(lowCutHz=260, chorus=0.22, ott=0.3, reverb=0.1, reverbSize=0.65, sidechain=0.85,
                sidechainReleaseS=0.22, eqHighDb=0.8, comp=0.2, compThresholdDb=-16, sendReverb=0.22),
        mixer=dict(gain=0.26, pan=0)),
    "Riser": dict(color="ffdddddd",
                  synth=dict(osc=0, noise=1.0, unison=1, cutoffHz=6000, resonance=1.6, keyTrack=0.0,
                             attackS=7.5, decayS=0.5, sustain=1.0, releaseS=0.2, masterGain=0.6),
                  fx=dict(lowCutHz=450, reverb=0.12, reverbSize=0.7, sendReverb=0.28), mixer=dict(gain=0.34, pan=0)),
    "Clap": dict(color="fff2d45a", kit="future-bass-pro", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(lowCutHz=180, reverb=0.06, eqMidDb=2, eqMidHz=1800, eqHighDb=1,
                        comp=0.3, compThresholdDb=-14, compRatio=3, sendReverb=0.2),
                 mixer=dict(gain=0.36, pan=0)),
    "Hats": dict(color="ffb0b6c0", kit="future-bass-pro", synth=dict(masterGain=1.0, unison=1),
                 fx=dict(lowCutHz=400, delay=0.04, eqHighDb=3, eqHighHz=10000, bitcrush=0.08, sendDelay=0.1),
                 mixer=dict(gain=0.24, pan=0.3)),
    "Glitch": dict(color="ff9a7cf2", kit="future-bass-pro", synth=dict(masterGain=1.0, unison=1),
                   fx=dict(lowCutHz=250, delay=0.1, delayFeedback=0.3, reverb=0.08,
                          bitcrush=0.42, stutter=0.38, stutterDiv=4, sendDelay=0.22, sendReverb=0.12),
                   mixer=dict(gain=0.28, pan=-0.25)),
}

V = {
    "Dm9": ([50, 53, 57, 60, 64], 38), "BbM9": ([46, 50, 53, 57, 60], 34),
    "FM7": ([48, 53, 57, 60, 64], 41), "Csus2": ([48, 55, 60, 62, 67], 36),
}
PROG = ["Dm9", "BbM9", "FM7", "Csus2"]


def pad(prog, vel=0.6):
    return [n(i * BAR, BAR - 30, p + 12, vel) for i, c in enumerate(prog) for p in V[c][0]]


def arp(prog):
    out = []
    for i, c in enumerate(prog):
        t = sorted(V[c][0])
        seq = [t[0], t[2], t[4], t[1] + 12, t[3], t[4] + 12, t[2] + 12, t[4]]
        for k in range(16):
            out.append(n(i * BAR + k * S16, S16 - 20, seq[k % 8] + 12, 0.85 if k % 3 == 0 else 0.6))
    return out


def sub(prog):
    out = []
    for i, c in enumerate(prog):
        r = V[c][1]
        out += [n(i * BAR, PPQ * 2 + PPQ // 2 - 40, r, 0.95), n(i * BAR + PPQ * 3, PPQ - 40, r, 0.85)]
    return out


# 声ネタ（音節は母音だけ：フォルマント表の位置を固定で a/e/i/o/u に当てる）
# 「a」「u」の位置は 7・11 倍音を強く出す（平均律から外れた音程が濁って聞こえる）ので使わない
CHOP_SYL = ["e", "o", "yo", "i", "e", "o", "ye", "i"]


def chops(prog, variant=0):
    pos_sets = [[0, 3, 6, 8, 10, 13, 14], [0, 2, 3, 6, 9, 12, 14, 15]]
    out = []
    k = 0
    for i, c in enumerate(prog):
        tones = sorted(set(p + 12 for p in V[c][0][:4]))  # 9th は外す（倍音がぶつかりやすい）
        pos = pos_sets[(i + variant) % 2]
        for j, s in enumerate(pos):
            ln = (pos[j + 1] - s) if j + 1 < len(pos) else 16 - s
            ln = min(ln, 3)
            p = tones[(j * 2 + i + variant) % len(tones)]
            out.append((i * 4 + s / 4, ln / 4, p, CHOP_SYL[k % len(CHOP_SYL)]))
            k += 1
    return out


K1, K2, CLAP, SNAP, HAT, HAT_S, HAT_O = 24, 35, 27, 43, 42, 44, 58
REV, CRASH, SHAKER, MARACAS, PEDAL = 52, 51, 82, 70, 68
KICK_NOTE = 50  # シンセキックの音程（D）


def beat(bars=4, variant=0):
    k, c, h, g = [], [], [], []
    for b in range(bars):
        kp = [0, 6, 10] if b % 2 == 0 else [0, 7, 10, 13]
        k += steps(b, kp, S16 * 2, [KICK_NOTE], 1.0)
        c += steps(b, [4, 12], S16, [CLAP], 0.9)
        for s in range(16):
            vel = [0.7, 0.35, 0.55, 0.4][s % 4] + (0.1 if s in (6, 14) else 0)
            h.append(n(b * BAR + s * S16, S16 // 2, HAT_S if s % 2 else HAT, vel))
        h += steps(b, [14], S16 * 2, [HAT_O], 0.5)
        # グリッチ：2小節ごとに最後の拍を32分のロール、ゴースト気味のスナップ
        if b % 2 == 1:
            for r in range(8):
                h.append(n(b * BAR + 12 * S16 + r * S16 // 2, S16 // 2 - 10, HAT_S, 0.35 + r * 0.07))
            g.append(n(b * BAR + 11 * S16, S16, CLAP, 0.35))
        # 音程のない（ノイズ系の）パーカッションだけでアクセント
        g += [n(b * BAR + 3 * S16, S16, SHAKER if b % 2 == 0 else MARACAS, 0.55),
              n(b * BAR + 9 * S16, S16, CLAP, 0.3) if variant else n(b * BAR + 9 * S16, S16, PEDAL, 0.45)]
    return k, c, h, g


DROP_HOOK = [(0, .75, 74), (.75, .75, 77), (1.5, .5, 76), (2, 1, 74), (3, .5, 72), (3.5, .5, 69),
             (4, .75, 70), (4.75, .75, 74), (5.5, .5, 72), (6, 2, 69),
             (8, .75, 72), (8.75, .75, 76), (9.5, .5, 77), (10, 1, 79), (11, .5, 77), (11.5, .5, 76),
             (12, 1.5, 74), (13.5, .5, 72), (14, 2, 74),
             (16, .75, 74), (16.75, .75, 77), (17.5, .5, 76), (18, 1, 74), (19, .5, 72), (19.5, .5, 69),
             (20, .75, 70), (20.75, .75, 74), (21.5, .5, 77), (22, 2, 81),
             (24, .75, 79), (24.75, .75, 77), (25.5, .5, 76), (26, 1, 77), (27, 1, 72),
             (28, 4, 74)]


def build(solo=None):
    b = AutoBuilder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    CH, CP, AR, SU, K, CL, H, G = (t[x] for x in ("Choir", "Chops", "Arp", "Sub", "Kick", "Clap", "Hats", "Glitch"))
    LE, SW, RI = t["Lead"], t["Saw"], t["Riser"]
    L = 4 * BAR

    # パッド：イントロは「ウー」から「アー」へ（WT_POS 0.05 → 0.85）、カットオフも開く
    open_vowel = [dict(param="wtPos", points=[[0, 0.05], [L, 0.85]]),
                  dict(param="cutoffHz", points=[[0, 1200], [L, 6000]])]
    breathe = [dict(param="wtPos", points=[[0, 0.85], [L // 2, 0.4], [L, 0.85]]),
               dict(param="cutoffHz", points=[[0, 6000], [L, 6000]])]
    build_up = [dict(param="wtPos", points=[[0, 0.2], [L, 1.0]]),
                dict(param="cutoffHz", points=[[0, 2000], [L, 9000]])]
    b.clip(CH, 4, pad(PROG, 0.55), [0], automation=open_vowel)
    b.clip(CH, 4, pad(PROG), [4, 8, 12, 16, 20, 28, 32], automation=breathe)
    b.clip(CH, 4, pad(PROG, 0.65), [24], automation=build_up)
    b.clip(CH, 2, [n(0, 2 * BAR - 60, p + 12, 0.6) for p in V["Dm9"][0]], [36],
           automation=[dict(param="wtPos", points=[[0, 0.85], [2 * BAR, 0.1]])])

    # アルペジオ：イントロでフィルターが開く。ブレイクで閉じ、ビルドで大きく開く
    cut = lambda pts: [dict(param="cutoffHz", points=pts)]
    b.clip(AR, 4, arp(PROG), [0], automation=cut([[0, 500], [L, 2500]]))
    b.clip(AR, 4, arp(PROG), [4, 8, 12, 16, 28, 32], automation=cut([[0, 2500], [L, 2500]]))
    b.clip(AR, 4, arp(PROG), [20], automation=cut([[0, 2500], [L // 2, 900], [L, 1200]]))
    b.clip(AR, 4, arp(PROG), [24], automation=cut([[0, 700], [L, 6000]]))
    b.clip(AR, 2, arp(PROG[:2]), [36], automation=cut([[0, 2500], [2 * BAR, 600]]))

    b.clip(SU, 4, sub(PROG), [4, 8, 12, 16, 24, 28, 32])
    b.clip(SU, 2, [n(0, 2 * BAR - 100, 38, 0.9)], [36])

    # 声ネタ風チョップ（母音位置は固定割り当て、e/i/o だけ）
    for v, at in ((0, [12, 28]), (1, [16, 20, 32])):
        notes, auto, _, _ = sing(chops(PROG, v), TEMPO, L, base_gain=1.3, consonants=False,
                                 vibrato=0.0, compensate=False, cutoff_cap=3200)
        b.clip(CP, 4, notes, at, automation=auto)

    k, c, h, g = beat(4, 0)
    b.clip(K, 4, k, [4, 8])
    b.clip(CL, 4, c, [4, 8])
    b.clip(H, 4, h, [4, 8])
    b.clip(G, 4, g, [4, 8])
    k, c, h, g = beat(4, 1)
    b.clip(K, 4, k, [12, 16])
    b.clip(CL, 4, c, [12, 16, 28, 32])
    b.clip(H, 4, h, [12, 16, 28, 32])
    b.clip(G, 4, g, [12, 16, 28, 32])
    # 入りのフィルハット（イントロ後半）とブレイクの逆再生シンバル
    b.clip(H, 2, [n(i * S16 * 2, S16, HAT_S, 0.3 + i * 0.03) for i in range(16)], [2])
    b.clip(G, 4, [n(2 * BAR, 2 * BAR, REV, 0.9)], [20])

    # ビルド：キック 4分 → 8分、クラップのロール、ライザー、最後の拍は無音
    bk = [n(bb * BAR + q * PPQ, S16 * 2, KICK_NOTE, 0.9) for bb in range(2) for q in range(4)]
    bk += [n(2 * BAR + e * PPQ // 2, S16 * 2 - 20, KICK_NOTE, 0.9) for e in range(8)]
    bk += [n(3 * BAR + e * PPQ // 2, S16 * 2 - 20, KICK_NOTE, 0.95) for e in range(6)]
    b.clip(K, 4, bk, [24])
    roll = []
    for bb, d in enumerate([4, 8, 16, 32]):
        step = BAR // d
        cnt = d if bb < 3 else d * 3 // 4
        roll += [n(bb * BAR + k * step, max(step - 10, 30), CLAP, 0.35 + 0.55 * (bb * d + k) / (4 * d)) for k in range(cnt)]
    b.clip(CL, 4, roll, [24])
    b.clip(H, 4, [n(bb * BAR + k * S16 * 2, S16, HAT, 0.4 + 0.1 * bb) for bb in range(3) for k in range(8)], [24])
    b.clip(RI, 4, [n(0, 4 * BAR - PPQ - 30, 60, 0.9)], [24])
    b.clip(G, 2, [n(0, 2 * BAR - PPQ, REV, 0.9)], [26])

    # ドロップ（クライマックス）
    dk = [x for bb in range(4) for x in steps(bb, [0, 4, 7, 8, 12, 14] if bb % 2 else [0, 4, 8, 10, 12], S16 * 2, [KICK_NOTE], 1.0)]
    b.clip(K, 4, dk, [28, 32])
    b.clip(G, 4, [n(0, BAR, CRASH, 0.9)], [28, 32])
    b.clip(LE, 8, [n(x * PPQ, l * PPQ - 40, p, 0.9) for x, l, p in DROP_HOOK], [28])
    b.clip(SW, 4, [n(i * BAR, BAR - 30, p + 12, 0.85) for i, c in enumerate(PROG) for p in V[c][0]], [28, 32])

    # 終わり
    b.clip(K, 1, [n(0, S16 * 2, KICK_NOTE, 1.0)], [36])
    b.clip(G, 2, [n(0, 2 * BAR, CRASH, 0.7)], [36])

    return dict(format="mobiledaw-project", version=1, title="グラス・ガーデン", tempo=TEMPO, timeSig=[4, 4],
                key=dict(root=2, scale="minor"),
                master=dict(gain=3.0, glue=0.65, thresholdDb=-15, ratio=2.0, softClip=0.5, ceiling=0.93),
                aux=dict(reverbReturn=1.0, reverbSize=0.78, delayReturn=0.62, delayFeedback=0.4),
                tracks=b.tracks, clips=b.clips, placements=b.placements)


def main():
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "app/assets/demos/electronica.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(build(solo), f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
