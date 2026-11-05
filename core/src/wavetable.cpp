#include "wavetable.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>

namespace mdaw {

namespace {

constexpr float kTwoPi = 6.28318530718f;
constexpr int kMaxHarm = 128;

// [table][band][frame][sample]
float gTables[wavetable::kTables][wavetable::kBands][wavetable::kFrames][wavetable::kFrameSize];
std::atomic<bool> gReady{false};

int bandMaxHarm(int band) noexcept { return kMaxHarm >> band; }

// テーブルごとの倍音プロファイル。frame は 0〜1（WT_POS の位置）、h は倍音番号（1〜）
// 戻り値はその倍音の大きさ。phase には位相（0〜1、1周=1）も返す
float harmonicAmp(int table, float frame, int h, float& phase) noexcept {
    phase = 0.0f;
    const float hf = static_cast<float>(h);
    switch (table) {
        case 1: { // Basic Shapes：サイン → 三角 → 矩形 → のこぎり を frame でモーフ
            float sine = 0.0f, tri = 0.0f, square = 0.0f, saw = 0.0f;
            if (h == 1)
                sine = 1.0f;
            if (h % 2 == 1) {
                tri = ((h / 2) % 2 == 0 ? 1.0f : -1.0f) * 0.81f / (hf * hf);
                square = 1.27f / hf;
            }
            saw = 0.64f / hf;
            // frame を3区間に分けてクロスフェード
            const float x = frame * 3.0f;
            const int seg = std::min(static_cast<int>(x), 2);
            const float f = x - static_cast<float>(seg);
            const float shapes[4] = {sine, tri, square, saw};
            return shapes[seg] * (1.0f - f) + shapes[seg + 1] * f;
        }
        case 2: { // Harmonic：倍音の山が frame で高い方へ移動する（スペクトルの掃引）
            const float center = 1.0f + frame * 24.0f;
            const float d = (hf - center) / 6.0f;
            float a = std::exp(-d * d) * 0.9f;
            if (h == 1)
                a += 0.8f; // 基音は常に残す
            a += 0.12f / hf; // 薄い土台
            return a;
        }
        case 3: { // Formant：母音 A→E→I→O→U のフォルマント（倍音番号で近似）を frame でモーフ
            // 母音ごとのフォルマント中心（倍音番号）。基音 ≒110Hz のときの目安
            static constexpr float kFormants[5][3] = {
                {7.0f, 11.0f, 26.0f}, // A
                {5.0f, 19.0f, 26.0f}, // E
                {3.0f, 23.0f, 30.0f}, // I
                {5.0f, 9.0f, 26.0f},  // O
                {3.0f, 7.0f, 24.0f},  // U
            };
            const float x = frame * 4.0f;
            const int seg = std::min(static_cast<int>(x), 3);
            const float f = x - static_cast<float>(seg);
            float a = 0.15f / hf; // 薄い土台
            for (int i = 0; i < 3; ++i) {
                const float c = kFormants[seg][i] * (1.0f - f) + kFormants[seg + 1][i] * f;
                const float d = (hf - c) / (i == 0 ? 2.5f : 4.0f);
                a += std::exp(-d * d) * (i == 0 ? 1.0f : 0.55f);
            }
            return a;
        }
        case 4: { // Digital：倍音のオン／オフが frame で増える荒い波形。位相はハッシュでばらす
            uint32_t hash = static_cast<uint32_t>(h) * 2654435761u;
            hash ^= hash >> 13;
            const float r = static_cast<float>(hash & 0xffff) / 65536.0f; // 0〜1
            phase = static_cast<float>((hash >> 16) & 0xffff) / 65536.0f;
            if (h == 1)
                return 0.9f;
            const float density = 0.15f + frame * 0.6f;
            return r < density ? 0.8f / hf : 0.0f;
        }
        case 5: { // Spectral Saw：太いソー系。frame でスペクトルの傾き（暗い→明るい）が変わる
            // 高次倍音を frame 依存の肩で落とす。frame=0 は太く暗く、frame=1 は素のソー近くまで開く
            const float shoulder = 3.0f + frame * 61.0f; // 肩の倍音番号 3〜64
            const float d = hf / shoulder;
            float a = 0.85f / hf / (1.0f + d * d);
            if (h == 1)
                a += 0.35f; // 基音を厚く
            return a;
        }
        case 6: { // Pulse Morph：パルス幅（デューティ比）が frame で 0.5→0.08 に細くなる
            // 矩形パルスの係数 sin(π・h・d)/h。符号の反転もそのまま使う（位相 0 の実係数）
            const float duty = 0.5f - frame * 0.42f;
            return 1.3f * std::sin(3.14159265f * hf * duty) / hf;
        }
        case 7: { // Choir：声の合唱っぽい倍音。ゆるいフォルマントの山＋倍音ごとの小さなばらつき
            uint32_t hash = static_cast<uint32_t>(h) * 2654435761u;
            hash ^= hash >> 13;
            const float jr = static_cast<float>(hash & 0xffff) / 65536.0f;       // 振幅のばらつき用
            phase = static_cast<float>((hash >> 16) & 0xffff) / 65536.0f * 0.5f; // 位相も少しばらす
            // frame で山全体が上がる（暗い「ウー」→ 明るい「アー」）
            const float shift = 0.75f + frame * 0.8f;
            float a = 0.2f / hf; // 薄い土台
            const float centers[3] = {4.0f, 9.0f, 20.0f};
            const float widths[3] = {2.2f, 4.5f, 8.0f};
            const float heights[3] = {1.0f, 0.6f, 0.35f};
            for (int i = 0; i < 3; ++i) {
                const float d = (hf - centers[i] * shift) / widths[i];
                a += std::exp(-d * d) * heights[i];
            }
            return a * (0.85f + 0.3f * jr); // 合唱の「人数感」
        }
        default:
            return 0.0f;
    }
}

// 1フレームを加算合成で作る（複素フェーザの回転で sin を毎回計算しない）
void buildFrame(int table, int band, int frame, float scale, float* out) noexcept {
    const int maxH = bandMaxHarm(band);
    const float t = wavetable::kFrames > 1
                        ? static_cast<float>(frame) / static_cast<float>(wavetable::kFrames - 1)
                        : 0.0f;
    // 倍音ごとのフェーザ（現在値と1サンプル分の回転）
    float re[kMaxHarm + 1], im[kMaxHarm + 1], cre[kMaxHarm + 1], cim[kMaxHarm + 1], amp[kMaxHarm + 1];
    for (int h = 1; h <= maxH; ++h) {
        float ph = 0.0f;
        amp[h] = harmonicAmp(table, t, h, ph);
        const float a0 = ph * kTwoPi;
        re[h] = std::cos(a0);
        im[h] = std::sin(a0);
        const float step = kTwoPi * static_cast<float>(h) / static_cast<float>(wavetable::kFrameSize);
        cre[h] = std::cos(step);
        cim[h] = std::sin(step);
    }
    for (int i = 0; i < wavetable::kFrameSize; ++i) {
        float v = 0.0f;
        for (int h = 1; h <= maxH; ++h) {
            v += amp[h] * im[h];
            const float nr = re[h] * cre[h] - im[h] * cim[h];
            im[h] = re[h] * cim[h] + im[h] * cre[h];
            re[h] = nr;
        }
        out[i] = v * scale;
        if ((i & 255) == 255) { // フェーザの大きさのずれを正す（1024サンプルで4回）
            for (int h = 1; h <= maxH; ++h) {
                const float m = std::sqrt(re[h] * re[h] + im[h] * im[h]);
                if (m > 1e-9f) {
                    re[h] /= m;
                    im[h] /= m;
                }
            }
        }
    }
}

float framePeak(int table, int frame) noexcept {
    float tmp[wavetable::kFrameSize];
    buildFrame(table, 0, frame, 1.0f, tmp);
    float peak = 0.0f;
    for (const float v : tmp)
        peak = std::max(peak, std::abs(v));
    return peak;
}

} // namespace

namespace wavetable {

void buildWavetables() {
    if (gReady.load(std::memory_order_acquire))
        return;
    for (int table = 1; table <= kTables; ++table) {
        for (int frame = 0; frame < kFrames; ++frame) {
            // バンド間で音量が変わらないよう、一番倍音の多いバンドのピークでそろえる
            const float peak = framePeak(table, frame);
            const float scale = peak > 1e-6f ? 0.85f / peak : 0.0f;
            for (int band = 0; band < kBands; ++band)
                buildFrame(table, band, frame, scale, gTables[table - 1][band][frame]);
        }
    }
    gReady.store(true, std::memory_order_release);
}

bool wavetablesReady() noexcept { return gReady.load(std::memory_order_acquire); }

float sampleWavetable(int table, float pos, float phase, float phaseInc) noexcept {
    if (!gReady.load(std::memory_order_acquire) || table < 1 || table > kTables)
        return 0.0f;
    // 倍音がナイキストを超えない一番倍音の多いバンドを選ぶ
    const float harmLimit = phaseInc > 1e-6f ? 0.5f / phaseInc : static_cast<float>(kMaxHarm);
    int band = 0;
    while (band < kBands - 1 && static_cast<float>(bandMaxHarm(band)) > harmLimit)
        ++band;

    const float framePos = std::clamp(pos, 0.0f, 1.0f) * static_cast<float>(kFrames - 1);
    const int f0 = std::min(static_cast<int>(framePos), kFrames - 2);
    const float fFrac = framePos - static_cast<float>(f0);

    const float x = phase * static_cast<float>(kFrameSize);
    const int i0 = std::min(static_cast<int>(x), kFrameSize - 1);
    const int i1 = (i0 + 1) % kFrameSize;
    const float iFrac = x - static_cast<float>(i0);

    const auto& tab = gTables[table - 1][band];
    const float a = tab[f0][i0] * (1.0f - iFrac) + tab[f0][i1] * iFrac;
    const float b = tab[f0 + 1][i0] * (1.0f - iFrac) + tab[f0 + 1][i1] * iFrac;
    return a * (1.0f - fFrac) + b * fFrac;
}

} // namespace wavetable

float warpPhase(float phase, int warp, float amount) noexcept {
    const float a = std::clamp(amount, 0.0f, 1.0f);
    float p = phase;
    switch (warp) {
        case 1: // bend：位相を正弦で曲げる（単調になる範囲に抑える）
            p = phase + 0.159f * a * std::sin(kTwoPi * phase);
            break;
        case 2: { // squeeze：位相の前半を圧縮／拡大する（PWM 的）
            const float k = 0.5f - 0.4f * a;
            p = phase < k ? 0.5f * phase / k : 0.5f + 0.5f * (phase - k) / (1.0f - k);
            break;
        }
        case 3: // sync：位相を最大4倍で回す
            p = phase * (1.0f + a * 3.0f);
            break;
        default:
            return phase;
    }
    p -= std::floor(p);
    return p;
}

} // namespace mdaw
