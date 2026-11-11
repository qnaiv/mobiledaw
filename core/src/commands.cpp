#include "commands.h"

#include "kit.h"

#include "mdaw.h"

#include <algorithm>
#include <cctype>
#include <cmath>

namespace mdaw {

namespace {

bool contains(const std::vector<Id>& ids, Id id) {
    return std::find(ids.begin(), ids.end(), id) != ids.end();
}

void removeNotes(Clip& clip, const std::vector<Id>& ids) {
    clip.notes.erase(std::remove_if(clip.notes.begin(), clip.notes.end(),
                                    [&](const Note& n) { return contains(ids, n.id); }),
                     clip.notes.end());
}

// 同じトラックで [start, start+len) が他の配置と重なるか
bool overlaps(const Project& p, Id trackId, int start, int len, Id ignorePlacement = kNoId) {
    for (const auto& pl : p.placements) {
        if (pl.trackId != trackId || pl.id == ignorePlacement)
            continue;
        if (start < pl.startBar + pl.lengthBars && pl.startBar < start + len)
            return true;
    }
    return false;
}

template <typename T>
void eraseById(std::vector<T>& items, Id id) {
    items.erase(std::remove_if(items.begin(), items.end(), [&](const T& t) { return t.id == id; }), items.end());
}

} // namespace

//==============================================================================
bool AddNotes::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr || notes_.empty())
        return false;
    for (const auto& n : notes_) {
        if (n.pitch < 0 || n.pitch > 127 || n.tick < 0 || n.tick >= clip->lengthTicks
            || n.length < ResizeNotes::kMinLength || !(n.velocity > 0.0f))
            return false;
    }
    for (auto& n : notes_) {
        if (n.id == kNoId)
            n.id = newId(); // 初回だけ振る。Redo では同じ id に戻る
        n.velocity = std::min(n.velocity, 1.0f);
        clip->notes.push_back(n);
    }
    clip->sortNotes();
    return true;
}

void AddNotes::revert(Project& p) {
    if (auto* clip = p.findClip(clipId_))
        removeNotes(*clip, addedIds());
}

std::vector<Id> AddNotes::addedIds() const {
    std::vector<Id> ids;
    for (const auto& n : notes_)
        ids.push_back(n.id);
    return ids;
}

//==============================================================================
bool DeleteNotes::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return false;
    removed_.clear();
    for (const auto& n : clip->notes)
        if (contains(ids_, n.id))
            removed_.push_back(n);
    if (removed_.empty())
        return false;
    removeNotes(*clip, ids_);
    return true;
}

void DeleteNotes::revert(Project& p) {
    if (auto* clip = p.findClip(clipId_)) {
        clip->notes.insert(clip->notes.end(), removed_.begin(), removed_.end());
        clip->sortNotes();
    }
}

//==============================================================================
bool MoveNotes::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return false;
    int64_t minTick = INT64_MAX, maxTick = INT64_MIN;
    int minPitch = 128, maxPitch = -1;
    for (const auto& n : clip->notes) {
        if (!contains(ids_, n.id))
            continue;
        minTick = std::min(minTick, n.tick);
        maxTick = std::max(maxTick, n.tick);
        minPitch = std::min(minPitch, n.pitch);
        maxPitch = std::max(maxPitch, n.pitch);
    }
    if (maxPitch < 0)
        return false;
    appliedTick_ = std::clamp(dTick_, -minTick, clip->lengthTicks - 1 - maxTick);
    appliedPitch_ = std::clamp(dPitch_, -minPitch, 127 - maxPitch);
    if (appliedTick_ == 0 && appliedPitch_ == 0)
        return false;
    shift(p, appliedTick_, appliedPitch_);
    return true;
}

void MoveNotes::revert(Project& p) { shift(p, -appliedTick_, -appliedPitch_); }

void MoveNotes::shift(Project& p, int64_t dt, int dp) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return;
    for (auto& n : clip->notes) {
        if (contains(ids_, n.id)) {
            n.tick += dt;
            n.pitch += dp;
        }
    }
    clip->sortNotes();
}

