#pragma once

// 再生用スナップショット（設計書「スレッド設計とリアルタイム安全性」）。
// コア（ワーカー）スレッドが編集のたびに Project から作る不変データ。
// 音声スレッドはこれを読むだけで、確保も解放もしない。
//
// ・クリップと配置を展開し、曲頭からの絶対 tick に並べたノートオン／オフの列にする
// ・配置がクリップより長いときはクリップを繰り返し、短いときは配置の終わりで切る
// ・トラックは「スロット」（Project::tracks の並び順、最大 8）で指す

#include <cstdint>
#include <memory>
#include <vector>

#include "model.h"
#include <functional>
#include <string>

#include "fx.h"
#include "kit.h"
#include "synth.h"

namespace mdaw {

struct SeqEvent {
    enum class Type : uint8_t { NoteOff = 0, NoteOn = 1 };
    int64_t tick = 0;
    Type type = Type::NoteOn;
    uint8_t slot = 0;
    uint8_t pitch = 60;
    float velocity = 0.8f;
};

struct SnapshotTrack {
    Id id = kNoId;
    SynthParams synth;
    KitPtr kit;     // ドラムキットのトラックなら読み込んだキット（無ければ鳴らない）
    KitPtr samplerKit;          // サンプラーの素材キット（サンプラーのトラックのみ）
    int samplerSound = -1;      // samplerKit->sounds の添字（名前から解決。解決できなければ -1 = 鳴らない）
    SamplerSettings sampler;    // サンプラーの設定（rootNote / gain / start を使う）
    FxParams fx;
    float gain = 0.8f;
    float pan = 0.0f;
    bool audible = true; // ミュート・ソロを反映した結果
};

// クリップのオートメーションを、配置と繰り返しに合わせて曲頭からの絶対 tick へ展開したもの
struct SnapshotAutoLane {
    uint8_t slot = 0;
    int paramId = 0;
    std::vector<AutomationPoint> points; // 絶対 tick 昇順

    bool valueAt(double tick, float& out) const noexcept { return automationValueAt(points, tick, out); }
};

struct PlaybackSnapshot {
    static constexpr int kMaxSlots = Project::kMaxTracks;

    double tempo = 120.0;
    int64_t ticksPerBar = kPpq * 4;
    int64_t loopEndTicks = kPpq * 4; // ループの終わり（曲が空なら1小節）
    std::vector<SnapshotTrack> tracks; // 最大 kMaxSlots
    std::vector<SeqEvent> events;      // tick 順。同じ tick ではオフが先
    std::vector<SnapshotAutoLane> automation; // スロット×パラメータごと（無ければ空＝従来動作）
    std::vector<int64_t> automationTicks;     // 全レーンのポイント位置（昇順・重複なし）。エンジンの区切り用

    // tick より後ろで最初のオートメーションのポイント位置。無ければ false
    bool nextAutomationTick(double tick, double& out) const noexcept;

    // tick 時点で鳴っているべき音を slot ごとの 128bit で返す（音声スレッドから呼んでよい）
    struct NoteSet {
        uint64_t bits[2] = {0, 0};
        void set(int p) noexcept { bits[p >> 6] |= (uint64_t{1} << (p & 63)); }
        void clear(int p) noexcept { bits[p >> 6] &= ~(uint64_t{1} << (p & 63)); }
        bool has(int p) const noexcept { return (bits[p >> 6] >> (p & 63)) & 1; }
    };
    void soundingAt(double tick, NoteSet* perSlot, int numSlots) const noexcept;

    // tick より後に来る最初のイベントの位置（tick ちょうどのものは含まない）
    size_t firstEventAfter(double tick) const noexcept;
};

// キットの ID → 読み込んだキット（コアスレッドで呼ぶ）。空なら全部「無い」扱い
using KitResolver = std::function<KitPtr(const std::string&)>;

std::unique_ptr<PlaybackSnapshot> buildSnapshot(const Project& project, const KitResolver& kits = {});

} // namespace mdaw
