// クリップのオートメーションのテスト：補間・整形・コマンド・スナップショット展開・再生・JSON。
#include <cmath>
#include <cstdio>
#include <memory>
#include <vector>

#include "automation.h"
#include "commands.h"
#include "engine.h"
#include "history.h"
#include "mdaw.h"
#include "playback.h"
#include "project_json.h"
#include "test_util.h"

namespace {

using namespace mdaw;

constexpr double kRate = 48000.0;
// 120 BPM では 1拍 = 24000 サンプル、1 tick = 25 サンプル
constexpr int kSamplesPerBeat = 24000;

bool near(float a, float b, float eps = 1e-4f) { return std::fabs(a - b) <= eps; }

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

    void addNote(Id clip, int64_t tick, int pitch, int64_t length) {
        Note n;
        n.tick = tick;
        n.pitch = pitch;
        n.length = length;
        n.velocity = 1.0f;
        CHECK(history.execute(std::make_unique<AddNotes>(clip, std::vector<Note>{n})));
    }

    bool setAutomation(Id clip, int paramId, std::vector<AutomationPoint> points) {
        AutomationLane lane;
        lane.paramId = paramId;
        lane.points = std::move(points);
        return history.execute(std::make_unique<SetClipAutomation>(clip, std::move(lane)));
    }
};

float peak(const std::vector<float>& x, size_t from, size_t to) {
    float p = 0.0f;
    for (size_t i = from; i < to && i < x.size(); ++i)
        p = std::max(p, std::abs(x[i]));
    return p;
}

std::vector<float> renderLeft(Engine& e, int frames, int block = 192) {
    std::vector<float> buf(static_cast<size_t>(block) * 2);
    std::vector<float> out;
    for (int done = 0; done < frames; done += block) {
        const int n = std::min(block, frames - done);
        e.render(buf.data(), n, 2);
        for (int i = 0; i < n; ++i)
            out.push_back(buf[static_cast<size_t>(i) * 2]);
    }
    return out;
}

// ---- 補間 -------------------------------------------------------------------

TEST(automation_interp_linear_and_hold) {
    const std::vector<AutomationPoint> pts{{0, 0.0f}, {kPpq, 1.0f}, {kPpq * 2, 0.5f}};
    float v = -1.0f;
    CHECK(!automationValueAt({}, 0, v));                       // ポイントなし
    CHECK(!automationValueAt(pts, -1, v));                     // 最初のポイントより前
    CHECK(automationValueAt(pts, 0, v) && near(v, 0.0f));      // ちょうど
    CHECK(automationValueAt(pts, kPpq / 2, v) && near(v, 0.5f)); // 中間は線形
    CHECK(automationValueAt(pts, kPpq, v) && near(v, 1.0f));
    CHECK(automationValueAt(pts, kPpq * 3 / 2, v) && near(v, 0.75f));
    CHECK(automationValueAt(pts, kPpq * 2, v) && near(v, 0.5f));
    CHECK(automationValueAt(pts, kPpq * 100, v) && near(v, 0.5f)); // 後ろは保持
}

TEST(automation_normalize_sorts_dedupes_and_clamps) {
    AutomationLane lane;
    lane.paramId = MDAW_PARAM_CUTOFF_HZ;
    lane.points = {{kPpq, 500.0f}, {0, 999999.0f}, {kPpq, 800.0f}, {-5, 100.0f}, {kPpq * 5, 100.0f}};
    normalizeAutomationLane(lane, kPpq * 4);
    CHECK(lane.points.size() == 2);
    CHECK(lane.points[0].tick == 0 && near(lane.points[0].value, 20000.0f)); // 上限に丸める
    CHECK(lane.points[1].tick == kPpq && near(lane.points[1].value, 800.0f)); // 同じ tick は後勝ち

    AutomationLane gain;
    gain.paramId = MDAW_PARAM_TRACK_GAIN;
    gain.points = {{0, 5.0f}};
    normalizeAutomationLane(gain, kPpq * 4);
    CHECK(near(gain.points[0].value, 2.0f)); // 音量は 0〜2

    AutomationLane uni;
    uni.paramId = MDAW_PARAM_UNISON;
    uni.points = {{0, 3.6f}};
    normalizeAutomationLane(uni, kPpq * 4);
    CHECK(near(uni.points[0].value, 4.0f)); // 整数パラメータは四捨五入
}

