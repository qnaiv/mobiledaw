#include "fx.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iterator>

#include "mdaw.h"

#include "grain_engine.h"

namespace mdaw {

namespace {
constexpr int kTrackLevel = -1;
constexpr int unitOf(FxUnitType t) { return static_cast<int>(t); }
} // namespace

// パラメータ仕様表。unit が所属ユニット（-1 = トラック直属）を決める単一の情報源で、
// ルーティング（commands / engine / session）と保存形式はすべてここを引く。
const FxParamSpec kFxParamSpecs[] = {
    {{MDAW_FX_LOWCUT_HZ, "lowCutHz", 20.0f, 12000.0f, false}, &FxParams::lowCutHz, unitOf(FxUnitType::LowCut)},
    {{MDAW_FX_SATURATION, "saturation", 0.0f, 1.0f, false}, &FxParams::saturation, unitOf(FxUnitType::Saturation)},
    {{MDAW_FX_CHORUS, "chorus", 0.0f, 1.0f, false}, &FxParams::chorus, unitOf(FxUnitType::Chorus)},
    {{MDAW_FX_OTT, "ott", 0.0f, 1.0f, false}, &FxParams::ott, unitOf(FxUnitType::Ott)},
    {{MDAW_FX_DELAY, "delay", 0.0f, 1.0f, false}, &FxParams::delay, unitOf(FxUnitType::Delay)},
    {{MDAW_FX_DELAY_FEEDBACK, "delayFeedback", 0.0f, 0.9f, false}, &FxParams::delayFeedback, unitOf(FxUnitType::Delay)},
    {{MDAW_FX_REVERB, "reverb", 0.0f, 1.0f, false}, &FxParams::reverb, unitOf(FxUnitType::Reverb)},
    {{MDAW_FX_REVERB_SIZE, "reverbSize", 0.0f, 1.0f, false}, &FxParams::reverbSize, unitOf(FxUnitType::Reverb)},
    {{MDAW_FX_SIDECHAIN, "sidechain", 0.0f, 1.0f, false}, &FxParams::sidechain, kTrackLevel},
    {{MDAW_FX_SIDECHAIN_RELEASE_S, "sidechainReleaseS", 0.03f, 1.0f, false}, &FxParams::sidechainReleaseS, kTrackLevel},
    {{MDAW_FX_SIDECHAIN_SOURCE, "sidechainSource", 0.0f, 1.0f, true}, &FxParams::sidechainSource, kTrackLevel},
    {{MDAW_FX_EQ_LOW_DB, "eqLowDb", -18.0f, 18.0f, false}, &FxParams::eqLowDb, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_LOW_HZ, "eqLowHz", 40.0f, 400.0f, false}, &FxParams::eqLowHz, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_MID_DB, "eqMidDb", -18.0f, 18.0f, false}, &FxParams::eqMidDb, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_MID_HZ, "eqMidHz", 200.0f, 8000.0f, false}, &FxParams::eqMidHz, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_MID_Q, "eqMidQ", 0.4f, 6.0f, false}, &FxParams::eqMidQ, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_HIGH_DB, "eqHighDb", -18.0f, 18.0f, false}, &FxParams::eqHighDb, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_EQ_HIGH_HZ, "eqHighHz", 1500.0f, 16000.0f, false}, &FxParams::eqHighHz, unitOf(FxUnitType::Eq)},
    {{MDAW_FX_COMP, "comp", 0.0f, 1.0f, false}, &FxParams::comp, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_COMP_THRESHOLD_DB, "compThresholdDb", -40.0f, 0.0f, false}, &FxParams::compThresholdDb, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_COMP_RATIO, "compRatio", 1.0f, 20.0f, false}, &FxParams::compRatio, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_COMP_ATTACK_MS, "compAttackMs", 0.2f, 80.0f, false}, &FxParams::compAttackMs, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_COMP_RELEASE_MS, "compReleaseMs", 20.0f, 400.0f, false}, &FxParams::compReleaseMs, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_COMP_MAKEUP_DB, "compMakeupDb", 0.0f, 18.0f, false}, &FxParams::compMakeupDb, unitOf(FxUnitType::Comp)},
    {{MDAW_FX_SEND_REVERB, "sendReverb", 0.0f, 1.0f, false}, &FxParams::sendReverb, kTrackLevel},
    {{MDAW_FX_SEND_DELAY, "sendDelay", 0.0f, 1.0f, false}, &FxParams::sendDelay, kTrackLevel},
    {{MDAW_FX_BITCRUSH, "bitcrush", 0.0f, 1.0f, false}, &FxParams::bitcrush, unitOf(FxUnitType::Bitcrush)},
    {{MDAW_FX_STUTTER, "stutter", 0.0f, 1.0f, false}, &FxParams::stutter, unitOf(FxUnitType::Stutter)},
    {{MDAW_FX_STUTTER_DIV, "stutterDiv", 0.0f, 4.0f, true}, &FxParams::stutterDiv, unitOf(FxUnitType::Stutter)},
    {{MDAW_FX_SIDECHAIN_ATTACK_S, "sidechainAttackS", 0.0005f, 0.05f, false}, &FxParams::sidechainAttackS, kTrackLevel},
    {{MDAW_FX_SIDECHAIN_HOLD_S, "sidechainHoldS", 0.0f, 0.5f, false}, &FxParams::sidechainHoldS, kTrackLevel},
    {{MDAW_FX_SIDECHAIN_CURVE, "sidechainCurve", 0.5f, 4.0f, false}, &FxParams::sidechainCurve, kTrackLevel},
    {{MDAW_FX_GRANULAR, "granular", 0.0f, 1.0f, false}, &FxParams::granular, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_SIZE_MS, "granularSizeMs", 10.0f, 500.0f, false}, &FxParams::granularSizeMs, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_DENSITY, "granularDensity", 1.0f, 80.0f, false}, &FxParams::granularDensity, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_POSITION_S, "granularPositionS", 0.0f, 3.9f, false}, &FxParams::granularPositionS, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_SPRAY, "granularSpray", 0.0f, 1.0f, false}, &FxParams::granularSpray, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_PITCH, "granularPitch", -24.0f, 24.0f, false}, &FxParams::granularPitch, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_PITCH_SPREAD, "granularPitchSpread", 0.0f, 12.0f, false}, &FxParams::granularPitchSpread, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_FREEZE, "granularFreeze", 0.0f, 1.0f, true}, &FxParams::granularFreeze, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_FEEDBACK, "granularFeedback", 0.0f, 0.9f, false}, &FxParams::granularFeedback, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_TEXTURE, "granularTexture", 0.0f, 1.0f, false}, &FxParams::granularTexture, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_TIMING_RANDOM, "granularTimingRandom", 0.0f, 1.0f, false}, &FxParams::granularTimingRandom, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_SIZE_RANDOM, "granularSizeRandom", 0.0f, 1.0f, false}, &FxParams::granularSizeRandom, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_REVERSE_CHANCE, "granularReverseChance", 0.0f, 1.0f, false}, &FxParams::granularReverseChance, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_ROAM, "granularRoam", 0.0f, 1.0f, false}, &FxParams::granularRoam, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_GRANULAR_ROAM_SPEED, "granularRoamSpeed", 0.01f, 0.5f, false}, &FxParams::granularRoamSpeed, unitOf(FxUnitType::Granular)},
    {{MDAW_FX_SHIMMER, "shimmer", 0.0f, 1.0f, false}, &FxParams::shimmer, unitOf(FxUnitType::Shimmer)},
    {{MDAW_FX_SHIMMER_SIZE, "shimmerSize", 0.0f, 1.0f, false}, &FxParams::shimmerSize, unitOf(FxUnitType::Shimmer)},
    {{MDAW_FX_SHIMMER_AMOUNT, "shimmerAmount", 0.0f, 1.0f, false}, &FxParams::shimmerAmount, unitOf(FxUnitType::Shimmer)},
    {{MDAW_FX_SHIMMER_TONE, "shimmerTone", 0.0f, 1.0f, false}, &FxParams::shimmerTone, unitOf(FxUnitType::Shimmer)},
    {{MDAW_FX_TAPE, "tape", 0.0f, 1.0f, false}, &FxParams::tape, unitOf(FxUnitType::Tape)},
    {{MDAW_FX_TAPE_WOW, "tapeWow", 0.0f, 1.0f, false}, &FxParams::tapeWow, unitOf(FxUnitType::Tape)},
    {{MDAW_FX_TAPE_SAT, "tapeSat", 0.0f, 1.0f, false}, &FxParams::tapeSat, unitOf(FxUnitType::Tape)},
    {{MDAW_FX_TAPE_HISS, "tapeHiss", 0.0f, 1.0f, false}, &FxParams::tapeHiss, unitOf(FxUnitType::Tape)},
    {{MDAW_FX_DELAY_DIV, "delayDiv", 0.0f, 4.0f, true}, &FxParams::delayDiv, unitOf(FxUnitType::Delay)},
    {{MDAW_FX_DELAY_PINGPONG, "delayPingpong", 0.0f, 1.0f, true}, &FxParams::delayPingpong, unitOf(FxUnitType::Delay)},
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