//==============================================================================
bool ResizeNotes::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return false;
    oldLengths_.clear();
    bool changed = false;
    for (auto& n : clip->notes) {
        if (!contains(ids_, n.id))
            continue;
        oldLengths_.emplace_back(n.id, n.length);
        const auto next = std::max(kMinLength, n.length + delta_);
        changed |= next != n.length;
        n.length = next;
    }
    if (!changed) {
        revert(p);
        return false;
    }
    return true;
}

void ResizeNotes::revert(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return;
    for (const auto& [id, len] : oldLengths_)
        if (auto* n = clip->findNote(id))
            n->length = len;
}

//==============================================================================
bool CreateClip::apply(Project& p) {
    if (p.findTrack(trackId_) == nullptr || startBar_ < 0 || lengthBars_ < 1)
        return false;
    if (overlaps(p, trackId_, startBar_, lengthBars_))
        return false;
    if (clip_.id == kNoId) {
        clip_.id = newId();
        clip_.trackId = trackId_;
        clip_.lengthTicks = p.ticksPerBar() * lengthBars_;
        placement_ = {newId(), clip_.id, trackId_, startBar_, lengthBars_};
    }
    p.clips.push_back(clip_);
    p.placements.push_back(placement_);
    return true;
}

void CreateClip::revert(Project& p) {
    eraseById(p.placements, placement_.id);
    eraseById(p.clips, clip_.id);
}

//==============================================================================
bool PlaceClip::apply(Project& p) {
    const auto* clip = p.findClip(clipId_);
    if (clip == nullptr || startBar_ < 0)
        return false;
    const auto perBar = p.ticksPerBar();
    const int bars = static_cast<int>((clip->lengthTicks + perBar - 1) / perBar);
    if (overlaps(p, clip->trackId, startBar_, bars))
        return false;
    if (placement_.id == kNoId)
        placement_ = {newId(), clipId_, clip->trackId, startBar_, bars};
    p.placements.push_back(placement_);
    return true;
}

void PlaceClip::revert(Project& p) { eraseById(p.placements, placement_.id); }

//==============================================================================
bool CloneClip::apply(Project& p) {
    const auto* src = p.findClip(clipId_);
    if (src == nullptr || startBar_ < 0)
        return false;
    const auto perBar = p.ticksPerBar();
    const int bars = static_cast<int>((src->lengthTicks + perBar - 1) / perBar);
    if (overlaps(p, src->trackId, startBar_, bars))
        return false;
    if (clone_.id == kNoId) {
        // ノートもオートメーションも vector のコピーでディープコピーになる。
        // ノートの ID は新しいクリップのものとして振り直す（Redo では同じ ID に戻る）
        clone_ = *src;
        clone_.id = newId();
        for (auto& n : clone_.notes)
            n.id = newId();
        placement_ = {newId(), clone_.id, src->trackId, startBar_, bars};
    }
    p.clips.push_back(clone_);
    p.placements.push_back(placement_);
    return true;
}

void CloneClip::revert(Project& p) {
    eraseById(p.placements, placement_.id);
    eraseById(p.clips, clone_.id);
}

//==============================================================================
bool RemovePlacement::apply(Project& p) {
    auto it = std::find_if(p.placements.begin(), p.placements.end(),
                           [&](const Placement& pl) { return pl.id == placementId_; });
    if (it == p.placements.end())
        return false;
    removed_ = *it;
    index_ = static_cast<size_t>(it - p.placements.begin());
    p.placements.erase(it);

    const bool stillUsed = std::any_of(p.placements.begin(), p.placements.end(),
                                       [&](const Placement& pl) { return pl.clipId == removed_.clipId; });
    removedClip_ = false;
    if (!stillUsed) {
        auto cit = std::find_if(p.clips.begin(), p.clips.end(), [&](const Clip& c) { return c.id == removed_.clipId; });
        if (cit != p.clips.end()) {
            clip_ = *cit;
            clipIndex_ = static_cast<size_t>(cit - p.clips.begin());
            p.clips.erase(cit);
            removedClip_ = true;
        }
    }
    return true;
}

