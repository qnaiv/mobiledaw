// ミキサーのメーター用ピーク取得（mdaw_track_peak / mdaw_master_peak）のテスト。
// コアは「最後に読んでからの最大値」を保持するだけで、減衰は UI 側の仕事。
#include <cmath>
#include <vector>

#include "engine.h"
#include "mdaw.h"
#include "session.h"
#include "test_util.h"

namespace {

constexpr double kRate = 48000.0;

void renderBlocks(mdaw::Engine& engine, int frames, int block = 192) {
    std::vector<float> buf(static_cast<size_t>(block) * 2);
    for (int done = 0; done < frames; done += block) {
        const int n = std::min(block, frames - done);
        engine.render(buf.data(), n, 2);
    }
}

} // namespace

// 無音では 0、音が出れば >0、読むと 0 に戻る（トラック・マスター共通）
TEST(test_track_and_master_peak) {
    mdaw::Engine e;
    e.prepare(kRate);
    mdaw::Session session(e);
    const mdaw::Id track = session.project().tracks.front().id;

    CHECK(e.trackPeak(0) == 0.0f);
    CHECK(e.masterPeak() == 0.0f);
    CHECK(e.trackPeak(-1) == 0.0f);     // 範囲外は 0
    CHECK(e.trackPeak(9999) == 0.0f);

    e.setParam(MDAW_PARAM_RELEASE_S, 0.05f); // リリースを短くして尾を早く消す
    session.previewTrack(track);             // 試聴の音はこのトラックの FX を通る
    e.noteOn(60, 1.0f);
    renderBlocks(e, 4800);

    const float tp = e.trackPeak(0);
    CHECK(tp > 0.05f);
    CHECK(e.trackPeak(0) == 0.0f); // 読み取りでリセット（この間は描画していない）
    const float mp = e.masterPeak();
    CHECK(mp > 0.05f);
    CHECK(e.masterPeak() == 0.0f);

    // 音を止めて出し切れば、次に読むピークはほぼ 0 に戻る
    // （noteOff はキュー経由なので、まず1秒描画してリリースを流し切ってから捨て読みする）
    e.noteOff(60);
    renderBlocks(e, 48000);
    e.trackPeak(0);
    e.masterPeak(); // 捨て読み
    renderBlocks(e, 24000);
    CHECK(e.trackPeak(0) < 0.0001f);
    CHECK(e.masterPeak() < 0.0001f);
}

// C API のガード：nullptr・存在しないトラック・音声が動いていなければ 0
TEST(test_peak_c_api_guards) {
    CHECK(mdaw_track_peak(nullptr, 1) == 0.0f);
    CHECK(mdaw_master_peak(nullptr) == 0.0f);
    mdaw_engine* e = mdaw_create();
    CHECK(e != nullptr);
    CHECK(mdaw_track_peak(e, 999999) == 0.0f);
    CHECK(mdaw_master_peak(e) == 0.0f);
    mdaw_destroy(e);
}
