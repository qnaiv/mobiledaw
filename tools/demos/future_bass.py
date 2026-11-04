#!/usr/bin/env python3
"""フューチャーベースのデモ曲（project.json）を作る。

  python3 tools/demos/future_bass.py [出力先] [--solo トラック名]

出力はアプリに同梱する app/assets/demos/future_bass.json（既定）。
音の確認は mdaw_render で wav にして聴く：
  build/mdaw_render app/assets/demos/future_bass.json /tmp/fb.wav

構成：150 BPM / C minor / 16小節
  1〜8小節  溜め：パッドのコード、プラックのアルペジオ、5小節目からハイハット、
             7〜8小節でスネアロールとノイズのライザー
  9〜16小節 ドロップ：刻むスーパーソー（キックで強く引っ込む）、キック、スネア、
             ハイハット、ベース、リード
コード：A♭M7 → B♭ → Gm7 → Cm9 を1小節ずつ
"""
import json
import sys

PPQ = 960
BAR = PPQ * 4
S16 = PPQ // 4

# ---- 音色（mdaw.h の MDAW_PARAM_* / MDAW_FX_* の保存名） -------------------------

SOUNDS = {
    # 厚く広がるスーパーソー。ドロップではキックで深く引っ込む
    "Chords": dict(
        color="ffc8f25a",
        synth=dict(cutoffHz=12000, resonance=0.8, attackS=0.004, decayS=0.6, sustain=0.75, releaseS=0.22,
                   detuneCents=42, masterGain=0.55, unison=9, width=0.95, blend=0.75, sub=0, noise=0.03,
                   drive=0.15, filterEnv=0.25, filterEnvDecayS=0.25, wave=0, osc=1),
        fx=dict(lowCutHz=180, saturation=0.15, chorus=0.35, ott=0.55, delay=0, reverb=0.3, reverbSize=0.7,
                sidechain=0.9, sidechainReleaseS=0.32),
        mixer=dict(gain=0.5, pan=0),
    ),
    # 短く弾ける音。フィルターが一瞬開いて閉じる
    "Pluck": dict(
        color="ff9a7cf2",
        synth=dict(cutoffHz=500, resonance=1.2, attackS=0.001, decayS=0.22, sustain=0.0, releaseS=0.18,
                   detuneCents=18, masterGain=0.7, unison=3, width=0.6, blend=0.7, filterEnv=0.62,
                   filterEnvDecayS=0.12, wave=0, osc=1),
        fx=dict(lowCutHz=250, chorus=0.2, ott=0.4, delay=0.35, delayFeedback=0.4, reverb=0.35, reverbSize=0.6,
                sidechain=0.5, sidechainReleaseS=0.25),
        mixer=dict(gain=0.7, pan=-0.15),
    ),
    # 矩形波を少し重ねたリード
    "Lead": dict(
        color="ffe879c6",
        synth=dict(cutoffHz=6000, resonance=1.0, attackS=0.004, decayS=0.3, sustain=0.6, releaseS=0.15,
                   detuneCents=16, masterGain=0.6, unison=4, width=0.45, blend=0.7, filterEnv=0.2,
                   filterEnvDecayS=0.15, wave=1, osc=1),
        fx=dict(lowCutHz=300, saturation=0.2, ott=0.35, delay=0.3, delayFeedback=0.35, reverb=0.3,
                reverbSize=0.6, sidechain=0.45, sidechainReleaseS=0.25),
        mixer=dict(gain=0.45, pan=0.12),
    ),
    # のこぎり＋1オクターブ下のサイン。スマホでも聞こえるよう倍音を残す
    "Bass": dict(
        color="ff5aa9f2",
        synth=dict(cutoffHz=420, resonance=0.9, attackS=0.003, decayS=0.3, sustain=0.85, releaseS=0.06,
                   detuneCents=10, masterGain=0.8, unison=2, width=0.0, blend=1.0, sub=0.7, drive=0.3,
                   filterEnv=0.15, filterEnvDecayS=0.1, wave=0, osc=0.8),
        fx=dict(saturation=0.25, sidechain=0.85, sidechainReleaseS=0.28),
        mixer=dict(gain=0.24, pan=0),
    ),
    # 音程が落ちるサイン（サブ）＋一瞬だけ開くのこぎりでアタック
    "Kick": dict(
        color="fff28c38",
        synth=dict(cutoffHz=40, resonance=0.7, attackS=0.0005, decayS=0.32, sustain=0.0, releaseS=0.05,
                   detuneCents=0, masterGain=1.0, unison=1, width=0, sub=1.0, filterEnv=0.8,
                   filterEnvDecayS=0.025, pitchEnv=30, pitchEnvDecayS=0.035, wave=0, osc=0.5),
        fx=dict(saturation=0.35, sidechainSource=1),
        mixer=dict(gain=0.7, pan=0),
    ),
    # ノイズ＋少しの胴鳴り、リバーブ
    "Snare": dict(
        color="fff2d45a",
        synth=dict(cutoffHz=1600, resonance=0.9, attackS=0.0005, decayS=0.17, sustain=0.0, releaseS=0.08,
                   detuneCents=0, masterGain=1.0, unison=1, noise=1.0, filterEnv=0.55, filterEnvDecayS=0.06,
                   pitchEnv=12, pitchEnvDecayS=0.02, wave=1, osc=0.35),
        fx=dict(lowCutHz=160, saturation=0.55, reverb=0.35, reverbSize=0.5),
        mixer=dict(gain=1.5, pan=0),
    ),
    # ノイズだけ、低いところを大きく削る
    "Hats": dict(
        color="ff5ad6c0",
        synth=dict(cutoffHz=16000, resonance=0.7, attackS=0.0005, decayS=0.045, sustain=0.0, releaseS=0.03,
                   unison=1, noise=1.0, osc=0, masterGain=1.0),
        fx=dict(lowCutHz=6000, reverb=0.12, reverbSize=0.3, sidechain=0.3, sidechainReleaseS=0.15),
        mixer=dict(gain=1.6, pan=0.2),
    ),
    # 溜めの最後に盛り上がるノイズ
    "Riser": dict(
        color="ffb0b6c0",
        synth=dict(cutoffHz=5000, resonance=1.5, attackS=3.0, decayS=1.0, sustain=1.0, releaseS=0.4,
                   unison=1, noise=1.0, osc=0, masterGain=0.6),
        fx=dict(lowCutHz=400, reverb=0.5, reverbSize=0.8),
        mixer=dict(gain=1.6, pan=0),
    ),
}