TEST(automation_param_keys_round_trip) {
    int id = -1;
    CHECK(automationParamFromKey("cutoffHz", id) && id == MDAW_PARAM_CUTOFF_HZ);
    CHECK(automationParamFromKey("wtPos", id) && id == MDAW_PARAM_WT_POS);
    CHECK(automationParamFromKey("reverb", id) && id == MDAW_FX_REVERB);
    CHECK(automationParamFromKey("gain", id) && id == MDAW_PARAM_TRACK_GAIN);
    CHECK(!automationParamFromKey("noSuchParam", id));
    CHECK(std::string(automationParamKey(MDAW_PARAM_WT_POS)) == "wtPos");
    CHECK(std::string(automationParamKey(MDAW_PARAM_TRACK_GAIN)) == "gain");
    CHECK(isAutomationParam(MDAW_PARAM_CUTOFF_HZ));
    CHECK(isAutomationParam(MDAW_FX_DELAY));
    CHECK(isAutomationParam(MDAW_PARAM_TRACK_GAIN));
    CHECK(!isAutomationParam(999));
}

// ---- コマンド -----------------------------------------------------------------

TEST(automation_command_apply_undo_redo) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    CHECK(s.setAutomation(clip, MDAW_PARAM_CUTOFF_HZ, {{kPpq, 900.0f}, {0, 300.0f}}));
    const auto* c = s.project.findClip(clip);
    CHECK(c != nullptr && c->automation.size() == 1);
    CHECK(c->automation[0].points.size() == 2);
    CHECK(c->automation[0].points[0].tick == 0); // 並べ替えてある

    // 同じ内容では変わらない
    CHECK(!s.setAutomation(clip, MDAW_PARAM_CUTOFF_HZ, {{0, 300.0f}, {kPpq, 900.0f}}));

    CHECK(s.history.undo());
    CHECK(s.project.findClip(clip)->automation.empty());
    CHECK(s.history.redo());
    CHECK(s.project.findClip(clip)->automation.size() == 1);

    // 空のレーンで消える。元々無ければ false
    CHECK(s.setAutomation(clip, MDAW_PARAM_CUTOFF_HZ, {}));
    CHECK(s.project.findClip(clip)->automation.empty());
    CHECK(!s.setAutomation(clip, MDAW_PARAM_CUTOFF_HZ, {}));

    // 対象外のパラメータは弾く
    CHECK(!s.setAutomation(clip, 999, {{0, 1.0f}}));
}

// ---- スナップショット ------------------------------------------------------------

TEST(automation_snapshot_expands_repeats_to_absolute_ticks) {
    Song s;
    const Id clip = s.createClip(s.track, 0, 2); // 2小節のクリップを
    auto place = std::make_unique<PlaceClip>(clip, 4);
    CHECK(s.history.execute(std::move(place))); // 4小節目にも置く（配置の長さはクリップと同じ2小節）
    CHECK(s.setAutomation(clip, MDAW_PARAM_WT_POS, {{0, 0.25f}, {kPpq * 4, 0.75f}}));

    auto snap = buildSnapshot(s.project);
    CHECK(snap->automation.size() == 1);
    const auto& lane = snap->automation[0];
    CHECK(lane.slot == 0 && lane.paramId == MDAW_PARAM_WT_POS);
    const int64_t bar = kPpq * 4;
    // 1回目：0 と 1小節ぶん先。2回目（4小節目から）：4小節と5小節の位置
    CHECK(lane.points.size() == 4);
    CHECK(lane.points[0].tick == 0 && near(lane.points[0].value, 0.25f));
    CHECK(lane.points[1].tick == bar && near(lane.points[1].value, 0.75f));
    CHECK(lane.points[2].tick == bar * 4 && near(lane.points[2].value, 0.25f));
    CHECK(lane.points[3].tick == bar * 5 && near(lane.points[3].value, 0.75f));

    double next = -1;
    CHECK(snap->nextAutomationTick(-0.5, next) && next == 0.0);
    CHECK(snap->nextAutomationTick(0.0, next) && next == static_cast<double>(bar));
    CHECK(!snap->nextAutomationTick(static_cast<double>(bar * 5), next));
}

TEST(automation_snapshot_empty_without_lanes) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNote(clip, 0, 60, kPpq);
    auto snap = buildSnapshot(s.project);
    CHECK(snap->automation.empty()); // オートメーションが無ければ従来どおり（空）
    CHECK(snap->automationTicks.empty());
}

// ---- 再生 ---------------------------------------------------------------------

