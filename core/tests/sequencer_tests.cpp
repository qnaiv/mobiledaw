// 再生用スナップショットとシーケンサーのテスト。オフラインで描画して、鳴る時刻を確かめる。
#include <cmath>
#include <cstdio>
#include <memory>
#include <vector>

#include "commands.h"
#include "engine.h"
#include "history.h"
#include "mdaw.h"
#include "playback.h"
#include "test_util.h"

namespace {

using namespace mdaw;

constexpr double kRate = 48000.0;
// 120 BPM では 1拍 = 0.5秒 = 24000 サンプル、1 tick = 25 サンプル
constexpr int kSamplesPerBeat = 24000;

struct Song {
    Project project = makeDefaultProject();
    History history{project};
    Id track = project.tracks.front().id;

    Id createClip(Id trackId, int startBar, int bars = 1) {
        auto c = std::make_unique<CreateClip>(trackId, startBar, bars);
        auto* raw = c.get();
        CHECK(history.execute(std::move(c)));
        return raw->clipId();
    }

    std::vector<Id> addNotes(Id clip, std::vector<Note> notes) {
        auto a = std::make_unique<AddNotes>(clip, std::move(notes));
        auto* raw = a.get();
        CHECK(history.execute(std::move(a)));
        return raw->addedIds();
    }

    Id addTrack() {
        auto t = std::make_unique<AddTrack>("Track", 0xFF66CCFF);
        auto* raw = t.get();
        CHECK(history.execute(std::move(t)));
        return raw->trackId();
    }
};

Note note(int64_t tick, int pitch, int64_t length) {
    Note n;
    n.tick = tick;
    n.pitch = pitch;
    n.length = length;
    n.velocity = 1.0f;
    return n;
}

struct Stereo {
    std::vector<float> l, r;
};

Stereo render(Engine& e, int frames, int block = 192) {
    std::vector<float> buf(static_cast<size_t>(block) * 2);
    Stereo out;
    for (int done = 0; done < frames; done += block) {
        const int n = std::min(block, frames - done);
        e.render(buf.data(), n, 2);
        for (int i = 0; i < n; ++i) {
            out.l.push_back(buf[static_cast<size_t>(i) * 2]);
            out.r.push_back(buf[static_cast<size_t>(i) * 2 + 1]);
        }
    }
    return out;
}

float peak(const std::vector<float>& x, size_t from = 0, size_t to = SIZE_MAX) {
    float p = 0.0f;
    to = std::min(to, x.size());
    for (size_t i = from; i < to; ++i)
        p = std::max(p, std::abs(x[i]));
    return p;
}

long firstNonZero(const std::vector<float>& x, size_t from = 0) {
    for (size_t i = from; i < x.size(); ++i)
        if (x[i] != 0.0f)
            return static_cast<long>(i);
    return -1;
}

// ---- スナップショット ---------------------------------------------------------

TEST(snapshot_expands_placements_to_absolute_ticks) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(kPpq, 60, kPpq / 2)});
    auto place = std::make_unique<PlaceClip>(clip, 2);
    CHECK(s.history.execute(std::move(place)));

    auto snap = buildSnapshot(s.project);
    const int64_t bar = kPpq * 4;
    CHECK(snap->loopEndTicks == bar * 3);
    CHECK(snap->tracks.size() == 1);
    CHECK(snap->events.size() == 4);
    CHECK(snap->events[0].tick == kPpq && snap->events[0].type == SeqEvent::Type::NoteOn);
    CHECK(snap->events[1].tick == kPpq + kPpq / 2 && snap->events[1].type == SeqEvent::Type::NoteOff);
    CHECK(snap->events[2].tick == bar * 2 + kPpq);
    CHECK(snap->events[3].tick == bar * 2 + kPpq + kPpq / 2);
}

TEST(snapshot_empty_song_loops_one_bar) {
    Song s;
    auto snap = buildSnapshot(s.project);
    CHECK(snap->loopEndTicks == kPpq * 4);
    CHECK(snap->events.empty());
}