void RemovePlacement::revert(Project& p) {
    if (removedClip_)
        p.clips.insert(p.clips.begin() + static_cast<std::ptrdiff_t>(std::min(clipIndex_, p.clips.size())), clip_);
    p.placements.insert(p.placements.begin() + static_cast<std::ptrdiff_t>(std::min(index_, p.placements.size())),
                        removed_);
}

//==============================================================================
bool ResizeClip::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr || bars_ < 1 || bars_ > kMaxBars)
        return false;
    const int64_t newLength = p.ticksPerBar() * bars_;
    if (newLength == clip->lengthTicks)
        return false;

    // 伸びた配置どうし・他のクリップとぶつからないか（同じクリップの複製も新しい長さで比べる）
    auto lengthOf = [&](const Placement& pl) { return pl.clipId == clipId_ ? bars_ : pl.lengthBars; };
    for (const auto& a : p.placements) {
        if (a.clipId != clipId_)
            continue;
        for (const auto& b : p.placements) {
            if (b.id == a.id || b.trackId != a.trackId)
                continue;
            if (a.startBar < b.startBar + lengthOf(b) && b.startBar < a.startBar + bars_)
                return false;
        }
    }

    oldLength_ = clip->lengthTicks;
    oldPlacementBars_.clear();
    for (auto& pl : p.placements) {
        if (pl.clipId == clipId_) {
            oldPlacementBars_.emplace_back(pl.id, pl.lengthBars);
            pl.lengthBars = bars_;
        }
    }
    removed_.clear();
    auto& notes = clip->notes;
    for (auto it = notes.begin(); it != notes.end();) {
        if (it->tick >= newLength) {
            removed_.push_back(*it);
            it = notes.erase(it);
        } else {
            ++it;
        }
    }
    // オートメーションも新しい長さに合わせて切り落とす（Undo で戻るよう控える）
    oldAutomation_ = clip->automation;
    for (auto& lane : clip->automation)
        normalizeAutomationLane(lane, newLength);
    clip->automation.erase(std::remove_if(clip->automation.begin(), clip->automation.end(),
                                          [](const AutomationLane& l) { return l.points.empty(); }),
                           clip->automation.end());
    clip->lengthTicks = newLength;
    return true;
}

void ResizeClip::revert(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return;
    clip->lengthTicks = oldLength_;
    clip->automation = oldAutomation_;
    clip->notes.insert(clip->notes.end(), removed_.begin(), removed_.end());
    clip->sortNotes();
    for (const auto& [id, bars] : oldPlacementBars_)
        if (auto* pl = p.findPlacement(id))
            pl->lengthBars = bars;
}

//==============================================================================
bool MovePlacement::apply(Project& p) {
    auto* pl = p.findPlacement(placementId_);
    if (pl == nullptr || newStart_ < 0 || newStart_ == pl->startBar)
        return false;
    if (overlaps(p, pl->trackId, newStart_, pl->lengthBars, pl->id))
        return false;
    oldStart_ = pl->startBar;
    pl->startBar = newStart_;
    return true;
}

void MovePlacement::revert(Project& p) {
    if (auto* pl = p.findPlacement(placementId_))
        pl->startBar = oldStart_;
}

//==============================================================================
bool AddTrack::apply(Project& p) {
    if (static_cast<int>(p.tracks.size()) >= Project::kMaxTracks)
        return false;
    if (track_.id == kNoId) {
        track_.id = newId();
        track_.name = name_;
        track_.color = color_;
    }
    p.tracks.push_back(track_);
    return true;
}

void AddTrack::revert(Project& p) { eraseById(p.tracks, track_.id); }

//==============================================================================
bool SetTrackKit::apply(Project& p) {
    auto* t = p.findTrack(trackId_);
    if (t == nullptr || t->kitId == kitId_ || (!kitId_.empty() && !isValidKitId(kitId_)))
        return false;
    old_ = t->kitId;
    t->kitId = kitId_;
    return true;
}

