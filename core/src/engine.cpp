#include "engine.h"

#include <algorithm>
#include <cmath>

namespace mdaw {

void Engine::prepare(double sampleRate) {
    sampleRate_.store(sampleRate, std::memory_order_relaxed);
    mono_.assign(kMaxBlock, 0.0f);
    synth_.prepare(sampleRate, kMaxBlock);
}

void Engine::handle(const Event& e) noexcept {
    switch (e.type) {
        case Event::Type::NoteOn:      synth_.noteOn(e.index, e.value); break;
        case Event::Type::NoteOff:     synth_.noteOff(e.index); break;
        case Event::Type::AllNotesOff: synth_.allNotesOff(); break;
        case Event::Type::Param:       synth_.setParam(e.index, e.value); break;
    }
}

void Engine::render(float* interleaved, int frames, int channels) noexcept {
    Event e;
    while (queue_.pop(e))
        handle(e);

    int done = 0;
    while (done < frames) {
        const int n = std::min(frames - done, kMaxBlock);
        synth_.render(mono_.data(), n);
        float* out = interleaved + static_cast<std::ptrdiff_t>(done) * channels;
        for (int i = 0; i < n; ++i) {
            // 合計が大きくなりすぎたときだけ柔らかく頭を抑える
            const float s = std::tanh(mono_[static_cast<std::size_t>(i)]);
            for (int c = 0; c < channels; ++c)
                out[i * channels + c] = s;
        }
        done += n;
    }

    framesRendered_.fetch_add(frames, std::memory_order_relaxed);
    activeVoices_.store(synth_.activeVoices(), std::memory_order_relaxed);
}

} // namespace mdaw