TEST(snapshot_cuts_notes_at_clip_end_and_puts_off_before_on) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    // 1小節目の最後から2拍ぶん → クリップの終わりで切れる。同じ音の連打は「オフ → オン」の順
    s.addNotes(clip, {note(kPpq * 3, 60, kPpq * 2), note(0, 62, kPpq), note(kPpq, 62, kPpq)});
    auto snap = buildSnapshot(s.project);
    bool cut = false;
    for (const auto& e : snap->events)
        if (e.pitch == 60 && e.type == SeqEvent::Type::NoteOff)
            cut = e.tick == kPpq * 4;
    CHECK(cut);
    // tick 960 には 62 のオフとオンが並ぶ。オフが先
    for (size_t i = 0; i + 1 < snap->events.size(); ++i)
        if (snap->events[i].tick == kPpq && snap->events[i + 1].tick == kPpq)
            CHECK(snap->events[i].type == SeqEvent::Type::NoteOff);
}

TEST(snapshot_resolves_mute_and_solo) {
    Song s;
    const Id t2 = s.addTrack();
    const Id t3 = s.addTrack();
    s.project.findTrack(t2)->mixer.solo = true;
    s.project.findTrack(t3)->mixer.mute = true;
    auto snap = buildSnapshot(s.project);
    CHECK(snap->tracks.size() == 3);
    CHECK(!snap->tracks[0].audible); // ソロがあるのでソロ以外は聞こえない
    CHECK(snap->tracks[1].audible);
    CHECK(!snap->tracks[2].audible);
}

// ---- シーケンサー -------------------------------------------------------------

TEST(sequencer_plays_note_at_exact_sample) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(kPpq, 60, kPpq / 2)}); // 2拍目の頭 = 24000 サンプル目
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.play();
    auto out = render(e, kSamplesPerBeat * 2);
    const long first = firstNonZero(out.l);
    std::printf("  first sample %ld\n", first);
    CHECK(first == kSamplesPerBeat);
    CHECK(peak(out.l, 0, kSamplesPerBeat) == 0.0f);
    CHECK(peak(out.l, kSamplesPerBeat) > 0.02f);
    CHECK(e.isPlaying());
}

TEST(sequencer_loops_back_to_start) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(0, 60, kPpq / 4)});
    Engine e;
    e.prepare(kRate);
    auto snap = buildSnapshot(s.project);
    snap->tracks[0].synth.releaseS = 0.02f;
    e.publish(std::move(snap));
    e.play();
    const int bar = kSamplesPerBeat * 4; // 2秒
    auto out = render(e, bar + kSamplesPerBeat);
    CHECK(peak(out.l, 0, 2000) > 0.02f);
    // 小節の後半は静か、ループの頭でまた鳴る
    CHECK(peak(out.l, bar / 2, bar) == 0.0f);
    CHECK(firstNonZero(out.l, bar / 2) == bar);
    CHECK(e.playheadTick() < kPpq * 2);
}

TEST(sequencer_stop_releases_and_rewinds) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(0, 60, kPpq * 4)});
    auto snap = buildSnapshot(s.project);
    snap->tracks[0].synth.releaseS = 0.02f;
    Engine e;
    e.prepare(kRate);
    e.publish(std::move(snap));
    e.play();
    render(e, 9600);
    CHECK(e.playheadTick() > 0);
    e.stop();
    auto out = render(e, 9600);
    CHECK(!e.isPlaying());
    CHECK(e.playheadTick() == 0);
    CHECK(peak(out.l, 4800) == 0.0f); // 20ms のリリースは 100ms 以内に消える
}

TEST(sequencer_deleted_note_stops_while_playing) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    auto ids = s.addNotes(clip, {note(0, 60, kPpq * 4)});
    auto snap = buildSnapshot(s.project);
    snap->tracks[0].synth.releaseS = 0.02f;
    Engine e;
    e.prepare(kRate);
    e.publish(std::move(snap));
    e.play();
    auto before = render(e, 9600);
    CHECK(peak(before.l, 4800) > 0.02f);

    CHECK(s.history.execute(std::make_unique<DeleteNotes>(clip, ids)));
    auto next = buildSnapshot(s.project);
    next->tracks[0].synth.releaseS = 0.02f;
    e.publish(std::move(next));
    auto after = render(e, 9600);
    CHECK(peak(after.l, 4800) == 0.0f);
    CHECK(e.isPlaying());
}

TEST(sequencer_edit_keeps_playhead_and_plays_new_note) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.play();
    auto silent = render(e, kSamplesPerBeat); // 1拍目は空
    CHECK(peak(silent.l) == 0.0f);
    // 再生中に 3拍目へノートを置く → 止めずにちゃんと鳴る
    s.addNotes(clip, {note(kPpq * 2, 64, kPpq / 2)});
    e.publish(buildSnapshot(s.project));
    auto out = render(e, kSamplesPerBeat * 2);
    CHECK(firstNonZero(out.l) == kSamplesPerBeat);
}

