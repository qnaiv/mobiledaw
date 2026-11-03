#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

#include "playback.h"
#include "spsc_queue.h"
#include "synth.h"

namespace mdaw {

struct Event {
    enum class Type : uint8_t { NoteOn, NoteOff, AllNotesOff, Param, TrackParam, Play, Stop, Seek, SetLoop };
    Type type = Type::NoteOn;
    uint8_t slot = 0;   // TrackParam のトラック
    int16_t index = 0;  // ノート番号 or パラメータID
    float value = 0.0f;
    int64_t tick = 0;   // Seek の位置、SetLoop の始まり
    int64_t tick2 = 0;  // SetLoop の終わり
};

// 音声スレッド側の本体。
// ・試聴（鍵盤・パラメータ）と再生操作は UI スレッドから SPSC キューで送る
// ・曲の中身はコアスレッドが publish() で渡す再生用スナップショットを読む
// ・使い終えたスナップショットは音声スレッドから返却キューに戻し、解放はコアスレッドが行う
class Engine {
public:
    static constexpr int kMaxBlock = 1024;
    static constexpr int kMaxSlots = PlaybackSnapshot::kMaxSlots;

    Engine();
    ~Engine(); // 音声スレッドが止まってから破棄すること

    // 音声スレッドが止まっている間に呼ぶ（確保あり）
    void prepare(double sampleRate);

    // 音声スレッドから呼ぶ（確保・ロックなし）。interleaved に frames × channels を上書きする。
    void render(float* interleaved, int frames, int channels) noexcept;

    // ---- UIスレッドから呼ぶ（試聴） ----
    bool noteOn(int note, float velocity) noexcept { return push({Event::Type::NoteOn, 0, (int16_t) note, velocity, 0, 0}); }
    bool noteOff(int note) noexcept { return push({Event::Type::NoteOff, 0, (int16_t) note, 0.0f, 0, 0}); }
    bool allNotesOff() noexcept { return push({Event::Type::AllNotesOff, 0, 0, 0.0f, 0, 0}); }
    bool setParam(int id, float value) noexcept { return push({Event::Type::Param, 0, (int16_t) id, value, 0, 0}); }
    // 再生中のトラックの音色をその場で変える（マクロを動かしている間）。確定値はスナップショットで届く
    bool setTrackParam(int slot, int id, float value) noexcept {
        if (slot < 0 || slot >= kMaxSlots)
            return false;
        return push({Event::Type::TrackParam, (uint8_t) slot, (int16_t) id, value, 0, 0});
    }

    // ---- UIスレッドから呼ぶ（再生操作） ----
    bool play() noexcept { return push({Event::Type::Play, 0, 0, 0.0f, 0, 0}); }
    bool stop() noexcept { return push({Event::Type::Stop, 0, 0, 0.0f, 0, 0}); } // 止めてループの頭へ戻る
    bool seek(int64_t tick) noexcept { return push({Event::Type::Seek, 0, 0, 0.0f, tick, 0}); }
    // ループする範囲（tick）を [start, end) に絞る。end <= start なら曲全体に戻す
    bool setLoop(int64_t start, int64_t end) noexcept { return push({Event::Type::SetLoop, 0, 0, 0.0f, start, end}); }

    // ---- コアスレッドから呼ぶ ----
    // 新しい再生用データを渡す。音声スレッドは次のバッファの頭で差し替える。
    void publish(std::unique_ptr<PlaybackSnapshot> snapshot);
    // 音声スレッドが使い終えたスナップショットを解放する（publish の中でも呼ばれる）
    void collectRetired();

    // ---- どのスレッドからでも（表示用） ----
    double sampleRate() const noexcept { return sampleRate_.load(std::memory_order_relaxed); }
    int64_t framesRendered() const noexcept { return framesRendered_.load(std::memory_order_relaxed); }
    int activeVoices() const noexcept { return activeVoices_.load(std::memory_order_relaxed); }
    bool isPlaying() const noexcept { return playingOut_.load(std::memory_order_relaxed); }
    int64_t playheadTick() const noexcept { return playheadOut_.load(std::memory_order_relaxed); }

private:
    struct Slot {
        Synth synth;
        Id trackId = kNoId;
        SynthParams snapParams;         // 直前のスナップショットの値（変わったときだけ反映する）
        PlaybackSnapshot::NoteSet held; // シーケンサーが鳴らしている音
        float gainL = 0.0f, gainR = 0.0f; // なめらかに追従させる現在値
    };

    bool push(const Event& e) noexcept { return queue_.push(e); }
    void handle(const Event& e) noexcept;
    void adoptPendingSnapshot() noexcept;
    void fireDueEvents() noexcept;
    void releaseSequencedNotes() noexcept;
    void rewindTo(double tick) noexcept;
    double loopStart() const noexcept;
    double loopEnd() const noexcept;
    void renderSegment(float* interleaved, int n, int channels) noexcept;

    SpscQueue<Event, 1024> queue_;
    Synth preview_; // 試聴鍵盤用
    std::array<Slot, kMaxSlots> slots_;
    std::vector<float> mono_, mixL_, mixR_;

    // スナップショットの受け渡し
    std::atomic<PlaybackSnapshot*> pending_{nullptr};
    SpscQueue<PlaybackSnapshot*, 64> retired_; // 音声 → コア
    PlaybackSnapshot* current_ = nullptr;        // 音声スレッドだけが触る

    // 再生状態（音声スレッドだけが触る）
    bool playing_ = false;
    double position_ = 0.0;   // tick
    double firedUpTo_ = -1.0; // この tick までのイベントは処理済み
    int64_t loopStart_ = 0;   // 範囲ループ（loopEnd_ が 0 なら曲全体）
    int64_t loopEnd_ = 0;
    size_t cursor_ = 0;       // 次に見るイベント

    std::atomic<double> sampleRate_{48000.0};
    std::atomic<int64_t> framesRendered_{0};
    std::atomic<int> activeVoices_{0};
    std::atomic<bool> playingOut_{false};
    std::atomic<int64_t> playheadOut_{0};
};

} // namespace mdaw