constexpr float kPi = 3.14159265f;

void setLowShelf(Biquad& b, float freq, float gainDb, double sr) noexcept {
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * kPi * freq / static_cast<float>(sr);
    const float cw = std::cos(w0);
    const float alpha = std::sin(w0) * 0.70710678f; // S = 1
    const float two = 2.0f * std::sqrt(A) * alpha;
    const float a0 = (A + 1.0f) + (A - 1.0f) * cw + two;
    b.b0 = A * ((A + 1.0f) - (A - 1.0f) * cw + two) / a0;
    b.b1 = 2.0f * A * ((A - 1.0f) - (A + 1.0f) * cw) / a0;
    b.b2 = A * ((A + 1.0f) - (A - 1.0f) * cw - two) / a0;
    b.a1 = -2.0f * ((A - 1.0f) + (A + 1.0f) * cw) / a0;
    b.a2 = ((A + 1.0f) + (A - 1.0f) * cw - two) / a0;
}

void setHighShelf(Biquad& b, float freq, float gainDb, double sr) noexcept {
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * kPi * freq / static_cast<float>(sr);
    const float cw = std::cos(w0);
    const float alpha = std::sin(w0) * 0.70710678f;
    const float two = 2.0f * std::sqrt(A) * alpha;
    const float a0 = (A + 1.0f) - (A - 1.0f) * cw + two;
    b.b0 = A * ((A + 1.0f) + (A - 1.0f) * cw + two) / a0;
    b.b1 = -2.0f * A * ((A - 1.0f) + (A + 1.0f) * cw) / a0;
    b.b2 = A * ((A + 1.0f) + (A - 1.0f) * cw - two) / a0;
    b.a1 = 2.0f * ((A - 1.0f) - (A + 1.0f) * cw) / a0;
    b.a2 = ((A + 1.0f) - (A - 1.0f) * cw - two) / a0;
}

void setPeak(Biquad& b, float freq, float gainDb, float q, double sr) noexcept {
    const float A = std::pow(10.0f, gainDb / 40.0f);
    const float w0 = 2.0f * kPi * freq / static_cast<float>(sr);
    const float cw = std::cos(w0);
    const float alpha = std::sin(w0) / (2.0f * std::max(q, 0.2f));
    const float a0 = 1.0f + alpha / A;
    b.b0 = (1.0f + alpha * A) / a0;
    b.b1 = (-2.0f * cw) / a0;
    b.b2 = (1.0f - alpha * A) / a0;
    b.a1 = (-2.0f * cw) / a0;
    b.a2 = (1.0f - alpha / A) / a0;
}

float readInterp(const float* buf, int size, int writePos, float delaySamples) noexcept {
    float pos = static_cast<float>(writePos) - delaySamples;
    while (pos < 0.0f)
        pos += static_cast<float>(size);
    const int i0 = static_cast<int>(pos);
    const float frac = pos - static_cast<float>(i0);
    const int a = i0 % size;
    const int b = (i0 + 1) % size;
    return buf[a] + (buf[b] - buf[a]) * frac;
}

float readInterp(const std::vector<float>& buf, int writePos, float delaySamples) noexcept {
    return readInterp(buf.data(), static_cast<int>(buf.size()), writePos, delaySamples);
}

// オールパス 1 段（Schroeder 型。単一バッファで |H| = 1）。
// buf には v[n] = x[n] + g・v[n-D] を貯め、y[n] = v[n-D] − g・v[n] を返す
float allpassProcess(std::vector<float>& buf, int& pos, float x, float g) noexcept {
    const int size = static_cast<int>(buf.size());
    const float delayed = buf[static_cast<size_t>(pos)];
    const float v = x + g * delayed;
    buf[static_cast<size_t>(pos)] = v;
    pos = (pos + 1) % size;
    return delayed - g * v;
}

// 2 タップ・クロスフェード式のピッチシフター（+12 半音固定、rate = 2）。
// 窓の両端でゲインが 0 になる sin^2 窓で 2 つの読みを混ぜるのでクリックが出ない
float pitchShiftUpOctave(std::vector<float>& buf, int& pos, float& phase, float x, float window) noexcept {
    const int size = static_cast<int>(buf.size());
    buf[static_cast<size_t>(pos)] = x;
    const float phB = phase + 0.5f < 1.0f ? phase + 0.5f : phase - 0.5f;
    auto tap = [&](float ph) {
        // 位相が進むほど遅延が縮む（= 読みが書き込みに追いつく）ので音程が上がる
        const float delay = (1.0f - ph) * window;
        float rp = static_cast<float>(pos) - delay;
        while (rp < 0.0f)
            rp += static_cast<float>(size);
        const int i0 = static_cast<int>(rp);
        const float frac = rp - static_cast<float>(i0);
        const float a = buf[static_cast<size_t>(i0 % size)];
        const float b = buf[static_cast<size_t>((i0 + 1) % size)];
        const float sn = std::sin(3.14159265f * ph);
        return (a + (b - a) * frac) * sn * sn;
    };
    const float y = tap(phase) + tap(phB);
    phase += 1.0f / window; // rate 2 なら (2-1)/window
    if (phase >= 1.0f)
        phase -= 1.0f;
    pos = (pos + 1) % size;
    return y;
}