# ---- 音の並び -----------------------------------------------------------------

#              A♭M7                  B♭                    Gm7                   Cm9（根音なし、根音はベース）
CHORDS = [[56, 60, 63, 67, 72], [58, 62, 65, 70, 74], [55, 58, 62, 65, 70], [58, 62, 63, 67, 74]]
ROOTS = [44, 46, 43, 48]  # A♭2 B♭2 G2 C3（サイン波は1オクターブ下）


def note(tick, length, pitch, vel=0.8):
    return (tick, length, pitch, vel)


def chords_build():
    # 1小節ずつ伸ばす（少し短く切ってつなぎ目を出す）
    return [note(i * BAR, BAR - 60, p, 0.62) for i, ch in enumerate(CHORDS) for p in ch]


# ドロップの刻み（16分の位置, 長さ）：頭・「タタッ」と前のめりに
DROP_RHYTHM = [(0, 3), (3, 3), (6, 2), (8, 2), (10, 3), (13, 3)]


def chords_drop():
    out = []
    for i, ch in enumerate(CHORDS):
        for pos, ln in DROP_RHYTHM:
            vel = 0.95 if pos in (0, 6, 10) else 0.82
            out += [note(i * BAR + pos * S16, ln * S16 - 40, p, vel) for p in ch]
    return out


def pluck_arp(which=range(4)):
    out = []
    for i, ci in enumerate(which):
        ch = CHORDS[ci]
        tones = sorted(ch[1:]) + [ch[1] + 12]
        seq = tones + tones[-2:0:-1]  # 上がって下がる
        for k in range(16):
            p = seq[k % len(seq)] + 12
            out.append(note(i * BAR + k * S16, S16 - 30, p, 0.85 if k % 4 == 0 else 0.7))
    return out


def bass_drop():
    out = []
    for i, r in enumerate(ROOTS):
        for pos, ln in DROP_RHYTHM:
            out.append(note(i * BAR + pos * S16, ln * S16 - 30, r, 0.9))
    return out


