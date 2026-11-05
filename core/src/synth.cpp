#include "synth.h"

#include <algorithm>
#include <cmath>
#include <iterator>

#include "mdaw.h"
#include "wavetable.h"

namespace mdaw {

const SynthParamSpec kSynthParamSpecs[] = {
    {{MDAW_PARAM_CUTOFF_HZ, "cutoffHz", 20.0f, 20000.0f, false}, &SynthParams::cutoffHz},
    {{MDAW_PARAM_RESONANCE, "resonance", 0.5f, 10.0f, false}, &SynthParams::resonance},
    {{MDAW_PARAM_ATTACK_S, "attackS", 0.0005f, 10.0f, false}, &SynthParams::attackS},
    {{MDAW_PARAM_DECAY_S, "decayS", 0.0005f, 10.0f, false}, &SynthParams::decayS},
    {{MDAW_PARAM_SUSTAIN, "sustain", 0.0f, 1.0f, false}, &SynthParams::sustain},
    {{MDAW_PARAM_RELEASE_S, "releaseS", 0.002f, 10.0f, false}, &SynthParams::releaseS},
    {{MDAW_PARAM_DETUNE_CENTS, "detuneCents", 0.0f, 100.0f, false}, &SynthParams::detuneCents},
    {{MDAW_PARAM_MASTER_GAIN, "masterGain", 0.0f, 1.0f, false}, &SynthParams::masterGain},
    {{MDAW_PARAM_UNISON, "unison", 1.0f, 16.0f, true}, &SynthParams::unison},
    {{MDAW_PARAM_WIDTH, "width", 0.0f, 1.0f, false}, &SynthParams::width},
    {{MDAW_PARAM_BLEND, "blend", 0.0f, 1.0f, false}, &SynthParams::blend},
    {{MDAW_PARAM_SUB, "sub", 0.0f, 1.0f, false}, &SynthParams::sub},
    {{MDAW_PARAM_NOISE, "noise", 0.0f, 1.0f, false}, &SynthParams::noise},
    {{MDAW_PARAM_DRIVE, "drive", 0.0f, 1.0f, false}, &SynthParams::drive},
    {{MDAW_PARAM_FILTER_ENV, "filterEnv", 0.0f, 1.0f, false}, &SynthParams::filterEnv},
    {{MDAW_PARAM_FILTER_ENV_DECAY_S, "filterEnvDecayS", 0.005f, 5.0f, false}, &SynthParams::filterEnvDecayS},
    {{MDAW_PARAM_PITCH_ENV, "pitchEnv", 0.0f, 48.0f, false}, &SynthParams::pitchEnv},
    {{MDAW_PARAM_PITCH_ENV_DECAY_S, "pitchEnvDecayS", 0.002f, 2.0f, false}, &SynthParams::pitchEnvDecayS},
    {{MDAW_PARAM_WAVE, "wave", 0.0f, 1.0f, true}, &SynthParams::wave},
    {{MDAW_PARAM_OSC, "osc", 0.0f, 1.0f, false}, &SynthParams::osc},
    {{MDAW_PARAM_WT_TABLE, "wtTable", 0.0f, 4.0f, true}, &SynthParams::wtTable},
    {{MDAW_PARAM_WT_POS, "wtPos", 0.0f, 1.0f, false}, &SynthParams::wtPos},
    {{MDAW_PARAM_WT_WARP, "wtWarp", 0.0f, 3.0f, true}, &SynthParams::wtWarp},
    {{MDAW_PARAM_WT_WARP_AMOUNT, "wtWarpAmount", 0.0f, 1.0f, false}, &SynthParams::wtWarpAmount},
};
const int kNumSynthParamSpecs = static_cast<int>(std::size(kSynthParamSpecs));

namespace {

constexpr int kControlBlock = 32; // エンベロープでフィルター・音程を動かす間隔（サンプル）
constexpr float kTwoPi = 6.28318530718f;

const SynthParamSpec* findSpec(int id) noexcept {
    for (const auto& s : kSynthParamSpecs)
        if (s.id == id)
            return &s;
    return nullptr;
}

float polyBlep(float t, float dt) noexcept {
    if (t < dt) {
        t /= dt;
        return t + t - t * t - 1.0f;
    }
    if (t > 1.0f - dt) {
        t = (t - 1.0f) / dt;
        return t * t + t + t + 1.0f;
    }
    return 0.0f;
}

// 速いサイン近似（位相 0〜1）
float fastSin(float phase) noexcept {
    const float x = phase < 0.5f ? phase : phase - 1.0f; // -0.5〜0.5
    const float y = 8.0f * x - 16.0f * x * std::abs(x);
    return 0.225f * (y * std::abs(y) - y) + y;
}

juce::ADSR::Parameters toAdsr(const SynthParams& p) noexcept {
    return {std::max(p.attackS, 0.0005f), std::max(p.decayS, 0.0005f), std::clamp(p.sustain, 0.0f, 1.0f),
            std::max(p.releaseS, 0.002f)};
}

uint32_t nextRandom(uint32_t& state) noexcept {
    state = state * 1664525u + 1013904223u;
    return state;
}

} // namespace

bool operator==(const SynthParams& a, const SynthParams& b) noexcept {
    for (const auto& s : kSynthParamSpecs)
        if (a.*(s.member) != b.*(s.member))
            return false;
    return true;
}

bool getSynthParam(const SynthParams& s, int id, float& out) noexcept {
    const auto* spec = findSpec(id);
    if (spec == nullptr)
        return false;
    out = s.*(spec->member);
    return true;
}

bool setSynthParam(SynthParams& s, int id, float value) noexcept {
    const auto* spec = findSpec(id);
    if (spec == nullptr || !std::isfinite(value))
        return false;
    value = std::clamp(value, spec->min, spec->max);
    if (spec->integer)
        value = std::round(value);
    s.*(spec->member) = value;
    return true;
}

void Svf::set(float cutoffHz, float q, double sampleRate) noexcept {
    const float fc = std::clamp(cutoffHz, 20.0f, static_cast<float>(sampleRate * 0.45));
    g = std::tan(3.14159265f * fc / static_cast<float>(sampleRate));
    k = 1.0f / std::max(q, 0.1f);
    a1 = 1.0f / (1.0f + g * (g + k));
    a2 = g * a1;
    a3 = g * a2;
}

//==============================================================================
void Voice::prepare(double sampleRate) {
    sampleRate_ = sampleRate;
    adsr_.setSampleRate(sampleRate);
    adsr_.reset();
    filterL_.reset();
    filterR_.reset();
    held_ = false;
    note_ = -1;
}

void Voice::start(int note, float velocity, const SynthParams& params, uint64_t age, uint32_t seed) {
    const bool wasActive = isActive();
    note_ = note;
    held_ = true;
    age_ = age;
    gain_ = std::pow(std::clamp(velocity, 0.0f, 1.0f), 1.5f) * 0.25f;
    filterEnv_ = 1.0f;
    pitchEnv_ = 1.0f;
    if (!wasActive)
        wtPos_ = params.wtPos;
    if (!wasActive) {
        // ユニゾンの位相はばらばらに始める（揃うと薄く、頭が強く鳴る）
        uint32_t r = seed | 1u;
        for (auto& ph : phase_)
            ph = static_cast<float>(nextRandom(r) >> 8) / 16777216.0f;
        subPhase_ = 0.0f;
        noise_ = r;
        filterL_.reset();
        filterR_.reset();
    }
    applyParams(params);
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
    p_ = params;
    adsr_.setParameters(toAdsr(params));
    filterEnvCoef_ = std::exp(-static_cast<float>(kControlBlock) /
                              (std::max(params.filterEnvDecayS, 0.001f) * static_cast<float>(sampleRate_)));
    pitchEnvCoef_ = std::exp(-static_cast<float>(kControlBlock) /
                             (std::max(params.pitchEnvDecayS, 0.001f) * static_cast<float>(sampleRate_)));
    layoutUnison();
    updateIncrements(p_.pitchEnv * pitchEnv_);
}

void Voice::layoutUnison() noexcept {
    const int n = std::clamp(static_cast<int>(std::lround(p_.unison)), 1, kMaxUnison);
    unison_ = n;
    float power = 0.0f;
    float gains[kMaxUnison];
    float pans[kMaxUnison];
    for (int i = 0; i < n; ++i) {
        const float x = n == 1 ? 0.0f : -1.0f + 2.0f * static_cast<float>(i) / static_cast<float>(n - 1);
        const float side = std::abs(x);
        detune_[i] = x * p_.detuneCents * 0.5f / 100.0f;
        gains[i] = n == 1 ? 1.0f : (1.0f - side) + p_.blend * side;
        // 対になる2本（±同じずらし）は左右に分け、隣の対とは向きを入れ替える
        const int pair = i < n / 2 ? i : n - 1 - i;
        float sign = (pair % 2 == 0) ? 1.0f : -1.0f;
        if (i >= n / 2)
            sign = -sign;
        pans[i] = std::clamp(p_.width * side * sign, -1.0f, 1.0f);
        power += gains[i] * gains[i];
    }
    // 本数を増やしても大きさがあまり変わらないよう、パワーでならす（中央1本のとき左右とも 1）
    const float norm = std::sqrt(2.0f) / std::sqrt(std::max(power, 1e-6f));
    for (int i = 0; i < n; ++i) {
        const float angle = (pans[i] + 1.0f) * 0.25f * 3.14159265f;
        gainL_[i] = std::cos(angle) * gains[i] * norm;
        gainR_[i] = std::sin(angle) * gains[i] * norm;
    }
}

void Voice::updateIncrements(float pitchOffsetSemis) noexcept {
    if (note_ < 0)
        return;
    const float base = static_cast<float>(note_) + pitchOffsetSemis - 69.0f;
    const float sr = static_cast<float>(sampleRate_);
    for (int i = 0; i < unison_; ++i)
        inc_[i] = std::min(440.0f * std::exp2((base + detune_[i]) / 12.0f) / sr, 0.45f);
    subInc_ = std::min(440.0f * std::exp2((base - 12.0f) / 12.0f) / sr, 0.45f);
}

void Voice::render(float* left, float* right, int numSamples) noexcept {
    if (!isActive())
        return;
    const bool square = p_.wave >= 0.5f;
    const bool useWt = p_.wtTable >= 0.5f;
    const int wtTable = std::clamp(static_cast<int>(std::lround(p_.wtTable)), 1, wavetable::kTables);
    const int wtWarp = std::clamp(static_cast<int>(std::lround(p_.wtWarp)), 0, 3);
    const float noiseLevel = p_.noise * 0.6f;
    const float subLevel = p_.sub * 0.9f;
    const float driveGain = 1.0f + p_.drive * 9.0f;
    const float driveMakeup = 1.0f / (1.0f + p_.drive * 2.0f);
    const bool drive = p_.drive > 0.001f;
    const float oscLevel = p_.osc;
    const int unison = oscLevel > 0.0f ? unison_ : 0;

    for (int start = 0; start < numSamples; start += kControlBlock) {
        const int end = std::min(numSamples, start + kControlBlock);

        if (p_.pitchEnv > 0.0f && pitchEnv_ > 1e-4f) {
            updateIncrements(p_.pitchEnv * pitchEnv_);
            pitchEnv_ *= pitchEnvCoef_;
        }
        wtPos_ += (p_.wtPos - wtPos_) * 0.35f; // WT_POS はブロック単位でなめらかに追従（ジッパー対策）
        const float cutoff = cutoffHz_ * std::exp2(p_.filterEnv * 7.0f * filterEnv_);
        filterL_.set(cutoff, p_.resonance, sampleRate_);
        filterR_.set(cutoff, p_.resonance, sampleRate_);
        filterEnv_ *= filterEnvCoef_;

        for (int s = start; s < end; ++s) {
            float l = 0.0f, r = 0.0f;
            for (int u = 0; u < unison; ++u) {
                const float ph = phase_[u];
                const float dt = inc_[u];
                float v;
                if (useWt) {
                    const float wp = wtWarp > 0 ? warpPhase(ph, wtWarp, p_.wtWarpAmount) : ph;
                    v = wavetable::sampleWavetable(wtTable, wtPos_, wp, dt);
                } else if (square) {
                    v = ph < 0.5f ? 1.0f : -1.0f;
                    v += polyBlep(ph, dt);
                    float ph2 = ph + 0.5f;
                    if (ph2 >= 1.0f)
                        ph2 -= 1.0f;
                    v -= polyBlep(ph2, dt);
                    v *= 0.7f;
                } else {
                    v = 2.0f * ph - 1.0f - polyBlep(ph, dt);
                }
                l += v * gainL_[u];
                r += v * gainR_[u];
                float next = ph + dt;
                if (next >= 1.0f)
                    next -= 1.0f;
                phase_[u] = next;
            }
            l *= oscLevel;
            r *= oscLevel;
            if (noiseLevel > 0.0f) {
                const float nl = static_cast<float>(static_cast<int32_t>(nextRandom(noise_))) * (1.0f / 2147483648.0f);
                const float nr = static_cast<float>(static_cast<int32_t>(nextRandom(noise_))) * (1.0f / 2147483648.0f);
                l += nl * noiseLevel;
                r += nr * noiseLevel;
            }
            if (drive) {
                l = std::tanh(l * driveGain) * driveMakeup;
                r = std::tanh(r * driveGain) * driveMakeup;
            }
            l = filterL_.process(l);
            r = filterR_.process(r);
            if (subLevel > 0.0f) {
                const float sv = fastSin(subPhase_) * subLevel;
                subPhase_ += subInc_;
                if (subPhase_ >= 1.0f)
                    subPhase_ -= 1.0f;
                l += sv;
                r += sv;
            }
            const float a = adsr_.getNextSample() * gain_;
            left[s] += l * a;
            right[s] += r * a;
        }
    }
    if (!isActive()) {
        held_ = false;
        note_ = -1;
    }
}

//==============================================================================
void Synth::prepare(double sampleRate, int /*maxBlock*/) {
    wavetable::buildWavetables(); // 音声スレッドが止まっている間に一度だけ作る（以後は読み取り専用）
    sampleRate_ = sampleRate;
    for (auto& v : voices_) {
        v.prepare(sampleRate);
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
    v->start(note, velocity, params_, ++ageCounter_, nextRandom(seed_));
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
    if (!setSynthParam(params_, id, value))
        return;
    if (id == MDAW_PARAM_CUTOFF_HZ || id == MDAW_PARAM_MASTER_GAIN)
        return; // この2つは render() 内でなめらかに追従させる
    for (auto& v : voices_)
        v.applyParams(params_);
}

void Synth::setParams(const SynthParams& params) noexcept {
    params_ = params;
    for (auto& v : voices_)
        v.applyParams(params_);
}

void Synth::render(float* left, float* right, int numSamples) noexcept {
    std::fill(left, left + numSamples, 0.0f);
    std::fill(right, right + numSamples, 0.0f);

    // カットオフはブロック単位でなめらかに追従させる（約20ms）
    const float k = 1.0f - std::exp(-static_cast<float>(numSamples) / static_cast<float>(0.02 * sampleRate_));
    smoothedCutoff_ += (params_.cutoffHz - smoothedCutoff_) * k;

    for (auto& v : voices_) {
        if (!v.isActive())
            continue;
        v.setCutoff(smoothedCutoff_);
        v.render(left, right, numSamples);
    }

    // 音量はサンプル単位で直線的に移す（ジッパーノイズ対策）
    const float startGain = smoothedGain_;
    const float endGain = startGain + (params_.masterGain - startGain) * k;
    const float step = (endGain - startGain) / static_cast<float>(std::max(numSamples, 1));
    float g = startGain;
    for (int i = 0; i < numSamples; ++i) {
        left[i] *= g;
        right[i] *= g;
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