// ユニット種別ごとのディレイライン需要（アリーナのセグメント数）
int segmentsFor(FxUnitType type) noexcept {
    switch (type) {
        case FxUnitType::Granular: return 2; // 4 秒
        case FxUnitType::Delay:
        case FxUnitType::Stutter: return 1; // 2 秒
        default: return 0;
    }
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

bool isFxParamId(int paramId) noexcept { return findSpec(paramId) != nullptr; }

bool fxParamUnit(int paramId, FxUnitType& out) noexcept {
    const auto* spec = findSpec(paramId);
    if (spec == nullptr || spec->unit < 0)
        return false;
    out = static_cast<FxUnitType>(spec->unit);
    return true;
}

bool isTrackLevelFxParam(int paramId) noexcept {
    const auto* spec = findSpec(paramId);
    return spec != nullptr && spec->unit < 0;
}

const char* fxUnitTypeKey(FxUnitType type) noexcept {
    switch (type) {
        case FxUnitType::LowCut: return "lowcut";
        case FxUnitType::Eq: return "eq";
        case FxUnitType::Saturation: return "saturation";
        case FxUnitType::Chorus: return "chorus";
        case FxUnitType::Comp: return "comp";
        case FxUnitType::Ott: return "ott";
        case FxUnitType::Bitcrush: return "bitcrush";
        case FxUnitType::Stutter: return "stutter";
        case FxUnitType::Granular: return "granular";
        case FxUnitType::Delay: return "delay";
        case FxUnitType::Reverb: return "reverb";
        case FxUnitType::Shimmer: return "shimmer";
        case FxUnitType::Tape: return "tape";
    }
    return "lowcut";
}

bool fxUnitTypeFromKey(const char* key, FxUnitType& out) noexcept {
    if (key == nullptr)
        return false;
    for (int i = 0; i < kNumFxUnitTypes; ++i) {
        const auto t = static_cast<FxUnitType>(i);
        if (std::strcmp(key, fxUnitTypeKey(t)) == 0) {
            out = t;
            return true;
        }
    }
    return false;
}

bool fxStageAffectsSound(FxUnitType type, const FxParams& p) noexcept {
    switch (type) {
        case FxUnitType::LowCut: return p.lowCutHz > 20.0f;
        case FxUnitType::Eq: return p.eqLowDb != 0.0f || p.eqMidDb != 0.0f || p.eqHighDb != 0.0f;
        case FxUnitType::Saturation: return p.saturation > 0.0f;
        case FxUnitType::Chorus: return p.chorus > 0.0f;
        case FxUnitType::Comp: return p.comp > 0.0f;
        case FxUnitType::Ott: return p.ott > 0.0f;
        case FxUnitType::Bitcrush: return p.bitcrush > 0.0f;
        case FxUnitType::Stutter: return p.stutter > 0.0f;
        case FxUnitType::Granular: return p.granular > 0.0f;
        case FxUnitType::Delay: return p.delay > 0.0f;
        case FxUnitType::Reverb: return p.reverb > 0.0f;
        case FxUnitType::Shimmer: return p.shimmer > 0.0f;
        case FxUnitType::Tape: return p.tape > 0.0f;
    }
    return false;
}

FxUnit makeFxUnit(FxUnitType type, const FxParams& flatSource) {
    FxUnit u;
    u.type = type;
    u.enabled = true;
    for (const auto& s : kFxParamSpecs)
        if (s.unit == unitOf(type))
            u.params.*(s.member) = flatSource.*(s.member);
    return u;
}

FxChainState defaultFxChain(const FxParams& flat, bool forceEnabled) {
    FxChainState c;
    for (int i = 0; i < kNumFxUnitTypes && c.count < kMaxFxUnits; ++i) {
        const auto type = static_cast<FxUnitType>(i);
        FxUnit u = makeFxUnit(type, flat);
        u.enabled = forceEnabled || fxStageAffectsSound(type, flat);
        c.units[static_cast<size_t>(c.count++)] = u;
    }
    return c;
}

std::vector<FxUnit> fxChainToVector(const FxChainState& chain) {
    std::vector<FxUnit> v;
    for (int i = 0; i < chain.count; ++i)
        v.push_back(chain.units[static_cast<size_t>(i)]);
    return v;
}

FxChainState fxChainFromVector(const std::vector<FxUnit>& units) {
    FxChainState c;
    c.count = static_cast<int>(std::min(units.size(), static_cast<size_t>(kMaxFxUnits)));
    for (int i = 0; i < c.count; ++i)
        c.units[static_cast<size_t>(i)] = units[static_cast<size_t>(i)];
    return c;
}

void mergeChainIntoFlat(FxParams& flat, const std::vector<FxUnit>& chain) {
    for (const auto& s : kFxParamSpecs) {
        if (s.unit < 0)
            continue;
        for (const auto& u : chain) {
            if (static_cast<int>(u.type) == s.unit) {
                flat.*(s.member) = u.params.*(s.member);
                break;
            }
        }
    }
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
void TrackFx::UnitState::resetDsp() noexcept {
    lowCutL.reset();
    lowCutR.reset();
    for (Biquad* b : {&eqLowL, &eqLowR, &eqMidL, &eqMidR, &eqHighL, &eqHighR})
        b->reset();
    compEnv = 0.0f;
    crushHold = 0;
    crushL = crushR = 0.0f;
    ott.reset();
    std::fill(chorusL.begin(), chorusL.end(), 0.0f);
    std::fill(chorusR.begin(), chorusR.end(), 0.0f);
    chorusPos = 0;
    chorusPhase = 0.0f;
    stutterPos = 0;
    stutterClock = 0;
    for (auto& g : grains)
        g = Grain{};
    grainWrite = 0;
    grainSpawn = 0.0f;
    grainRng = 0x9E3779B9u; // 種を戻してレンダーを再現可能に保つ
    prevWetL = prevWetR = 0.0f;
    freezeLp = 0.0f;
    fbHpL = fbHpR = 0.0f;
    grainNorm = 1.0f;
    roamPhase = 0.0;
    for (int k = 0; k < 4; ++k) {
        std::fill(diffL[k].begin(), diffL[k].end(), 0.0f);
        std::fill(diffR[k].begin(), diffR[k].end(), 0.0f);
        diffPosL[k] = diffPosR[k] = 0;
    }
    std::fill(shimPrevL.begin(), shimPrevL.end(), 0.0f);
    std::fill(shimPrevR.begin(), shimPrevR.end(), 0.0f);
    std::fill(shimInL.begin(), shimInL.end(), 0.0f);
    std::fill(shimInR.begin(), shimInR.end(), 0.0f);
    std::fill(shimBufL.begin(), shimBufL.end(), 0.0f);
    std::fill(shimBufR.begin(), shimBufR.end(), 0.0f);
    shimPos = shimPosR = 0;
    shimPhase = shimPhaseR = 0.0f;
    shimLpL = shimLpR = 0.0f;
    shimHpL = shimHpR = 0.0f;
    tapeWowPhase = 0.0f;
    tapeDriftPhase = 0.0f;
    tapeEnv = 0.0f;
    tapeLpL = tapeLpR = 0.0f;
    tapeRng = 0x2545F491u;
    delayPos = 0;
    delayLpL = delayLpR = 0.0f;
    reverb.reset();
}

void TrackFx::prepare(double sampleRate, int maxBlock) {
    sampleRate_ = sampleRate;
    segLen_ = static_cast<int>(sampleRate * 2.0) + 4;
    arenaL_.assign(static_cast<size_t>(kArenaSegments) * static_cast<size_t>(segLen_), 0.0f);
    arenaR_.assign(arenaL_.size(), 0.0f);
    // ディフューザーの遅延（Clouds の 32k 値を 48k 換算した解析レポート §2.3 の値。
    // サンプルレート比で拡縮する。値は grain_engine.h の共有定数）
    static constexpr const int* kDiffL = kGrainDiffuserDelaysL;
    static constexpr const int* kDiffR = kGrainDiffuserDelaysR;
    const double diffScale = sampleRate / 48000.0;
    for (auto& s : slots_) {
        s.chorusL.assign(static_cast<size_t>(sampleRate * 0.05) + 4, 0.0f);
        s.chorusR.assign(s.chorusL.size(), 0.0f);
        s.wetL.assign(static_cast<size_t>(std::max(maxBlock, 1)), 0.0f);
        s.wetR.assign(s.wetL.size(), 0.0f);
        for (int k = 0; k < 4; ++k) {
            s.diffL[k].assign(static_cast<size_t>(std::max(8, static_cast<int>(kDiffL[k] * diffScale))), 0.0f);
            s.diffR[k].assign(static_cast<size_t>(std::max(8, static_cast<int>(kDiffR[k] * diffScale))), 0.0f);
        }
        s.shimPrevL.assign(static_cast<size_t>(std::max(maxBlock, 1)), 0.0f);
        s.shimPrevR.assign(s.shimPrevL.size(), 0.0f);
        s.shimInL.assign(s.shimPrevL.size(), 0.0f);
        s.shimInR.assign(s.shimPrevL.size(), 0.0f);
        s.shimBufL.assign(8192, 0.0f);
        s.shimBufR.assign(8192, 0.0f);
        s.ott.prepare(sampleRate);
        s.reverb.setSampleRate(sampleRate);
        s.assigned = false;
        s.segStart = -1;
        s.segCount = 0;
    }
    if (chain_.count == 0)
        chain_ = defaultFxChain(trackLevel_, true);
    setChain(chain_, trackLevel_);
    reset();
}

void TrackFx::resetSlot(int i) noexcept {
    auto& s = slots_[static_cast<size_t>(i)];
    s.resetDsp();
    if (s.segStart >= 0 && s.segCount > 0) {
        const size_t begin = static_cast<size_t>(s.segStart) * static_cast<size_t>(segLen_);
        const size_t len = static_cast<size_t>(s.segCount) * static_cast<size_t>(segLen_);
        std::fill(arenaL_.begin() + static_cast<std::ptrdiff_t>(begin),
                  arenaL_.begin() + static_cast<std::ptrdiff_t>(begin + len), 0.0f);
        std::fill(arenaR_.begin() + static_cast<std::ptrdiff_t>(begin),
                  arenaR_.begin() + static_cast<std::ptrdiff_t>(begin + len), 0.0f);
    }
}

void TrackFx::reset() noexcept {
    for (int i = 0; i < kMaxFxUnits; ++i)
        resetSlot(i);
}

void TrackFx::applyUnitParams(UnitState& s, const FxParams& p) noexcept {
    // 係数をパラメータから作り直す段だけ（他段は処理時にパラメータを直接読む）
    switch (s.type) {
        case FxUnitType::LowCut:
            s.lowCutL.set(p.lowCutHz, 0.7071f, sampleRate_);
            s.lowCutR.set(p.lowCutHz, 0.7071f, sampleRate_);
            break;
        case FxUnitType::Eq:
            setLowShelf(s.eqLowL, p.eqLowHz, p.eqLowDb, sampleRate_);
            setLowShelf(s.eqLowR, p.eqLowHz, p.eqLowDb, sampleRate_);
            setPeak(s.eqMidL, p.eqMidHz, p.eqMidDb, p.eqMidQ, sampleRate_);
            setPeak(s.eqMidR, p.eqMidHz, p.eqMidDb, p.eqMidQ, sampleRate_);
            setHighShelf(s.eqHighL, p.eqHighHz, p.eqHighDb, sampleRate_);
            setHighShelf(s.eqHighR, p.eqHighHz, p.eqHighDb, sampleRate_);
            break;
        case FxUnitType::Reverb: {
            juce::Reverb::Parameters rp;
            rp.roomSize = 0.45f + 0.53f * p.reverbSize;
            rp.damping = 0.45f;
            rp.wetLevel = 1.0f;
            rp.dryLevel = 0.0f;
            rp.width = 1.0f;
            rp.freezeMode = 0.0f;
            s.reverb.setParameters(rp);
            break;
        }
        case FxUnitType::Shimmer: {
            // リバーブ本体は Reverb ユニットと同じ作り。大きさは shimmerSize で決める
            juce::Reverb::Parameters rp;
            rp.roomSize = 0.45f + 0.53f * p.shimmerSize;
            rp.damping = 0.4f;
            rp.wetLevel = 1.0f;
            rp.dryLevel = 0.0f;
            rp.width = 1.0f;
            rp.freezeMode = 0.0f;
            s.reverb.setParameters(rp);
            break;
        }
        default:
            break;
    }
}

void TrackFx::setChain(const FxChainState& chain, const FxParams& trackLevel) noexcept {
    trackLevel_ = trackLevel;
    chain_ = chain;
    // アリーナの割り当てはチェーンの種別の並びだけで決める（決定的）。
    // 種別か割り当てが変わったスロットだけ状態をリセットするので、
    // パラメータだけの変更ではディレイラインや粒の状態は残る（従来どおり）。
    int cursor = 0;
    for (int i = 0; i < kMaxFxUnits; ++i) {
        auto& s = slots_[static_cast<size_t>(i)];
        if (i >= chain.count) {
            if (s.assigned) {
                resetSlot(i);
                s.assigned = false;
                s.segStart = -1;
                s.segCount = 0;
                s.bufLen = 0;
            }
            continue;
        }
        const auto type = chain.units[static_cast<size_t>(i)].type;
        const int need = segmentsFor(type);
        int start = -1;
        if (need > 0 && cursor + need <= kArenaSegments) {
            start = cursor;
            cursor += need;
        }
        if (!s.assigned || s.type != type || s.segStart != start) {
            resetSlot(i); // 旧割り当てのラインを消してから差し替える
            s.type = type;
            s.assigned = true;
            s.segStart = start;
            s.segCount = need;
            s.bufLen = type == FxUnitType::Granular ? static_cast<int>(sampleRate_ * 4.0) + 4
                                                    : (need > 0 ? segLen_ : 0);
            resetSlot(i); // 新しい割り当て側も空から始める
        }
        applyUnitParams(s, chain.units[static_cast<size_t>(i)].params);
    }
}

void TrackFx::setParams(const FxParams& params) noexcept {
    setChain(defaultFxChain(params, true), params);
}

void TrackFx::setParam(int paramId, float value) noexcept {
    FxUnitType unit;
    if (fxParamUnit(paramId, unit)) {
        for (int i = 0; i < chain_.count; ++i) {
            auto& u = chain_.units[static_cast<size_t>(i)];
            if (u.type != unit)
                continue;
            if (setFxParam(u.params, paramId, value))
                applyUnitParams(slots_[static_cast<size_t>(i)], u.params);
            return;
        }
        return; // その種別のユニットがチェーンに無いライブ変更は当てる先が無い
    }
    if (isTrackLevelFxParam(paramId))
        setFxParam(trackLevel_, paramId, value);
}

bool TrackFx::setParamAutomated(int paramId, float value) noexcept {
    FxUnitType unit;
    if (fxParamUnit(paramId, unit)) {
        // 仕様: レーンは「そのパラメータを持つ最初の有効ユニット」に当てる
        for (int i = 0; i < chain_.count; ++i) {
            auto& u = chain_.units[static_cast<size_t>(i)];
            if (u.type != unit || !u.enabled)
                continue;
            if (setFxParam(u.params, paramId, value))
                applyUnitParams(slots_[static_cast<size_t>(i)], u.params);
            return true;
        }
        return false;
    }
    if (isTrackLevelFxParam(paramId))
        return setFxParam(trackLevel_, paramId, value);
    return false;
}

float TrackFx::grainRand(UnitState& s) noexcept {
    return grainRandNext(s.grainRng); // 共有ヘッダ（grain_engine.h）。式は従来と同一
}

double TrackFx::tailSeconds() const noexcept {
    // チェーンの実効の尾 = 有効ユニットそれぞれの尾の合計（直列なので足し合わさる）
    double t = 0.05;
    for (int i = 0; i < chain_.count; ++i) {
        const auto& u = chain_.units[static_cast<size_t>(i)];
        if (!u.enabled)
            continue;
        const auto& p = u.params;
        switch (u.type) {
            case FxUnitType::Chorus:
                if (p.chorus > 0.0f)
                    t += 0.1;
                break;
            case FxUnitType::Granular:
                if (p.granular > 0.0f) {
                    t += static_cast<double>(p.granularPositionS) + p.granularSizeMs / 1000.0 + 0.1;
                    if (p.granularFreeze >= 0.5f)
                        t += 5.0; // フリーズ中は粒が回り続ける
                    t += static_cast<double>(p.granularFeedback) * 3.0; // 戻すほど尾が伸びる
                }
                break;
            case FxUnitType::Delay:
                if (p.delay > 0.0f) {
                    static constexpr double kDivBeats[] = {1.0, 0.75, 0.5, 0.25, 4.0};
                    const int divI = std::clamp(static_cast<int>(std::lround(p.delayDiv)), 0, 4);
                    t += kDivBeats[divI] * 60.0 / std::max(tempo_, 20.0) * (1.0 + 12.0 * static_cast<double>(p.delayFeedback));
                }
                break;
            case FxUnitType::Reverb:
                if (p.reverb > 0.0f)
                    t += 1.5 + 4.0 * static_cast<double>(p.reverbSize);
                break;
            case FxUnitType::Shimmer:
                if (p.shimmer > 0.0f)
                    t += 1.5 + 4.0 * static_cast<double>(p.shimmerSize) + 3.0 * static_cast<double>(p.shimmerAmount);
                break;
            case FxUnitType::Tape:
                if (p.tape > 0.0f)
                    t += 0.1;
                break;
            default:
                break;
        }
    }
    return t;
}

void TrackFx::process(float* left, float* right, int n) noexcept {
    for (int i = 0; i < chain_.count; ++i) {
        const auto& u = chain_.units[static_cast<size_t>(i)];
        if (!u.enabled)
            continue;
        processUnit(slots_[static_cast<size_t>(i)], u.type, u.params, left, right, n);
    }
}

void TrackFx::processUnit(UnitState& s, FxUnitType type, const FxParams& p, float* left, float* right, int n) noexcept {
    const auto sr = static_cast<float>(sampleRate_);

    switch (type) {
        case FxUnitType::LowCut: {
            if (p.lowCutHz > 20.5f) {
                float hi = 0.0f;
                for (int i = 0; i < n; ++i) {
                    s.lowCutL.process(left[i], &hi);
                    left[i] = hi;
                    s.lowCutR.process(right[i], &hi);
                    right[i] = hi;
                }
            }
            break;
        }
        case FxUnitType::Eq: {
            if (std::abs(p.eqLowDb) > 0.05f || std::abs(p.eqMidDb) > 0.05f || std::abs(p.eqHighDb) > 0.05f) {
                for (int i = 0; i < n; ++i) {
                    float l = left[i], r = right[i];
                    if (std::abs(p.eqLowDb) > 0.05f) {
                        l = s.eqLowL.process(l);
                        r = s.eqLowR.process(r);
                    }
                    if (std::abs(p.eqMidDb) > 0.05f) {
                        l = s.eqMidL.process(l);
                        r = s.eqMidR.process(r);
                    }
                    if (std::abs(p.eqHighDb) > 0.05f) {
                        l = s.eqHighL.process(l);
                        r = s.eqHighR.process(r);
                    }
                    left[i] = l;
                    right[i] = r;
                }
            }
            break;
        }
        case FxUnitType::Saturation: {
            if (p.saturation > 0.0f) {
                const float g = 1.0f + p.saturation * 8.0f;
                const float makeup = 1.0f / std::tanh(g * 0.35f) * 0.35f; // よくある大きさ（-9 dBFS 付近）を保つ
                for (int i = 0; i < n; ++i) {
                    left[i] = std::tanh(left[i] * g) * makeup;
                    right[i] = std::tanh(right[i] * g) * makeup;
                }
            }
            break;
        }
        case FxUnitType::Chorus: {
            if (p.chorus > 0.0f && !s.chorusL.empty()) {
                // 2本の揺れる遅延を左右に。ゆっくり（0.4Hz）、深め
                const int size = static_cast<int>(s.chorusL.size());
                const float rate = 0.4f / sr;
                const float base = 0.012f * sr, depth = 0.004f * sr;
                const float wet = p.chorus * 0.6f;
                const float dry = 1.0f - p.chorus * 0.25f;
                for (int i = 0; i < n; ++i) {
                    s.chorusL[static_cast<size_t>(s.chorusPos)] = left[i];
                    s.chorusR[static_cast<size_t>(s.chorusPos)] = right[i];
                    const float lfoA = std::sin(6.2831853f * s.chorusPhase);
                    const float lfoB = std::cos(6.2831853f * s.chorusPhase);
                    const float wl = readInterp(s.chorusL.data(), size, s.chorusPos, base + depth * lfoA);
                    const float wr = readInterp(s.chorusR.data(), size, s.chorusPos, base + depth * lfoB);
                    left[i] = left[i] * dry + (wl - 0.3f * wr) * wet;
                    right[i] = right[i] * dry + (wr - 0.3f * wl) * wet;
                    s.chorusPos = (s.chorusPos + 1) % size;
                    s.chorusPhase += rate;
                    if (s.chorusPhase >= 1.0f)
                        s.chorusPhase -= 1.0f;
                }
            }
            break;
        }
        case FxUnitType::Comp: {
            if (p.comp > 0.001f) {
                const float atk = coefFor(std::max(0.0002, static_cast<double>(p.compAttackMs) / 1000.0), sampleRate_);
                const float rel = coefFor(std::max(0.005, static_cast<double>(p.compReleaseMs) / 1000.0), sampleRate_);
                const float thresh = fromDb(p.compThresholdDb);
                const float slope = 1.0f - 1.0f / std::max(p.compRatio, 1.0f);
                const float makeup = fromDb(p.compMakeupDb);
                const float mix = p.comp;
                for (int i = 0; i < n; ++i) {
                    const float peak = std::max(std::abs(left[i]), std::abs(right[i]));
                    const float c = peak > s.compEnv ? atk : rel;
                    s.compEnv = peak + (s.compEnv - peak) * c;
                    float g = 1.0f;
                    if (s.compEnv > thresh && s.compEnv > 1e-8f)
                        g = std::pow(thresh / s.compEnv, slope);
                    const float wet = g * makeup;
                    const float m = (1.0f - mix) + mix * wet;
                    left[i] *= m;
                    right[i] *= m;
                }
            }
            break;
        }
        case FxUnitType::Ott: {
            s.ott.process(left, right, n, p.ott);
            break;
        }
        case FxUnitType::Bitcrush: {
            if (p.bitcrush > 0.001f) {
                const float depth = p.bitcrush;
                const int bits = std::max(4, static_cast<int>(std::lround(16.0f - depth * 12.0f)));
                const int div = 1 + static_cast<int>(depth * 31.0f);
                const float step = 1.0f / static_cast<float>(1 << (bits - 1));
                for (int i = 0; i < n; ++i) {
                    if (s.crushHold == 0) {
                        s.crushL = std::round(left[i] / step) * step;
                        s.crushR = std::round(right[i] / step) * step;
                    }
                    left[i] = left[i] * (1.0f - depth) + s.crushL * depth;
                    right[i] = right[i] * (1.0f - depth) + s.crushR * depth;
                    s.crushHold = (s.crushHold + 1) % div;
                }
            }
            break;
        }
        case FxUnitType::Stutter: {
            float* bufL = lineL(s);
            float* bufR = lineR(s);
            if (p.stutter > 0.001f && bufL != nullptr && bufR != nullptr) {
                static constexpr float kBeats[] = {2.0f, 1.0f, 0.75f, 0.5f, 0.25f};
                const int divI = std::clamp(static_cast<int>(std::lround(p.stutterDiv)), 0, 4);
                const int size = s.bufLen;
                const float beat = static_cast<float>(60.0 / std::max(tempo_, 20.0));
                int len = static_cast<int>(kBeats[divI] * beat * sr);
                len = std::clamp(len, 32, size - 2);
                const float mix = p.stutter;
                const int grain = std::max(8, len / 4); // 区切りの先頭を4回くり返す
                for (int i = 0; i < n; ++i) {
                    bufL[static_cast<size_t>(s.stutterPos)] = left[i];
                    bufR[static_cast<size_t>(s.stutterPos)] = right[i];
                    const int phase = s.stutterClock % len;
                    int read = s.stutterPos - phase + (phase % grain);
                    read %= size;
                    if (read < 0)
                        read += size;
                    const float wl = bufL[static_cast<size_t>(read)];
                    const float wr = bufR[static_cast<size_t>(read)];
                    left[i] = left[i] * (1.0f - mix) + wl * mix;
                    right[i] = right[i] * (1.0f - mix) + wr * mix;
                    s.stutterPos = (s.stutterPos + 1) % size;
                    s.stutterClock = (s.stutterClock + 1) % len;
                }
            }
            break;
        }
        case FxUnitType::Granular: {
            float* bufL = lineL(s);
            float* bufR = lineR(s);
            if (p.granular > 0.001f && bufL != nullptr && bufR != nullptr) {
                // 直近 4 秒のリングから小さな粒を拾い、ピッチや位置をばらして撒き直す。
                // mix が 0 のときはここ自体を通らない（バッファにも書かない完全バイパス）。
                // Phase 2: Clouds／GrainBrick の解析（task35/AMBIENT-GRANULAR-ANALYSIS.md §4）に基づき、
                // 包絡の形（texture）＋後段ディフューザー、確率的な粒発生、長さ・逆再生のランダム化、
                // 位置の自律走査（roam）、保護付きフィードバック、実効粒数ベースの正規化を入れた。
                const int size = s.bufLen;
                const float mix = p.granular;
                const float grainLen = std::max(16.0f, p.granularSizeMs * 0.001f * sr); // 粒の長さ（サンプル）
                const float spawnRate = p.granularDensity / sr;                          // 1 サンプルあたりの発生数
                const double backBase = static_cast<double>(p.granularPositionS * sr);
                const float spraySamples = p.granularSpray * 0.4f * sr; // 最大 ±0.4 秒
                const bool freeze = p.granularFreeze >= 0.5f;
                const float fb = std::clamp(p.granularFeedback, 0.0f, 0.9f);
                // texture: 0〜0.75 が窓の形（windowShape 0〜1）、0.75〜1 がディフューザー量（Clouds と同じ配分）
                const float texture = std::clamp(p.granularTexture, 0.0f, 1.0f);
                const float windowShape = std::min(texture * 1.333f, 1.0f);
                const float diffusionBase = texture > 0.75f ? (texture - 0.75f) * 4.0f : 0.0f;
                const float timingRandom = std::clamp(p.granularTimingRandom, 0.0f, 1.0f);
                const float sizeRandom = std::clamp(p.granularSizeRandom, 0.0f, 1.0f);
                const float reverseChance = std::clamp(p.granularReverseChance, 0.0f, 1.0f);
                // フィードバック保護: ハイパスのカットオフ = 20 + 100・fb² Hz（Clouds 式）
                const float fbHpCoef = 1.0f - std::exp(-6.2831853f * (20.0f + 100.0f * fb * fb) / sr);
                const float freezeCoef = 1.0f - std::exp(-1.0f / (0.08f * sr)); // フリーズ量は約 80ms で寄せる
                const float normCoef = coefFor(0.03, sampleRate_);              // 正規化の平滑化（保持係数）
                // 包絡の平均パワー（矩形寄り→三角→ベルの順に変わる）からゲイン補償を出す
                const float envComp = 1.0f / std::sqrt(grainWindowAvgPower(windowShape));
                const double roamRate = static_cast<double>(std::clamp(p.granularRoamSpeed, 0.01f, 0.5f)) / sr;
                const double roamDepth = static_cast<double>(p.granularRoam) * 1.5 * sr; // 最大 ±1.5 秒

                // 包絡: texture の前半は「立った台形 → 三角」、後半は「三角 → Hann ベル」へ連続に変わる
                // （共有ヘッダ grain_engine.h の grainWindow。式は従来と同一）
                auto grainEnv = [&](float phase) noexcept { return grainWindow(phase, windowShape); };

                // 粒を 1 個起こす（周期発生・確率発生で共用。空きが無ければ落とす）
                auto spawnGrain = [&]() noexcept {
                    for (auto& g : s.grains) {
                        if (g.active)
                            continue;
                        const double jitter = static_cast<double>((grainRand(s) * 2.0f - 1.0f) * spraySamples);
                        // roam: 三角波で拾う位置をゆっくり走査する
                        const double tri = 1.0 - 2.0 * std::abs(s.roamPhase - std::floor(s.roamPhase + 0.5));
                        double back = backBase + jitter + tri * roamDepth;
                        back = std::clamp(back, 0.0, static_cast<double>(size - 2));
                        const float st = p.granularPitch + (grainRand(s) * 2.0f - 1.0f) * p.granularPitchSpread;
                        const double rateAbs = std::pow(2.0, static_cast<double>(st) / 12.0);
                        // 粒ごとに長さをばらす（sizeRandom）
                        const float lenFactor = std::max(0.15f, 1.0f + (grainRand(s) * 2.0f - 1.0f) * 0.9f * sizeRandom);
                        const bool rev = reverseChance > 0.0f && grainRand(s) < reverseChance;
                        if (rev) {
                            // 逆再生: 区間の終わりから後ろ向きに読む（未来は読めないので頭で止める）
                            double pos = static_cast<double>(s.grainWrite) - 1.0 - back
                                         + static_cast<double>(grainLen * lenFactor) * rateAbs;
                            const double head = static_cast<double>(s.grainWrite) - 1.0;
                            g.pos = std::min(pos, head);
                            g.rate = -rateAbs;
                        } else {
                            g.pos = static_cast<double>(s.grainWrite) - 1.0 - back;
                            g.rate = rateAbs;
                        }
                        g.phase = 0.0f;
                        g.step = 1.0f / (grainLen * lenFactor);
                        // 粒ごとに少しだけ左右へ散らす（定電力パン）
                        const float pan = (grainRand(s) * 2.0f - 1.0f) * 0.7f;
                        const float ang = (pan + 1.0f) * 0.7853982f;
                        g.panL = std::cos(ang);
                        g.panR = std::sin(ang);
                        g.active = true;
                        break;
                    }
                };

                for (int i = 0; i < n; ++i) {
                    s.freezeLp += ((freeze ? 1.0f : 0.0f) - s.freezeLp) * freezeCoef;
                    s.roamPhase += roamRate;
                    if (s.roamPhase >= 1.0)
                        s.roamPhase -= 1.0;

                    // まず今の音をリングへ。粒はこの少し後ろから拾う。
                    // フリーズ中は書かず（書き込み位置も進めず）、粒だけが凍った素材を回り続ける。
                    // フィードバックは前サンプルの粒出力を、ハイパス＋ソフトリミットを通してから
                    // 入力へ混ぜて書き込む（Clouds 式の保護。fb=0 では従来と完全一致）。
                    // フリーズ中はフィードバックがワンポールで消えていく（凍った素材を書き換えない）。
                    if (!freeze) {
                        const size_t w = static_cast<size_t>(s.grainWrite % size);
                        const float fbGain = fb * (1.0f - s.freezeLp);
                        if (fbGain > 0.0005f) {
                            s.fbHpL += fbHpCoef * (s.prevWetL - s.fbHpL);
                            s.fbHpR += fbHpCoef * (s.prevWetR - s.fbHpR);
                            bufL[w] = left[i] + std::tanh((s.prevWetL - s.fbHpL) * fbGain);
                            bufR[w] = right[i] + std::tanh((s.prevWetR - s.fbHpR) * fbGain);
                        } else {
                            bufL[w] = left[i];
                            bufR[w] = right[i];
                        }
                        ++s.grainWrite;
                    }

                    // 粒の発生: 周期成分（アキュムレータ）と確率成分（ベルヌーイ試行）のブレンド。
                    // timingRandom = 1 で毎サンプルの試行だけになり、発生間隔が非同期になる
                    s.grainSpawn += spawnRate * (1.0f - timingRandom);
                    while (s.grainSpawn >= 1.0f) {
                        s.grainSpawn -= 1.0f;
                        spawnGrain();
                    }
                    if (timingRandom > 0.0f && grainRand(s) < spawnRate * timingRandom)
                        spawnGrain();

                    // 粒の再生と実効粒数の数え上げ（正規化用）
                    float wetL = 0.0f, wetR = 0.0f;
                    int activeCount = 0;
                    for (auto& g : s.grains) {
                        if (!g.active)
                            continue;
                        ++activeCount;
                        const float env = grainEnv(g.phase);
                        const double p0 = std::floor(g.pos);
                        const float frac = static_cast<float>(g.pos - p0);
                        std::int64_t idx = static_cast<std::int64_t>(p0) % size;
                        if (idx < 0)
                            idx += size;
                        const int i0 = static_cast<int>(idx);
                        const int i1 = (i0 + 1) % size;
                        const float gl = bufL[i0] + (bufL[i1] - bufL[i0]) * frac;
                        const float gr = bufR[i0] + (bufR[i1] - bufR[i0]) * frac;
                        wetL += gl * env * g.panL;
                        wetR += gr * env * g.panR;
                        g.pos += g.rate;
                        g.phase += g.step;
                        if (g.phase >= 1.0f)
                            g.active = false;
                    }
                    // 正規化: 実効粒数から 1/√(n−1)（Clouds 式）を平滑化して使う。
                    // 旧来の静的な重なり推定より、密度や粒長を動かしても雲の音量が暴れない
                    const float normTarget = grainNormTarget(activeCount);
                    s.grainNorm = normTarget + (s.grainNorm - normTarget) * normCoef;
                    // 仕上げは Clouds と同じ一律のポストゲイン 1.2（mix は最後のブレンドで効く）
                    const float wetGain = s.grainNorm * envComp * 1.2f;
                    float outL = wetL * wetGain;
                    float outR = wetR * wetGain;
                    // 後段ディフューザー: 粒の出力をオールパス 4 段ずつで時間方向に塗り潰す。
                    // フリーズ中は量が自動で最大側へ寄る（Clouds のリバーブ自動ブーストの代替）
                    const float diffusion = std::clamp(std::max(diffusionBase, s.freezeLp * (0.35f + 0.65f * texture)), 0.0f, 1.0f);
                    if (diffusion > 0.001f) {
                        float dL = outL, dR = outR;
                        for (int k = 0; k < 4; ++k) {
                            dL = allpassProcess(s.diffL[k], s.diffPosL[k], dL, 0.6f);
                            dR = allpassProcess(s.diffR[k], s.diffPosR[k], dR, 0.6f);
                        }
                        outL += (dL - outL) * diffusion;
                        outR += (dR - outR) * diffusion;
                    }
                    s.prevWetL = outL; // フィードバックのタップはユニット自身のウェット出力
                    s.prevWetR = outR;
                    left[i] = left[i] * (1.0f - mix) + outL * mix;
                    right[i] = right[i] * (1.0f - mix) + outR * mix;
                }
            }
            break;
        }
        case FxUnitType::Delay: {
            float* bufL = lineL(s);
            float* bufR = lineR(s);
            if (p.delay > 0.0f && bufL != nullptr && bufR != nullptr) {
                const int size = s.bufLen;
                const float beat = static_cast<float>(60.0 / std::max(tempo_, 20.0));
                // 長さの選択（delayDiv）。既定の付点8分では従来の式と一致する
                static constexpr float kDivBeats[] = {1.0f, 0.75f, 0.5f, 0.25f, 4.0f};
                const int divI = std::clamp(static_cast<int>(std::lround(p.delayDiv)), 0, 4);
                const bool pingpong = p.delayPingpong >= 0.5f;
                const float timeL = std::min(kDivBeats[divI] * beat * sr, static_cast<float>(size - 2));
                // 右は左の 2/3（付点8分→8分）で広げる。ピンポン時は同じ長さで左右を往復させる
                const float timeR = pingpong ? timeL
                                             : std::min(kDivBeats[divI] * (2.0f / 3.0f) * beat * sr,
                                                        static_cast<float>(size - 2));
                const float fb = p.delayFeedback;
                const float lp = 1.0f - std::exp(-6.2831853f * 4500.0f / sr);
                const float hp = 1.0f - std::exp(-6.2831853f * 150.0f / sr);
                for (int i = 0; i < n; ++i) {
                    const float dl = readInterp(bufL, size, s.delayPos, timeL);
                    const float dr = readInterp(bufR, size, s.delayPos, timeR);
                    // 返りは高域を丸め、低域を少し削ってこもらせない
                    s.delayLpL += (dl - s.delayLpL) * lp;
                    s.delayLpR += (dr - s.delayLpR) * lp;
                    const float fl = s.delayLpL - s.delayLpL * hp * 0.5f;
                    const float fr = s.delayLpR - s.delayLpR * hp * 0.5f;
                    if (pingpong) {
                        // 返りを交差させ、読み出しも左右を入れ替える（左の音が右へ跳ねて戻る）
                        bufL[static_cast<size_t>(s.delayPos)] = left[i] + fr * fb;
                        bufR[static_cast<size_t>(s.delayPos)] = right[i] + fl * fb;
                        left[i] += dr * p.delay * 0.7f;
                        right[i] += dl * p.delay * 0.7f;
                    } else {
                        bufL[static_cast<size_t>(s.delayPos)] = left[i] + fl * fb;
                        bufR[static_cast<size_t>(s.delayPos)] = right[i] + fr * fb;
                        left[i] += dl * p.delay * 0.7f;
                        right[i] += dr * p.delay * 0.7f;
                    }
                    s.delayPos = (s.delayPos + 1) % size;
                }
            }
            break;
        }
        case FxUnitType::Reverb: {
            if (p.reverb > 0.0f) {
                const int m = std::min(n, static_cast<int>(s.wetL.size()));
                std::copy(left, left + m, s.wetL.begin());
                std::copy(right, right + m, s.wetR.begin());
                s.reverb.processStereo(s.wetL.data(), s.wetR.data(), m);
                const float wet = p.reverb * 0.6f;
                const float dry = 1.0f - p.reverb * 0.3f;
                for (int i = 0; i < m; ++i) {
                    left[i] = left[i] * dry + s.wetL[static_cast<size_t>(i)] * wet;
                    right[i] = right[i] * dry + s.wetR[static_cast<size_t>(i)] * wet;
                }
            }
            break;
        }
        case FxUnitType::Shimmer: {
            if (p.shimmer > 0.0f && !s.shimPrevL.empty()) {
                // リバーブの出力（前ブロック）を +12 半音シフトしてトーンを通し、
                // リバーブ入力へ戻す。戻すほど尾がオクターブ上のきらめきを帯びて伸びる。
                // 戻しは 1 ブロック遅れるが、残響の尾では知覚できない（ブロック単位の割り切り）。
                const int m = std::min(n, static_cast<int>(s.shimPrevL.size()));
                const float window = std::clamp(sr * 0.04f, 256.0f, 4096.0f); // シフターの窓（約 40ms）
                // トーン: 0 で暗く（700Hz）、1 で明るく（12kHz）まで対数で開く
                const float toneHz = 700.0f * std::pow(12000.0f / 700.0f, std::clamp(p.shimmerTone, 0.0f, 1.0f));
                const float lpCoef = 1.0f - std::exp(-6.2831853f * toneHz / sr);
                const float amount = std::clamp(p.shimmerAmount, 0.0f, 1.0f);
                // 戻しのゲイン: 基本は amount × 0.55。前ブロックの残響が大きいときは
                // その分だけ戻しを引く（ループ内リミッター）。リバーブ自体のゲインが
                // 周波数によっては 1 を超えるため、これが無いと自己持続してしまう
                float prevPeak = 0.0f;
                for (int i = 0; i < m; ++i) {
                    prevPeak = std::max(prevPeak, std::abs(s.shimPrevL[static_cast<size_t>(i)]));
                    prevPeak = std::max(prevPeak, std::abs(s.shimPrevR[static_cast<size_t>(i)]));
                }
                const float loopGain = amount * 0.75f * (prevPeak > 0.6f ? 0.6f / prevPeak : 1.0f);
                // 戻し経路のハイパス（約 120Hz）: リバーブのコームは DC を大きく増幅する
                // ため、これが無いと有限長の音の DC 成分がラッチして鳴り止まなくなる
                const float hpCoef = 1.0f - std::exp(-6.2831853f * 120.0f / sr);
                for (int i = 0; i < m; ++i) {
                    const float shL = pitchShiftUpOctave(s.shimBufL, s.shimPos, s.shimPhase, s.shimPrevL[static_cast<size_t>(i)], window);
                    const float shR = pitchShiftUpOctave(s.shimBufR, s.shimPosR, s.shimPhaseR, s.shimPrevR[static_cast<size_t>(i)], window);
                    s.shimLpL += (shL - s.shimLpL) * lpCoef;
                    s.shimLpR += (shR - s.shimLpR) * lpCoef;
                    s.shimHpL += (s.shimLpL - s.shimHpL) * hpCoef;
                    s.shimHpR += (s.shimLpR - s.shimHpR) * hpCoef;
                    // ソフトリミットは暴走防止で、小さい信号ではほぼ素通し
                    s.shimInL[static_cast<size_t>(i)] = left[i] + std::tanh((s.shimLpL - s.shimHpL) * loopGain);
                    s.shimInR[static_cast<size_t>(i)] = right[i] + std::tanh((s.shimLpR - s.shimHpR) * loopGain);
                }
                s.reverb.processStereo(s.shimInL.data(), s.shimInR.data(), m);
                // 今回のウェットを次ブロックの戻し用に控える（processStereo は入力を上書きする）
                std::copy(s.shimInL.begin(), s.shimInL.begin() + m, s.shimPrevL.begin());
                std::copy(s.shimInR.begin(), s.shimInR.begin() + m, s.shimPrevR.begin());
                const float wet = p.shimmer * 0.6f;
                const float dry = 1.0f - p.shimmer * 0.3f;
                for (int i = 0; i < m; ++i) {
                    left[i] = left[i] * dry + s.shimInL[static_cast<size_t>(i)] * wet;
                    right[i] = right[i] * dry + s.shimInR[static_cast<size_t>(i)] * wet;
                }
            }
            break;
        }
        case FxUnitType::Tape: {
            if (p.tape > 0.001f && !s.chorusL.empty()) {
                // 短い遅延の読み位置をゆっくり揺らしてピッチの揺れ（ワウフラッター）を作り、
                // 飽和とローパスで丸め、入力があるときだけ薄くヒスを足す「テープ劣化」。
                // ディレイラインはコーラス用の chorusL/R（0.05 秒）を流用する。
                const int size = static_cast<int>(s.chorusL.size());
                const float mix = p.tape;
                const float wow = std::clamp(p.tapeWow, 0.0f, 1.0f);
                const float base = 0.016f * sr;                       // 中心の遅延 16ms
                const float wowDepth = wow * 0.010f * sr;             // ワウ（約 0.55Hz）で ±10ms まで
                const float flutDepth = wow * 0.0015f * sr;           // フラッター（約 6.3Hz）で ±1.5ms
                const float driftDepth = wow * 0.005f * sr;           // さらに遅い漂い（約 0.13Hz）
                const float g = 1.0f + std::clamp(p.tapeSat, 0.0f, 1.0f) * 3.0f;
                const float satMakeup = 1.0f / std::tanh(g * 0.35f) * 0.35f; // Saturation 段と同じ音量合わせ
                const float lpCoef = 1.0f - std::exp(-6.2831853f * 5500.0f / sr);
                const float envRel = coefFor(0.25, sampleRate_);
                const float hissAmt = std::clamp(p.tapeHiss, 0.0f, 1.0f) * 0.02f;
                for (int i = 0; i < n; ++i) {
                    s.chorusL[static_cast<size_t>(s.chorusPos)] = left[i];
                    s.chorusR[static_cast<size_t>(s.chorusPos)] = right[i];
                    const float delay = std::clamp(base
                                                       + wowDepth * std::sin(6.2831853f * s.tapeWowPhase)
                                                       + flutDepth * std::sin(6.2831853f * s.tapeWowPhase * 11.0f)
                                                       + driftDepth * std::sin(6.2831853f * s.tapeDriftPhase + 1.7f),
                                                   32.0f, static_cast<float>(size - 2));
                    float wl = readInterp(s.chorusL.data(), size, s.chorusPos, delay);
                    float wr = readInterp(s.chorusR.data(), size, s.chorusPos, delay);
                    wl = std::tanh(wl * g) * satMakeup;
                    wr = std::tanh(wr * g) * satMakeup;
                    s.tapeLpL += (wl - s.tapeLpL) * lpCoef;
                    s.tapeLpR += (wr - s.tapeLpR) * lpCoef;
                    // ヒスのゲート: 入力レベルに追随させる（無音のトラックは静かなまま）
                    const float peak = std::max(std::abs(left[i]), std::abs(right[i]));
                    s.tapeEnv = peak > s.tapeEnv ? peak : peak + (s.tapeEnv - peak) * envRel;
                    float hiss = 0.0f;
                    if (hissAmt > 0.0f) {
                        s.tapeRng ^= s.tapeRng << 13;
                        s.tapeRng ^= s.tapeRng >> 17;
                        s.tapeRng ^= s.tapeRng << 5;
                        const float r = static_cast<float>(s.tapeRng >> 8) * (1.0f / 16777216.0f) * 2.0f - 1.0f;
                        hiss = r * hissAmt * std::min(1.0f, s.tapeEnv * 4.0f) * mix;
                    }
                    left[i] = left[i] * (1.0f - mix) + s.tapeLpL * mix + hiss;
                    right[i] = right[i] * (1.0f - mix) + s.tapeLpR * mix + hiss * 0.9f;
                    s.chorusPos = (s.chorusPos + 1) % size;
                    s.tapeWowPhase += 0.55f / sr;
                    if (s.tapeWowPhase >= 1.0f)
                        s.tapeWowPhase -= 1.0f;
                    s.tapeDriftPhase += 0.13f / sr;
                    if (s.tapeDriftPhase >= 1.0f)
                        s.tapeDriftPhase -= 1.0f;
                }
            }
            break;
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
    // 既定値（gain 3.2 / glue 1 / しきい値 -12 / 比 1.6 / softClip 1 / 天井 0.944）は
    // 以前ハードコードしていた式と同じになる。
    const float preGain = p_.gain;
    const float thresh = p_.thresholdDb;
    const float ratio = std::max(p_.ratio, 1.01f);
    const float ceiling = p_.ceiling;
    const float knee = p_.softClip >= 0.999f ? 0.6f : (0.6f * p_.softClip + (1.0f - p_.softClip));
    const float glueMix = p_.glue;
    const float span = std::max(1.0f - knee, 1e-4f);
    for (int i = 0; i < n; ++i) {
        float l = left[i] * preGain, r = right[i] * preGain;
        const float power = 0.5f * (l * l + r * r);
        const float c = power > glueEnv_ ? glueAttack_ : glueRelease_;
        glueEnv_ = power + (glueEnv_ - power) * c;
        if ((i & 15) == 0) {
            const float db = 10.0f * std::log10(std::max(glueEnv_, 1e-12f));
            glueGain_ = db > thresh ? fromDb((thresh - db) * (1.0f - 1.0f / ratio)) : 1.0f;
        }
        const float g = glueMix >= 0.999f ? glueGain_ : (1.0f + (glueGain_ - 1.0f) * glueMix);
        l *= g;
        r *= g;
        auto clip = [&](float x) {
            const float a = std::abs(x);
            if (a <= knee)
                return x;
            const float over = (a - knee) / span;
            return std::copysign(knee + span * std::tanh(over), x);
        };
        l = clip(l);
        r = clip(r);
        const float peak = std::max(std::abs(l), std::abs(r));
        const float needed = peak > ceiling ? ceiling / peak : 1.0f;
        limGain_ = needed < limGain_ ? needed : needed + (limGain_ - needed) * limRelease_;
        l *= limGain_;
        r *= limGain_;
        left[i] = std::clamp(l, -1.0f, 1.0f);
        right[i] = std::clamp(r, -1.0f, 1.0f);
    }
}

//==============================================================================
void AuxReturn::prepare(double sampleRate, int maxBlock) {
    sampleRate_ = sampleRate;
    delayL_.assign(static_cast<size_t>(sampleRate * 2.0) + 4, 0.0f);
    delayR_.assign(delayL_.size(), 0.0f);
    wetL_.assign(static_cast<size_t>(std::max(maxBlock, 1)), 0.0f);
    wetR_.assign(wetL_.size(), 0.0f);
    reverb_.setSampleRate(sampleRate);
    setParams(p_);
    reset();
}

void AuxReturn::reset() noexcept {
    std::fill(delayL_.begin(), delayL_.end(), 0.0f);
    std::fill(delayR_.begin(), delayR_.end(), 0.0f);
    delayPos_ = 0;
    delayLpL_ = delayLpR_ = 0.0f;
    reverb_.reset();
}

void AuxReturn::setParams(const AuxParams& params) noexcept {
    p_ = params;
    juce::Reverb::Parameters rp;
    rp.roomSize = 0.45f + 0.53f * std::clamp(p_.reverbSize, 0.0f, 1.0f);
    rp.damping = 0.4f;
    rp.wetLevel = 1.0f;
    rp.dryLevel = 0.0f;
    rp.width = 1.0f;
    rp.freezeMode = 0.0f;
    reverb_.setParameters(rp);
}

double AuxReturn::tailSeconds() const noexcept {
    double t = 0.05;
    if (p_.reverbReturn > 0.001f)
        t = std::max(t, 1.5 + 4.0 * p_.reverbSize);
    if (p_.delayReturn > 0.001f)
        t = std::max(t, 0.75 * 60.0 / std::max(tempo_, 20.0) * (1.0 + 12.0 * p_.delayFeedback));
    return t;
}

void AuxReturn::process(const float* revL, const float* revR, const float* dlyL, const float* dlyR, float* outL,
                        float* outR, int n) noexcept {
    const auto sr = static_cast<float>(sampleRate_);
    if (p_.reverbReturn > 0.001f) {
        const int m = std::min(n, static_cast<int>(wetL_.size()));
        std::copy(revL, revL + m, wetL_.begin());
        std::copy(revR, revR + m, wetR_.begin());
        reverb_.processStereo(wetL_.data(), wetR_.data(), m);
        const float g = p_.reverbReturn * 0.6f;
        for (int i = 0; i < m; ++i) {
            outL[i] += wetL_[static_cast<size_t>(i)] * g;
            outR[i] += wetR_[static_cast<size_t>(i)] * g;
        }
    }
    if (p_.delayReturn > 0.001f && !delayL_.empty()) {
        const int size = static_cast<int>(delayL_.size());
        const float beat = static_cast<float>(60.0 / std::max(tempo_, 20.0));
        const float timeL = std::min(0.75f * beat * sr, static_cast<float>(size - 2));
        const float timeR = std::min(0.5f * beat * sr, static_cast<float>(size - 2));
        const float fb = std::clamp(p_.delayFeedback, 0.0f, 0.9f);
        const float lp = 1.0f - std::exp(-6.2831853f * 4500.0f / sr);
        const float wet = p_.delayReturn * 0.7f;
        for (int i = 0; i < n; ++i) {
            const float dl = readInterp(delayL_, delayPos_, timeL);
            const float dr = readInterp(delayR_, delayPos_, timeR);
            delayLpL_ += (dl - delayLpL_) * lp;
            delayLpR_ += (dr - delayLpR_) * lp;
            delayL_[static_cast<size_t>(delayPos_)] = dlyL[i] + delayLpL_ * fb;
            delayR_[static_cast<size_t>(delayPos_)] = dlyR[i] + delayLpR_ * fb;
            outL[i] += dl * wet;
            outR[i] += dr * wet;
            delayPos_ = (delayPos_ + 1) % size;
        }
    }
}

} // namespace mdaw