TEST(sequencer_tracks_have_own_sound_and_pan) {
    Song s;
    const Id t2 = s.addTrack();
    s.project.findTrack(s.track)->mixer.pan = -1.0f; // 左だけ
    s.project.findTrack(t2)->mixer.pan = 1.0f;       // 右だけ
    const Id c1 = s.createClip(s.track, 0);
    s.addNotes(c1, {note(0, 48, kPpq)});
    const Id c2 = s.createClip(t2, 0);
    s.addNotes(c2, {note(kPpq * 2, 72, kPpq)});
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.play();
    auto out = render(e, kSamplesPerBeat * 3);
    // 1拍目：左のトラックだけ鳴る
    CHECK(peak(out.l, 0, kSamplesPerBeat) > 0.02f);
    CHECK(peak(out.r, 0, kSamplesPerBeat) == 0.0f);
    // 3拍目：右のトラックだけ鳴る（左は1拍目のノートのリリースが終わっている）
    CHECK(peak(out.r, kSamplesPerBeat * 2) > 0.02f);
    CHECK(peak(out.l, kSamplesPerBeat * 2) == 0.0f);
}

TEST(sequencer_muted_track_is_silent) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(0, 60, kPpq * 2)});
    s.project.tracks[0].mixer.mute = true;
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.play();
    auto out = render(e, kSamplesPerBeat);
    CHECK(peak(out.l) == 0.0f);
}

TEST(sequencer_seek_and_tempo) {
    Song s;
    s.history.execute(std::make_unique<SetTempo>(60.0)); // 1拍 = 1秒
    const Id clip = s.createClip(s.track, 0);
    s.addNotes(clip, {note(kPpq * 3, 60, kPpq / 2)});
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.seek(kPpq * 2); // 3拍目から
    e.play();
    auto out = render(e, 96000);
    CHECK(firstNonZero(out.l) == 48000); // 1拍（60 BPM なので1秒）後に鳴る
}

TEST(sequencer_many_publishes_while_playing) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    Engine e;
    e.prepare(kRate);
    e.play();
    // 描画と編集を交互に何度も行っても、落ちたり音が壊れたりしない
    for (int i = 0; i < 300; ++i) {
        s.addNotes(clip, {note((i * 37) % (kPpq * 4), 48 + i % 24, kPpq / 8)});
        e.publish(buildSnapshot(s.project));
        if (i % 3 == 0)
            e.publish(buildSnapshot(s.project)); // 受け取られる前の上書き
        auto out = render(e, 256, 128);
        for (float v : out.l)
            CHECK(std::isfinite(v) && std::abs(v) <= 1.0f);
    }
    e.collectRetired();
}

} // namespace

namespace {

using namespace mdaw;

// ピアノロールでクリップだけを繰り返す（範囲ループ）
TEST(sequencer_loop_range_repeats_only_that_part) {
    Song s;
    const Id clip = s.createClip(s.track, 1); // 2小節目
    s.addNotes(clip, {note(0, 60, kPpq / 4)});
    const Id other = s.createClip(s.track, 0); // 1小節目（範囲の外）
    s.addNotes(other, {note(0, 48, kPpq / 4)});
    auto snap = buildSnapshot(s.project);
    snap->tracks[0].synth.releaseS = 0.02f;
    Engine e;
    e.prepare(kRate);
    e.publish(std::move(snap));
    const int64_t bar = kPpq * 4;
    e.setLoop(bar, bar * 2);
    e.play(); // 位置 0 は範囲の外なので、範囲の頭から
    const int barSamples = kSamplesPerBeat * 4;
    auto out = render(e, barSamples * 2 + 2000);
    CHECK(firstNonZero(out.l) >= 0 && firstNonZero(out.l) <= 1); // すぐ2小節目のノート（エンベロープの最初の1サンプルは0）
    CHECK(peak(out.l, barSamples / 2, barSamples) == 0.0f); // 1小節目のノートは鳴らない
    CHECK(std::abs(firstNonZero(out.l, barSamples / 2) - barSamples) <= 1); // 1小節後にまた頭から
    CHECK(e.playheadTick() >= bar && e.playheadTick() < bar * 2);

    // 範囲を外すと曲全体に戻る（次は1小節目から）
    e.stop();
    e.setLoop(0, 0);
    render(e, 4800);
    CHECK(e.playheadTick() == 0);
}

} // namespace
