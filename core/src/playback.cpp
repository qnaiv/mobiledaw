#include "playback.h"

#include <algorithm>

namespace mdaw {

void PlaybackSnapshot::soundingAt(double tick, NoteSet* perSlot, int numSlots) const noexcept {
    for (int s = 0; s < numSlots; ++s)
        perSlot[s] = {};
    for (const auto& e : events) {
        if (static_cast<double>(e.tick) > tick)
            break;
        if (e.slot >= numSlots)
            continue;
        if (e.type == SeqEvent::Type::NoteOn)
            perSlot[e.slot].set(e.pitch);
        else
            perSlot[e.slot].clear(e.pitch);
    }
}

size_t PlaybackSnapshot::firstEventAfter(double tick) const noexcept {
    auto it = std::upper_bound(events.begin(), events.end(), tick,
                               [](double t, const SeqEvent& e) { return t < static_cast<double>(e.tick); });
    return static_cast<size_t>(it - events.begin());
}

std::unique_ptr<PlaybackSnapshot> buildSnapshot(const Project& project) {
    auto snap = std::make_unique<PlaybackSnapshot>();
    snap->tempo = std::clamp(project.tempo, 20.0, 400.0);
    snap->ticksPerBar = std::max<int64_t>(project.ticksPerBar(), 1);
    snap->loopEndTicks = std::max(project.lengthBars(), 1) * snap->ticksPerBar;

    bool anySolo = false;
    const size_t numTracks = std::min(project.tracks.size(), static_cast<size_t>(PlaybackSnapshot::kMaxSlots));
    for (size_t i = 0; i < numTracks; ++i)
        anySolo = anySolo || project.tracks[i].mixer.solo;

    for (size_t i = 0; i < numTracks; ++i) {
        const auto& t = project.tracks[i];
        SnapshotTrack st;
        st.id = t.id;
        st.synth = t.synth;
        st.gain = std::clamp(t.mixer.gain, 0.0f, 2.0f);
        st.pan = std::clamp(t.mixer.pan, -1.0f, 1.0f);
        st.audible = !t.mixer.mute && (!anySolo || t.mixer.solo);
        snap->tracks.push_back(st);
    }

    auto slotOf = [&](Id trackId) -> int {
        for (size_t i = 0; i < snap->tracks.size(); ++i)
            if (snap->tracks[i].id == trackId)
                return static_cast<int>(i);
        return -1;
    };

    for (const auto& pl : project.placements) {
        const int slot = slotOf(pl.trackId);
        const auto* clip = project.findClip(pl.clipId);
        if (slot < 0 || clip == nullptr || clip->lengthTicks <= 0 || pl.lengthBars <= 0)
            continue;
        const int64_t start = static_cast<int64_t>(pl.startBar) * snap->ticksPerBar;
        const int64_t end = start + static_cast<int64_t>(pl.lengthBars) * snap->ticksPerBar;
        // 配置の長さに合わせてクリップを繰り返す
        for (int64_t rep = start; rep < end; rep += clip->lengthTicks) {
            for (const auto& n : clip->notes) {
                if (n.tick < 0 || n.tick >= clip->lengthTicks || n.length <= 0 || n.pitch < 0 || n.pitch > 127)
                    continue;
                const int64_t on = rep + n.tick;
                if (on >= end)
                    continue;
                // クリップ・配置の終わりで切る
                const int64_t off = std::min({on + n.length, rep + clip->lengthTicks, end});
                SeqEvent e;
                e.slot = static_cast<uint8_t>(slot);
                e.pitch = static_cast<uint8_t>(n.pitch);
                e.velocity = std::clamp(n.velocity, 0.0f, 1.0f);
                e.tick = on;
                e.type = SeqEvent::Type::NoteOn;
                snap->events.push_back(e);
                e.tick = off;
                e.type = SeqEvent::Type::NoteOff;
                snap->events.push_back(e);
            }
        }
    }

    std::stable_sort(snap->events.begin(), snap->events.end(), [](const SeqEvent& a, const SeqEvent& b) {
        if (a.tick != b.tick)
            return a.tick < b.tick;
        if (a.type != b.type)
            return a.type == SeqEvent::Type::NoteOff; // 同じ tick ではオフを先に（同じ音の連打で切れないように）
        if (a.slot != b.slot)
            return a.slot < b.slot;
        return a.pitch < b.pitch;
    });
    return snap;
}

} // namespace mdaw
