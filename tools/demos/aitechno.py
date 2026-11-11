"""A.I.テクノ系インストのデモ曲（ネコミミ☆プロトコル／メモリー☆シャッフル）の共通部品。

・主旋律は Melody トラックのリードシンセ（モノ＋ポルタメント）。長い音だけ少し遅れてビブラートがかかる
  （lfoPitch のオートメーション）。2度以内の順次進行はつなげて滑らせ、跳躍と同じ音の連打は切って弾き直す
・コードは {名前: (ボイシング, ベースの根音)}。進行は [(名前, 拍)] の並び
・メロディは "拍/長さ/音名" の並び（例 "0/.5/D5 .5/.5/F5"）と、ローマ字の音節
・SWING（tick）を入れると16分の裏が遅れる（シャッフル）。歌もコードもドラムも同じずれ方
・check_melody() はメロディの音がその時のコードに対して半音でぶつからないか調べる（作るたびに表示）
"""
import copy
import json

from future_bass import n, PPQ, BAR, S16  # noqa: F401
from singer import AutoBuilder, lane

SWING = 0
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """"F#5" → 78、"Bb4" → 70"""
    p = NOTE[name[0]]
    i = 1
    while i < len(name) and name[i] in "#b":
        p += 1 if name[i] == "#" else -1
        i += 1
    return p + 12 * (int(name[i:]) + 1)


