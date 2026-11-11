#!/usr/bin/env python3
"""リズムセクションのワンショットを、自作の合成（と CC0 実録への自作レイヤー）で厚くする。

置き換える・追加するファイル:
  kits/house/            自作合成のキック・スネア・クラップ・シェイカー（44.1kHz ステレオ）
  kits/future-bass-pro/  自作合成のキック・スネア・ハット・クラップ（48kHz ステレオ）
  kits/acoustic-live/    CC0 の kick_real / snare_real / snare_rimshot を読み、
                         自作の胴・サブを足した kick_full / snare_full / rimshot_full を書く
                         （元の CC0 ファイルは残す。何度実行しても同じ結果）

外部のサンプルは追加しない。ライセンスは kits/_licenses/SYNTH_DRUMS.md。
使い方: python3 tools/kits/make_pro_drums.py
"""
import os

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "kits"))


def tvec(sr, dur):
    return np.arange(int(round(dur * sr))) / sr


def env(t, tau, attack=0.0):
    e = np.exp(-np.maximum(t - attack, 0.0) / tau)
    if attack > 0:
        e = np.where(t < attack, t / max(attack, 1e-5), e)
    return e


def noise(sr, dur, seed):
    return np.random.default_rng(seed).standard_normal(int(round(dur * sr)))


def one_pole(x, coeff):
    y = np.empty_like(x)
    s = 0.0
    c = float(coeff)
    for i, v in enumerate(x):
        s += c * (v - s)
        y[i] = s
    return y


def hp(x, sr, freq):
    # 1次ハイパス
    rc = 1.0 / (2 * np.pi * freq)
    a = rc / (rc + 1.0 / sr)
    y = np.empty_like(x)
    prev_x = 0.0
    prev_y = 0.0
    for i, v in enumerate(x):
        prev_y = a * (prev_y + v - prev_x)
        prev_x = v
        y[i] = prev_y
    return y


def lp(x, sr, freq):
    c = 1.0 - np.exp(-2 * np.pi * freq / sr)
    return one_pole(x, c)


def bp(x, sr, lo, hi):
    return lp(hp(x, sr, lo), sr, hi)


def pitch_sine(sr, f0, f1, tau_f, dur, tau_a, gain=1.0, drive=1.0):
    t = tvec(sr, dur)
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    phase = 2 * np.pi * np.cumsum(f) / sr
    x = np.sin(phase) * env(t, tau_a)
    if drive != 1.0:
        x = np.tanh(x * drive) / np.tanh(drive)
    return x * gain


def finish(x, sr, dur, peak_db=-1.0, fade_ms=6.0, stereo=True, channels=2):
    n = int(round(dur * sr))
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = np.column_stack([x, x]) if channels == 2 else x[:, None]
    if len(x) > n:
        x = x[:n]
    elif len(x) < n:
        x = np.pad(x, ((0, n - len(x)), (0, 0)))
    fade = int(sr * fade_ms / 1000)
    if fade > 1:
        x[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None]
    peak = np.max(np.abs(x))
    if peak > 0:
        x *= 10 ** (peak_db / 20) / peak
    x = np.clip(x, -1.0, 1.0)
    if not stereo:
        x = x.mean(axis=1)
    pcm = (x * 32767.0).astype(np.int16)
    return pcm


def write_wav(path, sr, pcm):
    import wave

    channels = 1 if pcm.ndim == 1 else pcm.shape[1]
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(sr)
        if channels == 1:
            w.writeframes(pcm.tobytes())
        else:
            w.writeframes(np.ascontiguousarray(pcm).tobytes())
    peak = np.max(np.abs(pcm)) / 32768.0
    print(f"  {os.path.relpath(path, ROOT):40s} {len(pcm)/sr:5.3f}s  peak {20*np.log10(peak+1e-12):6.2f} dB")


def house_kick(sr, techno=False):
    dur = 0.48 if techno else 0.58
    t = tvec(sr, dur)
    f_body = (175, 58, 0.028) if techno else (150, 48, 0.04)
    click = bp(noise(sr, dur, 3 if techno else 1), sr, 2000, 7500) * np.exp(-t / 0.0022) * 0.7
    knock = bp(noise(sr, dur, 5), sr, 180, 500) * np.exp(-t / 0.012) * 0.35
    body = pitch_sine(sr, f_body[0], f_body[1], f_body[2], dur, 0.11 if techno else 0.16, gain=1.0, drive=2.2)
    sub = pitch_sine(sr, f_body[1] + 8, f_body[1] * 0.85, 0.12, dur, 0.22 if not techno else 0.14, gain=0.55, drive=1.3)
    x = click + knock + body + sub
    # わずかに左右をずらしてステレオの厚み
    r = np.tanh(x * 1.15)
    late = lp(noise(sr, dur, 9), sr, 180) * env(t, 0.18) * 0.04
    return np.column_stack([np.tanh((x + late) * 1.05), np.tanh((r + late * 0.8) * 1.05)])


