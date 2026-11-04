#!/usr/bin/env python3
"""フォルダの wav から kit.json を作る（名前から音の種類を見て、GM ドラムの番号に割り当てる）。

  python3 tools/kits/make_kit_json.py kits/<id> [--name "表示名"] [--license CC0-1.0] [--force]

既に kit.json があれば書き換えない（--force で上書き）。出来たものは手で直してよい。
割り当て：Kick 36 / Snare 38 / Clap 39 / Rim・Sidestick 37 / Closed Hat 42 / Pedal Hat 44 /
Open Hat 46 / Crash 49 / Ride 51 / Ride Bell 53 / China 52 / Tom 45・47・50 / Cowbell 56 /
Claves 75 / Maracas 70 / Shaker 82 / それ以外 60〜、音程つきの 808 ベースは 84〜。
同じ種類が2つ以上あれば、近くの空いている番号へ。ハイハットどうしはチョーク 1。
"""
import argparse
import json
import os
import re

# (名前に含まれる語, 表示名, 第一候補の番号, 予備の番号)
RULES = [
    (r"bass_?808|808_?bass", None, 84, list(range(85, 100))),
    (r"kick|bd\b", "Kick", 36, [35, 24, 25, 26, 27]),
    (r"rim", "Rim", 37, [33, 34]),
    (r"side_?stick", "Sidestick", 37, [33, 34]),
    (r"clap", "Clap", 39, [28, 29, 30]),
    (r"snare|sn\b", "Snare", 38, [40, 31, 32, 41, 43]),
    (r"hi_?hat.*(pedal)|pedal", "Pedal Hat", 44, []),
    (r"hi_?hat.*(half)|half_?open", "Half Open Hat", 46, [58, 59]),
    (r"hi_?hat.*open|open_?hat|\boh\b", "Open Hat", 46, [58, 59, 66]),
    (r"hi_?hat|closed|\bch\b", "Closed Hat", 42, [65, 67, 68]),
    (r"china", "China", 52, []),
    (r"ride.*bell|bell.*ride", "Ride Bell", 53, []),
    (r"ride", "Ride", 51, [59]),
    (r"crash|cymbal", "Crash", 49, [57, 55, 54, 69, 71]),
    (r"tom.*(high|hi)\b|tom_high|tom_hi", "Tom Hi", 50, [48]),
    (r"tom.*mid", "Tom Mid", 47, [48]),
    (r"tom.*(low|lo)\b|tom_low|tom_lo", "Tom Low", 45, [43, 41]),
    (r"tom", "Tom", 47, [48, 45, 50]),
    (r"cowbell", "Cowbell", 56, []),
    (r"claves", "Claves", 75, []),
    (r"maracas", "Maracas", 70, []),
    (r"shaker", "Shaker", 82, [83]),
]
HATS = {"Closed Hat", "Open Hat", "Half Open Hat", "Pedal Hat"}


def pretty(stem):
    words = re.split(r"[_\-\s]+", stem)
    return " ".join(w.upper() if w.lower() in ("808", "vcsl") else w.capitalize() for w in words if w)


def classify(stem):
    s = stem.lower()
    for pattern, label, first, spare in RULES:
        if re.search(pattern, s):
            return label, first, spare
    return None, None, []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--name")
    ap.add_argument("--license", default="")
    ap.add_argument("--author", default="")
    ap.add_argument("--description", default="")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    out = os.path.join(a.dir, "kit.json")
    if os.path.exists(out) and not a.force:
        print(f"{out} は既にあります（--force で上書き）")
        return
    wavs = sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".wav"))
    used, sounds, other = set(), [], 60

    def take(first, spare):
        nonlocal other
        for n in [first, *spare]:
            if n is not None and n not in used:
                used.add(n)
                return n
        while other in used:
            other += 1
        used.add(other)
        return other

    def pitch_of(f):
        # bass_808_F1 のような音名を MIDI 番号に（無ければ大きい数）
        m = re.search(r"([A-G])(#|b)?(-?\d)(?!.*[A-G]#?-?\d)", os.path.splitext(f)[0])
        if not m:
            return 999
        base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[m.group(1)]
        return base + {"#": 1, "b": -1}.get(m.group(2), 0) + (int(m.group(3)) + 1) * 12

    # 先に「その種類の代表」っぽい短い名前から割り当てる（kick.wav が kick_soft.wav より先に 36 を取る）。
    # 音程つきの 808 ベースは低い順に並べる
    for f in sorted(wavs, key=lambda f: (pitch_of(f) if re.search(RULES[0][0], f.lower()) else 0, len(f), f)):
        stem = os.path.splitext(f)[0]
        label, first, spare = classify(stem)
        note = take(first, spare)
        entry = {"file": f, "name": pretty(stem), "note": note}
        if label in HATS:
            entry["choke"] = 1
        sounds.append(entry)
    sounds.sort(key=lambda s: s["note"])

    meta = {
        "name": a.name or pretty(os.path.basename(os.path.normpath(a.dir))),
        "version": 1,
        "author": a.author,
        "license": a.license,
        "description": a.description,
        "sounds": sounds,
    }
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    for s in sounds:
        print(f"  {s['note']:3d}  {s['name']}{'  (choke)' if 'choke' in s else ''}")


if __name__ == "__main__":
    main()
