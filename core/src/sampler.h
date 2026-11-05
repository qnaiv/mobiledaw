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

// メロディックサンプラー（4つ目の楽器）：キットの音を1つ借り、鍵盤の音程で鳴らす。
// ピッチは再生速度比（線形補間は DrumSampler と同じ）。ループはせず、
// ノートオフではリリース（既定 60ms）で減衰し、素材が終われば自然に消える。
// 音声スレッド専用。確保・ロックなし。
class MelodicSampler {
public:
    static constexpr int kVoices = 16;
    static constexpr double kReleaseSeconds = 0.06; // ノートオフから消えるまで
    static constexpr double kRetriggerSeconds = 0.005; // 同じ音の連打で前の音を落とす速さ

    void prepare(double sampleRate) noexcept { sampleRate_ = sampleRate; }
    // 素材や設定が変わったら、鳴っている音はすぐ止める（古い素材を読み続けないため）
    void setSound(const KitSound* sound, int rootNote, float gain, float start) noexcept;
    const KitSound* sound() const noexcept { return sound_; }
    int rootNote() const noexcept { return rootNote_; }
    void noteOn(int note, float velocity) noexcept;
    void noteOff(int note) noexcept;
    void stopAll() noexcept; // すぐ（5ms で）消す
    // left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;
    int activeVoices() const noexcept;

    // note を鳴らしたときの再生速度比（素材のサンプルレート換算込み）。テスト用
    double incrementFor(int note) const noexcept;

private:
    struct Voice {
        int note = -1;
        double pos = 0.0;
        double inc = 1.0;
        float gain = 0.0f;
        float fade = 1.0f;     // 1 = 普通に鳴っている
        float fadeStep = 0.0f; // 消すときに毎サンプル引く量（リリース／連打／全停止）
        uint64_t age = 0;
        bool active() const noexcept { return note >= 0; }
    };

    Voice* allocate(int note) noexcept;
    float fadeStepFor(double seconds) const noexcept;

    double sampleRate_ = 48000.0;
    const KitSound* sound_ = nullptr;
    int rootNote_ = 60;
    float gain_ = 1.0f;
    float start_ = 0.0f;
    std::array<Voice, kVoices> voices_{};
    uint64_t ageCounter_ = 0;
};

} // namespace mdaw
