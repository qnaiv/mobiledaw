#pragma once

#include <cstdint>
#include <deque>

#include "commands.h"

namespace mdaw {

// Undo/Redo の履歴（最大200件）。コマンドはすべてここを通してモデルに適用する。
class History {
public:
    static constexpr size_t kDefaultLimit = 200;

    explicit History(Project& project, size_t limit = kDefaultLimit) : project_(project), limit_(limit) {}

    // 適用できたら履歴に積んで true。Redo の履歴は消える。
    bool execute(CommandPtr command);
    // すでにモデルへ適用済みのコマンドを履歴に積む（編集グループの締めくくり用）
    void recordApplied(CommandPtr command);
    bool undo();
    bool redo();
    void clear();

    bool canUndo() const noexcept { return !undo_.empty(); }
    bool canRedo() const noexcept { return !redo_.empty(); }
    size_t undoCount() const noexcept { return undo_.size(); }

    // 変更のたびに増える番号（再生用スナップショットの作り直し・自動保存の判定に使う）
    uint64_t revision() const noexcept { return revision_; }

    Project& project() noexcept { return project_; }
    const Project& project() const noexcept { return project_; }

private:
    Project& project_;
    size_t limit_;
    std::deque<CommandPtr> undo_;
    std::deque<CommandPtr> redo_;
    uint64_t revision_ = 0;
};

} // namespace mdaw
