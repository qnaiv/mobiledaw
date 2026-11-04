#pragma once

// プロジェクトのデータモデル（設計書「データモデル」）。
// ・時間は 960 PPQ の tick。グリッドは表示と吸着の設定で、データには持たない
// ・音程は MIDI の絶対値。スケール外を畳むのは表示側の仕事
// ・クリップ（ノートの並び）と配置（どの小節にどのクリップ）を分ける
// このモデルはコア（ワーカー）スレッドだけが触る。音声スレッドは再生用スナップショットを読む。

#include <cstdint>
#include <string>
#include <vector>

#include "fx.h"
#include "synth.h"

namespace mdaw {

using Id = uint64_t;
constexpr Id kNoId = 0;
constexpr int64_t kPpq = 960;

// 衝突しにくいランダムな ID（0 は使わない）
Id newId();

struct Note {
    Id id = kNoId;
    int64_t tick = 0;    // クリップ先頭からの位置
    int64_t length = kPpq / 4;
    int pitch = 60;      // MIDI 0〜127
    float velocity = 0.8f;
};

struct Clip {
    Id id = kNoId;
    Id trackId = kNoId;
    int64_t lengthTicks = kPpq * 4; // 既定は4/4で1小節
    std::vector<Note> notes;        // 常に tick → pitch の順に並べておく

    Note* findNote(Id noteId);
    void sortNotes();
};

struct Placement {
    Id id = kNoId;
    Id clipId = kNoId;
    Id trackId = kNoId;
    int startBar = 0;   // 0始まり
    int lengthBars = 1;
};

struct Mixer {
    float gain = 0.8f;
    float pan = 0.0f;  // -1〜1
    bool mute = false;
    bool solo = false;
};

struct Track {
    Id id = kNoId;
    std::string name;
    uint32_t color = 0xFFC8F25A; // ARGB
    SynthParams synth;           // 今はシンセのみ。音色エンジンの切り替え（サンプラーなど）は M3 以降
    std::string kitId;           // 空ならシンセ、入っていればそのドラムキット（kits/<id>）を鳴らす
    FxParams fx;                 // トラックのエフェクト（音色を替えても残る）
    Mixer mixer;
};

struct Project {
    static constexpr int kVersion = 1;
    static constexpr int kMaxTracks = 8;

    std::string title = "無題の曲";
    double tempo = 120.0;
    int timeSigNumerator = 4;
    int timeSigDenominator = 4;
    int keyRoot = 0;              // 0 = C
    std::string scale = "minor";
    std::vector<Track> tracks;
    std::vector<Clip> clips;
    std::vector<Placement> placements;

    int64_t ticksPerBar() const noexcept { return kPpq * 4 * timeSigNumerator / timeSigDenominator; }

    Track* findTrack(Id id);
    Clip* findClip(Id id);
    Placement* findPlacement(Id id);
    const Track* findTrack(Id id) const;
    const Clip* findClip(Id id) const;

    // 全体の長さ（最後の配置の終わり、小節数）
    int lengthBars() const noexcept;
};

// 新規プロジェクト（空のトラックを1本）
Project makeDefaultProject();

} // namespace mdaw