TEST(automation_gain_zero_silences_note) {
    Song withLane, without;
    for (auto* s : {&withLane, &without}) {
        const Id clip = s->createClip(s->track, 0);
        s->addNote(clip, 0, 60, kPpq * 2);
    }
    CHECK(withLane.setAutomation(withLane.project.clips[0].id, MDAW_PARAM_TRACK_GAIN, {{0, 0.0f}}));

    Engine e1;
    e1.prepare(kRate);
    e1.publish(buildSnapshot(without.project));
    e1.play();
    const auto plain = renderLeft(e1, kSamplesPerBeat);
    CHECK(peak(plain, 4800, plain.size()) > 0.02f); // レーンなしは鳴る

    Engine e2;
    e2.prepare(kRate);
    e2.publish(buildSnapshot(withLane.project));
    e2.play();
    const auto muted = renderLeft(e2, kSamplesPerBeat);
    CHECK(peak(muted, 0, muted.size()) == 0.0f); // 音量 0 のレーンで消える
}

TEST(automation_gain_ramp_opens_at_point) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNote(clip, 0, 60, kPpq * 4); // 1小節鳴りっぱなし
    // 2拍目までは 0、そこから開く
    CHECK(s.setAutomation(clip, MDAW_PARAM_TRACK_GAIN, {{0, 0.0f}, {kPpq * 2, 0.0f}, {kPpq * 3, 1.6f}}));
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(s.project));
    e.play();
    const auto out = renderLeft(e, kSamplesPerBeat * 4);
    CHECK(peak(out, 4800, kSamplesPerBeat * 2 - 4800) == 0.0f);      // 前半は無音
    CHECK(peak(out, kSamplesPerBeat * 3, kSamplesPerBeat * 4) > 0.05f); // 開いた後は鳴る
}

// ---- JSON ----------------------------------------------------------------------

TEST(automation_json_round_trip) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNote(clip, 0, 60, kPpq);
    CHECK(s.setAutomation(clip, MDAW_PARAM_CUTOFF_HZ, {{0, 300.0f}, {kPpq * 2, 5000.0f}}));
    CHECK(s.setAutomation(clip, MDAW_PARAM_TRACK_GAIN, {{0, 0.0f}, {kPpq, 1.2f}}));

    const auto json = projectToJson(s.project);
    CHECK(json.find("\"automation\"") != std::string::npos);
    CHECK(json.find("\"cutoffHz\"") != std::string::npos);
    CHECK(json.find("\"gain\"") != std::string::npos);

    Project q;
    std::string error;
    CHECK(projectFromJson(json, q, error));
    CHECK(q.clips.size() == 1);
    const auto& lanes = q.clips[0].automation;
    CHECK(lanes.size() == 2);
    const auto* cutoff = q.clips[0].findAutomation(MDAW_PARAM_CUTOFF_HZ);
    CHECK(cutoff != nullptr && cutoff->points.size() == 2);
    CHECK(cutoff->points[1].tick == kPpq * 2 && near(cutoff->points[1].value, 5000.0f));
    const auto* gain = q.clips[0].findAutomation(MDAW_PARAM_TRACK_GAIN);
    CHECK(gain != nullptr && gain->points.size() == 2 && near(gain->points[1].value, 1.2f));
    // 往復しても同じ形になる
    CHECK(projectToJson(q) == json);
}

TEST(automation_json_absent_in_plain_project) {
    Song s;
    const Id clip = s.createClip(s.track, 0);
    s.addNote(clip, 0, 60, kPpq);
    const auto json = projectToJson(s.project);
    CHECK(json.find("automation") == std::string::npos); // レーンが無ければ今までと完全に同じ形
}

TEST(automation_json_drops_broken_lanes) {
    const std::string json = R"({
      "format": "mobiledaw-project", "version": 1,
      "tracks": [{"id": "00000000000000aa", "name": "T"}],
      "clips": [{"id": "00000000000000c1", "trackId": "00000000000000aa", "lengthTicks": 3840,
        "notes": [],
        "automation": [
          {"param": "noSuchParam", "points": [[0, 1.0]]},
          {"param": "cutoffHz", "points": [[99999, 500.0], [0, 999999.0], [0]]},
          {"param": "cutoffHz", "points": [[0, 100.0]]}
        ]}],
      "placements": [{"id": "00000000000000d1", "clipId": "00000000000000c1", "trackId": "00000000000000aa", "startBar": 0, "lengthBars": 1}]
    })";
    Project q;
    std::string error;
    CHECK(projectFromJson(json, q, error));
    CHECK(q.clips.size() == 1);
    CHECK(q.clips[0].automation.size() == 1); // 知らない名前と重複は捨てる
    const auto& lane = q.clips[0].automation[0];
    CHECK(lane.paramId == MDAW_PARAM_CUTOFF_HZ);
    CHECK(lane.points.size() == 1);           // 範囲外 tick と壊れた組は捨てる
    CHECK(lane.points[0].tick == 0 && near(lane.points[0].value, 20000.0f)); // 値は丸める
}

} // namespace
