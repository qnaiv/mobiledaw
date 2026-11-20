#pragma once

// グラニュラーの心臓部（粒の窓・発生乱数・正規化・オールパス拡散の素）を
// FX グラニュラー（fx.cpp）とグラニュラー楽器（sampler.cpp）で共有するための
// 小さなヘッダ。数式は fx.cpp の Phase 2 実装からそのまま切り出したもので、
// ここを変えると両方の音が変わる（FX 側はビット一致テストで担保する）。
// 音声スレッドで使うものだけを置く（確保・ロックなし）。

#include <cmath>
#include <cstdint>

namespace mdaw {

// 粒 1 個の再生状態（FX の TrackFx::Grain と同じ意味）。
// pos は読み位置（バッファ／素材の絶対位置。使う側が剰余やクランプで解釈する）。
struct GrainSlot {
    double pos = 0.0;   // 読み位置（絶対）
    double rate = 1.0;  // 再生レート（ピッチで決まる。負なら逆再生）
    float phase = 0.0f; // 包絡の進み 0〜1
    float step = 0.0f;  // 1 サンプルで進む包絡量（1 / 粒の長さ）
    float panL = 0.7071f, panR = 0.7071f;
    bool active = false;
};

// 決定的な xorshift（0〜1）。レンダーを再現可能に保つため種は呼び出し側が管理する。
inline float grainRandNext(std::uint32_t& state) noexcept {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return static_cast<float>(state >> 8) * (1.0f / 16777216.0f); // 0〜1
}

// 粒の包絡: texture の前半（windowShape 0〜0.5）は「立った台形 → 三角」、
// 後半（0.5〜1）は「三角 → Hann ベル」へ連続に変わる（Clouds の窓モーフ）。
inline float grainWindow(float phase, float windowShape) noexcept {
    if (windowShape < 0.5f) {
        const float a = 0.02f + (0.5f - 0.02f) * (windowShape * 2.0f); // 立ち上がりの割合
        return std::min(1.0f, std::min(phase, 1.0f - phase) / a);
    }
    const float tri = 1.0f - std::abs(2.0f * phase - 1.0f);
    const float sn = std::sin(3.14159265f * phase);
    const float t = (windowShape - 0.5f) * 2.0f;
    return tri + (sn * sn - tri) * t;
}

// 包絡の平均パワー（矩形寄り→三角→ベルの順に変わる）。ゲイン補償 envComp の元。
inline float grainWindowAvgPower(float windowShape) noexcept {
    return windowShape < 0.5f ? 0.97f + (0.333f - 0.97f) * (windowShape * 2.0f)
                              : 0.333f + (0.375f - 0.333f) * ((windowShape - 0.5f) * 2.0f);
}

// 実効粒数ベースの正規化（Clouds 式 1/√(n−1)。n が小さいときは 1）
inline float grainNormTarget(int activeCount) noexcept {
    return activeCount > 2 ? 1.0f / std::sqrt(static_cast<float>(activeCount - 1)) : 1.0f;
}

// オールパス 1 段（Schroeder 型。buf には v[n] = x[n] + g・v[n-D] を貯め、
// y[n] = v[n-D] − g・v[n] を返す）。fx.cpp の allpassProcess と同じ式。
inline float grainAllpassProcess(float* buf, int size, int& pos, float x, float g) noexcept {
    const float delayed = buf[static_cast<size_t>(pos)];
    const float v = x + g * delayed;
    buf[static_cast<size_t>(pos)] = v;
    pos = (pos + 1) % size;
    return delayed - g * v;
}

// ディフューザーの遅延（Clouds の 32k 値を 48k 換算した解析レポート §2.3 の値）。
// 使う側がサンプルレート比で拡縮する。
inline constexpr int kGrainDiffuserDelaysL[4] = {189, 270, 404, 666};
inline constexpr int kGrainDiffuserDelaysR[4] = {227, 308, 368, 608};

} // namespace mdaw
