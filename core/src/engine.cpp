#include "engine.h"

#include <algorithm>
#include <cmath>

namespace mdaw {

namespace {

constexpr double kTickEpsilon = 1e-6;

bool sameParams(const SynthParams& a, const SynthParams& b) noexcept {
    return a.cutoffHz == b.cutoffHz && a.resonance == b.resonance && a.attackS == b.attackS && a.decayS == b.decayS &&
           a.sustain == b.sustain && a.releaseS == b.releaseS && a.detuneCents == b.detuneCents &&
           a.masterGain == b.masterGain;
}

} // namespace

Engine::Engine() = default;

Engine::~Engine() {
    collectRetired();
    delete pending_.exchange(nullptr);
    delete current_;
}

void Engine::prepare(double sampleRate) {
    sampleRate_.store(sampleRate, std::memory_order_relaxed);
    mono_.assign(kMaxBlock, 0.0f);
    mixL_.assign(kMaxBlock, 0.0f);
    mixR_.assign(kMaxBlock, 0.0f);
    preview_.prepare(sampleRate, kMaxBlock);
    for (auto& s : slots_) {
        s.synth.prepare(sampleRate, kMaxBlock);
        s.held = {};
    }
}

//==============================================================================
// コアスレッド側

void Engine::publish(std::unique_ptr<PlaybackSnapshot> snapshot) {
    collectRetired();
    if (!snapshot)
        return;
    // 音声スレッドがまだ受け取っていない古いものは、ここで捨ててよい（音声スレッドは一度も見ていない）
    delete pending_.exchange(snapshot.release(), std::memory_order_acq_rel);
}

void Engine::collectRetired() {
    PlaybackSnapshot* old = nullptr;
    while (retired_.pop(old))
        delete old;
}

//==============================================================================
// 音声スレッド側

void Engine::handle(const Event& e) noexcept {
    switch (e.type) {
        case Event::Type::NoteOn:      preview_.noteOn(e.index, e.value); break;
        case Event::Type::NoteOff:     preview_.noteOff(e.index); break;
        case Event::Type::AllNotesOff: preview_.allNotesOff(); break;
        case Event::Type::Param:       preview_.setParam(e.index, e.value); break;
        case Event::Type::TrackParam:
            if (e.slot < kMaxSlots)
                slots_[e.slot].synth.setParam(e.index, e.value);
            break;
        case Event::Type::Play:
            if (!playing_) {
                playing_ = true;
                rewindTo(position_);
            }
            break;
        case Event::Type::Stop:
            playing_ = false;
            releaseSequencedNotes();
            rewindTo(0.0);
            break;
        case Event::Type::Seek: {
            releaseSequencedNotes();
            double t = static_cast<double>(std::max<int64_t>(e.tick, 0));
            if (current_ != nullptr && current_->loopEndTicks > 0)
                t = std::fmod(t, static_cast<double>(current_->loopEndTicks));
            rewindTo(t);
            break;
        }
    }
}

void Engine::rewindTo(double tick) noexcept {
    position_ = tick;
    firedUpTo_ = tick - 0.5; // tick ちょうどのイベントはこれから鳴らす
    cursor_ = current_ != nullptr ? current_->firstEventAfter(firedUpTo_) : 0;
    playheadOut_.store(static_cast<int64_t>(position_), std::memory_order_relaxed);
}

void Engine::releaseSequencedNotes() noexcept {
    for (auto& s : slots_) {
        for (int p = 0; p < 128; ++p)
            if (s.held.has(p))
                s.synth.noteOff(p);
        s.held = {};
    }
}

void Engine::adoptPendingSnapshot() noexcept {
    if (pending_.load(std::memory_order_acquire) == nullptr)
        return;
    // 返却キューが詰まっていたら今回は見送る（音声スレッドでは解放できないため）
    if (current_ != nullptr && !retired_.canPush())
        return;
    auto* next = pending_.exchange(nullptr, std::memory_order_acq_rel);
    if (next == nullptr)
        return;
    if (current_ != nullptr)
        retired_.push(current_);
    current_ = next;

    // トラックの割り当てと音色
    for (int i = 0; i < kMaxSlots; ++i) {
        auto& s = slots_[static_cast<size_t>(i)];
        const SnapshotTrack* t = i < static_cast<int>(current_->tracks.size()) ? &current_->tracks[static_cast<size_t>(i)] : nullptr;
        const Id id = t != nullptr ? t->id : kNoId;
        if (s.trackId != id) {
            // 別のトラックになった：鳴っている音は離して、音色は丸ごと入れ替える
            for (int p = 0; p < 128; ++p)
                if (s.held.has(p))
                    s.synth.noteOff(p);
            s.held = {};
            s.trackId = id;
            if (t != nullptr) {
                s.synth.setParams(t->synth);
                s.snapParams = t->synth;
            }
        } else if (t != nullptr && !sameParams(s.snapParams, t->synth)) {
            s.synth.setParams(t->synth);
            s.snapParams = t->synth;
        }
    }

    // 曲が短くなって再生位置がはみ出したら頭へ
    const double loopEnd = static_cast<double>(current_->loopEndTicks);
    if (position_ >= loopEnd) {
        releaseSequencedNotes();
        rewindTo(0.0);
    } else {
        cursor_ = current_->firstEventAfter(firedUpTo_);
    }

    // 消された・動かされたノートが鳴りっぱなしにならないよう、今鳴っているべきでない音を離す
    if (playing_) {
        PlaybackSnapshot::NoteSet should[kMaxSlots];
        current_->soundingAt(firedUpTo_, should, kMaxSlots);
        for (int i = 0; i < kMaxSlots; ++i) {
            auto& s = slots_[static_cast<size_t>(i)];
            for (int p = 0; p < 128; ++p) {
                if (s.held.has(p) && !should[i].has(p)) {
                    s.synth.noteOff(p);
                    s.held.clear(p);
                }
            }
        }
    }
}

void Engine::fireDueEvents() noexcept {
    const auto& events = current_->events;
    while (cursor_ < events.size() && static_cast<double>(events[cursor_].tick) <= position_ + kTickEpsilon) {
        const auto& e = events[cursor_++];
        if (e.slot >= kMaxSlots)
            continue;
        auto& s = slots_[e.slot];
        if (e.type == SeqEvent::Type::NoteOn) {
            s.synth.noteOn(e.pitch, e.velocity);
            s.held.set(e.pitch);
        } else if (s.held.has(e.pitch)) {
            s.synth.noteOff(e.pitch);
            s.held.clear(e.pitch);
        }
    }
    firedUpTo_ = position_ + kTickEpsilon;
}

void Engine::renderSegment(float* out, int n, int channels) noexcept {
    std::fill(mixL_.begin(), mixL_.begin() + n, 0.0f);
    std::fill(mixR_.begin(), mixR_.begin() + n, 0.0f);

    preview_.render(mono_.data(), n);
    for (int i = 0; i < n; ++i) {
        mixL_[static_cast<size_t>(i)] += mono_[static_cast<size_t>(i)];
        mixR_[static_cast<size_t>(i)] += mono_[static_cast<size_t>(i)];
    }

    // トラックの音量・定位はブロック内で直線的に追従（約10ms）
    const float k = 1.0f - std::exp(-static_cast<float>(n) / static_cast<float>(0.01 * sampleRate()));
    for (int si = 0; si < kMaxSlots; ++si) {
        auto& s = slots_[static_cast<size_t>(si)];
        float targetL = 0.0f, targetR = 0.0f;
        if (current_ != nullptr && si < static_cast<int>(current_->tracks.size())) {
            const auto& t = current_->tracks[static_cast<size_t>(si)];
            if (t.audible) {
                targetL = t.gain * std::min(1.0f, 1.0f - t.pan);
                targetR = t.gain * std::min(1.0f, 1.0f + t.pan);
            }
        }
        if (s.synth.activeVoices() == 0) {
            s.gainL = targetL;
            s.gainR = targetR;
            continue;
        }
        s.synth.render(mono_.data(), n);
        const float endL = s.gainL + (targetL - s.gainL) * k;
        const float endR = s.gainR + (targetR - s.gainR) * k;
        const float stepL = (endL - s.gainL) / static_cast<float>(n);
        const float stepR = (endR - s.gainR) / static_cast<float>(n);
        float gl = s.gainL, gr = s.gainR;
        for (int i = 0; i < n; ++i) {
            const float v = mono_[static_cast<size_t>(i)];
            mixL_[static_cast<size_t>(i)] += v * gl;
            mixR_[static_cast<size_t>(i)] += v * gr;
            gl += stepL;
            gr += stepR;
        }
        s.gainL = endL;
        s.gainR = endR;
    }

    for (int i = 0; i < n; ++i) {
        // 合計が大きくなりすぎたときだけ柔らかく頭を抑える
        const float l = std::tanh(mixL_[static_cast<size_t>(i)]);
        const float r = std::tanh(mixR_[static_cast<size_t>(i)]);
        float* frame = out + static_cast<std::ptrdiff_t>(i) * channels;
        if (channels == 1) {
            frame[0] = 0.5f * (l + r);
            continue;
        }
        frame[0] = l;
        frame[1] = r;
        for (int c = 2; c < channels; ++c)
            frame[c] = 0.5f * (l + r);
    }
}

void Engine::render(float* interleaved, int frames, int channels) noexcept {
    Event e;
    while (queue_.pop(e))
        handle(e);
    adoptPendingSnapshot();

    const double sr = sampleRate();
    int done = 0;
    while (done < frames) {
        int n = std::min(frames - done, kMaxBlock);
        const bool sequencing = playing_ && current_ != nullptr;
        double ticksPerSample = 0.0;
        double loopEnd = 0.0;
        if (sequencing) {
            fireDueEvents();
            ticksPerSample = current_->tempo * static_cast<double>(kPpq) / (60.0 * sr);
            loopEnd = static_cast<double>(current_->loopEndTicks);
            // 次のイベント（かループの終わり）までで区切る：イベントはサンプル単位で正確に鳴る
            double next = loopEnd;
            if (cursor_ < current_->events.size())
                next = std::min(next, static_cast<double>(current_->events[cursor_].tick));
            const double until = std::ceil((next - position_) / ticksPerSample - 1e-9);
            n = static_cast<int>(std::clamp(until, 1.0, static_cast<double>(n)));
        }

        renderSegment(interleaved + static_cast<std::ptrdiff_t>(done) * channels, n, channels);

        if (sequencing) {
            position_ += n * ticksPerSample;
            if (position_ >= loopEnd - kTickEpsilon) {
                releaseSequencedNotes();
                rewindTo(std::max(0.0, position_ - loopEnd));
            }
        }
        done += n;
    }

    int voices = preview_.activeVoices();
    for (const auto& s : slots_)
        voices += s.synth.activeVoices();
    framesRendered_.fetch_add(frames, std::memory_order_relaxed);
    activeVoices_.store(voices, std::memory_order_relaxed);
    playingOut_.store(playing_, std::memory_order_relaxed);
    playheadOut_.store(static_cast<int64_t>(position_), std::memory_order_relaxed);
}

} // namespace mdaw
