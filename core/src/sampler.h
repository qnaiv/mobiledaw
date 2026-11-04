#pragma once

// ドラムキットを鳴らす（ワンショット）。ノートオフでは止まらず、最後まで鳴る。
// チョーク（同じ番号の音どうしで止め合う）はハイハットの開閉用。音声スレッド専用。

#include <array>
#include <cstdint>

#include "kit.h"

namespace mdaw {

class DrumSampler {
public:
    static constexpr int kVoices = 24;

    void prepare(double sampleRate) noexcept { sampleRate_ = sampleRate; }
    // キットが変わったら、鳴っている音はすぐ止める（古いキットの音を読み続けないため）
    void setKit(const Kit* kit) noexcept;
    const Kit* kit() const noexcept { return kit_; }
    void noteOn(int note, float velocity) noexcept;
    void stopAll() noexcept; // すぐ（5ms で）消す
    // left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;
    int activeVoices() const noexcept;

private:
    struct Voice {
        const KitSound* sound = nullptr;
        double pos = 0.0;
        double inc = 1.0;
        float gain = 0.0f;
        float fade = 1.0f;     // 1 = 普通に鳴っている
        float fadeStep = 0.0f; // 止めるときに毎サンプル引く量
        uint64_t age = 0;
        bool active() const noexcept { return sound != nullptr; }
    };

    void choke(int group) noexcept;

    double sampleRate_ = 48000.0;
    const Kit* kit_ = nullptr;
    std::array<Voice, kVoices> voices_{};
    uint64_t ageCounter_ = 0;
};

} // namespace mdaw