def swung(beat):
    """拍 → 拍（シャッフルのずれを入れた後）"""
    t = round(beat * PPQ)
    if SWING and t % S16 == 0 and (t // S16) % 2 == 1:
        t += SWING
    return t / PPQ


def tk(beat):
    return int(round(swung(beat) * PPQ))


def note(beat, beats, pitch, vel=0.8, gap=30):
    s, e = tk(beat), tk(beat + beats)
    return n(s, max(20, e - s - gap), pitch, vel)


# ---- 音色 -----------------------------------------------------------------------------
BASE = {
    "EP": dict(  # ローズ風のエレピ（矩形波を絞って、弾いた瞬間だけ開く。コーラスで揺らす）
        color="ff5ad6c0",
        synth=dict(wave=1, osc=1, unison=2, detuneCents=6, width=0.45, blend=0.95, drive=0.05,
                   cutoffHz=1500, resonance=0.7, filterEnv=0.35, filterEnvDecayS=0.25, keyTrack=0.4,
                   attackS=0.003, decayS=0.9, sustain=0.35, releaseS=0.3, masterGain=0.6),
        fx=dict(lowCutHz=220, saturation=0.1, chorus=0.45, ott=0.1, sendReverb=0.2),
        mixer=dict(gain=0.4, pan=-0.15),
    ),
    "Gtr": dict(  # クリーンなカッティング・ギター風のプラック（ゴーストは短く小さく）
        color="ffffd27a",
        synth=dict(wave=0, osc=1, unison=2, detuneCents=5, width=0.5, blend=0.9,
                   cutoffHz=1600, resonance=1.2, filterEnv=0.6, filterEnvDecayS=0.07, keyTrack=0.5,
                   attackS=0.001, decayS=0.16, sustain=0.0, releaseS=0.05, masterGain=0.5),
        fx=dict(lowCutHz=350, eqMidDb=2, eqMidHz=1800, chorus=0.3, sendReverb=0.1, sendDelay=0.06),
        mixer=dict(gain=0.36, pan=0.3),
    ),
    "Bass": dict(  # 丸いシンセベース（矩形＋サブ。モノで少しすべらせる）
        color="ff5aa9f2",
        synth=dict(wave=1, osc=0.6, sub=0.7, unison=1, mono=1, glideS=0.015, drive=0.15,
                   cutoffHz=750, resonance=0.9, filterEnv=0.4, filterEnvDecayS=0.09, keyTrack=0.3,
                   attackS=0.003, decayS=0.3, sustain=0.6, releaseS=0.05, masterGain=0.7),
        fx=dict(saturation=0.15, eqLowDb=1, eqLowHz=80, comp=0.3, compThresholdDb=-16, compRatio=3),
        mixer=dict(gain=0.4, pan=0),
    ),
    "Lead": dict(  # フックをなぞる矩形波のリード（携帯ゲーム機っぽい）
        color="ff7af0ff",
        synth=dict(wave=1, unison=1, cutoffHz=5500, attackS=0.002, decayS=0.15, sustain=0.55,
                   releaseS=0.06, masterGain=0.45),
        fx=dict(lowCutHz=400, eqHighDb=-2, eqHighHz=6000, sendDelay=0.2, sendReverb=0.12),
        mixer=dict(gain=0.36, pan=-0.2),
    ),
    "Arp": dict(
        color="ff9ae6ff",
        synth=dict(wave=1, unison=1, cutoffHz=3200, attackS=0.001, decayS=0.07, sustain=0, releaseS=0.03,
                   masterGain=0.4),
        fx=dict(lowCutHz=500, sendDelay=0.2),
        mixer=dict(gain=0.3, pan=0.35),
    ),
    "Beep": dict(
        color="fffff3a0",
        synth=dict(wave=1, unison=1, cutoffHz=2600, attackS=0.001, decayS=0.06, sustain=0, releaseS=0.03,
                   masterGain=0.45),
        fx=dict(lowCutHz=600, sendReverb=0.25, sendDelay=0.2),
        mixer=dict(gain=0.2, pan=0.25),
    ),
    "Pad": dict(
        color="ffd89af2",
        synth=dict(wtTable=5, wtPos=0.3, unison=5, detuneCents=14, width=0.8, blend=0.7, cutoffHz=1700,
                   attackS=0.3, decayS=0.8, sustain=0.85, releaseS=0.4, masterGain=0.4),
        fx=dict(lowCutHz=300, chorus=0.25, sendReverb=0.35),
        mixer=dict(gain=0.3, pan=0),
    ),
}


def sounds(*names, **over):
    """BASE から names を選んで複製。over={名前: dict(synth=..., fx=..., mixer=...)} で上書き、新しい音色も足せる"""
    out = {}
    for k in names:
        out[k] = copy.deepcopy(BASE[k]) if k in BASE else {}
    for k, v in over.items():
        s = out.setdefault(k, {})
        for part, d in v.items():
            if isinstance(d, dict):
                s.setdefault(part, {}).update(d)
            else:
                s[part] = d
    return out


# ---- コード -------------------------------------------------------------------------------
def timeline(prog):
    """[(名前, 拍)] → [(名前, 始まりの拍, 拍)]"""
    out, b = [], 0.0
    for c, beats in prog:
        out.append((c, b, beats))
        b += beats
    return out


def length(prog):
    return sum(b for _, b in prog)


def chord_at(tl, beat):
    for c, s, l in tl:
        if s <= beat + 1e-6 < s + l:
            return c, s, l
    return tl[-1]


def pcs(CH, c, tr=0):
    v, r = CH[c]
    out = {(x + tr) % 12 for x in v} | {(r + tr) % 12}
    if not out & {(r + 6 + tr) % 12, (r + 8 + tr) % 12}:
        out.add((r + 7 + tr) % 12)  # 5度は省いてあってもコードの音
    return out


def comp(CH, prog, pos16, len16=1.5, vel=0.7, tr=0, up=0, push=True, top=None):
    """コードを16分の位置 pos16（1小節の中、0〜15）で刻む。push=True なら次のコードの16分前は次のコード（食い）"""
    tl = timeline(prog)
    total = length(prog)
    out = []
    for bar in range(int(total // 4)):
        for p in pos16:
            beat = bar * 4 + p / 4
            c = chord_at(tl, beat + (0.25 if push else 0))[0]
            notes = CH[c][0] if top is None else CH[c][0][-top:]
            for x in notes:
                out.append(note(beat, len16 / 4, x + tr + up, vel if p % 4 == 0 else vel * 0.9))
    return out


def held(CH, prog, vel=0.45, tr=0, up=0):
    return [note(s, l, x + tr + up, vel, gap=40) for c, s, l in timeline(prog) for x in CH[c][0]]


def pattern_hits(pat):
    """'x.g.' のような16分のパターン（1小節 16 文字）→ [(16分位置, 文字, 長さ16分)]"""
    pat = pat.replace(" ", "")
    hits = []
    for i, ch in enumerate(pat):
        if ch in ".-":
            continue
        ln = 1
        while i + ln < len(pat) and pat[i + ln] == "-":
            ln += 1
        hits.append((i, ch, ln))
    return hits


def gtr(CH, prog, pat, tr=0, up=12, vel=0.7, notes=3):
    """カッティング：x = コードの上の notes 音、g = ゴースト（ミュートっぽく短く小さく）"""
    tl = timeline(prog)
    out = []
    bars = int(length(prog) // 4)
    hits = pattern_hits(pat)
    per = len(pat.replace(" ", ""))
    for bar in range(bars * 16 // per):
        for p, ch, ln in hits:
            beat = (bar * per + p) / 4
            c = chord_at(tl, beat + 0.25)[0]
            v = CH[c][0][-notes:]
            for x in v:
                if ch == "g":
                    out.append(note(beat, 0.12, x + tr + up, vel * 0.3, gap=0))
                else:
                    out.append(note(beat, ln / 4 * 0.8, x + tr + up, vel * (1 if p % 4 == 0 else 0.85), gap=10))
    return out


def bassline(CH, prog, pat, tr=0, approach=True, vel=0.9):
    """1小節 16 文字のパターン：R 根音、O 1オクターブ上、5 5度（コードに無ければ根音）、g ゴースト、- のばす。
    approach=True なら、コードが変わる直前の音を次の根音の半音下（下がるときは半音上）にする（クロマチック・アプローチ）"""
    tl = timeline(prog)
    total = length(prog)
    hits = pattern_hits(pat)
    out = []
    for bar in range(int(total // 4)):
        for p, ch, ln in hits:
            beat = bar * 4 + p / 4
            c, s, l = chord_at(tl, beat)
            r = CH[c][1] + tr
            end = beat + ln / 4
            if ch == "g":
                out.append(note(beat, 0.1, r + 12, vel * 0.35, gap=0))
                continue
            pitch = {"R": r, "O": r + 12, "5": r + 7 if (r + 7) % 12 in pcs(CH, c, tr) else r + 12}[ch]
            nxt = end >= s + l - 0.25 - 1e-6 and s + l < total
            if approach and nxt and ln <= 2 and p % 4 != 0:
                r2 = CH[chord_at(tl, s + l)[0]][1] + tr
                if abs(r2 - r) > 1:
                    pitch = r2 - 1 if r2 > r else r2 + 1
            out.append(note(beat, ln / 4, pitch, vel if p % 4 == 0 else vel * 0.85, gap=25))
    return out


def arp(CH, prog, tr=0, up=12, vel=0.5, rate=4):
    tl = timeline(prog)
    out = []
    for k in range(int(length(prog) * rate)):
        beat = k / rate
        v = [x + up + tr for x in CH[chord_at(tl, beat)[0]][0]]
        seq = v + v[-2:0:-1]
        out.append(note(beat, 1 / rate, seq[k % len(seq)], vel if k % rate == 0 else vel * 0.75, gap=20))
    return out


def lead(mel, up=0, vel=0.8, gap=20):
    """メロディ（parse_mel の結果）をリードの音符に"""
    return [note(b, l, p + up, vel, gap=gap) for b, l, p, _ in mel]


def parse_mel(start, spec, text):
    """"拍/長さ/音名" の並び＋音節 → [(拍, 長さ, 音程, 音節)]（拍は start から）"""
    items = spec.split()
    syl = text.split() if text else ["a"] * len(items)
    assert len(items) == len(syl), (spec, text, len(items), len(syl))
    out = []
    for it, s in zip(items, syl):
        b, l, p = it.split("/")
        out.append((start + float(b), float(l), midi(p), s))
    return out


def shift(mel, beats):
    return [(b + beats, l, p, s) for b, l, p, s in mel]


def coin(beat, notes):
    return [note(beat, 0.125, notes[0], 0.7, 0), note(beat + 0.125, 0.125, notes[1], 0.7, 0),
            note(beat + 0.25, 0.5, notes[2], 0.75)]


def powerup(beat, tones):
    return [note(beat + k * 0.125, 0.12, p, 0.6 + 0.04 * k, 0) for k, p in enumerate(tones)]


# ---- 確認 ---------------------------------------------------------------------------------------
def check_melody(label, mel, CH, prog, tr=0, quiet=False):
    """メロディの各音を、鳴っている間のコードと比べる。
    × = 長い（0.5拍以上）のにボイシングの音と短2度／短9度でぶつかる、△ = コードの外の音（短い経過音なら可）"""
    tl = timeline(prog)
    bad = 0
    for b, l, p, s in mel:
        pc = (p + tr) % 12
        t = b
        while t < b + l - 1e-6:
            c, cs, cl = chord_at(tl, t)
            P = pcs(CH, c, tr)
            clash = any((pc - q) % 12 in (1, 11) for q in P) and pc not in P
            dur = min(b + l, cs + cl) - t
            if clash and dur >= 0.5:
                bad += 1
                print(f"  × {label} 拍{t:5.2f} {s:>4} {p + tr:3d} on {c} (長さ {dur:.2f})")
            elif pc not in P and dur >= 0.75 and not quiet:
                print(f"  △ {label} 拍{t:5.2f} {s:>4} {p + tr:3d} on {c} (長さ {dur:.2f})")
            t = cs + cl
    return bad


class Song:
    """小節ごとのコード（分析用の地図）と、トラック・クリップ作り"""

    def __init__(self, sounds_, tempo, solo=None):
        self.b = AutoBuilder()
        self.tempo = tempo
        self.t = {k: self.b.track(k, v, solo) for k, v in sounds_.items()}
        self.map = []  # (始まりの拍, 終わりの拍, pcs)

    def chords(self, bar, CH, prog, tr=0):
        for c, s, l in timeline(prog):
            self.map.append((bar * 4 + s, bar * 4 + s + l, sorted(pcs(CH, c, tr))))

    def clip(self, name, bars, notes, at, automation=None):
        self.b.clip(self.t[name], bars, notes, at, automation=automation)

    def melody(self, mel, bars, at, vib=0.07, tr=0, vel=0.85, slur=2):
        """主旋律をリードシンセ（Melody トラック）で。2度以内でつながる音はレガート（グライド）、
        跳躍・同じ音・休みの前は切る。0.45 秒より長い音は 0.22 秒あとからビブラートを深くする"""
        tps = self.tempo / 60.0 * PPQ
        ev = sorted(mel)
        clip = bars * BAR
        notes, vibl = [], [(0, 0.0)]
        for i, (b, l, p, _) in enumerate(ev):
            s0, e0 = tk(b), tk(b + l)
            nxt = ev[i + 1] if i + 1 < len(ev) else None
            if nxt is not None and abs(nxt[0] - (b + l)) < 1e-6:
                end = e0 + 20 if 0 < abs(nxt[2] - p) <= slur else e0 - 45
            else:
                end = e0 - 40
            end = min(end, clip - 1)
            on_beat = abs(b - round(b)) < 1e-6
            notes.append(n(s0, end - s0, p + tr, vel if on_beat else vel * 0.88))
            vibl.append((max(0, s0 - 10), 0.0))
            if (end - s0) / tps > 0.45 and vib > 0:
                a0 = s0 + int(0.22 * tps)
                vibl += [(a0, 0.0), (a0 + int((end - a0) * 0.6), vib), (end - 2, vib)]
        auto = [dict(param="lfoPitch", points=lane([(min(t, clip), v) for t, v in vibl]))]
        self.b.clip(self.t["Melody"], bars, notes, at, automation=auto)

    def project(self, title, key_root, master, aux=None):
        return dict(format="mobiledaw-project", version=1, title=title, tempo=self.tempo, timeSig=[4, 4],
                    key=dict(root=key_root, scale="major"), master=master,
                    aux=aux or dict(reverbReturn=0.75, reverbSize=0.5, delayReturn=0.45, delayFeedback=0.3),
                    tracks=self.b.tracks, clips=self.b.clips, placements=self.b.placements)

    def write_map(self, path):
        sec = 60.0 / self.tempo
        json.dump([[a * sec, z * sec, p] for a, z, p in sorted(self.map)], open(path, "w"))


def main(build, out, map_path):
    import sys
    args = sys.argv[1:]
    solo = None
    if "--solo" in args:
        i = args.index("--solo")
        solo = args[i + 1]
        del args[i:i + 2]
    song, data = build(solo)
    path = args[0] if args else out
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    song.write_map(map_path)
    print(path, "tracks", len(data["tracks"]), "bars", max(p["startBar"] + p["lengthBars"] for p in data["placements"]))
