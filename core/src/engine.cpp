#include "engine.h"

#include "automation.h"
#include "mdaw.h"

#include <algorithm>
#include <cmath>

namespace mdaw {

namespace {

constexpr double kTickEpsilon = 1e-6;

} // namespace

Engine::Engine() = default;

Engine::~Engine() {
    collectRetired();
    delete pending_.exchange(nullptr);
    delete current_;
}

void Engine::prepare(double sampleRate) {
    sampleRate_.store(sampleRate, std::memory_order_relaxed);
    for (auto* b : {&bufL_, &bufR_, &prevL_, &prevR_, &mixL_, &mixR_})
        b->assign(kMaxBlock, 0.0f);
    preview_.prepare(sampleRate, kMaxBlock);
    master_.prepare(sampleRate);
    for (auto& s : slots_) {
        s.synth.prepare(sampleRate, kMaxBlock);
        s.drums.prepare(sampleRate);
        s.sampler.prepare(sampleRate);
        s.fx.prepare(sampleRate, kMaxBlock);
        s.held = {};
        s.tailSamples = 0;
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
        case Event::Type::NoteOn:
            // 試聴：サンプラーのトラックを選んでいればそのサンプラーで、キットならそのキットで、
            // そうでなければ試聴用のシンセで
            if (previewSlot_ >= 0 && slots_[static_cast<size_t>(previewSlot_)].samplerSound != nullptr)
                slots_[static_cast<size_t>(previewSlot_)].sampler.noteOn(e.index, e.value);
            else if (previewSlot_ >= 0 && slots_[static_cast<size_t>(previewSlot_)].kit != nullptr)
                slots_[static_cast<size_t>(previewSlot_)].drums.noteOn(e.index, e.value);
            else
                preview_.noteOn(e.index, e.value);
            break;
        case Event::Type::NoteOff:
            // サンプラーの試聴はリリースで止める（キットはワンショットなので従来どおり何もしない）
            if (previewSlot_ >= 0 && slots_[static_cast<size_t>(previewSlot_)].samplerSound != nullptr)
                slots_[static_cast<size_t>(previewSlot_)].sampler.noteOff(e.index);
            else
                preview_.noteOff(e.index);
            break;
        case Event::Type::AllNotesOff: preview_.allNotesOff(); break;
        case Event::Type::Param:       preview_.setParam(e.index, e.value); break;
        case Event::Type::TrackParam:
            if (e.slot < kMaxSlots) {
                auto& s = slots_[e.slot];
                if (e.index >= MDAW_FX_FIRST) {
                    FxParams f = s.fx.params();
                    if (setFxParam(f, e.index, e.value))
                        s.fx.setParams(f);
                } else {
                    s.synth.setParam(e.index, e.value);
                }
            }
            break;
        case Event::Type::PreviewSlot:
            previewSlot_ = e.index;
            break;
        case Event::Type::Play:
            if (!playing_) {
                playing_ = true;
                // ループの外にいたら頭から
                rewindTo(position_ >= loopStart() && position_ < loopEnd() ? position_ : loopStart());
            }
            break;
        case Event::Type::Stop:
            playing_ = false;
            releaseSequencedNotes();
            rewindTo(loopStart());
            break;
        case Event::Type::Seek: {
            releaseSequencedNotes();
            double t = static_cast<double>(std::max<int64_t>(e.tick, 0));
            const double ls = loopStart(), le = loopEnd();
            if (le > ls && (t < ls || t >= le))
                t = ls + std::fmod(std::max(0.0, t - ls), le - ls);
            rewindTo(t);
            break;
        }
        case Event::Type::SetLoop: {
            if (e.tick2 > e.tick && e.tick >= 0) {
                loopStart_ = e.tick;
                loopEnd_ = e.tick2;
            } else {
                loopStart_ = loopEnd_ = 0;
            }
            // 止まっているときはループの頭へ。再生中は範囲の外にいるときだけ頭へ
            if (!playing_ || position_ < loopStart() || position_ >= loopEnd()) {
                releaseSequencedNotes();
                rewindTo(loopStart());
            }
            break;
        }
    }
}

double Engine::loopStart() const noexcept {
    return loopEnd_ > loopStart_ ? static_cast<double>(loopStart_) : 0.0;
}

double Engine::loopEnd() const noexcept {
    if (loopEnd_ > loopStart_)
        return static_cast<double>(loopEnd_);
    return current_ != nullptr ? static_cast<double>(current_->loopEndTicks) : 0.0;
}

void Engine::rewindTo(double tick) noexcept {
    position_ = tick;
    firedUpTo_ = tick - 0.5; // tick ちょうどのイベントはこれから鳴らす
    cursor_ = current_ != nullptr ? current_->firstEventAfter(firedUpTo_) : 0;
    playheadOut_.store(static_cast<int64_t>(position_), std::memory_order_relaxed);
    // 位置が飛んだら、オートメーションの掛かり具合もその位置に合わせ直す
    if (current_ != nullptr && !current_->automation.empty()) {
        resetAutomatedSlots();
        if (playing_)
            applyAutomation(position_);
    }
}

// オートメーションが付いているスロットだけ、音色・FX・音量をスナップショットの素の値へ戻す
void Engine::resetAutomatedSlots() noexcept {
    if (current_ == nullptr)
        return;
    bool done[kMaxSlots] = {};
    for (const auto& lane : current_->automation) {
        const int i = lane.slot;
        if (i >= kMaxSlots || done[i])
            continue;
        done[i] = true;
        if (i >= static_cast<int>(current_->tracks.size()))
            continue;
        auto& s = slots_[static_cast<size_t>(i)];
        const auto& t = current_->tracks[static_cast<size_t>(i)];
        s.synth.setParams(t.synth);
        s.fx.setParams(t.fx);
        s.autoGain = -1.0f;
    }
}

// tick 時点のオートメーション値を、対象スロットのシンセ／FX／音量へその場で反映する。
// ライブで音色を触る TrackParam と同じ経路（シンセは setParam、FX は丸ごと差し替え）。
// 掛かっていない（最初のポイントより前）レーンは何もしない。素への復帰は resetAutomatedSlots が担う。
void Engine::applyAutomation(double tick) noexcept {
    if (current_ == nullptr)
        return;
    for (const auto& lane : current_->automation) {
        float v = 0.0f;
        if (!lane.valueAt(tick, v) || lane.slot >= kMaxSlots)
            continue;
        auto& s = slots_[lane.slot];
        if (lane.paramId == MDAW_PARAM_TRACK_GAIN) {
            s.autoGain = std::clamp(v, 0.0f, 2.0f);
        } else if (lane.paramId >= MDAW_FX_FIRST) {
            FxParams f = s.fx.params();
            if (setFxParam(f, lane.paramId, v))
                s.fx.setParams(f);
        } else {
            s.synth.setParam(lane.paramId, v);
        }
    }
}

void Engine::releaseSequencedNotes() noexcept {
    for (auto& s : slots_) {
        for (int p = 0; p < 128; ++p)
            if (s.held.has(p)) {
                s.synth.noteOff(p);
                s.sampler.noteOff(p); // 鳴っていない楽器には何もしない
            }
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
    // 古いスナップショットは、スロットが新しいキットを指し直してから返す
    // （返したとたんにコアスレッドが解放して、古いキットの音を読めなくなるため）
    PlaybackSnapshot* old = current_;
    current_ = next;

    // トラックの割り当てと音色
    for (int i = 0; i < kMaxSlots; ++i) {
        auto& s = slots_[static_cast<size_t>(i)];
        const SnapshotTrack* t = i < static_cast<int>(current_->tracks.size()) ? &current_->tracks[static_cast<size_t>(i)] : nullptr;
        const Id id = t != nullptr ? t->id : kNoId;
        if (s.trackId != id) {
            // 別のトラックになった：鳴っている音は離して、音色は丸ごと入れ替える
            for (int p = 0; p < 128; ++p)
                if (s.held.has(p)) {
                    s.synth.noteOff(p);
                    s.sampler.noteOff(p);
                }
            s.held = {};
            s.trackId = id;
            s.fx.reset();
            s.tailSamples = 0;
            if (t != nullptr) {
                s.synth.setParams(t->synth);
                s.snapParams = t->synth;
                s.fx.setParams(t->fx);
                s.snapFx = t->fx;
            }
        } else if (t != nullptr) {
            if (s.snapParams != t->synth) {
                s.synth.setParams(t->synth);
                s.snapParams = t->synth;
            }
            if (s.snapFx != t->fx) {
                s.fx.setParams(t->fx);
                s.snapFx = t->fx;
            }
        }
        s.fx.setTempo(current_->tempo);
        const Kit* kit = t != nullptr ? t->kit.get() : nullptr;
        if (kit != s.kit) {
            s.drums.setKit(kit); // 鳴っていた古いキットの音はここで止まる
            s.kit = kit;
        }
        // サンプラーの素材と設定（素材が差し替わったら鳴っていた音は止まる。設定だけなら鳴らしたまま）
        const KitSound* wantSound = (t != nullptr && t->samplerKit != nullptr && t->samplerSound >= 0
                                     && t->samplerSound < static_cast<int>(t->samplerKit->sounds.size()))
                                        ? &t->samplerKit->sounds[static_cast<size_t>(t->samplerSound)]
                                        : nullptr;
        const SamplerSettings wantSettings = t != nullptr ? t->sampler : SamplerSettings{};
        if (wantSound != s.samplerSound || wantSettings != s.snapSampler) {
            s.sampler.setSound(wantSound, wantSettings.rootNote, wantSettings.gain, wantSettings.start);
            s.samplerSound = wantSound;
            s.snapSampler = wantSettings;
        }
    }

    // オートメーションの状態は新しいスナップショットに合わせ直す（レーンを消す編集でも素に戻るように）
    if ((old != nullptr && !old->automation.empty()) || !current_->automation.empty()) {
        resetAutomatedSlots();
        if (playing_)
            applyAutomation(position_);
    }

    if (old != nullptr)
        retired_.push(old);

    // 曲が短くなって再生位置がはみ出したらループの頭へ
    if (position_ >= loopEnd() || position_ < loopStart()) {
        releaseSequencedNotes();
        rewindTo(loopStart());
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
                    s.sampler.noteOff(p);
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
            if (s.samplerSound != nullptr)
                s.sampler.noteOn(e.pitch, e.velocity);
            else if (s.kit != nullptr)
                s.drums.noteOn(e.pitch, e.velocity);
            else
                s.synth.noteOn(e.pitch, e.velocity);
            s.held.set(e.pitch);
            if (s.fx.params().sidechainSource >= 0.5f)
                sidechainTrigger_ = true;
        } else if (s.held.has(e.pitch)) {
            s.synth.noteOff(e.pitch);
            s.sampler.noteOff(e.pitch); // サンプラーの音はリリースで止める（シンセには何もしない）
            s.held.clear(e.pitch);
        }
    }
    firedUpTo_ = position_ + kTickEpsilon;
}

void Engine::renderSegment(float* out, int n, int channels) noexcept {
    const auto un = static_cast<size_t>(n);
    std::fill(mixL_.begin(), mixL_.begin() + n, 0.0f);
    std::fill(mixR_.begin(), mixR_.begin() + n, 0.0f);
    const double sr = sampleRate();

    // 試聴の音。トラックを選んでいればそのトラックのエフェクトに通す
    const bool previewing = preview_.activeVoices() > 0;
    if (previewing) {
        preview_.setLfoClock(lfoClockPos_, lfoClockInc_);
        preview_.render(prevL_.data(), prevR_.data(), n);
    }
    const bool previewToSlot = previewing && previewSlot_ >= 0;
    if (previewing && !previewToSlot) {
        for (size_t i = 0; i < un; ++i) {
            mixL_[i] += prevL_[i];
            mixR_[i] += prevR_[i];
        }
    }

    // サイドチェイン：キックが鳴った所から数える
    if (sidechainTrigger_) {
        sidechainTrigger_ = false;
        sidechainAge_ = 0;
        for (auto& s : slots_)
            s.duckStart = s.duck;
    }
    const auto attack = static_cast<int64_t>(0.002 * sr);

    // トラックの音量・定位はブロック内で直線的に追従（約10ms）
    const float k = 1.0f - std::exp(-static_cast<float>(n) / static_cast<float>(0.01 * sr));
    for (int si = 0; si < kMaxSlots; ++si) {
        auto& s = slots_[static_cast<size_t>(si)];
        float targetL = 0.0f, targetR = 0.0f;
        if (current_ != nullptr && si < static_cast<int>(current_->tracks.size())) {
            const auto& t = current_->tracks[static_cast<size_t>(si)];
            if (t.audible) {
                const float g = s.autoGain >= 0.0f ? s.autoGain : t.gain; // オートメーション中はそちらが優先
                targetL = g * std::min(1.0f, 1.0f - t.pan);
                targetR = g * std::min(1.0f, 1.0f + t.pan);
            }
        }
        const bool sounding = s.synth.activeVoices() > 0 || s.drums.activeVoices() > 0 || s.sampler.activeVoices() > 0
                              || (previewToSlot && previewSlot_ == si);
        if (sounding)
            s.tailSamples = static_cast<int64_t>(s.fx.tailSeconds() * sr);
        if (!sounding && s.tailSamples <= 0) {
            s.gainL = targetL;
            s.gainR = targetR;
            s.duck = 0.0f;
            continue;
        }
        s.tailSamples -= n;

        s.synth.setLfoClock(lfoClockPos_, lfoClockInc_);
        s.synth.render(bufL_.data(), bufR_.data(), n);
        if (s.drums.activeVoices() > 0)
            s.drums.render(bufL_.data(), bufR_.data(), n);
        if (s.sampler.activeVoices() > 0)
            s.sampler.render(bufL_.data(), bufR_.data(), n);
        if (previewToSlot && previewSlot_ == si) {
            for (size_t i = 0; i < un; ++i) {
                bufL_[i] += prevL_[i];
                bufR_[i] += prevR_[i];
            }
        }
        s.fx.process(bufL_.data(), bufR_.data(), n);

        const float endL = s.gainL + (targetL - s.gainL) * k;
        const float endR = s.gainR + (targetR - s.gainR) * k;
        const float stepL = (endL - s.gainL) / static_cast<float>(n);
        const float stepR = (endR - s.gainR) / static_cast<float>(n);
        float gl = s.gainL, gr = s.gainR;
        const auto& fx = s.fx.params();
        const float depth = fx.sidechainSource >= 0.5f ? 0.0f : fx.sidechain;
        const auto release = static_cast<int64_t>(std::max(0.03f, fx.sidechainReleaseS) * sr);
        for (size_t i = 0; i < un; ++i) {
            float g = 1.0f;
            if (depth > 0.0f) {
                // 2ms で引っ込み、(1-x)^2 の形で戻る（戻り始めが速く、最後はゆっくり）
                const int64_t age = sidechainAge_ + static_cast<int64_t>(i);
                float env = 0.0f;
                if (age < attack)
                    env = s.duckStart + (1.0f - s.duckStart) * static_cast<float>(age) / static_cast<float>(attack);
                else if (age < attack + release) {
                    const float x = 1.0f - static_cast<float>(age - attack) / static_cast<float>(release);
                    env = x * x;
                }
                s.duck = env;
                g = 1.0f - depth * env;
            }
            mixL_[i] += bufL_[i] * gl * g;
            mixR_[i] += bufR_[i] * gr * g;
            gl += stepL;
            gr += stepR;
        }
        s.gainL = endL;
        s.gainR = endR;
    }
    sidechainAge_ = std::min<int64_t>(sidechainAge_ + n, int64_t{1} << 40);

    if (masterEnabled_)
        master_.process(mixL_.data(), mixR_.data(), n);

    for (size_t i = 0; i < un; ++i) {
        const float l = mixL_[i];
        const float r = mixR_[i];
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
    // 先に新しい曲データを受け取り、そのあとで再生操作を反映する（位置の判定に最新の長さを使うため）
    adoptPendingSnapshot();
    Event e;
    while (queue_.pop(e))
        handle(e);

    const double sr = sampleRate();
    int done = 0;
    while (done < frames) {
        int n = std::min(frames - done, kMaxBlock);
        const bool sequencing = playing_ && current_ != nullptr;
        double ticksPerSample = 0.0;
        double loopEnd = 0.0;
        if (sequencing) {
            fireDueEvents();
            // この区間の頭の位置でオートメーションを掛ける（レーンが無ければ何もしない）
            if (!current_->automation.empty())
                applyAutomation(position_);
            ticksPerSample = current_->tempo * static_cast<double>(kPpq) / (60.0 * sr);
            loopEnd = this->loopEnd();
            // 次のイベント（かループの終わり）までで区切る：イベントはサンプル単位で正確に鳴る
            double next = loopEnd;
            if (cursor_ < current_->events.size())
                next = std::min(next, static_cast<double>(current_->events[cursor_].tick));
            // オートメーションのポイントでも区切る（補間がポイント単位で折れるように）
            double nextAuto = 0.0;
            if (current_->nextAutomationTick(position_ + kTickEpsilon, nextAuto))
                next = std::min(next, nextAuto);
            const double until = std::ceil((next - position_) / ticksPerSample - 1e-9);
            n = static_cast<int>(std::clamp(until, 1.0, static_cast<double>(n)));
        }

        // テンポ同期 LFO の時計：再生中は曲位置、止まっている間はテンポで自由進行（試聴でも揺れるように）
        if (sequencing) {
            lfoClockPos_ = position_;
            lfoClockInc_ = ticksPerSample;
        } else {
            const double tempo = current_ != nullptr ? current_->tempo : 120.0;
            lfoClockPos_ = lfoFreePos_;
            lfoClockInc_ = tempo * static_cast<double>(kPpq) / (60.0 * sr);
        }

        renderSegment(interleaved + static_cast<std::ptrdiff_t>(done) * channels, n, channels);

        if (!sequencing)
            lfoFreePos_ += n * lfoClockInc_;
        if (sequencing) {
            position_ += n * ticksPerSample;
            if (position_ >= loopEnd - kTickEpsilon) {
                releaseSequencedNotes();
                rewindTo(loopStart() + std::max(0.0, position_ - loopEnd));
            }
        }
        done += n;
    }

    int voices = preview_.activeVoices();
    for (const auto& s : slots_)
        voices += s.synth.activeVoices() + s.drums.activeVoices() + s.sampler.activeVoices();
    framesRendered_.fetch_add(frames, std::memory_order_relaxed);
    activeVoices_.store(voices, std::memory_order_relaxed);
    playingOut_.store(playing_, std::memory_order_relaxed);
    playheadOut_.store(static_cast<int64_t>(position_), std::memory_order_relaxed);
}

} // namespace mdaw