LEAD = [  # (拍, 長さ（拍）, 音程)
    (0.0, 0.75, 79), (0.75, 0.75, 75), (1.5, 0.5, 72), (2.0, 1.0, 75), (3.0, 1.0, 77),
    (4.0, 0.75, 77), (4.75, 0.75, 74), (5.5, 0.5, 70), (6.0, 1.0, 74), (7.0, 1.0, 75),
    (8.0, 0.75, 74), (8.75, 0.75, 70), (9.5, 0.5, 67), (10.0, 1.0, 70), (11.0, 1.0, 74),
    (12.0, 1.5, 75), (13.5, 0.5, 74), (14.0, 2.0, 72),
]


def lead():
    return [note(int(b * PPQ), int(l * PPQ) - 30, p, 0.85) for b, l, p in LEAD]


def kick_bar(variation):
    # ハーフタイムのノリ：1拍目と2拍目の裏、変化の小節は4拍目の裏にも
    ticks = [0, int(1.5 * PPQ)] + ([int(3.5 * PPQ)] if variation else [])
    return [note(t, S16 * 2, 43, 1.0) for t in ticks]


def kicks():
    return [(t + b * BAR, l, p, v) for b in range(4) for t, l, p, v in kick_bar(b == 3)]


def snares_drop():
    return [note(b * BAR + 2 * PPQ, S16 * 2, 50, 0.95) for b in range(4)]


def snare_roll():
    # 7小節目は8分、8小節目は16分で、だんだん強く
    out = []
    for k in range(8):
        out.append(note(k * PPQ // 2, S16, 50, 0.45 + 0.03 * k))
    for k in range(16):
        out.append(note(BAR + k * S16, S16 - 20, 50, 0.6 + 0.025 * k))
    return out


def hats(bars, dense):
    out = []
    for b in range(bars):
        for k in range(16 if dense else 8):
            step = S16 if dense else S16 * 2
            t = b * BAR + k * step
            off = (k % 2 == 1) if not dense else (k % 4 == 2)
            vel = 0.85 if off else 0.5
            out.append(note(t, S16, 72, vel))
    return out


def riser():
    return [note(0, BAR * 2 - 120, 60, 0.9)]


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
        self.tracks.append(dict(id=tid, name=name, color=sound["color"],
                                instrument=dict(type="synth", params=sound["synth"]),
                                fx=sound["fx"], mixer=mixer))
        return tid

    def clip(self, track, bars, notes, at):
        cid = self.nid()
        self.clips.append(dict(id=cid, trackId=track, lengthTicks=bars * BAR, notes=[
            dict(id=self.nid(), tick=t, length=max(1, l), pitch=p, velocity=round(v, 3))
            for t, l, p, v in sorted(notes)]))
        for start in at:
            self.placements.append(dict(id=self.nid(), clipId=cid, trackId=track, startBar=start, lengthBars=bars))
        return cid


def build(solo=None):
    b = Builder()
    t = {name: b.track(name, SOUNDS[name], solo) for name in SOUNDS}
    b.clip(t["Chords"], 4, chords_build(), [0, 4])
    b.clip(t["Chords"], 4, chords_drop(), [8, 12])
    b.clip(t["Pluck"], 2, pluck_arp([2, 3]), [2])  # 3小節目から入る（Gm7・Cm9 の2小節）
    b.clip(t["Pluck"], 4, pluck_arp(), [4])
    b.clip(t["Lead"], 4, lead(), [8, 12])
    b.clip(t["Bass"], 4, bass_drop(), [8, 12])
    b.clip(t["Kick"], 4, kicks(), [8, 12])
    b.clip(t["Snare"], 2, snare_roll(), [6])
    b.clip(t["Snare"], 4, snares_drop(), [8, 12])
    b.clip(t["Hats"], 2, hats(2, False), [4])
    b.clip(t["Hats"], 4, hats(4, True), [8, 12])
    b.clip(t["Riser"], 2, riser(), [6])
    return dict(format="mobiledaw-project", version=1, tempo=150.0, timeSig=[4, 4],
                key=dict(root=0, scale="minor"), tracks=b.tracks, clips=b.clips, placements=b.placements)


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
