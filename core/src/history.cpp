#include "history.h"

namespace mdaw {

bool History::execute(CommandPtr command) {
    if (!command || !command->apply(project_))
        return false;
    undo_.push_back(std::move(command));
    if (undo_.size() > limit_)
        undo_.pop_front();
    redo_.clear();
    ++revision_;
    return true;
}

void History::recordApplied(CommandPtr command) {
    if (!command)
        return;
    undo_.push_back(std::move(command));
    if (undo_.size() > limit_)
        undo_.pop_front();
    redo_.clear();
    ++revision_;
}

bool History::undo() {
    if (undo_.empty())
        return false;
    auto command = std::move(undo_.back());
    undo_.pop_back();
    command->revert(project_);
    redo_.push_back(std::move(command));
    ++revision_;
    return true;
}

bool History::redo() {
    if (redo_.empty())
        return false;
    auto command = std::move(redo_.back());
    redo_.pop_back();
    if (!command->apply(project_)) {
        // 通常は起きない（Undo で元の状態に戻っているはず）。起きたら Redo 履歴を捨てる
        redo_.clear();
        return false;
    }
    undo_.push_back(std::move(command));
    ++revision_;
    return true;
}

void History::clear() {
    undo_.clear();
    redo_.clear();
}

} // namespace mdaw
