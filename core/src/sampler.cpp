#include "sampler.h"

#include <algorithm>
#include <cmath>

#include "mdaw.h"

namespace mdaw {

//==============================================================================
// グラニュラー楽器のパラメータ仕様表（ID・保存キー・範囲・丸めの単一の情報源）

const GranularSamplerParamSpec kGranularSamplerParamSpecs[] = {
    {{MDAW_SAMPLER_GRANULAR, "enabled", 0.0f, 1.0f, true}, &GranularSamplerSettings::enabled},
    {{MDAW_SAMPLER_GRANULAR_SIZE_MS, "sizeMs", 10.0f, 500.0f, false}, &GranularSamplerSettings::sizeMs},
    {{MDAW_SAMPLER_GRANULAR_DENSITY, "density", 1.0f, 80.0f, false}, &GranularSamplerSettings::density},
    {{MDAW_SAMPLER_GRANULAR_POSITION, "position", 0.0f, 1.0f, false}, &GranularSamplerSettings::position},
    {{MDAW_SAMPLER_GRANULAR_SPRAY, "spray", 0.0f, 1.0f, false}, &GranularSamplerSettings::spray},
    {{MDAW_SAMPLER_GRANULAR_TEXTURE, "texture", 0.0f, 1.0f, false}, &GranularSamplerSettings::texture},
    {{MDAW_SAMPLER_GRANULAR_PITCH_SPREAD, "pitchSpread", 0.0f, 12.0f, false}, &GranularSamplerSettings::pitchSpread},
    {{MDAW_SAMPLER_GRANULAR_TIMING_RANDOM, "timingRandom", 0.0f, 1.0f, false}, &GranularSamplerSettings::timingRandom},
    {{MDAW_SAMPLER_GRANULAR_SIZE_RANDOM, "sizeRandom", 0.0f, 1.0f, false}, &GranularSamplerSettings::sizeRandom},
    {{MDAW_SAMPLER_GRANULAR_REVERSE, "reverseChance", 0.0f, 1.0f, false}, &GranularSamplerSettings::reverseChance},
    {{MDAW_SAMPLER_GRANULAR_POSITION_MODE, "positionMode", 0.0f, 2.0f, true}, &GranularSamplerSettings::positionMode},
    {{MDAW_SAMPLER_GRANULAR_ROAM, "roam", 0.0f, 1.0f, false}, &GranularSamplerSettings::roam},
    {{MDAW_SAMPLER_GRANULAR_ROAM_SPEED, "roamSpeed", 0.01f, 0.5f, false}, &GranularSamplerSettings::roamSpeed},
    {{MDAW_SAMPLER_GRANULAR_FEEDBACK, "feedback", 0.0f, 0.9f, false}, &GranularSamplerSettings::feedback},
    {{MDAW_SAMPLER_GRANULAR_FREEZE, "freeze", 0.0f, 1.0f, true}, &GranularSamplerSettings::freeze},
    {{MDAW_SAMPLER_GRANULAR_PITCH_QUANTIZE, "pitchQuantize", 0.0f, 1.0f, true}, &GranularSamplerSettings::pitchQuantize},
    {{MDAW_SAMPLER_GRANULAR_PITCH_DRIFT, "pitchDrift", 0.0f, 6.0f, false}, &GranularSamplerSettings::pitchDrift},
};
const int kNumGranularSamplerParamSpecs = static_cast<int>(std::size(kGranularSamplerParamSpecs));

namespace {
const GranularSamplerParamSpec* findGranularSpec(int id) noexcept {
    for (const auto& s : kGranularSamplerParamSpecs)
        if (s.id == id)
            return &s;
    return nullptr;
}
} // namespace

bool isGranularSamplerParamId(int paramId) noexcept { return findGranularSpec(paramId) != nullptr; }

bool getGranularSamplerParam(const GranularSamplerSettings& g, int paramId, float& out) noexcept {
    const auto* spec = findGranularSpec(paramId);
    if (spec == nullptr)
        return false;
    out = g.*(spec->member);
    return true;
}

bool setGranularSamplerParam(GranularSamplerSettings& g, int paramId, float value) noexcept {
    const auto* spec = findGranularSpec(paramId);
    if (spec == nullptr || !std::isfinite(value))
        return false;
    value = std::clamp(value, spec->min, spec->max);
    if (spec->integer)
        value = std::round(value);
    g.*(spec->member) = value;
    return true;
}

void DrumSampler::setKit(const Kit* kit) noexcept {
    if (kit == kit_)
        return;
    kit_ = kit;
    for (auto& v : voices_)
        v.sound = nullptr;
}

void DrumSampler::choke(int group) noexcept {
    const float step = 1.0f / static_cast<float>(0.005 * sampleRate_);
    for (auto& v : voices_)
        if (v.active() && v.sound->choke == group && v.fadeStep == 0.0f)
            v.fadeStep = step;
}

void DrumSampler::stopAll() noexcept {
    const float step = 1.0f / static_cast<float>(0.005 * sampleRate_);
    for (auto& v : voices_)
        if (v.active() && v.fadeStep == 0.0f)
            v.fadeStep = step;
}

void DrumSampler::noteOn(int note, float velocity) noexcept {
    if (kit_ == nullptr)
        return;
    const float vel = std::pow(std::clamp(velocity, 0.0f, 1.0f), 1.2f);
    for (const auto& s : kit_->sounds) {
        if (s.note != note || s.frames() == 0)
            continue;
        if (s.choke > 0)
            choke(s.choke);
        // 空き → 一番古い音を使う
        Voice* slot = nullptr;
        for (auto& v : voices_)
            if (!v.active()) {
                slot = &v;
                break;
            }
        if (slot == nullptr) {
            slot = &voices_[0];
            for (auto& v : voices_)
                if (v.age < slot->age)
                    slot = &v;
        }
        slot->sound = &s;
        slot->pos = 0.0;
        slot->inc = s.sampleRate / sampleRate_;
        slot->gain = vel * s.gain;
        slot->fade = 1.0f;
        slot->fadeStep = 0.0f;
        slot->age = ++ageCounter_;
    }
}

void DrumSampler::render(float* left, float* right, int numSamples) noexcept {
    for (auto& v : voices_) {
        if (!v.active())
            continue;
        const auto* s = v.sound;
        const float* l = s->left.data();
        const float* r = s->right.empty() ? l : s->right.data();
        const int last = s->frames() - 1;
        for (int i = 0; i < numSamples; ++i) {
            const auto i0 = static_cast<int>(v.pos);
            if (i0 >= last || v.fade <= 0.0f) {
                v.sound = nullptr;
                break;
            }
            const auto frac = static_cast<float>(v.pos - i0);
            const float g = v.gain * v.fade;
            left[i] += (l[i0] + (l[i0 + 1] - l[i0]) * frac) * g;
            right[i] += (r[i0] + (r[i0 + 1] - r[i0]) * frac) * g;
            v.pos += v.inc;
            v.fade -= v.fadeStep;
        }
    }
}

int DrumSampler::activeVoices() const noexcept {
    int n = 0;
    for (const auto& v : voices_)
        n += v.active() ? 1 : 0;
    return n;
}

//==============================================================================
// MelodicSampler

void MelodicSampler::prepare(double sampleRate) {
    sampleRate_ = sampleRate;
    // フィードバック用の素材時間軸バッファ（4 秒分。実際に使う長さは素材ごとに fbLen_）
    fbL_.assign(192000, 0.0f);
    fbR_.assign(192000, 0.0f);
    // 雲のディフューザー（FX グラニュラーと同じ遅延をサンプルレート比で拡縮）
    const double diffScale = sampleRate / 48000.0;
    for (int ci = 0; ci < kClouds; ++ci) {
        auto& c = clouds_[ci];
        for (int k = 0; k < 4; ++k) {
            c.diffL[k].assign(static_cast<size_t>(std::max(8, static_cast<int>(kGrainDiffuserDelaysL[k] * diffScale))), 0.0f);
            c.diffR[k].assign(static_cast<size_t>(std::max(8, static_cast<int>(kGrainDiffuserDelaysR[k] * diffScale))), 0.0f);
            c.diffPosL[k] = c.diffPosR[k] = 0;
        }
    }
}

void MelodicSampler::setSound(const KitSound* sound, int rootNote, float gain, float start) noexcept {
    rootNote_ = std::clamp(rootNote, 0, 127);
    gain_ = std::clamp(gain, 0.0f, 2.0f);
    start_ = std::clamp(start, 0.0f, 1.0f);
    if (sound == sound_)
        return;
    sound_ = sound;
    for (auto& v : voices_)
        v.note = -1;
    // グラニュラーの雲とフィードバックも古い素材のものは捨てる
    for (int ci = 0; ci < kClouds; ++ci)
        clouds_[ci].note = -1;
    fbLen_ = 0;
    if (sound != nullptr && sound->frames() > 0) {
        const auto cap = static_cast<int64_t>(fbL_.size());
        fbLen_ = static_cast<int>(std::min<int64_t>({static_cast<int64_t>(sound->frames()),
                                                     static_cast<int64_t>(4.0 * sound->sampleRate), cap}));
        std::fill(fbL_.begin(), fbL_.begin() + fbLen_, 0.0f);
        std::fill(fbR_.begin(), fbR_.begin() + fbLen_, 0.0f);
    }
}

void MelodicSampler::setGranularSettings(const GranularSamplerSettings& g) noexcept {
    if (g == granular_)
        return;
    const bool wasEnabled = granularEnabled();
    granular_ = g;
    if (wasEnabled && !granularEnabled()) {
        // モードを切ったら雲は短く落とす（クリックを避けて 5ms フェード）
        const float step = fadeStepFor(kRetriggerSeconds);
        for (int ci = 0; ci < kClouds; ++ci) {
            auto& c = clouds_[ci];
            if (c.active() && c.fadeStep == 0.0f)
                c.fadeStep = step;
        }
    }
}

float MelodicSampler::fadeStepFor(double seconds) const noexcept {
    return 1.0f / static_cast<float>(std::max(1.0, seconds * sampleRate_));
}

double MelodicSampler::incrementFor(int note) const noexcept {
    if (sound_ == nullptr || sampleRate_ <= 0.0)
        return 0.0;
    // 基準音程から ±4 オクターブまでに丸める（極端な速さ・遅さで破綻させない）
    const double ratio = std::pow(2.0, std::clamp(note - rootNote_, -48, 48) / 12.0);
    return sound_->sampleRate / sampleRate_ * ratio;
}

MelodicSampler::Voice* MelodicSampler::allocate(int note) noexcept {
    // 同じ音がまだ鳴っていたら先に落とす（連打で重ならないように）
    for (auto& v : voices_)
        if (v.active() && v.note == note && v.fadeStep == 0.0f)
            v.fadeStep = fadeStepFor(kRetriggerSeconds);
    // 空き → 一番古い音を使う（DrumSampler と同じ方針）
    for (auto& v : voices_)
        if (!v.active())
            return &v;
    Voice* slot = &voices_[0];
    for (auto& v : voices_)
        if (v.age < slot->age)
            slot = &v;
    return slot;
}

MelodicSampler::CloudVoice* MelodicSampler::allocateCloud(int note) noexcept {
    // 同じ音の雲がまだ鳴っていたら先に落とす（従来ボイスと同じ方針）
    for (int ci = 0; ci < kClouds; ++ci) {
        auto& c = clouds_[ci];
        if (c.active() && c.note == note && c.fadeStep == 0.0f)
            c.fadeStep = fadeStepFor(kRetriggerSeconds);
    }
    for (int ci = 0; ci < kClouds; ++ci)
        if (!clouds_[ci].active())
            return &clouds_[ci];
    CloudVoice* slot = &clouds_[0];
    for (int ci = 0; ci < kClouds; ++ci)
        if (clouds_[ci].age < slot->age)
            slot = &clouds_[ci];
    return slot;
}

void MelodicSampler::noteOn(int note, float velocity) noexcept {
    if (sound_ == nullptr || sound_->frames() <= 0 || note < 0 || note > 127)
        return;
    const float vel = std::pow(std::clamp(velocity, 0.0f, 1.0f), 1.2f); // DrumSampler と同じ音量カーブ
    if (granularEnabled()) {
        // グラニュラーモード: 素材全体を読み素材に、ノートごとに雲を 1 つ起こす
        CloudVoice* c = allocateCloud(note);
        const double frames = static_cast<double>(sound_->frames() - 1);
        c->note = note;
        c->centre = (granular_.positionMode >= 0.5f && granular_.positionMode < 1.5f)
                        ? songPos_ * frames
                        : static_cast<double>(granular_.position) * frames;
        c->baseRate = incrementFor(note);
        c->gain = vel * sound_->gain * gain_;
        c->fade = 1.0f;
        c->fadeStep = 0.0f;
        for (auto& g : c->grains)
            g.active = false;
        c->spawnAcc = 0.0f;
        c->norm = 1.0f;
        c->roamPhase = 0.0;
        c->driftPhase = 0.37; // ドリフトは roam と位相をずらして始める
        c->freezeLp = 0.0f;
        c->fbHpL = c->fbHpR = 0.0f;
        c->prevWetL = c->prevWetR = 0.0f;
        c->age = ++ageCounter_;
        // 種は発音の並びだけで決める（レンダーを再現可能に保つ）
        c->rng = 0x9E3779B9u ^ static_cast<std::uint32_t>(c->age * 0x85EBCA6Bull);
        if (c->rng == 0)
            c->rng = 0x9E3779B9u;
        return;
    }
    Voice* slot = allocate(note);
    slot->note = note;
    slot->pos = static_cast<double>(start_) * static_cast<double>(sound_->frames() - 1);
    slot->inc = incrementFor(note);
    slot->gain = vel * sound_->gain * gain_;
    slot->fade = 1.0f;
    slot->fadeStep = 0.0f;
    slot->age = ++ageCounter_;
}

void MelodicSampler::noteOff(int note) noexcept {
    const float step = fadeStepFor(kReleaseSeconds);
    for (auto& v : voices_)
        if (v.active() && v.note == note && v.fadeStep == 0.0f)
            v.fadeStep = step;
    const float cloudStep = fadeStepFor(kCloudReleaseSeconds);
    for (int ci = 0; ci < kClouds; ++ci) {
        auto& c = clouds_[ci];
        if (c.active() && c.note == note && c.fadeStep == 0.0f)
            c.fadeStep = cloudStep;
    }
}

void MelodicSampler::stopAll() noexcept {
    const float step = fadeStepFor(kRetriggerSeconds);
    for (auto& v : voices_)
        if (v.active() && v.fadeStep == 0.0f)
            v.fadeStep = step;
    for (int ci = 0; ci < kClouds; ++ci) {
        auto& c = clouds_[ci];
        if (c.active() && c.fadeStep == 0.0f)
            c.fadeStep = step;
    }
}

void MelodicSampler::render(float* left, float* right, int numSamples) noexcept {
    if (sound_ == nullptr)
        return;
    const auto* s = sound_;
    const float* l = s->left.data();
    const float* r = s->right.empty() ? l : s->right.data();
    const int last = s->frames() - 1;
    for (auto& v : voices_) {
        if (!v.active())
            continue;
        for (int i = 0; i < numSamples; ++i) {
            const auto i0 = static_cast<int>(v.pos);
            if (i0 >= last || v.fade <= 0.0f) {
                v.note = -1;
                break;
            }
            const auto frac = static_cast<float>(v.pos - i0);
            const float g = v.gain * v.fade;
            left[i] += (l[i0] + (l[i0 + 1] - l[i0]) * frac) * g;
            right[i] += (r[i0] + (r[i0 + 1] - r[i0]) * frac) * g;
            v.pos += v.inc;
            v.fade -= v.fadeStep;
        }
    }
    renderClouds(left, right, numSamples);
}

int MelodicSampler::activeVoices() const noexcept {
    int n = 0;
    for (const auto& v : voices_)
        n += v.active() ? 1 : 0;
    return n + activeClouds();
}

int MelodicSampler::activeClouds() const noexcept {
    int n = 0;
    for (int ci = 0; ci < kClouds; ++ci)
        n += clouds_[ci].active() ? 1 : 0;
    return n;
}

//==============================================================================
// グラニュラーモードの描画。粒の窓・発生・拡散・正規化は FX グラニュラーと
// 共有（grain_engine.h）で、読み先が「直近のリング」ではなく「素材全体」なのと、
// 読み中心の進み方（positionMode）が違うだけ、という位置づけ。
//   0 = 全体クロール: 中心が素材を実時間で進み、終端で頭へ戻る（進行が残る）
//   1 = 曲位置同期  : 中心 = 曲の再生位置 × 素材の長さ（和声が曲に付いてくる）
//   2 = 狭域ループ  : 中心は position のまま（意図的に静止したテクスチャ用）
// フィードバックは雲の出力を「素材と同じ時間軸」のバッファへ書き戻し、
// 粒が素材 + 戻しとして拾う（素材内循環）。fb=0 では読みも書きもしない。
void MelodicSampler::renderClouds(float* left, float* right, int numSamples) noexcept {
    if (sound_ == nullptr || sound_->frames() <= 1)
        return;
    bool any = false;
    for (int ci = 0; ci < kClouds; ++ci)
        any = any || clouds_[ci].active();
    if (!any)
        return;

    const auto* s = sound_;
    const float* srcL = s->left.data();
    const float* srcR = s->right.empty() ? srcL : s->right.data();
    const int frames = s->frames();
    const double srcRate = s->sampleRate;
    const double outRate = sampleRate_;
    const GranularSamplerSettings& p = granular_;

    const float grainLenBase = std::max(16.0f, p.sizeMs * 0.001f * static_cast<float>(srcRate)); // 粒の長さ（素材フレーム）
    const float spawnRate = p.density / static_cast<float>(outRate); // 1 サンプルあたりの発生数
    const float sprayFrames = p.spray * 0.4f * static_cast<float>(srcRate); // 最大 ±0.4 秒
    const float texture = std::clamp(p.texture, 0.0f, 1.0f);
    const float windowShape = std::min(texture * 1.333f, 1.0f);
    const float diffusionBase = texture > 0.75f ? (texture - 0.75f) * 4.0f : 0.0f;
    const float timingRandom = std::clamp(p.timingRandom, 0.0f, 1.0f);
    const float sizeRandom = std::clamp(p.sizeRandom, 0.0f, 1.0f);
    const float reverseChance = std::clamp(p.reverseChance, 0.0f, 1.0f);
    const float fb = std::clamp(p.feedback, 0.0f, 0.9f);
    const bool freeze = p.freeze >= 0.5f;
    const int mode = static_cast<int>(std::lround(p.positionMode));
    const float fbHpCoef = 1.0f - std::exp(-6.2831853f * (20.0f + 100.0f * fb * fb) / static_cast<float>(outRate));
    const float freezeCoef = 1.0f - std::exp(-1.0f / (0.08f * static_cast<float>(outRate)));
    const float normCoef = static_cast<float>(std::exp(-1.0 / (0.03 * outRate))); // 保持係数（FX の coefFor と同じ）
    const float envComp = 1.0f / std::sqrt(grainWindowAvgPower(windowShape));
    const double centreAdvance = srcRate / outRate; // 実時間で素材を進む量
    const double roamRate = static_cast<double>(std::clamp(p.roamSpeed, 0.01f, 0.5f)) / outRate;
    const double roamDepth = static_cast<double>(p.roam) * 1.5 * srcRate; // 最大 ±1.5 秒
    const double driftRate = static_cast<double>(std::clamp(p.roamSpeed, 0.01f, 0.5f)) * 0.61 / outRate;
    const bool quantize = p.pitchQuantize >= 0.5f;
    // 粒ピッチ量子化の音程セットと重み（オフライン試作 v2 と同じ配分。0 が多め）
    static constexpr float kQuantSteps[10] = {-12, -7, -5, 0, 0, 0, 4, 7, 12, 12};
    static constexpr float kQuantCum[10] = {0.10f, 0.17f, 0.24f, 0.40f, 0.56f, 0.72f, 0.80f, 0.88f, 0.95f, 1.0f};

    for (int ci = 0; ci < kClouds; ++ci) {
        auto& c = clouds_[ci];
        if (!c.active())
            continue;

        // 粒を 1 個起こす（周期発生・確率発生で共用。空きが無ければ落とす）
        auto spawnGrain = [&]() noexcept {
            for (auto& g : c.grains) {
                if (g.active)
                    continue;
                const double jitter = static_cast<double>((grainRandNext(c.rng) * 2.0f - 1.0f) * sprayFrames);
                const double tri = 1.0 - 2.0 * std::abs(c.roamPhase - std::floor(c.roamPhase + 0.5));
                double centre = c.centre + tri * roamDepth + jitter;
                // ピッチ: 量子化ありは音程セットから選び、微細なブレ（±0.15 半音）だけ重ねる。
                // なしは pitchSpread の連続ブレ。どちらにもドリフト（ゆっくりした漂い）が乗る
                const double driftNow = std::sin(c.driftPhase * 6.28318530718) * static_cast<double>(p.pitchDrift);
                float st;
                if (quantize) {
                    const float pick = grainRandNext(c.rng);
                    int qi = 9;
                    for (int k = 0; k < 10; ++k)
                        if (pick < kQuantCum[k]) {
                            qi = k;
                            break;
                        }
                    st = static_cast<float>(static_cast<double>(kQuantSteps[qi]) + driftNow
                                            + (grainRandNext(c.rng) * 2.0f - 1.0f) * 0.15f);
                } else {
                    st = static_cast<float>(driftNow + (grainRandNext(c.rng) * 2.0f - 1.0f) * p.pitchSpread);
                }
                const double rateAbs = c.baseRate * std::pow(2.0, static_cast<double>(st) / 12.0);
                const float lenFactor = std::max(0.15f, 1.0f + (grainRandNext(c.rng) * 2.0f - 1.0f) * 0.9f * sizeRandom);
                const double grainLen = static_cast<double>(grainLenBase * lenFactor); // 素材フレーム
                const bool rev = reverseChance > 0.0f && grainRandNext(c.rng) < reverseChance;
                double pos = rev ? centre + grainLen : centre;
                // 素材の範囲へ畳む（終端をまたぐ粒は頭と地続きに読む）
                pos = std::fmod(pos, static_cast<double>(frames));
                if (pos < 0.0)
                    pos += frames;
                g.pos = pos;
                g.rate = rev ? -rateAbs : rateAbs;
                g.phase = 0.0f;
                g.step = static_cast<float>(rateAbs / std::max(grainLen, 1.0));
                const float pan = (grainRandNext(c.rng) * 2.0f - 1.0f) * 0.7f;
                const float ang = (pan + 1.0f) * 0.7853982f;
                g.panL = std::cos(ang);
                g.panR = std::sin(ang);
                g.active = true;
                break;
            }
        };

        for (int i = 0; i < numSamples; ++i) {
            c.freezeLp += ((freeze ? 1.0f : 0.0f) - c.freezeLp) * freezeCoef;
            c.roamPhase += roamRate;
            if (c.roamPhase >= 1.0)
                c.roamPhase -= 1.0;
            c.driftPhase += driftRate;
            if (c.driftPhase >= 1.0)
                c.driftPhase -= 1.0;

            // 読み中心の進行（フリーズ中は止まる）
            if (!freeze) {
                if (mode == 1) {
                    c.centre = songPos_ * static_cast<double>(frames - 1);
                } else if (mode == 0) {
                    c.centre += centreAdvance;
                    if (c.centre >= frames)
                        c.centre -= frames;
                }
            }

            // 粒の発生: FX と同じ「周期アキュムレータ＋ベルヌーイ試行」のブレンド
            c.spawnAcc += spawnRate * (1.0f - timingRandom);
            while (c.spawnAcc >= 1.0f) {
                c.spawnAcc -= 1.0f;
                spawnGrain();
            }
            if (timingRandom > 0.0f && grainRandNext(c.rng) < spawnRate * timingRandom)
                spawnGrain();

            // 粒の再生と実効粒数の数え上げ
            float wetL = 0.0f, wetR = 0.0f;
            int activeCount = 0;
            const float fbGain = fb * (1.0f - c.freezeLp);
            for (auto& g : c.grains) {
                if (!g.active)
                    continue;
                ++activeCount;
                const float env = grainWindow(g.phase, windowShape);
                const double p0 = std::floor(g.pos);
                const float frac = static_cast<float>(g.pos - p0);
                int i0 = static_cast<int>(p0);
                if (i0 >= frames)
                    i0 -= frames;
                const int i1 = i0 + 1 < frames ? i0 + 1 : 0;
                float gl = srcL[i0] + (srcL[i1] - srcL[i0]) * frac;
                float gr = srcR[i0] + (srcR[i1] - srcR[i0]) * frac;
                if (fbGain > 0.0005f && fbLen_ > 0) {
                    const int fi = i0 % fbLen_;
                    gl += fb * fbL_[static_cast<size_t>(fi)];
                    gr += fb * fbR_[static_cast<size_t>(fi)];
                }
                wetL += gl * env * g.panL;
                wetR += gr * env * g.panR;
                g.pos += g.rate;
                if (g.pos >= frames)
                    g.pos -= frames;
                else if (g.pos < 0.0)
                    g.pos += frames;
                g.phase += g.step;
                if (g.phase >= 1.0f)
                    g.active = false;
            }
            // 正規化と仕上げゲイン（FX と同じ: 1/√(n−1) を平滑化し、包絡補償 × 一律 1.2）
            const float normTarget = grainNormTarget(activeCount);
            c.norm = normTarget + (c.norm - normTarget) * normCoef;
            const float wetGain = c.norm * envComp * 1.2f;
            float outL = wetL * wetGain;
            float outR = wetR * wetGain;
            // 後段ディフューザー（フリーズ中は自動で強まる。FX と同じ配分）
            const float diffusion = std::clamp(std::max(diffusionBase, c.freezeLp * (0.35f + 0.65f * texture)), 0.0f, 1.0f);
            if (diffusion > 0.001f) {
                float dL = outL, dR = outR;
                for (int k = 0; k < 4; ++k) {
                    dL = grainAllpassProcess(c.diffL[k].data(), static_cast<int>(c.diffL[k].size()), c.diffPosL[k], dL, 0.6f);
                    dR = grainAllpassProcess(c.diffR[k].data(), static_cast<int>(c.diffR[k].size()), c.diffPosR[k], dR, 0.6f);
                }
                outL += (dL - outL) * diffusion;
                outR += (dR - outR) * diffusion;
            }
            // フィードバック: 前サンプルの雲の出力を保護（HP＋tanh）して素材の時間軸へ
            // 書き戻す。読み側は fb 倍で拾うので、ループゲインは fb の 1 乗で収まる
            if (fbGain > 0.0005f && fbLen_ > 0) {
                int64_t w = static_cast<int64_t>(std::floor(c.centre)) % fbLen_;
                if (w < 0)
                    w += fbLen_;
                c.fbHpL += fbHpCoef * (c.prevWetL - c.fbHpL);
                c.fbHpR += fbHpCoef * (c.prevWetR - c.fbHpR);
                fbL_[static_cast<size_t>(w)] = std::tanh((c.prevWetL - c.fbHpL) * 1.5f);
                fbR_[static_cast<size_t>(w)] = std::tanh((c.prevWetR - c.fbHpR) * 1.5f);
            }
            const float g2 = c.gain * c.fade;
            c.prevWetL = outL * g2;
            c.prevWetR = outR * g2;
            left[i] += outL * g2;
            right[i] += outR * g2;
            c.fade -= c.fadeStep;
            if (c.fade <= 0.0f) {
                c.note = -1;
                break;
            }
        }
    }
}

} // namespace mdaw
