#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

#include "spsc_queue.h"
#include "synth.h"

namespace mdaw {

struct Event {
    enum class Type : uint8_t { NoteOn, NoteOff, AllNotesOff, Param };
    Type type = Type::NoteOn;
    int16_t index = 0; // ノート番号 or パラメータID
    float value = 0.0f;
};

// 音声スレッド側の本体。UIスレッドからは noteOn などでキューに積み、
// 音声スレッドが render() の頭で取り出して反映する。
class Engine {
public:
    static constexpr int kMaxBlock = 1024;

    // 音声スレッドが止まっている間に呼ぶ（確保あり）
    void prepare(double sampleRate);

    // 音声スレッドから呼ぶ（確保・ロックなし）。interleaved に frames × channels を上書きする。
    void render(float* interleaved, int frames, int channels) noexcept;

    // UIスレッドから呼ぶ
    bool noteOn(int note, float velocity) noexcept { return queue_.push({Event::Type::NoteOn, (int16_t) note, velocity}); }
    bool noteOff(int note) noexcept { return queue_.push({Event::Type::NoteOff, (int16_t) note, 0.0f}); }
    bool allNotesOff() noexcept { return queue_.push({Event::Type::AllNotesOff, 0, 0.0f}); }
    bool setParam(int id, float value) noexcept { return queue_.push({Event::Type::Param, (int16_t) id, value}); }

    double sampleRate() const noexcept { return sampleRate_.load(std::memory_order_relaxed); }
    int64_t framesRendered() const noexcept { return framesRendered_.load(std::memory_order_relaxed); }
    int activeVoices() const noexcept { return activeVoices_.load(std::memory_order_relaxed); }

private:
    void handle(const Event& e) noexcept;

    SpscQueue<Event, 1024> queue_;
    Synth synth_;
    std::vector<float> mono_;
    std::atomic<double> sampleRate_{48000.0};
    std::atomic<int64_t> framesRendered_{0};
    std::atomic<int> activeVoices_{0};
};

} // namespace mdaw
