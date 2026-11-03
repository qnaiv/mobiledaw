#include "synth.h"

#include <algorithm>
#include <cmath>

#include "mdaw.h"

namespace mdaw {

namespace {

float polyBlep(double t, double dt) noexcept {
    if (t < dt) {
        t /= dt;
        return static_cast<float>(t + t - t * t - 1.0);
    }
    if (t > 1.0 - dt) {
        t = (t - 1.0) / dt;
        return static_cast<float>(t * t + t + t + 1.0);
    }
    return 0.0f;
}

double noteToHz(int note) noexcept {
    return 440.0 * std::pow(2.0, (note - 69) / 12.0);
}

float clampCutoff(float hz, double sampleRate) noexcept {
    return std::clamp(hz, 20.0f, static_cast<float>(sampleRate * 0.45));
}

juce::ADSR::Parameters toAdsr(const SynthParams& p) noexcept {
    return {std::max(p.attackS, 0.0005f), std::max(p.decayS, 0.0005f),
            std::clamp(p.sustain, 0.0f, 1.0f), std::max(p.releaseS, 0.002f)};
}

} // namespace

float PolyBlepSaw::next() noexcept {
    const auto t = phase_;
    float v = static_cast<float>(2.0 * t - 1.0);
    v -= polyBlep(t, inc_);
    phase_ += inc_;
    if (phase_ >= 1.0)
        phase_ -= 1.0;
    return v;
}

//==============================================================================
void Voice::prepare(double sampleRate, int maxBlock) {
    sampleRate_ = sampleRate;
    adsr_.setSampleRate(sampleRate);
    filter_.setType(juce::dsp::StateVariableTPTFilterType::lowpass);
    filter_.prepare({sampleRate, static_cast<juce::uint32>(std::max(maxBlock, 1)), 1});
    adsr_.reset();
    held_ = false;
    note_ = -1;
}

void Voice::start(int note, float velocity, const SynthParams& params, uint64_t age) {
    const bool wasActive = isActive();
    note_ = note;
    held_ = true;
    age_ = age;
    gain_ = std::pow(std::clamp(velocity, 0.0f, 1.0f), 1.5f) * 0.25f;
    applyParams(params);
    if (!wasActive) {
        oscA_.reset(0.0);
        oscB_.reset(0.37);
        filter_.reset();
    }
    adsr_.noteOn();
}

void Voice::release() noexcept {
    held_ = false;
    adsr_.noteOff();
}

void Voice::kill() noexcept {
    held_ = false;
    adsr_.reset();
}

void Voice::applyParams(const SynthParams& params) noexcept {
    adsr_.setParameters(toAdsr(params));
    filter_.setResonance(std::clamp(params.resonance, 0.5f, 10.0f));
    detuneCents_ = params.detuneCents;
    updateFrequencies();
}

void Voice::setCutoff(float hz) noexcept {
    filter_.setCutoffFrequency(clampCutoff(hz, sampleRate_));
}

void Voice::updateFrequencies() noexcept {
    if (note_ < 0)
        return;
    const double base = noteToHz(note_);
    oscA_.setFrequency(base, sampleRate_);
    oscB_.setFrequency(base * std::pow(2.0, detuneCents_ / 1200.0), sampleRate_);
}

void Voice::render(float* out, int numSamples) noexcept {
    if (!isActive())
        return;
    for (int i = 0; i < numSamples; ++i) {
        const float osc = 0.5f * (oscA_.next() + oscB_.next());
        const float filtered = filter_.processSample(0, osc);
        out[i] += filtered * adsr_.getNextSample() * gain_;
    }
    if (!isActive()) {
        held_ = false;
        note_ = -1;
    }
}

//==============================================================================
void Synth::prepare(double sampleRate, int maxBlock) {
    sampleRate_ = sampleRate;
    for (auto& v : voices_) {
        v.prepare(sampleRate, maxBlock);
        v.applyParams(params_);
        v.setCutoff(params_.cutoffHz);
    }
    smoothedCutoff_ = params_.cutoffHz;
    smoothedGain_ = params_.masterGain;
}

Voice* Synth::findVoiceFor(int note) noexcept {
    // 同じ音が鳴っていれば鳴らし直す
    for (auto& v : voices_)
        if (v.isActive() && v.note() == note)
            return &v;
    for (auto& v : voices_)
        if (!v.isActive())
            return &v;
    // 空きがなければ、離された音の中で一番古いもの → 全体で一番古いものを奪う
    Voice* oldest = nullptr;
    for (auto& v : voices_)
        if (!v.isHeld() && (oldest == nullptr || v.age() < oldest->age()))
            oldest = &v;
    if (oldest != nullptr)
        return oldest;
    oldest = &voices_[0];
    for (auto& v : voices_)
        if (v.age() < oldest->age())
            oldest = &v;
    return oldest;
}

void Synth::noteOn(int note, float velocity) noexcept {
    if (note < 0 || note > 127)
        return;
    auto* v = findVoiceFor(note);
    v->start(note, velocity, params_, ++ageCounter_);
    v->setCutoff(smoothedCutoff_);
}

void Synth::noteOff(int note) noexcept {
    for (auto& v : voices_)
        if (v.isHeld() && v.note() == note)
            v.release();
}

void Synth::allNotesOff() noexcept {
    for (auto& v : voices_)
        if (v.isHeld())
            v.release();
}

void Synth::setParam(int id, float value) noexcept {
    if (!std::isfinite(value))
        return;
    switch (id) {
        case MDAW_PARAM_CUTOFF_HZ:    params_.cutoffHz = std::clamp(value, 20.0f, 20000.0f); return;
        case MDAW_PARAM_MASTER_GAIN:  params_.masterGain = std::clamp(value, 0.0f, 1.0f); return;
        case MDAW_PARAM_RESONANCE:    params_.resonance = value; break;
        case MDAW_PARAM_ATTACK_S:     params_.attackS = value; break;
        case MDAW_PARAM_DECAY_S:      params_.decayS = value; break;
        case MDAW_PARAM_SUSTAIN:      params_.sustain = value; break;
        case MDAW_PARAM_RELEASE_S:    params_.releaseS = value; break;
        case MDAW_PARAM_DETUNE_CENTS: params_.detuneCents = std::clamp(value, -100.0f, 100.0f); break;
        default: return;
    }
    for (auto& v : voices_)
        v.applyParams(params_);
}

void Synth::render(float* mono, int numSamples) noexcept {
    std::fill(mono, mono + numSamples, 0.0f);

    // カットオフはブロック単位でなめらかに追従させる（約20ms）
    const float k = 1.0f - std::exp(-static_cast<float>(numSamples) / static_cast<float>(0.02 * sampleRate_));
    smoothedCutoff_ += (params_.cutoffHz - smoothedCutoff_) * k;

    for (auto& v : voices_) {
        if (!v.isActive())
            continue;
        v.setCutoff(smoothedCutoff_);
        v.render(mono, numSamples);
    }

    // 音量はサンプル単位で直線的に移す（ジッパーノイズ対策）
    const float startGain = smoothedGain_;
    const float endGain = startGain + (params_.masterGain - startGain) * k;
    const float step = (endGain - startGain) / static_cast<float>(std::max(numSamples, 1));
    float g = startGain;
    for (int i = 0; i < numSamples; ++i) {
        mono[i] *= g;
        g += step;
    }
    smoothedGain_ = endGain;
}

int Synth::activeVoices() const noexcept {
    int n = 0;
    for (const auto& v : voices_)
        n += v.isActive() ? 1 : 0;
    return n;
}

} // namespace mdaw
