#!/usr/bin/env python3
"""future-bass-pro キットの生成スクリプト。

素材は (a) numpy/scipy による自作合成 と (b) kits/future-bass の CC0 素材
（TR-808 実機録音）のリサンプル・整形・重ね のみ。外部素材は使わない。
出力: 48kHz / 16bit / ステレオ WAV。
使い方: python3 build_kit.py <出力フォルダ> <既存 future-bass キットのフォルダ>
"""
import json
import os
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 48000
rng = np.random.default_rng(20261105)

OUT = sys.argv[1]
SRC = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------- helpers

def tvec(dur):
    return np.arange(int(round(dur * SR))) / SR

def exp_env(t, tau, attack=0.0):
    e = np.exp(-np.maximum(t - attack, 0.0) / tau)
    if attack > 0:
        e = np.where(t < attack, t / attack, e)
    return e

def pitch_sine(f0, f1, tau_f, dur, tau_a, gain=1.0, drive=1.0):
    t = tvec(dur)
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(phase) * exp_env(t, tau_a)
    if drive != 1.0:
        x = np.tanh(x * drive) / np.tanh(drive)
    return x * gain

def const_sine(freq, dur, tau_a, gain=1.0):
    t = tvec(dur)
    return np.sin(2 * np.pi * freq * t) * exp_env(t, tau_a) * gain

def pitch_sine_gain(f0, f1, tau_f, dur, tau_a, gain):
    t = tvec(dur)
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * exp_env(t, tau_a) * gain

def noise(dur, seed):
    r = np.random.default_rng(seed)
    return r.standard_normal(int(round(dur * SR)))

def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)

