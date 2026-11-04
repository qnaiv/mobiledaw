#include "session.h"

#include "engine.h"
#include "mdaw.h"
#include "playback.h"
#include "project_json.h"

namespace mdaw {

Session::Session(Engine& engine) : engine_(engine), project_(makeDefaultProject()), history_(project_) {
    engine_.publish(snapshot());
}

std::unique_ptr<PlaybackSnapshot> Session::snapshot() {
    return buildSnapshot(project_, [this](const std::string& id) { return kits_.get(id); });
}

void Session::changed() {
    ++version_;
    engine_.publish(snapshot());
}

void Session::setKitsRoot(const std::string& dir) {
    kits_.setRoot(dir);
    engine_.publish(snapshot());
}

void Session::reloadKits() {
    kits_.clear();
    engine_.publish(snapshot()); // 中身は変わらないので版は上げない（保存し直さない）
}

void Session::newProject() {
    group_.reset();
    groupDepth_ = 0;
    project_ = makeDefaultProject();
    history_.clear();
    changed();
    savedVersion_ = version_;
}

bool Session::load(const std::string& path) {
    Project loaded;
    std::string error;
    if (!loadProjectFile(path, loaded, error)) {
        error_ = error;
        return false;
    }
    group_.reset();
    groupDepth_ = 0;
    project_ = std::move(loaded);
    history_.clear();
    changed();
    savedVersion_ = version_;
    error_.clear();
    return true;
}

bool Session::save(const std::string& path) {
    std::string error;
    if (!saveProjectFile(project_, path, error)) {
        error_ = error;
        return false;
    }
    savedVersion_ = version_;
    error_.clear();
    return true;
}

const std::string& Session::json() {
    if (jsonVersion_ != version_) {
        json_ = projectToJson(project_);
        jsonVersion_ = version_;
    }
    return json_;
}

bool Session::execute(CommandPtr command) {
    if (!command)
        return false;
    if (group_ != nullptr) {
        if (!command->apply(project_))
            return false;
        group_->addApplied(std::move(command));
    } else if (!history_.execute(std::move(command))) {
        return false;
    }
    changed();
    return true;
}

bool Session::undo() {
    if (group_ != nullptr || !history_.undo())
        return false;
    changed();
    return true;
}

bool Session::redo() {
    if (group_ != nullptr || !history_.redo())
        return false;
    changed();
    return true;
}

void Session::beginGroup(const char* label) {
    if (groupDepth_++ == 0)
        group_ = std::make_unique<CompoundCommand>(label);
}

void Session::endGroup() {
    if (groupDepth_ == 0)
        return;
    if (--groupDepth_ > 0)
        return;
    auto group = std::move(group_);
    if (group != nullptr && !group->empty())
        history_.recordApplied(std::move(group));
}

int Session::slotOf(Id trackId) const noexcept {
    for (size_t i = 0; i < project_.tracks.size() && i < static_cast<size_t>(Project::kMaxTracks); ++i)
        if (project_.tracks[i].id == trackId)
            return static_cast<int>(i);
    return -1;
}

void Session::previewTrack(Id trackId) {
    const auto* t = project_.findTrack(trackId);
    if (t == nullptr)
        return;
    engine_.allNotesOff();
    for (int i = 0; i < kNumSynthParamSpecs; ++i)
        engine_.setParam(kSynthParamSpecs[i].id, t->synth.*(kSynthParamSpecs[i].member));
    engine_.setPreviewSlot(slotOf(trackId)); // そのトラックのエフェクトを通して聴く
}

bool Session::setTrackParamLive(Id trackId, int paramId, float value) {
    const int slot = slotOf(trackId);
    if (slot < 0 || paramId < 0 || paramId >= MDAW_FX_END || (paramId >= MDAW_PARAM_COUNT && paramId < MDAW_FX_FIRST))
        return false;
    return engine_.setTrackParam(slot, paramId, value);
}

} // namespace mdaw
