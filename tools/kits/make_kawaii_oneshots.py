#!/usr/bin/env python3
"""かわいいフューチャーベース用の自作ワンショット（ボーカルチョップとピアノ）。

外部の録音は使わない。正弦・倍音の加算と簡単なバンドパスだけ。
出力: kits/kawaii-oneshots/  48kHz / 16bit / モノラル
ライセンスは kits/_licenses/SYNTH_DRUMS.md と同じ（自作・表示不要）。
"""
import json
import os

import numpy as np

SR = 48000
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "kits", "kawaii-oneshots"))


def tvec(dur):
    return np.arange(int(round(dur * SR))) / SR


def env(t, tau, attack=0.004):
    e = np.exp(-np.maximum(t - attack, 0.0) / tau)
    e = np.where(t < attack, t / max(attack, 1e-4), e)
    return e


def bp(x, lo, hi):
    # 1次のハイパス→ローパス。scipy なしで足りる
    def one(sig, freq, hp=False):
        if hp:
            a = (1.0 / (2 * np.pi * freq)) / (1.0 / (2 * np.pi * freq) + 1.0 / SR)
            y = np.empty_like(sig)
            px = py = 0.0
            for i, v in enumerate(sig):
                py = a * (py + v - px)
                px = v
                y[i] = py
            return y
        c = 1.0 - np.exp(-2 * np.pi * freq / SR)
        y = np.empty_like(sig)
        s = 0.0
        for i, v in enumerate(sig):
            s += c * (v - s)
            y[i] = s
        return y

    return one(one(x, lo, hp=True), hi, hp=False)


def formant(harm, f0, dur, vowels, tau=0.18):
    """vowels: (f1, f2, f3)。harm は倍音列のソース。"""
    t = tvec(dur)
    x = np.zeros_like(t)
    for k in range(1, harm):
        x += np.sin(2 * np.pi * f0 * k * t) / k
    x *= env(t, tau, 0.006)
    f1, f2, f3 = vowels
    y = bp(x, f1 * 0.7, f1 * 1.35) * 1.0
    y += bp(x, f2 * 0.75, f2 * 1.3) * 0.7
    y += bp(x, f3 * 0.8, min(f3 * 1.25, 12000)) * 0.35
    return y


def piano(f0=261.63, dur=1.1):
    t = tvec(dur)
    x = np.zeros_like(t)
    for k, amp, tau in ((1, 1.0, 0.55), (2, 0.45, 0.32), (3, 0.22, 0.2), (4, 0.16, 0.14),
                        (5, 0.1, 0.1), (6, 0.06, 0.08), (8, 0.04, 0.06)):
        x += np.sin(2 * np.pi * f0 * k * t) * np.exp(-t / tau) * amp
    click = np.random.default_rng(3).standard_normal(len(t)) * np.exp(-t / 0.004) * 0.15
    return x + click


def finish(x, dur, peak_db=-2.0):
    n = int(round(dur * SR))
    x = np.asarray(x, dtype=np.float64)[:n]
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(x)) or 1.0
    x *= 10 ** (peak_db / 20) / peak
    return np.clip(x, -1, 1)


def write(name, x):
    import wave
    pcm = (x * 32767).astype(np.int16)
    path = os.path.join(ROOT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name:16} {len(x)/SR:.3f}s")


def main():
    os.makedirs(ROOT, exist_ok=True)
    # C4 = 60。高い声の「あ」「お」を固定フォルマントで短く
    write("ah.wav", finish(formant(24, 261.63, 0.42, (800, 1250, 2700), 0.12), 0.42, -2.5))
    write("oh.wav", finish(formant(24, 261.63, 0.4, (520, 880, 2600), 0.13), 0.4, -2.5))
    write("piano.wav", finish(piano(), 1.1, -2.0))
    meta = {
        "name": "Kawaii Oneshots",
        "version": 1,
        "author": "Qnaiv",
        "license": "自作合成（同梱可・表示不要）",
        "description": "かわいいフューチャーベース用。固定フォルマントの「あ」「お」と、倍音のピアノ。すべて自作",
        "sounds": [
            {"file": "ah.wav", "name": "Ah", "note": 60},
            {"file": "oh.wav", "name": "Oh", "note": 62},
            {"file": "piano.wav", "name": "Piano", "note": 64},
        ],
    }
    with open(os.path.join(ROOT, "kit.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("wrote", ROOT)


if __name__ == "__main__":
    main()
