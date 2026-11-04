#pragma once

// 開いているプロジェクト1つ分の状態（設計書の「コア」）。
// モデル・Undo 履歴・保存を持ち、変更のたびに再生用スナップショットを作ってエンジンへ渡す。
// C API（mdaw_api.cpp）はこのクラスの薄い包みで、呼び出しは UI スレッド1本から来る前提。

#include <cstdint>
#include <memory>
#include <string>

#include "commands.h"
#include "history.h"
#include "kit.h"
#include "model.h"

namespace mdaw {

class Engine;

class Session {
public:
    explicit Session(Engine& engine);

    // ---- プロジェクト全体 ----
    void newProject();
    bool load(const std::string& path); // 失敗したら今のプロジェクトはそのまま、lastError() に理由
    bool save(const std::string& path);
    const std::string& json();          // プロジェクト全体の JSON（project.json と同じ形）
    uint64_t version() const noexcept { return version_; } // 中身が変わるたびに増える
    bool dirty() const noexcept { return version_ != savedVersion_; }
    const std::string& lastError() const noexcept { return error_; }

    // ---- 編集 ----
    // 適用できたら true。編集グループの中なら、最後にまとめて1つの Undo になる
    bool execute(CommandPtr command);
    bool undo();
    bool redo();
    bool canUndo() const noexcept { return group_ == nullptr && history_.canUndo(); }
    bool canRedo() const noexcept { return group_ == nullptr && history_.canRedo(); }

    // 1ジェスチャーの間の編集をまとめる（入れ子は数えるだけで、一番外の end で締める）
    void beginGroup(const char* label = "Group");
    void endGroup();

    // ---- 音だけ（モデルは変えない） ----
    void previewTrack(Id trackId);                                  // 試聴鍵盤をそのトラックの音色に
    bool setTrackParamLive(Id trackId, int paramId, float value);   // 再生中の音色をその場で変える

    // ---- ドラムキット ----
    void setKitsRoot(const std::string& dir);  // kits/<id>/kit.json を探す場所
    void reloadKits();                         // ダウンロードし直したら呼ぶ（鳴らし直す）
    std::string kitError(const std::string& id) { kits_.get(id); return kits_.error(id); }
    // 今の曲の再生用データ（書き出し用。キットも解決済み）
    std::unique_ptr<struct PlaybackSnapshot> snapshot();

    const Project& project() const noexcept { return project_; }
    int slotOf(Id trackId) const noexcept;

private:
    void changed();

    Engine& engine_;
    Project project_;
    History history_;
    uint64_t version_ = 1;
    uint64_t savedVersion_ = 1;
    std::string json_;
    uint64_t jsonVersion_ = 0;
    std::string error_;
    KitCache kits_;
    std::unique_ptr<CompoundCommand> group_;
    int groupDepth_ = 0;
};

} // namespace mdaw
