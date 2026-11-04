#include "fx.h"

#include <algorithm>
#include <cmath>
#include <iterator>

#include "mdaw.h"

namespace mdaw {

const FxParamSpec kFxParamSpecs[] = {
    {{MDAW_FX_LOWCUT_HZ, "lowCutHz", 20.0f, 12000.0f, false}, &FxParams::lowCutHz},
    {{MDAW_FX_SATURATION, "saturation", 0.0f, 1.0f, false}, &FxParams::saturation},
    {{MDAW_FX_CHORUS, "chorus", 0.0f, 1.0f, false}, &FxParams::chorus},
    {{MDAW_FX_OTT, "ott", 0.0f, 1.0f, false}, &FxParams::ott},
    {{MDAW_FX_DELAY, "delay", 0.0f, 1.0f, false}, &FxParams::delay},
    {{MDAW_FX_DELAY_FEEDBACK, "delayFeedback", 0.0f, 0.9f, false}, &FxParams::delayFeedback},
    {{MDAW_FX_REVERB, "reverb", 0.0f, 1.0f, false}, &FxParams::reverb},
    {{MDAW_FX_REVERB_SIZE, "reverbSize", 0.0f, 1.0f, false}, &FxParams::reverbSize},
    {{MDAW_FX_SIDECHAIN, "sidechain", 0.0f, 1.0f, false}, &FxParams::sidechain},
    {{MDAW_FX_SIDECHAIN_RELEASE_S, "sidechainReleaseS", 0.03f, 1.0f, false}, &FxParams::sidechainReleaseS},
    {{MDAW_FX_SIDECHAIN_SOURCE, "sidechainSource", 0.0f, 1.0f, true}, &FxParams::sidechainSource},
};
const int kNumFxParamSpecs = static_cast<int>(std::size(kFxParamSpecs));

namespace {

const FxParamSpec* findSpec(int id) noexcept {
    for (const auto& s : kFxParamSpecs)
        if (s.id == id)
            return &s;
    return nullptr;
}

float coefFor(double seconds, double sampleRate) noexcept {
    return static_cast<float>(std::exp(-1.0 / (std::max(seconds, 1e-5) * sampleRate)));
}

float toDb(float x) noexcept { return 20.0f * std::log10(std::max(x, 1e-9f)); }
float fromDb(float db) noexcept { return std::pow(10.0f, db / 20.0f); }

float readInterp(const std::vector<float>& buf, int writePos, float delaySamples) noexcept {
    const int size = static_cast<int>(buf.size());
    float pos = static_cast<float>(writePos) - delaySamples;
    while (pos < 0.0f)
        pos += static_cast<float>(size);
    const int i0 = static_cast<int>(pos);
    const float frac = pos - static_cast<float>(i0);
    const int a = i0 % size;
    const int b = (i0 + 1) % size;
    return buf[static_cast<size_t>(a)] + (buf[static_cast<size_t>(b)] - buf[static_cast<size_t>(a)]) * frac;
}

} // namespace

bool operator==(const FxParams& a, const FxParams& b) noexcept {
    for (const auto& s : kFxParamSpecs)
        if (a.*(s.member) != b.*(s.member))
            return false;
    return true;
}

bool getFxParam(const FxParams& f, int id, float& out) noexcept {
    const auto* spec = findSpec(id);
    if (spec == nullptr)
        return false;
    out = f.*(spec->member);
    return true;
}

bool setFxParam(FxParams& f, int id, float value) noexcept {
    const auto* spec = findSpec(id);
    if (spec == nullptr || !std::isfinite(value))
        return false;
    value = std::clamp(value, spec->min, spec->max);
    if (spec->integer)
        value = std::round(value);
    f.*(spec->member) = value;
    return true;
}

//==============================================================================
void Ott::prepare(double sampleRate) {
    sampleRate_ = sampleRate;
    const float q = 0.7071f;
    for (Svf* f : {&lowL_, &lowR_, &lowL2_, &lowR2_})
        f->set(120.0f, q, sampleRate);
    for (Svf* f : {&highL_, &highR_, &highL2_, &highR2_})
        f->set(2500.0f, q, sampleRate);
    attack_ = coefFor(0.003, sampleRate);
    release_ = coefFor(0.09, sampleRate);
    reset();
}

void Ott::reset() noexcept {
    for (Svf* f : {&lowL_, &lowR_, &lowL2_, &lowR2_, &highL_, &highR_, &highL2_, &highR2_})
        f->reset();
    for (auto& b : bands_)
        b = {};
}

void Ott::process(float* left, float* right, int n, float depth) noexcept {
    if (depth <= 0.0f)
        return;
    // 帯域ごとのしきい値（dBFS）。上はこれより大きいと抑え、下はこれより小さいと持ち上げる
    constexpr float kDownThresh[3] = {-24.0f, -22.0f, -26.0f};
    constexpr float kUpThresh[3] = {-42.0f, -40.0f, -44.0f};
    constexpr float kDownRatio = 4.0f;
    constexpr float kUpRatio = 3.0f;
    constexpr float kMaxUpDb = 18.0f;
    constexpr int kControl = 16;
    const float makeup = fromDb(3.0f);

    for (int start = 0; start < n; start += kControl) {
        const int end = std::min(n, start + kControl);
        float bandsL[3][kControl], bandsR[3][kControl];
        for (int s = start; s < end; ++s) {
            const int i = s - start;
            float hiL = 0.0f, hiR = 0.0f;
            // 低域：ローパス2回 / 残り：ハイパス2回 → それをさらに中域と高域に分ける
            float restL = 0.0f, restR = 0.0f;
            const float lowL = lowL2_.process(lowL_.process(left[s], &restL));
            const float lowR = lowR2_.process(lowR_.process(right[s], &restR));
            const float midL = highL2_.process(highL_.process(restL, &hiL));
            const float midR = highR2_.process(highR_.process(restR, &hiR));
            bandsL[0][i] = lowL;
            bandsR[0][i] = lowR;
            bandsL[1][i] = midL;
            bandsR[1][i] = midR;
            bandsL[2][i] = hiL;
            bandsR[2][i] = hiR;
            for (int b = 0; b < 3; ++b) {
                const float level = std::max(std::abs(bandsL[b][i]), std::abs(bandsR[b][i]));
                auto& band = bands_[b];
                const float c = level > band.env ? attack_ : release_;
                band.env = level + (band.env - level) * c;
            }
        }
        // 帯域ごとの量を決める（16サンプルに1回）
        float target[3];
        for (int b = 0; b < 3; ++b) {
            const float db = toDb(bands_[b].env);
            float g = 0.0f;
            if (db > kDownThresh[b])
                g = (kDownThresh[b] - db) * (1.0f - 1.0f / kDownRatio);
            else if (db < kUpThresh[b] && db > -75.0f)
                g = std::min((kUpThresh[b] - db) * (1.0f - 1.0f / kUpRatio), kMaxUpDb);
            target[b] = fromDb(g);
        }
        for (int s = start; s < end; ++s) {
            const int i = s - start;
            const float t = static_cast<float>(i + 1) / static_cast<float>(end - start);
            float l = 0.0f, r = 0.0f;
            for (int b = 0; b < 3; ++b) {
                const float g = bands_[b].gain + (target[b] - bands_[b].gain) * t;
                l += bandsL[b][i] * g;
                r += bandsR[b][i] * g;
            }
            // 深さ＝元の音との混ぜ具合（本家 OTT と同じ考え方）
            left[s] = left[s] * (1.0f - depth) + l * makeup * depth;
            right[s] = right[s] * (1.0f - depth) + r * makeup * depth;
        }
        for (int b = 0; b < 3; ++b)
            bands_[b].gain = target[b];
    }
}

//==============================================================================
void TrackFx::prepare(double sampleRate, int maxBlock) {
    sampleRate_ = sampleRate;
    chorusL_.assign(static_cast<size_t>(sampleRate * 0.05) + 4, 0.0f);
    chorusR_.assign(chorusL_.size(), 0.0f);
    delayL_.assign(static_cast<size_t>(sampleRate * 2.0) + 4, 0.0f);
    delayR_.assign(delayL_.size(), 0.0f);
    wetL_.assign(static_cast<size_t>(std::max(maxBlock, 1)), 0.0f);
    wetR_.assign(wetL_.size(), 0.0f);
    ott_.prepare(sampleRate);
    reverb_.setSampleRate(sampleRate);
    setParams(p_);
    reset();
}

void TrackFx::reset() noexcept {
    lowCutL_.reset();
    lowCutR_.reset();
    std::fill(chorusL_.begin(), chorusL_.end(), 0.0f);
    std::fill(chorusR_.begin(), chorusR_.end(), 0.0f);
    std::fill(delayL_.begin(), delayL_.end(), 0.0f);
    std::fill(delayR_.begin(), delayR_.end(), 0.0f);
    delayLpL_ = delayLpR_ = 0.0f;
    ott_.reset();
    reverb_.reset();
}

void TrackFx::setParams(const FxParams& params) noexcept {
    p_ = params;
    lowCutL_.set(p_.lowCutHz, 0.7071f, sampleRate_);
    lowCutR_.set(p_.lowCutHz, 0.7071f, sampleRate_);
    juce::Reverb::Parameters rp;
    rp.roomSize = 0.45f + 0.53f * p_.reverbSize;
    rp.damping = 0.45f;
    rp.wetLevel = 1.0f;
    rp.dryLevel = 0.0f;
    rp.width = 1.0f;
    rp.freezeMode = 0.0f;
    reverb_.setParameters(rp);
}

double TrackFx::tailSeconds() const noexcept {
    double t = 0.05;
    if (p_.chorus > 0.0f)
        t = std::max(t, 0.1);
    if (p_.delay > 0.0f)
        t = std::max(t, 0.75 * 60.0 / std::max(tempo_, 20.0) * (1.0 + 12.0 * p_.delayFeedback));
    if (p_.reverb > 0.0f)
        t = std::max(t, 1.5 + 4.0 * p_.reverbSize);
    return t;
}

void TrackFx::process(float* left, float* right, int n) noexcept {
    const auto sr = static_cast<float>(sampleRate_);

    if (p_.lowCutHz > 20.5f) {
        float hi = 0.0f;
        for (int i = 0; i < n; ++i) {
            lowCutL_.process(left[i], &hi);
            left[i] = hi;
            lowCutR_.process(right[i], &hi);
            right[i] = hi;
        }
    }

    if (p_.saturation > 0.0f) {
        const float g = 1.0f + p_.saturation * 8.0f;
        const float makeup = 1.0f / std::tanh(g * 0.35f) * 0.35f; // よくある大きさ（-9 dBFS 付近）を保つ
        for (int i = 0; i < n; ++i) {
            left[i] = std::tanh(left[i] * g) * makeup;
            right[i] = std::tanh(right[i] * g) * makeup;
        }
    }

    if (p_.chorus > 0.0f) {
        // 2本の揺れる遅延を左右に。ゆっくり（0.4Hz）、深め
        const int size = static_cast<int>(chorusL_.size());
        const float rate = 0.4f / sr;
        const float base = 0.012f * sr, depth = 0.004f * sr;
        const float wet = p_.chorus * 0.6f;
        const float dry = 1.0f - p_.chorus * 0.25f;
        for (int i = 0; i < n; ++i) {
            chorusL_[static_cast<size_t>(chorusPos_)] = left[i];
            chorusR_[static_cast<size_t>(chorusPos_)] = right[i];
            const float lfoA = std::sin(6.2831853f * chorusPhase_);
            const float lfoB = std::cos(6.2831853f * chorusPhase_);
            const float wl = readInterp(chorusL_, chorusPos_, base + depth * lfoA);
            const float wr = readInterp(chorusR_, chorusPos_, base + depth * lfoB);
            left[i] = left[i] * dry + (wl - 0.3f * wr) * wet;
            right[i] = right[i] * dry + (wr - 0.3f * wl) * wet;
            chorusPos_ = (chorusPos_ + 1) % size;
            chorusPhase_ += rate;
            if (chorusPhase_ >= 1.0f)
                chorusPhase_ -= 1.0f;
        }
    }

    ott_.process(left, right, n, p_.ott);

    if (p_.delay > 0.0f) {
        const int size = static_cast<int>(delayL_.size());
        const float beat = static_cast<float>(60.0 / std::max(tempo_, 20.0));
        const float timeL = std::min(0.75f * beat * sr, static_cast<float>(size - 2));
        const float timeR = std::min(0.5f * beat * sr, static_cast<float>(size - 2)); // 右は8分で広げる
        const float fb = p_.delayFeedback;
        const float lp = 1.0f - std::exp(-6.2831853f * 4500.0f / sr);
        const float hp = 1.0f - std::exp(-6.2831853f * 150.0f / sr);
        for (int i = 0; i < n; ++i) {
            const float dl = readInterp(delayL_, delayPos_, timeL);
            const float dr = readInterp(delayR_, delayPos_, timeR);
            // 返りは高域を丸め、低域を少し削ってこもらせない
            delayLpL_ += (dl - delayLpL_) * lp;
            delayLpR_ += (dr - delayLpR_) * lp;
            const float fl = delayLpL_ - delayLpL_ * hp * 0.5f;
            const float fr = delayLpR_ - delayLpR_ * hp * 0.5f;
            delayL_[static_cast<size_t>(delayPos_)] = left[i] + fl * fb;
            delayR_[static_cast<size_t>(delayPos_)] = right[i] + fr * fb;
            left[i] += dl * p_.delay * 0.7f;
            right[i] += dr * p_.delay * 0.7f;
            delayPos_ = (delayPos_ + 1) % size;
        }
    }

    if (p_.reverb > 0.0f) {
        const int m = std::min(n, static_cast<int>(wetL_.size()));
        std::copy(left, left + m, wetL_.begin());
        std::copy(right, right + m, wetR_.begin());
        reverb_.processStereo(wetL_.data(), wetR_.data(), m);
        const float wet = p_.reverb * 0.6f;
        const float dry = 1.0f - p_.reverb * 0.3f;
        for (int i = 0; i < m; ++i) {
            left[i] = left[i] * dry + wetL_[static_cast<size_t>(i)] * wet;
            right[i] = right[i] * dry + wetR_[static_cast<size_t>(i)] * wet;
        }
    }
}

//==============================================================================
void MasterBus::prepare(double sampleRate) {
    sampleRate_ = sampleRate;
    glueAttack_ = coefFor(0.01, sampleRate);
    glueRelease_ = coefFor(0.15, sampleRate);
    limRelease_ = coefFor(0.08, sampleRate);
    glueEnv_ = 0.0f;
    glueGain_ = 1.0f;
    limGain_ = 1.0f;
}

void MasterBus::process(float* left, float* right, int n) noexcept {
    constexpr float kGlueThreshDb = -12.0f; // RMS で見る
    constexpr float kGlueRatio = 1.6f;
    constexpr float kCeiling = 0.944f; // -0.5 dBFS
    constexpr float kPreGain = 3.2f;   // +10 dB。トラックは余裕を持って小さめに作り、ここで持ち上げる
    constexpr float kKnee = 0.6f;      // ここから上はやわらかく丸める（瞬間的な山を削って音圧を出す）
    for (int i = 0; i < n; ++i) {
        float l = left[i] * kPreGain, r = right[i] * kPreGain;
        // まとめるコンプ（ゆっくり、浅く。瞬間の山ではなく平均の大きさで見る）
        const float power = 0.5f * (l * l + r * r);
        const float c = power > glueEnv_ ? glueAttack_ : glueRelease_;
        glueEnv_ = power + (glueEnv_ - power) * c;
        if ((i & 15) == 0) {
            const float db = 10.0f * std::log10(std::max(glueEnv_, 1e-12f));
            glueGain_ = db > kGlueThreshDb ? fromDb((kGlueThreshDb - db) * (1.0f - 1.0f / kGlueRatio)) : 1.0f;
        }
        l *= glueGain_;
        r *= glueGain_;
        // ソフトクリップ：kKnee までは素通し、その上は tanh で天井へ寄せる
        auto clip = [](float x) {
            const float a = std::abs(x);
            if (a <= kKnee)
                return x;
            const float over = (a - kKnee) / (1.0f - kKnee);
            return std::copysign(kKnee + (1.0f - kKnee) * std::tanh(over), x);
        };
        l = clip(l);
        r = clip(r);
        // リミッター：天井を超える分だけ即座に下げ、ゆっくり戻す
        const float peak = std::max(std::abs(l), std::abs(r));
        const float needed = peak > kCeiling ? kCeiling / peak : 1.0f;
        limGain_ = needed < limGain_ ? needed : needed + (limGain_ - needed) * limRelease_;
        l *= limGain_;
        r *= limGain_;
        left[i] = std::clamp(l, -1.0f, 1.0f);
        right[i] = std::clamp(r, -1.0f, 1.0f);
    }
}

} // namespace mdaw
