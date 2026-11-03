#include "model.h"

#include <algorithm>
#include <random>

namespace mdaw {

Id newId() {
    static thread_local std::mt19937_64 rng{std::random_device{}()};
    Id id = kNoId;
    while (id == kNoId)
        id = rng();
    return id;
}

Note* Clip::findNote(Id noteId) {
    for (auto& n : notes)
        if (n.id == noteId)
            return &n;
    return nullptr;
}

void Clip::sortNotes() {
    std::stable_sort(notes.begin(), notes.end(), [](const Note& a, const Note& b) {
        return a.tick != b.tick ? a.tick < b.tick : a.pitch < b.pitch;
    });
}

template <typename T>
static T* findById(std::vector<T>& items, Id id) {
    for (auto& item : items)
        if (item.id == id)
            return &item;
    return nullptr;
}

Track* Project::findTrack(Id id) { return findById(tracks, id); }
Clip* Project::findClip(Id id) { return findById(clips, id); }
Placement* Project::findPlacement(Id id) { return findById(placements, id); }
const Track* Project::findTrack(Id id) const { return const_cast<Project*>(this)->findTrack(id); }
const Clip* Project::findClip(Id id) const { return const_cast<Project*>(this)->findClip(id); }

int Project::lengthBars() const noexcept {
    int end = 0;
    for (const auto& p : placements)
        end = std::max(end, p.startBar + p.lengthBars);
    return end;
}

Project makeDefaultProject() {
    Project p;
    Track t;
    t.id = newId();
    t.name = "Track 1";
    p.tracks.push_back(t);
    return p;
}

} // namespace mdaw
