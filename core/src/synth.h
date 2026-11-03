#pragma once

#include <array>
#include <cstdint>

#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_dsp/juce_dsp.h>

namespace mdaw {

struct SynthParams {
    float cutoffHz = 6000.0f;
    float resonance = 0.9f;
    float attackS = 0.005f;
    float decayS = 0.25f;
    float sustain = 0.7f;
    float releaseS = 0.3f;
    float detuneCents = 7.0f;
    float masterGain = 0.6f;
};

// SynthParams を mdaw.h の MDAW_PARAM_* で読み書きする（範囲外の値は丸める）
bool getSynthParam(const SynthParams& s, int paramId, float& out) noexcept;
bool setSynthParam(SynthParams& s, int paramId, float value) noexcept;

// 帯域制限付きのノコギリ波（PolyBLEP）。
class PolyBlepSaw {
public:
    void setFrequency(double hz, double sampleRate) noexcept { inc_ = hz / sampleRate; }
    void reset(double phase = 0.0) noexcept { phase_ = phase; }
    float next() noexcept;

private:
    double phase_ = 0.0;
    double inc_ = 0.0;
};

class Voice {
public:
    void prepare(double sampleRate, int maxBlock);
    void start(int note, float velocity, const SynthParams& params, uint64_t age);
    void release() noexcept;
    void kill() noexcept;
    void applyParams(const SynthParams& params) noexcept;
    void setCutoff(float hz) noexcept;
    // 自分の音を out に足し込む。
    void render(float* out, int numSamples) noexcept;

    bool isActive() const noexcept { return adsr_.isActive(); }
    bool isHeld() const noexcept { return held_; }
    int note() const noexcept { return note_; }
    uint64_t age() const noexcept { return age_; }

private:
    void updateFrequencies() noexcept;

    double sampleRate_ = 48000.0;
    PolyBlepSaw oscA_, oscB_;
    juce::ADSR adsr_;
    juce::dsp::StateVariableTPTFilter<float> filter_;
    float detuneCents_ = 0.0f;
    float gain_ = 0.0f;
    int note_ = -1;
    bool held_ = false;
    uint64_t age_ = 0;
};

// 8ボイスのポリフォニックシンセ（M1用の最小構成）。音声スレッド専用。
class Synth {
public:
    static constexpr int kNumVoices = 8;

    void prepare(double sampleRate, int maxBlock);
    void noteOn(int note, float velocity) noexcept;
    void noteOff(int note) noexcept;
    void allNotesOff() noexcept;
    void setParam(int id, float value) noexcept;
    void setParams(const SynthParams& params) noexcept;
    void render(float* mono, int numSamples) noexcept;

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
};

} // namespace mdaw
