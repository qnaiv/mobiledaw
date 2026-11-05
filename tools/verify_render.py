#!/usr/bin/env python3
"""future-bass-pro の全音を1音ずつ鳴らす検証プロジェクトを作り、
mdaw_render の出力を音ごとに数値チェックする。

使い方:
  python3 verify_render.py gen     # test_project.json を作る（_verify/）
  python3 verify_render.py check   # render_out.wav を解析して合否を出す
"""
import json
import os
import sys

import numpy as np
from scipy.io import wavfile

HERE = os.path.dirname(os.path.abspath(__file__))
KIT_DIR = os.path.join(HERE, "..", "kits", "future-bass-pro")
VDIR = os.path.join(HERE, "..", "_verify")
TEMPO = 155.0
PPQ = 960
TPS = TEMPO / 60 * PPQ  # ticks per second
GAP = 0.45

PARAMS = {"cutoffHz": 18000, "resonance": 0.7, "attackS": 0.0005, "decayS": 0.26,
          "sustain": 0.0, "releaseS": 0.04, "detuneCents": 0, "masterGain": 1.0,
          "unison": 1, "width": 0, "sub": 0.0, "filterEnv": 0.0,
          "filterEnvDecayS": 0.025, "pitchEnv": 0, "pitchEnvDecayS": 0.03,
          "wave": 0, "osc": 0.5}


def load_kit():
    with open(os.path.join(KIT_DIR, "kit.json"), encoding="utf-8") as f:
        kit = json.load(f)
    out = []
    for s in kit["sounds"]:
        rate, data = wavfile.read(os.path.join(KIT_DIR, s["file"]))
        out.append((s, len(data) / rate))
    return out


def gen():
    sounds = load_kit()
    notes, onsets = [], []
    t = 0.5
    for i, (s, dur) in enumerate(sounds):
        onsets.append((s, t))
        notes.append({"id": f"{0x1000 + i:016x}", "tick": int(round(t * TPS)),
                      "length": 120, "pitch": s["note"], "velocity": 0.95})
        t += dur + GAP
    total_ticks = int(round(t * TPS)) + PPQ * 4
    bars = int(np.ceil(total_ticks / (PPQ * 4)))
    proj = {
        "format": "mobiledaw-project", "version": 1, "tempo": TEMPO,
        "timeSig": [4, 4], "key": {"root": 2, "scale": "major"},
        "tracks": [{"id": "0000000000000001", "name": "Pro Drums",
                    "color": "fff28c38",
                    "instrument": {"type": "kit", "kit": "future-bass-pro",
                                   "params": PARAMS},
                    "fx": {}, "mixer": {"gain": 1.0, "pan": 0,
                                        "mute": False, "solo": False}}],
        "clips": [{"id": "0000000000000002", "trackId": "0000000000000001",
                   "lengthTicks": total_ticks, "notes": notes,
                   "automation": []}],
        "placements": [{"id": "0000000000000003",
                        "clipId": "0000000000000002",
                        "trackId": "0000000000000001",
                        "startBar": 0, "lengthBars": bars}],
    }
    with open(os.path.join(VDIR, "test_project.json"), "w", encoding="utf-8") as f:
        json.dump(proj, f)
    with open(os.path.join(VDIR, "onsets.json"), "w") as f:
        json.dump([(s["name"], s["note"], t0) for s, t0 in onsets], f)
    print(f"project: {len(notes)} notes, {bars} bars, {t:.1f}s")


def check():
    with open(os.path.join(VDIR, "onsets.json")) as f:
        onsets = json.load(f)
    rate, data = wavfile.read(os.path.join(VDIR, "render_out.wav"))
    x = data.astype(np.float64) / 32768.0
    if x.ndim > 1:
        x = x.mean(axis=1)
    overall_peak = np.max(np.abs(x))
    print(f"render: {len(x)/rate:.1f}s @ {rate}Hz, overall peak {overall_peak:.4f}")
    fails = []
    rows = []
    for i, (name, note, t0) in enumerate(onsets):
        t1 = onsets[i + 1][2] if i + 1 < len(onsets) else len(x) / rate
        seg = x[int(max(t0 - 0.05, 0) * rate):int(t1 * rate)]
        rms = np.sqrt(np.mean(seg ** 2)) if len(seg) else 0
        peak = np.max(np.abs(seg)) if len(seg) else 0
        rms_db = 20 * np.log10(rms) if rms > 0 else -999
        ok = rms_db > -55 and peak <= 1.0
        rows.append((name, note, rms_db, peak, ok))
        if not ok:
            fails.append(name)
    for name, note, rms_db, peak, ok in rows:
        print(f"  {'OK ' if ok else 'FAIL'} note {note:3d} {name:20s} rms {rms_db:7.2f} dB  peak {peak:.3f}")
    print("RESULT:", "ALL OK" if not fails else f"FAILED: {fails}")
    return 1 if fails else 0


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen()
    else:
        sys.exit(check())