def house_snare(sr):
    dur = 0.28
    t = tvec(sr, dur)
    tone = np.sin(2 * np.pi * 196 * t) * env(t, 0.045) * 0.45
    tone += np.sin(2 * np.pi * 332 * t) * env(t, 0.03) * 0.2
    snap = bp(noise(sr, dur, 21), sr, 1800, 8000) * np.exp(-t / 0.004) * 0.9
    body = bp(noise(sr, dur, 22), sr, 180, 1200) * env(t, 0.07) * 0.7
    tail = bp(noise(sr, dur, 23), sr, 800, 4000) * env(t, 0.09) * 0.25
    x = np.tanh((tone + snap + body + tail) * 1.3)
    return np.column_stack([x, x * 0.96])


def house_clap(sr):
    dur = 0.42
    t = tvec(sr, dur)
    bursts_at = (0.0, 0.011, 0.021, 0.034)
    x = np.zeros_like(t)
    n = bp(noise(sr, dur, 31), sr, 900, 4500)
    for i, t0 in enumerate(bursts_at):
        x += n * np.exp(-np.maximum(t - t0, 0) / 0.018) * (t >= t0) * (0.55 + 0.15 * i)
    tail = bp(noise(sr, dur, 32), sr, 700, 3500) * np.exp(-np.maximum(t - 0.04, 0) / 0.09) * (t >= 0.04) * 0.45
    x = np.tanh((x + tail) * 1.4)
    # 広いクラップ：片側を数 ms 遅らせる
    delay = int(0.004 * sr)
    r = np.concatenate([np.zeros(delay), x[:-delay]])
    return np.column_stack([x, r])


def house_shaker(sr):
    dur = 0.18
    t = tvec(sr, dur)
    x = bp(noise(sr, dur, 41), sr, 4000, 12000) * env(t, 0.03)
    x += bp(noise(sr, dur, 42), sr, 1500, 5000) * env(t, 0.05) * 0.35
    return np.column_stack([x, x])


def fb_kick(sr, kind):
    # kind: main / punch / soft / sub
    dur = {"main": 0.62, "punch": 0.42, "soft": 0.5, "sub": 0.85}[kind]
    f1 = {"main": 52, "punch": 58, "soft": 49, "sub": 40}[kind]
    t = tvec(sr, dur)
    click = bp(noise(sr, dur, 50 + len(kind)), sr, 2200, 8000) * np.exp(-t / 0.002) * (0.45 if kind != "soft" else 0.2)
    body = pitch_sine(sr, 160 if kind != "sub" else 90, f1, 0.035, dur, 0.12, gain=0.95, drive=1.8)
    sub = pitch_sine(sr, f1 + 6, f1 * 0.72, 0.14, dur, 0.28 if kind == "sub" else 0.18, gain=0.7 if kind == "sub" else 0.48)
    x = np.tanh(click + body + sub)
    return np.column_stack([x, x])


def fb_snare(sr, kind):
    dur = {"main": 0.26, "tight": 0.16, "snap": 0.1}[kind]
    t = tvec(sr, dur)
    tone_f = 210 if kind != "snap" else 240
    tone = np.sin(2 * np.pi * tone_f * t) * env(t, 0.04 if kind != "snap" else 0.02) * 0.4
    snap = bp(noise(sr, dur, 70), sr, 2000, 9000) * np.exp(-t / (0.003 if kind == "snap" else 0.005))
    body = bp(noise(sr, dur, 71), sr, 200, 1400) * env(t, 0.06) * (0.35 if kind == "tight" else 0.6)
    x = np.tanh((tone + snap + body) * 1.25)
    return np.column_stack([x, x])


def fb_hat(sr, kind):
    dur = {"closed": 0.12, "short": 0.055, "open": 0.22}[kind]
    t = tvec(sr, dur)
    # 金属的な部分音＋ノイズ。正弦の非整数倍でチープなノイズハットより硬くする
    x = np.zeros_like(t)
    rng = np.random.default_rng(80)
    for k in range(8):
        f = 2800 * (1.4 ** (k * 0.35)) * (0.97 + 0.06 * rng.random())
        x += np.sin(2 * np.pi * f * t + rng.random()) * (0.35 / (1 + k * 0.4))
    x *= env(t, 0.02 if kind != "open" else 0.05)
    n = hp(noise(sr, dur, 90), sr, 6000) * env(t, 0.015 if kind == "short" else 0.028)
    x = np.tanh((x + n * 0.8) * 1.4)
    return np.column_stack([x, x * 0.92])


def fb_clap(sr, wide=False):
    dur = 0.36 if wide else 0.22
    t = tvec(sr, dur)
    n = bp(noise(sr, dur, 100 if wide else 101), sr, 1000, 5000)
    x = np.zeros_like(t)
    times = (0.0, 0.01, 0.02, 0.033) if wide else (0.0, 0.008, 0.016)
    for i, t0 in enumerate(times):
        x += n * np.exp(-np.maximum(t - t0, 0) / 0.016) * (t >= t0) * (0.5 + 0.15 * i)
    if wide:
        x += bp(noise(sr, dur, 102), sr, 600, 3000) * env(t, 0.1) * 0.35
    x = np.tanh(x * 1.5)
    if wide:
        d = int(0.006 * sr)
        r = np.concatenate([np.zeros(d), x[:-d]])
        return np.column_stack([x, r])
    return np.column_stack([x, x])


