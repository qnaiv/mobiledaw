// C API のプロジェクト操作と Session（編集 → 再生用データ → 音）のテスト
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include <juce_core/juce_core.h>

#include "commands.h"
#include "engine.h"
#include "mdaw.h"
#include "session.h"
#include "test_util.h"

namespace {

using namespace mdaw;

// mdaw_project_json を読んで数を数える
struct Json {
    juce::var root;
    explicit Json(mdaw_engine* e) { root = juce::JSON::parse(juce::String::fromUTF8(mdaw_project_json(e))); }
    int count(const char* key) const {
        auto* a = root.getProperty(key, juce::var()).getArray();
        return a ? a->size() : -1;
    }
    int noteCount() const {
        int n = 0;
        if (auto* clips = root.getProperty("clips", juce::var()).getArray())
            for (auto& c : *clips)
                if (auto* notes = c.getProperty("notes", juce::var()).getArray())
                    n += notes->size();
        return n;
    }
    juce::var firstNote() const {
        auto* clips = root.getProperty("clips", juce::var()).getArray();
        if (clips == nullptr || clips->isEmpty())
            return {};
        auto* notes = (*clips)[0].getProperty("notes", juce::var()).getArray();
        return notes && !notes->isEmpty() ? (*notes)[0] : juce::var();
    }
    double tempo() const { return root.getProperty("tempo", 0.0); }
};

std::string tempPath(const char* name) {
    return juce::File::getSpecialLocation(juce::File::tempDirectory)
        .getChildFile(juce::String("mdaw_test_") + name + "_" + juce::String(juce::Random::getSystemRandom().nextInt()))
        .getFullPathName()
        .toStdString();
}

TEST(api_new_project_starts_clean) {
    mdaw_engine* e = mdaw_create();
    Json j(e);
    CHECK(j.count("tracks") == 1);
    CHECK(j.count("clips") == 0);
    CHECK(mdaw_project_is_dirty(e) == 0);
    CHECK(mdaw_can_undo(e) == 0);
    mdaw_destroy(e);
}

TEST(api_edit_undo_redo) {
    mdaw_engine* e = mdaw_create();
    const auto v0 = mdaw_project_version(e);
    const mdaw_id track = mdaw_add_track(e, "Bass", 0xFF3366FFu);
    CHECK(track != 0);
    mdaw_id placement = 0;
    const mdaw_id clip = mdaw_create_clip(e, track, 0, 1, &placement);
    CHECK(clip != 0 && placement != 0);
    const mdaw_id n1 = mdaw_add_note(e, clip, 0, 480, 60, 0.9f);
    const mdaw_id n2 = mdaw_add_note(e, clip, 960, 480, 64, 0.9f);
    CHECK(n1 != 0 && n2 != 0 && n1 != n2);
    CHECK(mdaw_project_version(e) > v0);
    CHECK(mdaw_project_is_dirty(e) == 1);
    CHECK(Json(e).noteCount() == 2);

    const mdaw_id both[] = {n1, n2};
    CHECK(mdaw_move_notes(e, clip, both, 2, 240, 2) == 1);
    CHECK(mdaw_resize_notes(e, clip, both, 1, 240) == 1);
    auto first = Json(e).firstNote();
    CHECK(static_cast<int>(first.getProperty("tick", -1)) == 240);
    CHECK(static_cast<int>(first.getProperty("pitch", -1)) == 62);
    CHECK(static_cast<int>(first.getProperty("length", -1)) == 720);

    CHECK(mdaw_delete_notes(e, clip, both, 2) == 1);
    CHECK(Json(e).noteCount() == 0);
    CHECK(mdaw_undo(e) == 1);
    CHECK(Json(e).noteCount() == 2);
    CHECK(mdaw_redo(e) == 1);
    CHECK(Json(e).noteCount() == 0);

    // 複製と配置の移動
    const mdaw_id copy = mdaw_place_clip(e, clip, 1);
    CHECK(copy != 0);
    CHECK(mdaw_move_placement(e, copy, 3) == 1);
    CHECK(Json(e).count("placements") == 2);
    CHECK(mdaw_remove_placement(e, copy) == 1);
    CHECK(Json(e).count("placements") == 1);

    CHECK(mdaw_set_tempo(e, 90.0) == 1);
    CHECK(Json(e).tempo() == 90.0);
    CHECK(mdaw_set_track_param(e, track, MDAW_PARAM_CUTOFF_HZ, 1200.0f) == 1);
    CHECK(mdaw_set_track_param_live(e, track, MDAW_PARAM_CUTOFF_HZ, 900.0f) == 1);
    mdaw_preview_track(e, track);
    mdaw_destroy(e);
}

TEST(api_rejects_bad_input) {
    mdaw_engine* e = mdaw_create();
    const auto v = mdaw_project_version(e);
    CHECK(mdaw_add_note(e, 12345, 0, 480, 60, 1.0f) == 0);   // ないクリップ
    CHECK(mdaw_create_clip(e, 0, 0, 1, nullptr) == 0);       // ないトラック
    CHECK(mdaw_delete_notes(e, 1, nullptr, 3) == 0);
    CHECK(mdaw_move_placement(e, 999, 2) == 0);
    CHECK(mdaw_set_track_param_live(e, 42, MDAW_PARAM_CUTOFF_HZ, 1.0f) == 0);
    CHECK(mdaw_undo(e) == 0);
    CHECK(mdaw_project_version(e) == v); // 失敗した操作では変わらない
    CHECK(mdaw_add_note(nullptr, 1, 0, 1, 60, 1.0f) == 0);
    CHECK(std::string(mdaw_project_json(nullptr)).empty());
    mdaw_destroy(e);
}

TEST(api_edit_group_is_one_undo) {
    mdaw_engine* e = mdaw_create();
    const mdaw_id track = mdaw_add_track(e, "Lead", 0xFFFFFFFFu);
    const mdaw_id clip = mdaw_create_clip(e, track, 0, 1, nullptr);
    mdaw_begin_edit_group(e);
    for (int i = 0; i < 4; ++i)
        CHECK(mdaw_add_note(e, clip, i * 240, 240, 60 + i, 0.8f) != 0);
    CHECK(mdaw_can_undo(e) == 0);       // グループの途中は Undo できない
    CHECK(Json(e).noteCount() == 4);    // でも中身はもう反映されている
    mdaw_end_edit_group(e);
    CHECK(mdaw_undo(e) == 1);
    CHECK(Json(e).noteCount() == 0);
    CHECK(Json(e).count("clips") == 1); // クリップ作成は別の Undo
    CHECK(mdaw_redo(e) == 1);
    CHECK(Json(e).noteCount() == 4);
    // 空のグループは履歴に残らない
    mdaw_begin_edit_group(e);
    mdaw_end_edit_group(e);
    CHECK(mdaw_undo(e) == 1);
    CHECK(Json(e).noteCount() == 0);
    mdaw_destroy(e);
}

TEST(api_save_and_load) {
    const auto path = tempPath("save.json");
    mdaw_engine* a = mdaw_create();
    const mdaw_id track = mdaw_add_track(a, "Keys", 0xFF00FF00u);
    const mdaw_id clip = mdaw_create_clip(a, track, 1, 1, nullptr);
    mdaw_add_note(a, clip, 480, 240, 67, 0.7f);
    CHECK(mdaw_project_save(a, path.c_str()) == MDAW_OK);
    CHECK(mdaw_project_is_dirty(a) == 0);
    const std::string saved = mdaw_project_json(a);

    mdaw_engine* b = mdaw_create();
    CHECK(mdaw_project_load(b, path.c_str()) == MDAW_OK);
    CHECK(std::string(mdaw_project_json(b)) == saved);
    CHECK(mdaw_project_is_dirty(b) == 0);
    CHECK(mdaw_can_undo(b) == 0);

    // 読めないファイルなら今のプロジェクトはそのまま
    CHECK(mdaw_project_load(b, (path + ".missing").c_str()) == MDAW_ERR_FILE);
    CHECK(std::string(mdaw_last_error(b)).size() > 0);
    CHECK(std::string(mdaw_project_json(b)) == saved);

    mdaw_project_new(b);
    CHECK(Json(b).count("clips") == 0);
    CHECK(mdaw_project_is_dirty(b) == 0);

    juce::File(path).deleteFile();
    mdaw_destroy(a);
    mdaw_destroy(b);
}

// 編集すると、そのまま再生に反映される（コア → スナップショット → 音声）
TEST(session_edits_reach_the_audio) {
    Engine engine;
    engine.prepare(48000.0);
    Session session(engine);
    const Id track = session.project().tracks.front().id;
    auto create = std::make_unique<CreateClip>(track, 0, 1);
    auto* raw = create.get();
    CHECK(session.execute(std::move(create)));
    const Id clip = raw->clipId();

    Note n;
    n.tick = kPpq; // 2拍目
    n.length = kPpq / 2;
    n.pitch = 60;
    n.velocity = 1.0f;
    CHECK(session.execute(std::make_unique<AddNotes>(clip, std::vector<Note>{n})));

    engine.play();
    std::vector<float> buf(256 * 2);
    long first = -1;
    for (long frame = 0; frame < 48000 && first < 0; frame += 256) {
        engine.render(buf.data(), 256, 2);
        for (int i = 0; i < 256; ++i)
            if (buf[static_cast<size_t>(i) * 2] != 0.0f) {
                first = frame + i;
                break;
            }
    }
    CHECK(first == 24000);

    // Undo するとノートは消え、次のループでは鳴らない
    CHECK(session.undo());
    engine.stop();
    for (int frame = 0; frame < 48000; frame += 256) // 鳴っていた音のリリースが終わるまで待つ
        engine.render(buf.data(), 256, 2);
    engine.play();
    float peak = 0.0f;
    for (int frame = 0; frame < 48000; frame += 256) {
        engine.render(buf.data(), 256, 2);
        for (float v : buf)
            peak = std::max(peak, std::abs(v));
    }
    CHECK(peak == 0.0f);
}

} // namespace
