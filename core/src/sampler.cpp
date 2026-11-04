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

} // namespace mdaw