def hp(x, f, order=2):
    sos = signal.butter(order, f, btype="highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)

def lp(x, f, order=2):
    sos = signal.butter(order, f, btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)

def bursts(dur, times, tau, lo, hi, gains, seed, tail_tau=0.0, tail_gain=0.0):
    """クラップ用：微小バースト列＋尾。モノラルで返す。"""
    t = tvec(dur)
    x = np.zeros_like(t)
    n = noise(dur, seed)
    for t0, g in zip(times, gains):
        m = t >= t0
        seg = np.zeros_like(t)
        seg[m] = np.exp(-(t[m] - t0) / tau)
        x += bp(n, lo, hi) * seg * g
    if tail_tau > 0:
        t0 = times[-1]
        m = t >= t0
        seg = np.zeros_like(t)
        seg[m] = np.exp(-(t[m] - t0) / tail_tau)
        x += bp(noise(dur, seed + 7), lo, hi) * seg * tail_gain
    return x

def stereo(mono):
    return np.column_stack([mono, mono])

def decorrelate_tail(mono_like_l, mono_like_r):
    return np.column_stack([mono_like_l, mono_like_r])

def finish(x, dur, peak_db, fade_ms=8.0, exact=False):
    """長さを dur に揃え、末尾フェード、ピーク正規化して int16 ステレオで返す。"""
    n = int(round(dur * SR))
    if x.ndim == 1:
        x = stereo(x)
    if len(x) > n:
        x = x[:n]
    elif len(x) < n:
        x = np.pad(x, ((0, n - len(x)), (0, 0)))
    fade = int(SR * fade_ms / 1000)
    if fade > 0:
        ramp = np.linspace(1.0, 0.0, fade)[:, None]
        x[-fade:] *= ramp
    peak = np.max(np.abs(x))
    if peak > 0:
        x = x * (10 ** (peak_db / 20) / peak)
    return np.clip(x, -1.0, 1.0)

def save(name, x):
    wavfile.write(os.path.join(OUT, name), SR, (x * 32767).astype(np.int16))
    peak = np.max(np.abs(x))
    rms = np.sqrt(np.mean(x.astype(np.float64) ** 2))
    print(f"{name:24s} {len(x)/SR:6.3f}s  peak {20*np.log10(peak):6.2f} dB  rms {20*np.log10(rms):6.2f} dB")

def load_src(name):
    """既存キット（44.1kHz）の WAV を 48kHz float モノラルで読む。"""
    rate, data = wavfile.read(os.path.join(SRC, name))
    x = data.astype(np.float64) / 32768.0
    if x.ndim > 1:
        x = x.mean(axis=1)
    if rate != SR:
        g = np.gcd(rate, SR)
        x = signal.resample_poly(x, SR // g, rate // g)
    # 先頭の無音を切る
    idx = np.argmax(np.abs(x) > 0.002)
    return x[idx:]

def trim_env(x, dur, fade_ms=30.0):
    n = int(round(dur * SR))
    if len(x) > n:
        x = x[:n].copy()
    fade = int(SR * fade_ms / 1000)
    if fade > 0 and len(x) >= fade:
        x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return x

# ---------------------------------------------------------------- kicks
# キーは D：胴は D2=73.42Hz に落ち着き、サブは D1=36.71Hz。

def kick_main():
    dur = 0.55
    t = tvec(dur)
    click = bp(noise(dur, 11), 1800, 7000) * np.exp(-t / 0.003) * 0.55
    body = pitch_sine(155, 73.42, 0.045, dur, 0.085, gain=0.95, drive=1.6)
    sub = pitch_sine_gain(44, 36.71, 0.10, dur, 0.13, 0.50)
    return finish(click + body + sub, dur, -0.5)

def kick_punch():
    dur = 0.40
    t = tvec(dur)
    click = bp(noise(dur, 12), 2000, 8000) * np.exp(-t / 0.0025) * 0.8
    tick = pitch_sine_gain(1200, 400, 0.004, dur, 0.004, 0.25)
    body = pitch_sine(175, 80, 0.035, dur, 0.060, gain=0.95, drive=2.2)
    sub = const_sine(36.71, dur, 0.09, gain=0.35)
    return finish(click + tick + body + sub, dur, -0.5)

def kick_subdeep():
    dur = 0.80
    t = tvec(dur)
    click = bp(noise(dur, 13), 1200, 4000) * np.exp(-t / 0.004) * 0.25
    body = pitch_sine(130, 62, 0.07, dur, 0.14, gain=0.85, drive=1.3)
    sub = const_sine(36.71, dur, 0.22, gain=0.60)
    return finish(click + body + sub, dur, -0.6, fade_ms=15)

def kick_soft():
    dur = 0.45
    t = tvec(dur)
    tick = lp(noise(dur, 14), 3000) * np.exp(-t / 0.005) * 0.30
    body = pitch_sine(120, 65, 0.05, dur, 0.10, gain=0.95, drive=1.2)
    sub = const_sine(36.71, dur, 0.12, gain=0.40)
    return finish(tick + body + sub, dur, -1.0, fade_ms=12)

def sub_tail():
    dur = 0.90
    x = pitch_sine_gain(73.42, 36.71, 0.18, dur, 0.28, 0.92)
    x += pitch_sine_gain(146.84, 73.42, 0.18, dur, 0.20, 0.07)
    return finish(x, dur, -1.0, fade_ms=25)

# ---------------------------------------------------------------- snares
# 全てドライ（リバーブなし）。胴 ~190Hz＋帯域を絞ったノイズ＋薄いクラップ。

def snare_body(f0, f1, tau_f, tau_a, gain, ring_f=0.0, ring_g=0.0, ring_tau=0.03):
    dur = 0.30
    x = pitch_sine(f0, f1, tau_f, dur, tau_a, gain=gain, drive=1.5)
    if ring_f:
        t = tvec(dur)
        x += np.sin(2 * np.pi * ring_f * t) * exp_env(t, ring_tau) * ring_g
    return x

def snare(noise_bp, noise_tau, noise_gain, body, clap_gain=0.0, dur=0.24, seed=21):
    t = tvec(dur)
    n = bp(noise(dur, seed), *noise_bp) * np.exp(-t / noise_tau) * noise_gain
    tick = hp(noise(dur, seed + 1), 5000) * np.exp(-t / 0.002) * 0.35
    x = body[: len(t)] + n + tick
    if clap_gain > 0:
        x += bursts(dur, [0.0, 0.011, 0.023], 0.004, 1300, 5000,
                    [0.8, 0.9, 1.0], seed + 2, tail_tau=0.05, tail_gain=0.4) * clap_gain
    return hp(x, 150, order=1)

def make_snares():
    b = snare_body(300, 188, 0.030, 0.035, 0.85, ring_f=341, ring_g=0.22, ring_tau=0.02)
    save("snare_main.wav", finish(snare((1700, 9500), 0.028, 0.80, b, clap_gain=0.28), 0.24, -0.5))
    b = snare_body(320, 200, 0.026, 0.028, 0.85)
    save("snare_tight.wav", finish(snare((2000, 10000), 0.018, 0.75, b), 0.16, -0.5))
    b = snare_body(330, 205, 0.030, 0.032, 0.85, ring_f=368, ring_g=0.18, ring_tau=0.018)
    save("snare_bright.wav", finish(snare((2800, 12500), 0.030, 0.90, b, clap_gain=0.18), 0.22, -0.5))
    b = snare_body(430, 255, 0.025, 0.028, 0.80, ring_f=840, ring_g=0.16, ring_tau=0.05)
    save("snare_pop.wav", finish(snare((2500, 9000), 0.020, 0.55, b), 0.18, -0.7))
    b = snare_body(300, 188, 0.030, 0.032, 0.50, ring_f=341, ring_g=0.12, ring_tau=0.02)
    save("snare_ghost.wav", finish(snare((1700, 9000), 0.022, 0.40, b), 0.20, -4.0))
    dur = 0.09
    t = tvec(dur)
    n = bp(noise(dur, 29), 2400, 8500) * np.exp(-t / 0.012) * 0.9
    blip = pitch_sine_gain(260, 210, 0.02, dur, 0.012, 0.40)
    save("snare_snap.wav", finish(n + blip, dur, -0.6, fade_ms=4))
    # リムショット： 2つの短い共鳴＋クリック
    dur = 0.09
    t = tvec(dur)
    x = (np.sin(2 * np.pi * 415 * t) * np.exp(-t / 0.006) * 0.6
         + np.sin(2 * np.pi * 1720 * t) * np.exp(-t / 0.004) * 0.5
         + hp(noise(dur, 30), 3000) * np.exp(-t / 0.002) * 0.3)
    save("rimshot_pro.wav", finish(np.tanh(x * 1.4), dur, -0.8, fade_ms=4))

# ---------------------------------------------------------------- claps

def make_claps():
    dur = 0.32
    mono = bursts(dur, [0.0, 0.012, 0.024, 0.037], 0.005, 1100, 6000,
                  [0.7, 0.8, 0.9, 1.0], 31, tail_tau=0.055, tail_gain=0.55)
    save("clap_main.wav", finish(mono, dur, -0.6, fade_ms=12))
    dur = 0.38
    bl = bursts(dur, [0.0, 0.014, 0.028, 0.045], 0.005, 1100, 6500,
                [0.7, 0.85, 0.9, 1.0], 32, tail_tau=0.075, tail_gain=0.6)
    br = bursts(dur, [0.002, 0.016, 0.030, 0.047], 0.005, 1100, 6500,
                [0.7, 0.85, 0.9, 1.0], 33, tail_tau=0.075, tail_gain=0.6)
    save("clap_wide.wav", finish(np.column_stack([bl, br]), dur, -0.6, fade_ms=14))
    dur = 0.17
    mono = bursts(dur, [0.0, 0.009, 0.018], 0.004, 1200, 6000,
                  [0.85, 0.95, 1.0], 34, tail_tau=0.030, tail_gain=0.4)
    save("clap_tight.wav", finish(mono, dur, -0.6, fade_ms=8))

# ---------------------------------------------------------------- hats (808素材の加工)

def make_hats():
    closed = load_src("808_hihat_closed.wav")
    open_s = load_src("808_hihat_open_short.wav")
    open_l = load_src("808_hihat_open_long.wav")

    x = trim_env(hp(closed, 6800), 0.14, 25)
    save("hat_closed.wav", finish(x, len(x) / SR, -1.2, fade_ms=4))
    t = np.arange(len(closed)) / SR
    x = trim_env(hp(closed * np.exp(-t / 0.022), 7000), 0.07, 12)
    save("hat_closed_short.wav", finish(x, len(x) / SR, -1.2, fade_ms=3))
    x = trim_env(hp(lp(closed, 9000), 6000), 0.14, 25)
    save("hat_closed_soft.wav", finish(x, len(x) / SR, -6.0, fade_ms=4))
    x = trim_env(hp(closed * np.exp(-t / 0.016), 6000), 0.055, 10)
    x = lp(x, 8000)
    save("hat_pedal.wav", finish(x, len(x) / SR, -3.0, fade_ms=3))
    x = trim_env(hp(open_l, 6500), 1.30, 60)
    save("hat_open_long.wav", finish(x, len(x) / SR, -1.5, fade_ms=20))
    x = trim_env(hp(open_s, 6800), 0.45, 40)
    save("hat_open_short.wav", finish(x, len(x) / SR, -1.5, fade_ms=12))

# ---------------------------------------------------------------- cymbals / fx

def synth_crash(dur=2.4, seed=41):
    t = tvec(dur)
    x = np.zeros((len(t), 2))
    for ch, sd in enumerate((seed, seed + 5)):
        n = noise(dur, sd)
        y = np.zeros_like(t)
        for fc, bw, tau, g in [(4300, 2600, 0.55, 0.5), (5700, 3000, 0.75, 0.45),
                               (7600, 3600, 0.95, 0.4), (10200, 4200, 0.65, 0.3)]:
            y += bp(n, fc - bw / 2, fc + bw / 2) * np.exp(-t / tau) * g
        y += hp(n, 6000) * np.exp(-t / 0.7) * 0.35
        for f, tau, g in [(5230, 0.30, 0.05), (6890, 0.26, 0.04), (8120, 0.22, 0.035), (10900, 0.18, 0.03)]:
            y += np.sin(2 * np.pi * f * t) * np.exp(-t / tau) * g
        x[:, ch] = y
    return x

def make_cymbals():
    cym = load_src("808_cymbal.wav")
    x = trim_env(hp(cym, 5500), 1.90, 120)
    st = np.column_stack([x, np.roll(x, 17) * 0.92 + hp(x, 9000) * 0.08])
    save("808_cymbal_pro.wav", finish(st, len(x) / SR, -1.2, fade_ms=30))

    crash = synth_crash()
    base = trim_env(hp(cym, 5500), 2.4, 120)
    crash[: len(base), 0] += base * 0.55
    crash[: len(base), 1] += base * 0.55
    save("crash_pro.wav", finish(crash, 2.4, -0.7, fade_ms=40))
    return crash

def make_reverse_and_impact(crash):
    bar = 60.0 / 155.0 * 4  # 155 BPM の1小節
    rev = crash[::-1].copy()
    n = int(round(bar * SR))
    if len(rev) > n:
        rev = rev[:n]
    tt = np.arange(len(rev)) / len(rev)
    swell = (np.sin(tt * np.pi / 2) ** 1.5)[:, None]
    rev = rev * swell
    save("cymbal_reverse.wav", finish(rev, bar, -0.8, fade_ms=1.0))

    dur = 1.30
    t = tvec(dur)
    imp = crash[: len(t)] * np.exp(-t / 0.5)[:, None] * 0.7
    kick = pitch_sine_gain(130, 46, 0.06, dur, 0.12, 0.9)
    drop = pitch_sine_gain(95, 30, 0.35, dur, 0.30, 0.8)
    nb = hp(noise(dur, 51), 3000) * np.exp(-t / 0.05) * 0.4
    mono = kick + drop + nb
    imp[:, 0] += mono
    imp[:, 1] += mono
    save("impact_pro.wav", finish(imp, dur, -0.3, fade_ms=20))

def gliss_saw(f0, f1, dur, harmonics=18):
    t = tvec(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        x += np.sin(phase * k) / k
    return x, f

def make_risers():
    bar = 60.0 / 155.0 * 4
    for name, dur in [("riser_long.wav", bar * 4), ("riser_short.wav", bar * 2)]:
        t = tvec(dur)
        u = t / dur
        saw, f = gliss_saw(146.83, 587.33, dur)
        saw = lp(saw, 5200) * (0.25 + 0.35 * u)
        fc = 350 * (9500 / 350) ** u
        # 帯域中心を時間変化させる簡易スイープ：チャープに追従する帯域ノイズの近似として
        # ノイズを複数バンドに割り、重みをスイープさせる
        nz = np.zeros_like(t)
        bands = [(300, 900), (800, 2000), (1800, 4200), (3800, 8000), (7000, 14000)]
        src = noise(dur, 61)
        for i, (lo, hi) in enumerate(bands):
            center = (np.log(lo) + np.log(hi)) / 2
            w = np.exp(-((np.log(350 * (9500 / 350) ** u) - center) ** 2) / (2 * 0.55 ** 2))
            nz += bp(src, lo, hi) * w
        nz *= (0.15 + 0.85 * u) * 0.8
        trem = 1 - 0.25 * u * (0.5 + 0.5 * np.sin(2 * np.pi * (4 + 7 * u) * t))
        x = (saw * trem + nz)
        save(name, finish(stereo(x), dur, -3.5, fade_ms=30))
    dur = bar * 2
    t = tvec(dur)
    u = t / dur
    saw, f = gliss_saw(587.33, 146.83, dur)
    saw = lp(saw, 5200) * 0.35 * (1 - 0.6 * u)
    nz = np.zeros_like(t)
    bands = [(300, 900), (800, 2000), (1800, 4200), (3800, 8000), (7000, 14000)]
    src = noise(dur, 63)
    for lo, hi in bands:
        center = (np.log(lo) + np.log(hi)) / 2
        w = np.exp(-((np.log(9500 * (280 / 9500) ** u) - center) ** 2) / (2 * 0.55 ** 2))
        nz += bp(src, lo, hi) * w
    nz *= (1 - 0.7 * u) * 0.7
    x = (saw + nz) * exp_env(t, dur * 0.9)
    save("downlifter.wav", finish(stereo(x), dur, -3.5, fade_ms=60))

# ---------------------------------------------------------------- toms (808素材＋正弦補強)

def make_toms():
    for src_name, out_name, dur in [("808_tom_low.wav", "tom_low.wav", 0.50),
                                    ("808_tom_mid.wav", "tom_mid.wav", 0.45),
                                    ("808_tom_high.wav", "tom_high.wav", 0.40)]:
        x = load_src(src_name)
        # 主成分の周波数を推定して正弦で補強
        spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
        freqs = np.fft.rfftfreq(len(x), 1 / SR)
        f0 = freqs[20 + np.argmax(spec[20:200])]
        t = np.arange(len(x)) / SR
        rein = np.sin(2 * np.pi * f0 * t) * np.exp(-t / 0.11) * 0.32
        y = trim_env(x + rein, dur, 40)
        save(out_name, finish(y, len(y) / SR, -0.9, fade_ms=15))

# ---------------------------------------------------------------- perc（控えめに移植）

def make_perc():
    ports = [("808_cowbell.wav", "cowbell.wav", -6.0, 0.35),
             ("perc_finger_cymbal.wav", "finger_cymbal.wav", -8.0, 1.2),
             ("perc_bubble.wav", "bubble.wav", -8.0, 0.3),
             ("perc_water_drop.wav", "water_drop.wav", -8.0, 0.5),
             ("perc_sparkle_chime.wav", "sparkle_chime.wav", -9.0, 1.0),
             ("808_maracas.wav", "maracas.wav", -9.0, 0.3),
             ("808_claves.wav", "claves.wav", -7.0, 0.2),
             ("shaker_bright.wav", "shaker.wav", -8.0, 0.4)]
    for src_name, out_name, peak_db, max_dur in ports:
        x = load_src(src_name)
        if src_name == "shaker_bright.wav":
            x = lp(x, 7500)
        x = trim_env(x, min(len(x) / SR, max_dur), 25)
        save(out_name, finish(x, len(x) / SR, peak_db, fade_ms=10))
    dur = 1.0
    x = pitch_sine_gain(110, 73.42, 0.10, dur, 0.35, 0.95)
    x += pitch_sine_gain(220, 146.84, 0.10, dur, 0.22, 0.10)
    save("bass_808_d.wav", finish(x, dur, -1.2, fade_ms=20))

# ---------------------------------------------------------------- main

if __name__ == "__main__":
    save("kick_main.wav", kick_main())
    save("kick_punch.wav", kick_punch())
    save("kick_subdeep.wav", kick_subdeep())
    save("kick_soft.wav", kick_soft())
    save("sub_tail.wav", sub_tail())
    make_snares()
    make_claps()
    make_hats()
    crash = make_cymbals()
    make_reverse_and_impact(crash)
    make_risers()
    make_toms()
    make_perc()
    print("done ->", OUT)
