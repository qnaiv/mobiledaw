#include "sampler.h"

#include <algorithm>
#include <cmath>

namespace mdaw {

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

void MelodicSampler::setSound(const KitSound* sound, int rootNote, float gain, float start) noexcept {
    rootNote_ = std::clamp(rootNote, 0, 127);
    gain_ = std::clamp(gain, 0.0f, 2.0f);
    start_ = std::clamp(start, 0.0f, 1.0f);
    if (sound == sound_)
        return;
    sound_ = sound;
    for (auto& v : voices_)
        v.note = -1;
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

void MelodicSampler::noteOn(int note, float velocity) noexcept {
    if (sound_ == nullptr || sound_->frames() <= 0 || note < 0 || note > 127)
        return;
    const float vel = std::pow(std::clamp(velocity, 0.0f, 1.0f), 1.2f); // DrumSampler と同じ音量カーブ
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
}

void MelodicSampler::stopAll() noexcept {
    const float step = fadeStepFor(kRetriggerSeconds);
    for (auto& v : voices_)
        if (v.active() && v.fadeStep == 0.0f)
            v.fadeStep = step;
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
}

int MelodicSampler::activeVoices() const noexcept {
    int n = 0;
    for (const auto& v : voices_)
        n += v.active() ? 1 : 0;
    return n;
}

} // namespace mdaw
