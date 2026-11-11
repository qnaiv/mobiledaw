"""シンセに歌詞を「歌わせる」ための道具（デモ曲用）。

歌詞はローマ字の音節（"ki", "shi", "N" = ん）を、メロディの1音ずつに割り当てる。
  ・母音  … Vox トラック（ウェーブテーブルのフォルマント表 wtTable=3）の WT_POS を音節ごとに
            オートメーション。表のフォルマントは倍音番号なので、音程ごとに一番近い位置を
            vowels.best_pos で選ぶ（音程補正）。母音ごとにカットオフも動かして明るさを変える
  ・子音  … 無声子音（k s sh t ch ts h f p）は別トラックのノイズを短く鳴らす。
            子音ごとに lowCutHz（FX）と cutoffHz をオートメーションして帯域を変える（簡易バンドパス）。
            子音は拍の少し前に置き、母音（音程）が拍の頭に来るようにする
  ・有声子音 m n r y w（と母音だけの音節）はノートを重ねてレガート（モノ＋グライド＝ポルタメント）。
            m/n は「ウ」の位置と低いカットオフから母音へ、y は「イ」から、w は「ウ」から滑らせる。
            m n r b d g はトラック音量を一瞬下げて区切りを付ける
  ・ビブラート … 長い音だけ、後半で lfoPitch を 0 → 深く（オートメーション）
"""
from future_bass import Builder, n, PPQ, BAR
from vowels import best_pos

CONS = {  # 子音: (長さ ms, lowCutHz, cutoffHz, 強さ)
    "k": (35, 1400, 4200, 0.75), "g": (20, 700, 2600, 0.35),
    "s": (95, 4800, 14000, 0.62), "sh": (95, 2300, 8500, 0.66),
    "z": (55, 4200, 11000, 0.3), "j": (55, 2200, 7500, 0.36),
    "t": (28, 2800, 7500, 0.75), "d": (16, 1500, 4200, 0.35),
    "ch": (65, 2500, 8500, 0.72), "ts": (75, 4200, 12500, 0.66),
    "h": (75, 700, 3800, 0.42), "f": (75, 900, 5000, 0.4),
    "p": (20, 400, 2200, 0.75), "b": (16, 300, 1600, 0.35),
}
LEGATO = {"", "m", "n", "r", "y", "w"}           # 前の音から切らずに滑らせる
DIP = {"m": 0.35, "n": 0.4, "r": 0.6, "b": 0.3, "d": 0.4, "g": 0.4, "y": 0.75, "w": 0.6}
VOWEL_CUTOFF = {"a": 5200, "i": 6500, "u": 2600, "e": 5600, "o": 3200}


def split(syl):
    if syl == "N":
        return "N", "u"
    for c in ("sh", "ch", "ts"):
        if syl.startswith(c):
            return c, syl[len(c):]
    if syl[0] in "aiueo":
        return "", syl
    return syl[0], syl[1:]


class AutoBuilder(Builder):
    def clip(self, track, bars, notes, at, automation=None):
        super().clip(track, bars, notes, at)
        if automation:
            self.clips[-1]["automation"] = automation


def lane(points):
    """[(tick, 値)] を tick 昇順・重複なし（後勝ち）に整える"""
    d = {}
    for t, v in points:
        d[int(t)] = round(float(v), 4)
    return [[t, d[t]] for t in sorted(d)]


FIXED = {"a": 0.0, "e": 0.25, "i": 0.5, "o": 0.75, "u": 1.0}


VOWEL_ID = {"a": 0, "e": 1, "i": 2, "o": 3, "u": 4}


