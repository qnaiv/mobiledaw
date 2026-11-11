"""フォルマント表（core/src/wavetable.cpp の table 3）の母音位置を、音程ごとに補正して選ぶ。
表のフォルマントは倍音番号で決まる（音程が上がると一緒に上がる）ので、
実際の日本語の母音フォルマント（Hz）に一番近くなる WT_POS を音程ごとに探す。"""
import math
KF = [(7, 11, 26), (5, 19, 26), (3, 23, 30), (5, 9, 26), (3, 7, 24)]  # A E I O U（倍音番号）
# 日本語の母音（やや高めの声）F1, F2, F3 [Hz]
TARGET = {"a": (800, 1250, 2700), "i": (320, 2400, 3100), "u": (360, 1350, 2500),
          "e": (520, 1950, 2700), "o": (520, 880, 2600)}
W = (1.0, 1.0, 0.3)

def table_formants(pos):
    x = pos * 4.0
    seg = min(int(x), 3)
    f = x - seg
    return [KF[seg][i] * (1 - f) + KF[seg + 1][i] * f for i in range(3)]

def best_pos(vowel, pitch):
    f0 = 440.0 * 2 ** ((pitch - 69) / 12)
    tgt = TARGET[vowel]
    best = None
    for k in range(201):
        pos = k / 200
        fm = table_formants(pos)
        err = sum(W[i] * (math.log2(fm[i] * f0 / tgt[i])) ** 2 for i in range(3))
        if best is None or err < best[0]:
            best = (err, pos)
    return round(best[1], 3), best[0]

if __name__ == "__main__":
    for p in (43, 48, 52, 55, 57, 60, 64):
        print(p, {v: best_pos(v, p) for v in "aiueo"})