def fatten_acoustic(path, kind):
    import wave

    with wave.open(path) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        raw = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        raw = raw.reshape(-1, ch).mean(axis=1)
    peak0 = np.max(np.abs(raw)) + 1e-9
    # 先頭の無音は切らない（アタックの位置を保つ）
    dur = max(len(raw) / sr, 0.42 if kind == "kick" else 0.32)
    n = int(round(dur * sr))
    src = np.zeros(n)
    src[: len(raw)] = raw
    t = tvec(sr, dur)
    if kind == "kick":
        body = pitch_sine(sr, 130, 52, 0.03, dur, 0.16, gain=0.55, drive=1.6)
        sub = pitch_sine(sr, 60, 46, 0.1, dur, 0.24, gain=0.42, drive=1.2)
        # 元のアタックは残し、低い胴だけ足す
        x = src + lp(body + sub, sr, 180) * 0.85
    else:
        tone = np.sin(2 * np.pi * 188 * t) * env(t, 0.05) * 0.28
        body = bp(noise(sr, dur, 7), sr, 180, 900) * env(t, 0.06) * 0.22
        x = src + tone + body
    # 元のピークを大きく超えない
    x *= peak0 / (np.max(np.abs(x)) + 1e-9) * 0.98
    return sr, np.clip(x, -1.0, 1.0)


def main():
    print("house")
    house = os.path.join(ROOT, "house")
    sr = 44100
    write_wav(os.path.join(house, "kick_house.wav"), sr, finish(house_kick(sr, False), sr, 0.58, -1.2))
    write_wav(os.path.join(house, "kick_techno.wav"), sr, finish(house_kick(sr, True), sr, 0.48, -1.2))
    write_wav(os.path.join(house, "snare_tight_dry.wav"), sr, finish(house_snare(sr), sr, 0.28, -1.5))
    write_wav(os.path.join(house, "clap_wide.wav"), sr, finish(house_clap(sr), sr, 0.42, -1.5))
    write_wav(os.path.join(house, "shaker_bright.wav"), sr, finish(house_shaker(sr), sr, 0.18, -3.0))

    print("future-bass-pro")
    fb = os.path.join(ROOT, "future-bass-pro")
    sr = 48000
    write_wav(os.path.join(fb, "kick_main.wav"), sr, finish(fb_kick(sr, "main"), sr, 0.62, -1.0))
    write_wav(os.path.join(fb, "kick_punch.wav"), sr, finish(fb_kick(sr, "punch"), sr, 0.42, -1.0))
    write_wav(os.path.join(fb, "kick_soft.wav"), sr, finish(fb_kick(sr, "soft"), sr, 0.5, -2.5))
    write_wav(os.path.join(fb, "kick_subdeep.wav"), sr, finish(fb_kick(sr, "sub"), sr, 0.85, -1.5))
    write_wav(os.path.join(fb, "snare_main.wav"), sr, finish(fb_snare(sr, "main"), sr, 0.26, -1.2))
    write_wav(os.path.join(fb, "snare_tight.wav"), sr, finish(fb_snare(sr, "tight"), sr, 0.16, -1.5))
    write_wav(os.path.join(fb, "snare_snap.wav"), sr, finish(fb_snare(sr, "snap"), sr, 0.1, -1.0))
    write_wav(os.path.join(fb, "hat_closed.wav"), sr, finish(fb_hat(sr, "closed"), sr, 0.12, -2.0))
    write_wav(os.path.join(fb, "hat_closed_short.wav"), sr, finish(fb_hat(sr, "short"), sr, 0.055, -2.0))
    write_wav(os.path.join(fb, "hat_open_short.wav"), sr, finish(fb_hat(sr, "open"), sr, 0.22, -2.0))
    write_wav(os.path.join(fb, "clap_main.wav"), sr, finish(fb_clap(sr, False), sr, 0.22, -1.2))
    write_wav(os.path.join(fb, "clap_tight.wav"), sr, finish(fb_clap(sr, False), sr, 0.16, -1.2))
    write_wav(os.path.join(fb, "clap_wide.wav"), sr, finish(fb_clap(sr, True), sr, 0.36, -1.5))

    print("acoustic-live (CC0 source + synthesized body)")
    ac = os.path.join(ROOT, "acoustic-live")
    for src, dst, kind in (
        ("kick_real.wav", "kick_full.wav", "kick"),
        ("snare_real.wav", "snare_full.wav", "snare"),
        ("snare_rimshot.wav", "rimshot_full.wav", "snare"),
    ):
        sr, x = fatten_acoustic(os.path.join(ac, src), kind)
        pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
        write_wav(os.path.join(ac, dst), sr, pcm)


if __name__ == "__main__":
    main()