def sing(lyric, tempo, clip_ticks, transpose=0, base_gain=1.0, consonants=True, vibrato=0.12, compensate=True, cutoff_cap=20000, fixed_formant=False):
    """lyric: [(拍, 長さ拍, 音程, 音節)]（クリップ先頭からの拍）。
    戻り値: (vox ノート, vox オートメーション, 子音ノート, 子音オートメーション)"""
    tps = tempo / 60.0 * PPQ  # ticks / 秒
    ms = lambda x: x / 1000.0 * tps
    ev = sorted(lyric)
    bp = best_pos if compensate else (lambda v, p: (FIXED[v], 0.0))
    vox, cons = [], []
    wt, cut, gain, vib, vow = [], [], [], [], []
    clc, ccut = [], []
    gain.append((0, base_gain))
    vib.append((0, 0.0))
    for i, (beat, lb, pitch, syl) in enumerate(ev):
        p = pitch + transpose
        c, v = split(syl)
        start = beat * PPQ
        end = (beat + lb) * PPQ
        nxt = ev[i + 1] if i + 1 < len(ev) else None
        # ノートの終わり：次の音節に滑らせるか、次の子音の前で切るか
        if nxt is not None and abs(nxt[0] * PPQ - end) < 1:
            nc, _ = split(nxt[3])
            if nc in LEGATO or nc == "N":
                end_t = end + ms(25)                  # 重ねる → レガート＋グライド
            else:
                end_t = end - ms(CONS[nc][0] + 10)    # 子音の分だけ空ける
        else:
            end_t = end - 40
        end_t = min(end_t, clip_ticks - 1)
        vox.append(n(start, end_t - start, p, 0.9))
        # 母音（音程補正した WT_POS）とカットオフ
        target = bp(v, p)[0]
        vc = min(VOWEL_CUTOFF[v] if c != "N" else 900, cutoff_cap)
        pre = start - 12
        if c in ("m", "n", "N"):
            wt += [(pre, bp("u", p)[0]), (start + ms(55), target)]
            cut += [(pre, 750), (start + ms(70), vc)]
        elif c == "y":
            wt += [(pre, bp("i", p)[0]), (start + ms(50), target)]
            cut += [(pre, VOWEL_CUTOFF["i"]), (start + ms(50), vc)]
        elif c == "w":
            wt += [(pre, bp("u", p)[0]), (start + ms(50), target)]
            cut += [(pre, 1500), (start + ms(50), vc)]
        else:
            wt += [(pre, wt[-1][1] if wt else target), (start + ms(18), target)]
            cut += [(pre, cut[-1][1] if cut else vc), (start + ms(18), vc)]
        if fixed_formant:
            vid = VOWEL_ID[v]
            vow += [(pre, vow[-1][1] if vow else vid), (start + ms(12), vid)]
        # 区切りの音量の谷
        if c in DIP:
            gain += [(pre, base_gain), (start + 4, base_gain * DIP[c]), (start + ms(55), base_gain)]
        # ビブラート：0.5秒より長い音だけ、後半で深くする
        dur_s = (end_t - start) / tps
        vib.append((pre, 0.0))
        if dur_s > 0.5 and vibrato > 0:
            vib += [(start + ms(250), 0.0), (start + ms(250) + (end_t - start - ms(250)) * 0.6, vibrato),
                    (end_t - 2, vibrato)]
        # 子音（無声・摩擦はノイズトラック）
        if consonants and c in CONS:
            dur, lc, cf, vel = CONS[c]
            cs = max(0, start - ms(dur))
            ce = start + ms(8) if c not in ("s", "sh", "ts", "h", "f", "ch") else start + ms(12)
            cons.append(n(cs, max(30, ce - cs), 60, vel))
            clc += [(cs - 4, lc)]
            ccut += [(cs - 4, cf)]
    wt = [(max(0, t), v) for t, v in wt]
    cut = [(max(0, t), min(v, cutoff_cap)) for t, v in cut]
    gain = [(max(0, t), v) for t, v in gain]
    vib = [(max(0, t), v) for t, v in vib]
    clamp = lambda pts: [(min(t, clip_ticks), v) for t, v in pts]
    vauto = [dict(param="wtPos", points=lane(clamp(wt))), dict(param="cutoffHz", points=lane(clamp(cut))),
             dict(param="gain", points=lane(clamp(gain))), dict(param="lfoPitch", points=lane(clamp(vib)))]
    if fixed_formant and vow:
        vauto.append(dict(param="formantVowel", points=lane(clamp([(max(0, t), v) for t, v in vow]))))
    cauto = None
    if cons:
        cauto = [dict(param="lowCutHz", points=lane([(max(0, t), v) for t, v in clc])),
                 dict(param="cutoffHz", points=lane([(max(0, t), v) for t, v in ccut]))]
    return vox, vauto, cons, cauto


def talkbox(notes, tempo, clip_ticks, vibrato=0.14):
    """トークボックス／ワウ風：1音ごとに「ウ」→「ア」→「オ」へ母音を開き、カットオフも一緒に開く。
    notes: [(拍, 長さ拍, 音程)]。重なった音はレガート（グライド）。戻り値: (ノート, オートメーション)"""
    tps = tempo / 60.0 * PPQ
    ms = lambda x: x / 1000.0 * tps
    ev = sorted(notes)
    out, wt, cut, vib = [], [], [], [(0, 0.0)]
    for i, (beat, lb, p) in enumerate(ev):
        s, e = beat * PPQ, (beat + lb) * PPQ
        nxt = ev[i + 1] if i + 1 < len(ev) else None
        legato = nxt is not None and abs(nxt[0] * PPQ - e) < 1 and lb < 1.01
        e_t = min(clip_ticks - 1, e + ms(20) if legato else e - 50)
        out.append(n(s, e_t - s, p, 0.9))
        wt += [(s - 10, 1.0), (s + ms(110), 0.02), (e_t, 0.6 if lb >= 1 else 0.3)]
        cut += [(s - 10, 1100), (s + ms(110), 5200), (e_t, 2600)]
        vib.append((s - 10, 0.0))
        if (e_t - s) / tps > 0.45:
            vib += [(s + ms(200), 0.0), (s + ms(200) + (e_t - s - ms(200)) * 0.5, vibrato), (e_t - 2, vibrato)]
    c = lambda pts: lane([(min(max(0, t), clip_ticks), v) for t, v in pts])
    return out, [dict(param="wtPos", points=c(wt)), dict(param="cutoffHz", points=c(cut)),
                 dict(param="lfoPitch", points=c(vib))]
