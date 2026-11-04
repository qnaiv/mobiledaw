#pragma once

// 曲を wav に書き出す（設計：バックログ「書き出し」）。
// 再生用とは別のエンジンを自分のスレッドで回し、音声スレッドを使わずリアルタイムより速く計算する。
// 呼ぶ側（UI スレッド）は start() のあと progress() を見て待つ。

#include <atomic>
#include <string>
#include <thread>

#include <memory>

#include "model.h"
#include "playback.h"

namespace mdaw {

class Exporter {
public:
    enum State : int { Idle = 0, Running = 1, Done = 2, Failed = 3, Cancelled = 4 };

    static constexpr double kSampleRate = 48000.0;

    ~Exporter();

    // project は呼んだ時点の写しを使う。trackId が kNoId なら曲全体（仕上げあり）、
    // それ以外はそのトラックだけ（ミュート・ソロは無視、仕上げなし）。書き出し中なら false
    bool start(std::unique_ptr<PlaybackSnapshot> snapshot, const std::string& path, Id trackId);
    void cancel() noexcept { cancel_.store(true); }

    State state() const noexcept { return static_cast<State>(state_.load()); }
    float progress() const noexcept { return progress_.load(); }
    // state() が Failed のときの理由（Running の間は読まないこと）
    const std::string& error() const noexcept { return error_; }

    // 書き出しの本体（テストからも直接呼ぶ）。失敗したら false と error
    static bool render(std::unique_ptr<PlaybackSnapshot> snap, const std::string& path, Id trackId,
                       const std::atomic<bool>* cancel, std::atomic<float>* progress, std::string& error);

private:
    void join();

    std::thread thread_;
    std::atomic<int> state_{Idle};
    std::atomic<float> progress_{0.0f};
    std::atomic<bool> cancel_{false};
    std::string error_;
};

} // namespace mdaw