void SetTrackKit::revert(Project& p) {
    if (auto* t = p.findTrack(trackId_))
        t->kitId = old_;
}

bool SetTrackSampler::apply(Project& p) {
    auto* t = p.findTrack(trackId_);
    if (t == nullptr)
        return false;
    auto next = next_;
    if (!next.kitId.empty() && !isValidKitId(next.kitId))
        return false;
    next.rootNote = std::clamp(next.rootNote, 0, 127);
    next.gain = std::clamp(next.gain, 0.0f, 2.0f);
    next.start = std::clamp(next.start, 0.0f, 1.0f);
    if (t->sampler == next)
        return false;
    old_ = t->sampler;
    t->sampler = next;
    return true;
}

void SetTrackSampler::revert(Project& p) {
    if (auto* t = p.findTrack(trackId_))
        t->sampler = old_;
}

bool SetProjectTitle::apply(Project& p) {
    auto t = title_;
    const auto notSpace = [](unsigned char c) { return !std::isspace(c); };
    t.erase(t.begin(), std::find_if(t.begin(), t.end(), notSpace));
    t.erase(std::find_if(t.rbegin(), t.rend(), notSpace).base(), t.end());
    if (t.empty() || t.size() > 64 || t == p.title)
        return false;
    old_ = p.title;
    p.title = t;
    return true;
}

namespace {

MasterParams clampMaster(MasterParams m) noexcept {
    if (!std::isfinite(m.gain))
        m.gain = MasterParams{}.gain;
    m.gain = std::clamp(m.gain, 0.25f, 8.0f);
    m.glue = std::clamp(m.glue, 0.0f, 1.0f);
    m.thresholdDb = std::clamp(m.thresholdDb, -36.0f, 0.0f);
    m.ratio = std::clamp(m.ratio, 1.0f, 8.0f);
    m.softClip = std::clamp(m.softClip, 0.0f, 1.0f);
    m.ceiling = std::clamp(m.ceiling, 0.5f, 1.0f);
    return m;
}

AuxParams clampAux(AuxParams a) noexcept {
    a.reverbReturn = std::clamp(a.reverbReturn, 0.0f, 2.0f);
    a.reverbSize = std::clamp(a.reverbSize, 0.0f, 1.0f);
    a.delayReturn = std::clamp(a.delayReturn, 0.0f, 2.0f);
    a.delayFeedback = std::clamp(a.delayFeedback, 0.0f, 0.9f);
    return a;
}

} // namespace

bool SetMaster::apply(Project& p) {
    const MasterParams next = clampMaster(next_);
    if (!std::isfinite(next_.gain) || next == p.master)
        return false;
    old_ = p.master;
    p.master = next;
    return true;
}

void SetMaster::revert(Project& p) { p.master = old_; }

bool SetAux::apply(Project& p) {
    const AuxParams next = clampAux(next_);
    if (next == p.aux)
        return false;
    old_ = p.aux;
    p.aux = next;
    return true;
}

void SetAux::revert(Project& p) { p.aux = old_; }

bool SetTrackMixer::apply(Project& p) {
    auto* t = p.findTrack(trackId_);
    if (t == nullptr || !std::isfinite(next_.gain) || !std::isfinite(next_.pan))
        return false;
    Mixer m = next_;
    m.gain = std::clamp(m.gain, 0.0f, 2.0f);
    m.pan = std::clamp(m.pan, -1.0f, 1.0f);
    const Mixer& cur = t->mixer;
    if (m.gain == cur.gain && m.pan == cur.pan && m.mute == cur.mute && m.solo == cur.solo)
        return false;
    old_ = cur;
    t->mixer = m;
    return true;
}

void SetTrackMixer::revert(Project& p) {
    if (auto* t = p.findTrack(trackId_))
        t->mixer = old_;
}

bool RenameTrack::apply(Project& p) {
    auto* t = p.findTrack(trackId_);
    if (t == nullptr || t->name == name_ || name_.empty() || name_.size() > 64)
        return false;
    old_ = t->name;
    t->name = name_;
    return true;
}

