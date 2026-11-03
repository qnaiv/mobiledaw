// project.json の読み書きのテスト
#include <memory>

#include <juce_core/juce_core.h>

#include "commands.h"
#include "history.h"
#include "mdaw.h"
#include "project_json.h"
#include "test_util.h"

namespace {

using namespace mdaw;

Project sampleProject() {
    Project p = makeDefaultProject();
    History h(p);
    h.execute(std::make_unique<SetTempo>(96.5));
    h.execute(std::make_unique<AddTrack>("Bass ベース", 0xFF5AA9F2u));
    auto create = std::make_unique<CreateClip>(p.tracks[0].id, 0, 2);
    auto* raw = create.get();
    h.execute(std::move(create));
    Note a; a.tick = 0; a.pitch = 60; a.length = kPpq; a.velocity = 0.5f;
    Note b; b.tick = kPpq * 3; b.pitch = 67; b.length = kPpq / 2;
    h.execute(std::make_unique<AddNotes>(raw->clipId(), std::vector<Note>{a, b}));
    h.execute(std::make_unique<PlaceClip>(raw->clipId(), 4));
    h.execute(std::make_unique<SetTrackSynthParam>(p.tracks[1].id, MDAW_PARAM_RELEASE_S, 1.25f));
    p.keyRoot = 9;
    p.tracks[1].mixer.mute = true;
    return p;
}

TEST(json_round_trip_keeps_everything) {
    const Project p = sampleProject();
    const auto json = projectToJson(p);
    Project q;
    std::string error;
    CHECK(projectFromJson(json, q, error));
    CHECK(error.empty());
    CHECK(q.tempo == 96.5);
    CHECK(q.keyRoot == 9);
    CHECK(q.tracks.size() == 2);
    CHECK(q.tracks[1].name == "Bass ベース");
    CHECK(q.tracks[1].color == 0xFF5AA9F2u);
    CHECK(q.tracks[1].mixer.mute);
    CHECK(q.tracks[1].synth.releaseS == 1.25f);
    CHECK(q.clips.size() == 1);
    CHECK(q.clips[0].id == p.clips[0].id);
    CHECK(q.clips[0].lengthTicks == kPpq * 8);
    CHECK(q.clips[0].notes.size() == 2);
    CHECK(q.clips[0].notes[0].id == p.clips[0].notes[0].id);
    CHECK(q.clips[0].notes[0].velocity == 0.5f);
    CHECK(q.clips[0].notes[1].tick == kPpq * 3);
    CHECK(q.placements.size() == 2);
    CHECK(q.placements[1].startBar == 4);
    // もう一度書き出しても同じ文字列になる
    CHECK(projectToJson(q) == json);
}

TEST(json_rejects_other_files_and_newer_versions) {
    Project q = makeDefaultProject();
    const auto before = q.tracks[0].id;
    std::string error;
    CHECK(!projectFromJson("not json", q, error));
    CHECK(!error.empty());
    CHECK(!projectFromJson(R"({"format":"something-else","version":1})", q, error));
    CHECK(!projectFromJson(R"({"format":"mobiledaw-project","version":99,"tracks":[]})", q, error));
    CHECK(q.tracks[0].id == before); // 失敗しても元のまま
}

TEST(json_drops_broken_parts_but_keeps_the_rest) {
    const std::string json = R"({
      "format": "mobiledaw-project", "version": 1, "tempo": 999,
      "tracks": [{"id": "00000000000000aa", "name": "T"}, {"id": "bad"}],
      "clips": [
        {"id": "00000000000000c1", "trackId": "00000000000000aa", "lengthTicks": 3840,
         "notes": [{"id": "0000000000000001", "tick": 0, "length": 480, "pitch": 60},
                   {"id": "0000000000000002", "tick": 99999, "length": 480, "pitch": 60},
                   {"id": "0000000000000003", "tick": 0, "length": 480, "pitch": 300}]},
        {"id": "00000000000000c2", "trackId": "00000000000000ff", "lengthTicks": 3840}
      ],
      "placements": [
        {"id": "00000000000000d1", "clipId": "00000000000000c1", "trackId": "00000000000000aa", "startBar": 0, "lengthBars": 1},
        {"id": "00000000000000d2", "clipId": "00000000000000c2", "trackId": "00000000000000ff", "startBar": 0, "lengthBars": 1}
      ]
    })";
    Project q;
    std::string error;
    CHECK(projectFromJson(json, q, error));
    CHECK(q.tempo == 300.0);          // 範囲内に丸める
    CHECK(q.tracks.size() == 1);      // id が壊れたトラックは捨てる
    CHECK(q.clips.size() == 1);       // 存在しないトラックのクリップは捨てる
    CHECK(q.clips[0].notes.size() == 1);
    CHECK(q.placements.size() == 1);
}

TEST(json_file_save_and_load) {
    const auto dir = juce::File::getSpecialLocation(juce::File::tempDirectory)
                         .getChildFile("mdaw-test-" + juce::String::toHexString(juce::Random::getSystemRandom().nextInt64()));
    const auto path = dir.getChildFile("song.qdaw").getChildFile("project.json").getFullPathName().toStdString();
    const Project p = sampleProject();
    std::string error;
    CHECK(saveProjectFile(p, path, error));
    Project q;
    CHECK(loadProjectFile(path, q, error));
    CHECK(q.clips.size() == 1 && q.clips[0].notes.size() == 2);
    // 上書き保存しても壊れない
    CHECK(saveProjectFile(q, path, error));
    CHECK(loadProjectFile(path, q, error));
    CHECK(!loadProjectFile(path + ".missing", q, error));
    dir.deleteRecursively();
}

} // namespace
