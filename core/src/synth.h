#pragma once

#include <array>
#include <cstdint>

#include <juce_audio_basics/juce_audio_basics.h>

namespace mdaw {

// シンセの音色。保存・読み込み・範囲の丸めは kSynthParamSpecs の表で一括して扱う
struct SynthParams {
    float cutoffHz = 6000.0f;
    float resonance = 0.9f;
    float attackS = 0.005f;
    float decayS = 0.25f;
    float sustain = 0.7f;
    float releaseS = 0.3f;
    float detuneCents = 7.0f;
    float masterGain = 0.6f;
    float unison = 2.0f;
    float width = 0.5f;
    float blend = 0.8f;
    float sub = 0.0f;
    float noise = 0.0f;
    float drive = 0.0f;
    float filterEnv = 0.0f;
    float filterEnvDecayS = 0.3f;
    float pitchEnv = 0.0f;
    float pitchEnvDecayS = 0.05f;
    float wave = 0.0f;
    float osc = 1.0f;
    float wtTable = 0.0f;     // 0 = 従来オシレーター（旧プロジェクトの音は不変）
    float wtPos = 0.0f;       // ウェーブテーブルのフレーム位置 0〜1
    float wtWarp = 0.0f;      // 位相ワープ 0=なし、1=bend、2=squeeze、3=sync
    float wtWarpAmount = 0.0f;
};

struct ParamSpec {
    int id;
    const char* key; // 保存ファイルでの名前
    float min, max;
    bool integer;
};

struct SynthParamSpec : ParamSpec {
    float SynthParams::*member;
};

extern const SynthParamSpec kSynthParamSpecs[];
extern const int kNumSynthParamSpecs;

bool operator==(const SynthParams& a, const SynthParams& b) noexcept;
inline bool operator!=(const SynthParams& a, const SynthParams& b) noexcept { return !(a == b); }

// SynthParams を mdaw.h の MDAW_PARAM_* で読み書きする（範囲外の値は丸める）
bool getSynthParam(const SynthParams& s, int paramId, float& out) noexcept;
bool setSynthParam(SynthParams& s, int paramId, float value) noexcept;

// 2次の状態変数フィルター（TPT）。係数は呼ぶ側が間引いて更新する
struct Svf {
    float g = 0.0f, k = 1.0f, a1 = 0.0f, a2 = 0.0f, a3 = 0.0f;
    float ic1 = 0.0f, ic2 = 0.0f;
    void set(float cutoffHz, float q, double sampleRate) noexcept;
    void reset() noexcept { ic1 = ic2 = 0.0f; }
    // 戻り値はローパス。high を渡すとハイパスも返す
    float process(float x, float* high = nullptr) noexcept {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        if (high != nullptr)
            *high = x - k * v1 - v2;
        return v2;
    }
};

class Voice {
public:
    static constexpr int kMaxUnison = 16;

    void prepare(double sampleRate);
    void start(int note, float velocity, const SynthParams& params, uint64_t age, uint32_t seed);
    void release() noexcept;
    void kill() noexcept;
    void applyParams(const SynthParams& params) noexcept;
    void setCutoff(float hz) noexcept { cutoffHz_ = hz; }
    // 自分の音を left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;

    bool isActive() const noexcept { return adsr_.isActive(); }
    bool isHeld() const noexcept { return held_; }
    int note() const noexcept { return note_; }
    uint64_t age() const noexcept { return age_; }

private:
    void layoutUnison() noexcept;
    void updateIncrements(float pitchOffsetSemis) noexcept;

    double sampleRate_ = 48000.0;
    SynthParams p_;
    juce::ADSR adsr_;
    Svf filterL_, filterR_;

    int unison_ = 1;
    float phase_[kMaxUnison] = {};
    float inc_[kMaxUnison] = {};
    float detune_[kMaxUnison] = {}; // 半音
    float gainL_[kMaxUnison] = {};
    float gainR_[kMaxUnison] = {};
    float subPhase_ = 0.0f, subInc_ = 0.0f;
    uint32_t noise_ = 1;

    float cutoffHz_ = 6000.0f;
    float wtPos_ = 0.0f; // 平滑化した WT_POS（control block 単位で追従）
    float filterEnv_ = 0.0f, filterEnvCoef_ = 0.0f;
    float pitchEnv_ = 0.0f, pitchEnvCoef_ = 0.0f;
    float gain_ = 0.0f;
    int note_ = -1;
    bool held_ = false;
    uint64_t age_ = 0;
};

// 8ボイスのポリフォニックシンセ（ステレオ・ユニゾン最大16本）。音声スレッド専用。
class Synth {
public:
    static constexpr int kNumVoices = 8;

    void prepare(double sampleRate, int maxBlock);
    void noteOn(int note, float velocity) noexcept;
    void noteOff(int note) noexcept;
    void allNotesOff() noexcept;
    void setParam(int id, float value) noexcept;
    void setParams(const SynthParams& params) noexcept;
    // left/right を上書きする
    void render(float* left, float* right, int numSamples) noexcept;

    int activeVoices() const noexcept;
    const SynthParams& params() const noexcept { return params_; }

private:
    Voice* findVoiceFor(int note) noexcept;

    std::array<Voice, kNumVoices> voices_;
    SynthParams params_;
    float smoothedCutoff_ = 6000.0f;
    float smoothedGain_ = 0.6f;
    double sampleRate_ = 48000.0;
    uint64_t ageCounter_ = 0;
    uint32_t seed_ = 0x9E3779B9u;
};

} // namespace mdaw