void RenameTrack::revert(Project& p) {
    if (auto* t = p.findTrack(trackId_))
        t->name = old_;
}

//==============================================================================
bool SetTempo::apply(Project& p) {
    if (!std::isfinite(bpm_))
        return false;
    const double next = std::clamp(bpm_, 20.0, 300.0);
    if (next == p.tempo)
        return false;
    old_ = p.tempo;
    p.tempo = next;
    return true;
}

void SetTempo::revert(Project& p) { p.tempo = old_; }

//==============================================================================
bool SetKey::apply(Project& p) {
    if (root_ < 0 || root_ > 11 || scale_.empty() || scale_.size() > 32)
        return false;
    if (root_ == p.keyRoot && scale_ == p.scale)
        return false;
    oldRoot_ = p.keyRoot;
    oldScale_ = p.scale;
    p.keyRoot = root_;
    p.scale = scale_;
    return true;
}

void SetKey::revert(Project& p) {
    p.keyRoot = oldRoot_;
    p.scale = oldScale_;
}

//==============================================================================
namespace {
// シンセの音色とエフェクトを同じ ID の並びで読み書きする
bool getTrackParam(const Track& t, int id, float& out) {
    return id >= MDAW_FX_FIRST ? getFxParam(t.fx, id, out) : getSynthParam(t.synth, id, out);
}
bool setTrackParam(Track& t, int id, float value) {
    return id >= MDAW_FX_FIRST ? setFxParam(t.fx, id, value) : setSynthParam(t.synth, id, value);
}
} // namespace

bool SetTrackSynthParam::apply(Project& p) {
    auto* t = p.findTrack(trackId_);
    if (t == nullptr || !getTrackParam(*t, paramId_, old_))
        return false;
    Track next = *t;
    if (!setTrackParam(next, paramId_, value_))
        return false;
    float applied = 0.0f;
    getTrackParam(next, paramId_, applied);
    if (applied == old_)
        return false;
    setTrackParam(*t, paramId_, applied);
    return true;
}

void SetTrackSynthParam::revert(Project& p) {
    if (auto* t = p.findTrack(trackId_))
        setTrackParam(*t, paramId_, old_);
}

//==============================================================================
bool SetClipAutomation::apply(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr || !isAutomationParam(next_.paramId))
        return false;
    AutomationLane next = next_;
    normalizeAutomationLane(next, clip->lengthTicks);
    auto* cur = clip->findAutomation(next_.paramId);
    hadOld_ = cur != nullptr;
    if (hadOld_)
        old_ = *cur;
    if (next.points.empty()) {
        if (!hadOld_)
            return false; // 元々無いレーンを消そうとした
        clip->automation.erase(std::remove_if(clip->automation.begin(), clip->automation.end(),
                                              [&](const AutomationLane& l) { return l.paramId == next_.paramId; }),
                               clip->automation.end());
        return true;
    }
    if (hadOld_ && old_ == next)
        return false; // 変わらない
    if (cur != nullptr)
        *cur = next;
    else
        clip->automation.push_back(next);
    return true;
}

void SetClipAutomation::revert(Project& p) {
    auto* clip = p.findClip(clipId_);
    if (clip == nullptr)
        return;
    clip->automation.erase(std::remove_if(clip->automation.begin(), clip->automation.end(),
                                          [&](const AutomationLane& l) { return l.paramId == next_.paramId; }),
                           clip->automation.end());
    if (hadOld_)
        clip->automation.push_back(old_);
}

//==============================================================================
bool CompoundCommand::apply(Project& p) {
    applied_ = 0;
    for (auto& c : children_) {
        if (!c->apply(p)) {
            // 途中で失敗したら、そこまでを戻して全体を無かったことにする
            while (applied_ > 0)
                children_[--applied_]->revert(p);
            return false;
        }
        ++applied_;
    }
    return applied_ > 0;
}

void CompoundCommand::revert(Project& p) {
    while (applied_ > 0)
        children_[--applied_]->revert(p);
    applied_ = 0;
}

} // namespace mdaw
