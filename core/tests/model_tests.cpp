// データモデル・編集コマンド・Undo のテスト
#include <memory>

#include "commands.h"
#include "history.h"
#include "mdaw.h"
#include "test_util.h"

namespace {

using namespace mdaw;

struct Fixture {
    Project project = makeDefaultProject();
    History history{project};
    Id track = project.tracks.front().id;
    Id clip = kNoId;

    Fixture() {
        auto create = std::make_unique<CreateClip>(track, 0, 1);
        auto* raw = create.get();
        history.execute(std::move(create));
        clip = raw->clipId();
    }

    std::vector<Id> addNotes(std::vector<Note> notes) {
        auto add = std::make_unique<AddNotes>(clip, std::move(notes));
        auto* raw = add.get();
        if (!history.execute(std::move(add)))
            return {};
        return raw->addedIds();
    }

    Clip& theClip() { return *project.findClip(clip); }
};

Note note(int64_t tick, int pitch, int64_t length = kPpq / 2) {
    Note n;
    n.tick = tick;
    n.pitch = pitch;
    n.length = length;
    return n;
}

TEST(model_create_clip_places_it) {
    Fixture f;
    CHECK(f.project.clips.size() == 1);
    CHECK(f.project.placements.size() == 1);
    CHECK(f.theClip().lengthTicks == kPpq * 4);
    CHECK(f.project.lengthBars() == 1);
}

TEST(model_add_notes_assigns_ids_and_sorts) {
    Fixture f;
    auto ids = f.addNotes({note(kPpq, 64), note(0, 60), note(0, 55)});
    CHECK(ids.size() == 3);
    for (auto id : ids)
        CHECK(id != kNoId);
    const auto& n = f.theClip().notes;
    CHECK(n.size() == 3);
    CHECK(n[0].tick == 0 && n[0].pitch == 55);
    CHECK(n[1].tick == 0 && n[1].pitch == 60);
    CHECK(n[2].tick == kPpq);
}

TEST(model_invalid_notes_are_rejected_whole) {
    Fixture f;
    CHECK(f.addNotes({note(0, 60), note(0, 200)}).empty());   // 音域外が1つでもあれば全部やめる
    CHECK(f.addNotes({note(kPpq * 4, 60)}).empty());         // クリップの外
    CHECK(f.addNotes({note(0, 60, 1)}).empty());              // 短すぎ
    CHECK(f.theClip().notes.empty());
    CHECK(f.history.undoCount() == 1); // CreateClip だけ
}

TEST(model_undo_redo_add_keeps_same_ids) {
    Fixture f;
    auto ids = f.addNotes({note(0, 60)});
    CHECK(f.history.undo());
    CHECK(f.theClip().notes.empty());
    CHECK(f.history.redo());
    CHECK(f.theClip().notes.size() == 1);
    CHECK(f.theClip().notes[0].id == ids[0]);
}

TEST(model_move_notes_clamps_to_clip_and_range) {
    Fixture f;
    auto ids = f.addNotes({note(0, 60), note(kPpq, 120)});
    auto move = std::make_unique<MoveNotes>(f.clip, ids, -kPpq, +12);
    auto* raw = move.get();
    CHECK(f.history.execute(std::move(move)));
    CHECK(raw->appliedDeltaTicks() == 0);  // 先頭のノートが0より前に出られない
    CHECK(raw->appliedDeltaPitch() == 7);  // 120 → 127 まで
    CHECK(f.theClip().findNote(ids[1])->pitch == 127);
    CHECK(f.history.undo());
    CHECK(f.theClip().findNote(ids[0])->pitch == 60);
    CHECK(f.theClip().findNote(ids[1])->pitch == 120);
}

TEST(model_move_that_does_nothing_is_not_recorded) {
    Fixture f;
    auto ids = f.addNotes({note(0, 0)});
    const auto before = f.history.undoCount();
    CHECK(!f.history.execute(std::make_unique<MoveNotes>(f.clip, ids, -10, -1)));
    CHECK(f.history.undoCount() == before);
}

TEST(model_delete_and_undo_restores_notes) {
    Fixture f;
    auto ids = f.addNotes({note(0, 60), note(kPpq, 62), note(kPpq * 2, 63)});
    CHECK(f.history.execute(std::make_unique<DeleteNotes>(f.clip, std::vector<Id>{ids[0], ids[2]})));
    CHECK(f.theClip().notes.size() == 1);
    CHECK(f.history.undo());
    CHECK(f.theClip().notes.size() == 3);
    CHECK(f.theClip().notes[0].id == ids[0]);
    CHECK(f.theClip().notes[2].id == ids[2]);
}

TEST(model_resize_has_minimum_length) {
    Fixture f;
    auto ids = f.addNotes({note(0, 60, kPpq)});
    CHECK(f.history.execute(std::make_unique<ResizeNotes>(f.clip, ids, -kPpq * 10)));
    CHECK(f.theClip().notes[0].length == ResizeNotes::kMinLength);
    CHECK(f.history.undo());
    CHECK(f.theClip().notes[0].length == kPpq);
}

TEST(model_place_clip_duplicates_by_reference) {
    Fixture f;
    f.addNotes({note(0, 60)});
    auto place = std::make_unique<PlaceClip>(f.clip, 1);
    CHECK(f.history.execute(std::move(place)));
    CHECK(f.project.placements.size() == 2);
    CHECK(f.project.clips.size() == 1); // 実体は1つ
    CHECK(f.project.lengthBars() == 2);
    // 重なる位置には置けない
    CHECK(!f.history.execute(std::make_unique<PlaceClip>(f.clip, 1)));
}

TEST(model_remove_last_placement_removes_clip_and_undo_restores) {
    Fixture f;
    f.addNotes({note(0, 60)});
    const auto placementId = f.project.placements.front().id;
    CHECK(f.history.execute(std::make_unique<RemovePlacement>(placementId)));
    CHECK(f.project.placements.empty());
    CHECK(f.project.clips.empty());
    CHECK(f.history.undo());
    CHECK(f.project.placements.size() == 1);
    CHECK(f.project.clips.size() == 1);
    CHECK(f.theClip().notes.size() == 1);
}

TEST(model_move_placement_respects_overlap) {
    Fixture f;
    CHECK(f.history.execute(std::make_unique<PlaceClip>(f.clip, 2)));
    const auto first = f.project.placements.front().id;
    CHECK(!f.history.execute(std::make_unique<MovePlacement>(first, 2)));
    CHECK(f.history.execute(std::make_unique<MovePlacement>(first, 5)));
    CHECK(f.project.findPlacement(first)->startBar == 5);
    CHECK(f.history.undo());
    CHECK(f.project.findPlacement(first)->startBar == 0);
}

TEST(model_track_limit_and_tempo) {
    Fixture f;
    for (int i = 1; i < Project::kMaxTracks; ++i)
        CHECK(f.history.execute(std::make_unique<AddTrack>("T", 0xFF000000u)));
    CHECK(!f.history.execute(std::make_unique<AddTrack>("over", 0xFF000000u)));
    CHECK(f.history.execute(std::make_unique<SetTempo>(500.0)));
    CHECK(f.project.tempo == 300.0);
    CHECK(f.history.undo());
    CHECK(f.project.tempo == 120.0);
}

TEST(model_synth_param_command) {
    Fixture f;
    CHECK(f.history.execute(std::make_unique<SetTrackSynthParam>(f.track, MDAW_PARAM_CUTOFF_HZ, 900.0f)));
    CHECK(f.project.tracks[0].synth.cutoffHz == 900.0f);
    CHECK(!f.history.execute(std::make_unique<SetTrackSynthParam>(f.track, MDAW_PARAM_CUTOFF_HZ, 900.0f)));
    CHECK(f.history.undo());
    CHECK(f.project.tracks[0].synth.cutoffHz == SynthParams{}.cutoffHz);
}

TEST(model_compound_is_one_undo_and_all_or_nothing) {
    Fixture f;
    auto ids = f.addNotes({note(0, 60)});
    const auto before = f.history.undoCount();

    auto ok = std::make_unique<CompoundCommand>("line tool");
    ok->add(std::make_unique<AddNotes>(f.clip, std::vector<Note>{note(kPpq, 62)}));
    ok->add(std::make_unique<AddNotes>(f.clip, std::vector<Note>{note(kPpq * 2, 63)}));
    CHECK(f.history.execute(std::move(ok)));
    CHECK(f.theClip().notes.size() == 3);
    CHECK(f.history.undoCount() == before + 1);
    CHECK(f.history.undo());
    CHECK(f.theClip().notes.size() == 1);

    auto bad = std::make_unique<CompoundCommand>("partly invalid");
    bad->add(std::make_unique<AddNotes>(f.clip, std::vector<Note>{note(kPpq, 62)}));
    bad->add(std::make_unique<AddNotes>(f.clip, std::vector<Note>{note(0, 999)}));
    CHECK(!f.history.execute(std::move(bad)));
    CHECK(f.theClip().notes.size() == 1); // 途中まで入ったものも戻っている
    CHECK(f.theClip().notes[0].id == ids[0]);
}

TEST(model_history_limit_and_revision) {
    Project p = makeDefaultProject();
    History h(p, 3);
    const auto r0 = h.revision();
    for (int bpm = 100; bpm < 106; ++bpm)
        CHECK(h.execute(std::make_unique<SetTempo>(bpm)));
    CHECK(h.undoCount() == 3);
    CHECK(h.revision() == r0 + 6);
    while (h.undo()) {}
    CHECK(p.tempo == 102.0); // 古い3件は捨てられているので 102 までしか戻らない
    CHECK(h.execute(std::make_unique<SetTempo>(140)));
    CHECK(!h.canRedo()); // 新しい編集で Redo は消える
}

} // namespace
