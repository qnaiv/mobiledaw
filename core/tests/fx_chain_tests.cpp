// FX チェーン（Phase 1）のテスト: 移行のビット一致、チェーン順序、複数ユニット、
// 無効ユニットのバイパス、上限、グラニュラーの freeze / feedback / メイクアップ。
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "commands.h"
#include "engine.h"
#include "fx.h"
#include "history.h"
#include "mdaw.h"
#include "model.h"
#include "playback.h"
#include "project_json.h"
#include "test_util.h"

namespace {

using namespace mdaw;

constexpr double kRate = 48000.0;

float rmsOf(const std::vector<float>& x, size_t from, size_t to) {
    double sum = 0.0;
    size_t n = 0;
    for (size_t i = from; i < to && i < x.size(); ++i) {
        sum += static_cast<double>(x[i]) * x[i];
        ++n;
    }
    return n > 0 ? static_cast<float>(std::sqrt(sum / static_cast<double>(n))) : 0.0f;
}

float peakOf(const std::vector<float>& x) {
    float p = 0.0f;
    for (float v : x)
        p = std::max(p, std::abs(v));
    return p;
}

bool allFinite(const std::vector<float>& x) {
    for (float v : x)
        if (!std::isfinite(v))
            return false;
    return true;
}

// インターリーブでレンダーする（エンジン経由。スナップショット採用も通る）
std::vector<float> renderProject(const Project& project, int frames) {
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(project));
    e.play();
    std::vector<float> out;
    std::vector<float> buf(512 * 2);
    for (int done = 0; done < frames; done += 512) {
        const int n = std::min(512, frames - done);
        e.render(buf.data(), n, 2);
        out.insert(out.end(), buf.begin(), buf.begin() + n * 2);
    }
    return out;
}

// TrackFx にサイン波（または無音）を流して左だけ集める
std::vector<float> runFx(TrackFx& fx, int totalSamples, bool withInput) {
    std::vector<float> out;
    std::vector<float> l(256), r(256);
    double phase = 0.0;
    for (int done = 0; done < totalSamples; done += 256) {
        for (int i = 0; i < 256; ++i) {
            const float v = withInput && done + i < 48000 ? 0.5f * static_cast<float>(std::sin(phase)) : 0.0f;
            l[static_cast<size_t>(i)] = r[static_cast<size_t>(i)] = v;
            phase += 2.0 * 3.14159265 * 440.0 / kRate;
        }
        fx.process(l.data(), r.data(), 256);
        out.insert(out.end(), l.begin(), l.end());
    }
    return out;
}

FxUnit unitOf(FxUnitType type, const FxParams& p, bool enabled = true) {
    FxUnit u = makeFxUnit(type, p);
    u.enabled = enabled;
    return u;
}

// 旧形式（fxChain 無し・フラット fx）のプロジェクト JSON。複数段が有効な状態
const char* kLegacyJson = R"JSON({
  "format": "mobiledaw-project", "version": 1, "title": "移行テスト", "tempo": 100,
  "timeSig": [4, 4], "key": {"root": 0, "scale": "minor"},
  "tracks": [{
    "id": "0000000000001001", "name": "パッド", "color": "ffc8f25a",
    "instrument": {"type": "synth", "params": {}},
    "fx": {"lowCutHz": 200, "eqLowDb": 3, "eqMidDb": -2, "saturation": 0.3, "chorus": 0,
           "comp": 0.5, "ott": 0, "bitcrush": 0.3, "stutter": 0,
           "granular": 0.7, "granularSizeMs": 180, "granularDensity": 30, "granularPositionS": 0.4,
           "granularSpray": 0.5, "granularPitch": 12, "granularPitchSpread": 3,
           "delay": 0.4, "delayFeedback": 0.4, "reverb": 0.5, "reverbSize": 0.7,
           "sendReverb": 0.3, "sendDelay": 0.2},
    "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
  }],
  "clips": [{
    "id": "0000000000002001", "trackId": "0000000000001001", "lengthTicks": 15360,
    "notes": [
      {"id": "0000000000003001", "tick": 0, "length": 3840, "pitch": 57, "velocity": 0.8},
      {"id": "0000000000003002", "tick": 0, "length": 3840, "pitch": 60, "velocity": 0.8},
      {"id": "0000000000003003", "tick": 0, "length": 3840, "pitch": 64, "velocity": 0.8},
      {"id": "0000000000003004", "tick": 3840, "length": 3840, "pitch": 55, "velocity": 0.8},
      {"id": "0000000000003005", "tick": 3840, "length": 3840, "pitch": 59, "velocity": 0.8},
      {"id": "0000000000003006", "tick": 3840, "length": 3840, "pitch": 62, "velocity": 0.8}
    ]
  }],
  "placements": [{"id": "0000000000004001", "clipId": "0000000000002001", "trackId": "0000000000001001", "startBar": 0, "lengthBars": 4}]
})JSON";

// kLegacyJson と同じ内容をコードで組んだプロジェクト（チェーンは空＝フラット互換経路）
Project makeFlatTwin() {
    Project p;
    p.title = "移行テスト";
    p.tempo = 100.0;
    Track t;
    t.id = 0x1001;
    t.name = "パッド";
    FxParams& f = t.fx;
    f.lowCutHz = 200.0f;
    f.eqLowDb = 3.0f;
    f.eqMidDb = -2.0f;
    f.saturation = 0.3f;
    f.comp = 0.5f;
    f.bitcrush = 0.3f;
    f.granular = 0.7f;
    f.granularSizeMs = 180.0f;
    f.granularDensity = 30.0f;
    f.granularPositionS = 0.4f;
    f.granularSpray = 0.5f;
    f.granularPitch = 12.0f;
    f.granularPitchSpread = 3.0f;
    f.delay = 0.4f;
    f.delayFeedback = 0.4f;
    f.reverb = 0.5f;
    f.reverbSize = 0.7f;
    f.sendReverb = 0.3f;
    f.sendDelay = 0.2f;
    p.tracks.push_back(t);
    Clip c;
    c.id = 0x2001;
    c.trackId = 0x1001;
    c.lengthTicks = 15360;
    const int pitches[6] = {57, 60, 64, 55, 59, 62};
    for (int i = 0; i < 6; ++i) {
        Note n;
        n.id = static_cast<Id>(0x3001 + i);
        n.tick = i < 3 ? 0 : 3840;
        n.length = 3840;
        n.pitch = pitches[i];
        n.velocity = 0.8f;
        c.notes.push_back(n);
    }
    c.sortNotes();
    p.clips.push_back(c);
    Placement pl;
    pl.id = 0x4001;
    pl.clipId = 0x2001;
    pl.trackId = 0x1001;
    pl.startBar = 0;
    pl.lengthBars = 4;
    p.placements.push_back(pl);
    return p;
}

const FxUnit* findUnit(const Track& t, FxUnitType type, int nth = 0) {
    for (const auto& u : t.fxChain)
        if (u.type == type && nth-- == 0)
            return &u;
    return nullptr;
}

} // namespace

// 移行: 旧形式 JSON を読んで組んだチェーンと、フラット互換経路のレンダーがビット一致する
TEST(fxchain_migration_render_is_bit_identical) {
    Project migrated;
    std::string error;
    CHECK(projectFromJson(kLegacyJson, migrated, error));
    CHECK(migrated.tracks.size() == 1);
    const Track& t = migrated.tracks[0];
    CHECK(t.fxChain.size() == static_cast<size_t>(kNumFxUnitTypes));
    // enabled は「実際に効く状態か」で決まる
    CHECK(findUnit(t, FxUnitType::LowCut)->enabled);
    CHECK(findUnit(t, FxUnitType::Eq)->enabled);
    CHECK(findUnit(t, FxUnitType::Saturation)->enabled);
    CHECK(!findUnit(t, FxUnitType::Chorus)->enabled);   // chorus = 0
    CHECK(findUnit(t, FxUnitType::Comp)->enabled);
    CHECK(!findUnit(t, FxUnitType::Ott)->enabled);      // ott = 0
    CHECK(findUnit(t, FxUnitType::Bitcrush)->enabled);
    CHECK(!findUnit(t, FxUnitType::Stutter)->enabled);  // stutter = 0
    CHECK(findUnit(t, FxUnitType::Granular)->enabled);
    CHECK(findUnit(t, FxUnitType::Delay)->enabled);
    CHECK(findUnit(t, FxUnitType::Reverb)->enabled);
    // 値は旧値のまま写っている
    CHECK(findUnit(t, FxUnitType::Granular)->params.granular == 0.7f);
    CHECK(findUnit(t, FxUnitType::Granular)->params.granularPitch == 12.0f);
    CHECK(t.fx.sendReverb == 0.3f); // センドはトラック直属のまま

    const auto a = renderProject(migrated, 48000 * 4);
    const auto b = renderProject(makeFlatTwin(), 48000 * 4);
    CHECK(peakOf(a) > 0.05f); // 鳴っている
    CHECK(a == b);            // ビット単位で一致
}

// チェーンの順序が音に効く: リバーブ→ディレイ と ディレイ→リバーブ は違う音になる
TEST(fxchain_order_matters) {
    FxParams dp;
    dp.delay = 0.5f;
    dp.delayFeedback = 0.45f;
    FxParams rp;
    rp.reverb = 0.6f;
    rp.reverbSize = 0.7f;
    auto render = [&](bool delayFirst) {
        TrackFx fx;
        fx.prepare(kRate, 256);
        fx.setTempo(120.0);
        FxChainState chain;
        chain.units[0] = unitOf(delayFirst ? FxUnitType::Delay : FxUnitType::Reverb, delayFirst ? dp : rp);
        chain.units[1] = unitOf(delayFirst ? FxUnitType::Reverb : FxUnitType::Delay, delayFirst ? rp : dp);
        chain.count = 2;
        fx.setChain(chain, FxParams{});
        return runFx(fx, 48000 * 2, true);
    };
    const auto a = render(true);
    const auto b = render(false);
    CHECK(allFinite(a) && allFinite(b));
    CHECK(rmsOf(a, 24000, 48000) > 0.01f);
    CHECK(a != b);
}

// グラニュラーを 2 個重ねると、1 個とは違う（そして鳴っている）音になる
TEST(fxchain_two_granular_units_stack) {
    FxParams gp;
    gp.granular = 0.8f;
    gp.granularSizeMs = 150.0f;
    gp.granularDensity = 30.0f;
    gp.granularPositionS = 0.3f;
    gp.granularFeedback = 0.0f;
    auto render = [&](int count) {
        TrackFx fx;
        fx.prepare(kRate, 256);
        FxChainState chain;
        for (int i = 0; i < count; ++i)
            chain.units[static_cast<size_t>(i)] = unitOf(FxUnitType::Granular, gp);
        chain.count = count;
        fx.setChain(chain, FxParams{});
        return runFx(fx, 48000 * 2, true);
    };
    const auto one = render(1);
    const auto two = render(2);
    CHECK(allFinite(two));
    CHECK(rmsOf(two, 24000, 48000) > 0.01f);
    CHECK(one != two);
}

// 無効ユニットは完全バイパス（ユニットが無いチェーンとビット一致）
TEST(fxchain_disabled_unit_is_bypass) {
    FxParams gp;
    gp.granular = 0.9f;
    gp.granularFeedback = 0.0f;
    auto render = [&](int mode) { // 0=無し 1=無効 2=有効
        TrackFx fx;
        fx.prepare(kRate, 256);
        FxChainState chain;
        if (mode > 0) {
            chain.units[0] = unitOf(FxUnitType::Granular, gp, mode == 2);
            chain.count = 1;
        }
        fx.setChain(chain, FxParams{});
        return runFx(fx, 48000, true);
    };
    const auto none = render(0);
    const auto off = render(1);
    const auto on = render(2);
    CHECK(none == off);
    CHECK(on != none);
}

// 上限 16: JSON 読み込みで切り詰め、追加コマンドも上限で止まる
TEST(fxchain_cap_is_enforced) {
    std::string json = R"({"format":"mobiledaw-project","version":1,"title":"cap","tempo":120,)"
                       R"("tracks":[{"id":"0000000000001001","name":"t","instrument":{"type":"synth","params":{}},)"
                       R"("fxChain":[)";
    for (int i = 0; i < 18; ++i)
        json += R"({"type":"granular","enabled":true,"params":{"granular":0.5}})" + std::string(i < 17 ? "," : "");
    json += R"(],"mixer":{"gain":0.8}}],"clips":[],"placements":[]})";
    Project p;
    std::string error;
    CHECK(projectFromJson(json, p, error));
    CHECK(p.tracks.size() == 1);
    CHECK(static_cast<int>(p.tracks[0].fxChain.size()) == kMaxFxUnits);

    History history{p};
    CHECK(!history.execute(std::make_unique<AddFxUnit>(0x1001, FxUnitType::Delay))); // 満杯では追加できない
    CHECK(history.execute(std::make_unique<RemoveFxUnit>(0x1001, 0)));
    CHECK(history.execute(std::make_unique<AddFxUnit>(0x1001, FxUnitType::Delay)));
    CHECK(static_cast<int>(p.tracks[0].fxChain.size()) == kMaxFxUnits);
    CHECK(p.tracks[0].fxChain.back().type == FxUnitType::Delay);
    CHECK(history.undo());
    CHECK(p.tracks[0].fxChain.back().type == FxUnitType::Granular);
}

// フリーズ: 入力が止まっても粒が凍った素材を回し続ける（非フリーズでは消える）。
// フリーズは「素材を取り込んでから」切り替える（最初からオンだと何も取り込めない）
TEST(fxchain_freeze_keeps_sound_after_input_stops) {
    auto render = [&](bool freeze) {
        FxParams p;
        p.granular = 1.0f;
        p.granularSizeMs = 120.0f;
        p.granularDensity = 30.0f;
        p.granularPositionS = 0.2f;
        p.granularSpray = 0.2f;
        p.granularFeedback = 0.0f;
        TrackFx fx;
        fx.prepare(kRate, 256);
        fx.setParams(p);
        std::vector<float> out;
        std::vector<float> l(256), r(256);
        double phase = 0.0;
        bool toggled = false;
        for (int done = 0; done < 48000 * 3; done += 256) {
            if (freeze && !toggled && done >= 48000) {
                fx.setParam(MDAW_FX_GRANULAR_FREEZE, 1.0f); // 1 秒取り込んでから凍らせる
                toggled = true;
            }
            for (int i = 0; i < 256; ++i) {
                const float v = done + i < 48000 ? 0.5f * static_cast<float>(std::sin(phase)) : 0.0f;
                l[static_cast<size_t>(i)] = r[static_cast<size_t>(i)] = v;
                phase += 2.0 * 3.14159265 * 440.0 / kRate;
            }
            fx.process(l.data(), r.data(), 256);
            out.insert(out.end(), l.begin(), l.end());
        }
        return out;
    };
    const auto frozen = render(true);
    const auto plain = render(false);
    const float frozenTail = rmsOf(frozen, 48000 + 24000, 48000 * 3); // 止めて 0.5〜2 秒
    const float plainTail = rmsOf(plain, 48000 + 24000, 48000 * 3);
    std::printf("  フリーズ 尾 %.4f / 通常 尾 %.5f\n", frozenTail, plainTail);
    CHECK(frozenTail > 0.01f);
    CHECK(plainTail < 0.003f);
    CHECK(frozenTail > plainTail * 5.0f);
}

// フィードバック: 戻すほど尾が伸びて大きく残る
TEST(fxchain_feedback_lengthens_tail) {
    auto render = [&](float fb, double& tailSeconds) {
        FxParams p;
        p.granular = 1.0f;
        p.granularSizeMs = 120.0f;
        p.granularDensity = 30.0f;
        p.granularPositionS = 0.2f;
        p.granularSpray = 0.2f;
        p.granularFeedback = fb;
        TrackFx fx;
        fx.prepare(kRate, 256);
        fx.setParams(p);
        tailSeconds = fx.tailSeconds();
        return runFx(fx, 48000 * 3, true);
    };
    double tail0 = 0.0, tailFb = 0.0;
    const auto noFb = render(0.0f, tail0);
    const auto withFb = render(0.85f, tailFb);
    const float late0 = rmsOf(noFb, 48000 + 36000, 48000 * 3);   // 止めて 0.75〜2 秒
    const float lateFb = rmsOf(withFb, 48000 + 36000, 48000 * 3);
    std::printf("  フィードバック 尾 fb=0 %.5f / fb=0.85 %.4f（tailSeconds %.2f → %.2f）\n", late0, lateFb, tail0, tailFb);
    CHECK(allFinite(withFb));
    CHECK(lateFb > late0 * 2.0f);
    CHECK(tailFb > tail0);
}

// メイクアップ: mix 0.7 でウェット込みの出力がドライから -4 dB 以内に収まり、クリップしない。
// 題材はパッド的な和音フレーズ（粒が拾う対象として代表的なもの）で測る
TEST(fxchain_wet_makeup_level) {
    auto phrase = [&](TrackFx& fx, int totalSamples) {
        std::vector<float> out;
        std::vector<float> l(256), r(256);
        double ph[3] = {0.0, 0.0, 0.0};
        const double freqs[3] = {220.0, 261.63, 329.63}; // A3 / C4 / E4
        for (int done = 0; done < totalSamples; done += 256) {
            for (int i = 0; i < 256; ++i) {
                // 2 秒周期でゆっくり膨らむフレーズ
                const double t = static_cast<double>(done + i) / kRate;
                const float env = 0.55f + 0.45f * static_cast<float>(std::sin(6.2831853 * t / 2.0));
                float v = 0.0f;
                for (int k = 0; k < 3; ++k) {
                    v += 0.22f * static_cast<float>(std::sin(ph[k])) * env;
                    ph[k] += 2.0 * 3.14159265 * freqs[k] / kRate;
                }
                l[static_cast<size_t>(i)] = r[static_cast<size_t>(i)] = v;
            }
            fx.process(l.data(), r.data(), 256);
            out.insert(out.end(), l.begin(), l.end());
        }
        return out;
    };
    TrackFx dryFx;
    dryFx.prepare(kRate, 256);
    dryFx.setParams(FxParams{});
    const auto dry = phrase(dryFx, 48000 * 2);
    const float dryRms = rmsOf(dry, 24000, 48000);

    FxParams p;
    p.granular = 0.7f;
    p.granularSizeMs = 180.0f;
    p.granularDensity = 30.0f;
    p.granularPositionS = 0.4f;
    p.granularSpray = 0.5f;
    p.granularPitch = 12.0f;
    p.granularPitchSpread = 3.0f;
    p.granularFeedback = 0.0f; // メイクアップだけを測る
    TrackFx fx;
    fx.prepare(kRate, 256);
    fx.setParams(p);
    const auto wet = phrase(fx, 48000 * 2);
    const float wetRms = rmsOf(wet, 24000, 48000);
    const float ratioDb = 20.0f * std::log10(wetRms / std::max(dryRms, 1e-9f));
    std::printf("  メイクアップ ドライ %.4f / mix0.7 %.4f（%.1f dB）ピーク %.3f\n", dryRms, wetRms, ratioDb, peakOf(wet));
    CHECK(ratioDb >= -4.0f);
    CHECK(peakOf(wet) <= 1.0f);
}

// チェーンの保存往復: 並び・有効・値が保たれ、fx には直属だけが残る
TEST(fxchain_json_roundtrip_preserves_chain) {
    Project proj;
    Track t;
    t.id = 7;
    FxParams rp;
    rp.reverb = 0.5f;
    FxParams dp;
    dp.delay = 0.4f;
    FxParams gp;
    gp.granular = 0.6f;
    gp.granularFreeze = 1.0f;
    t.fxChain = {unitOf(FxUnitType::Reverb, rp), unitOf(FxUnitType::Delay, dp, false),
                 unitOf(FxUnitType::Granular, gp)};
    t.fx.sendReverb = 0.25f;
    mergeChainIntoFlat(t.fx, t.fxChain);
    proj.tracks.push_back(t);

    const std::string json = projectToJson(proj);
    CHECK(json.find("\"fxChain\"") != std::string::npos);
    Project back;
    std::string error;
    CHECK(projectFromJson(json, back, error));
    CHECK(back.tracks.size() == 1);
    CHECK(back.tracks[0].fxChain == t.fxChain);
    CHECK(back.tracks[0].fx == t.fx);
    CHECK(back.tracks[0].fx.granularFreeze == 1.0f); // 87 番も名前で往復する
}

// フラット書き込み（プリセット／マクロ経路）: 無効ユニットは値が効く状態になったら自動で有効になる
TEST(fxchain_flat_write_auto_enables_and_undoes) {
    Project p;
    std::string error;
    CHECK(projectFromJson(kLegacyJson, p, error));
    History history{p};
    // 移行直後、コーラスは無効（量 0）。フラットに書くと最初のコーラスユニットへ当たり、有効になる
    CHECK(history.execute(std::make_unique<SetTrackSynthParam>(0x1001, MDAW_FX_CHORUS, 0.5f)));
    const auto* chorus = findUnit(p.tracks[0], FxUnitType::Chorus);
    CHECK(chorus != nullptr && chorus->enabled);
    CHECK(chorus->params.chorus == 0.5f);
    CHECK(p.tracks[0].fx.chorus == 0.5f); // 互換ビューも同期
    CHECK(history.undo());
    chorus = findUnit(p.tracks[0], FxUnitType::Chorus);
    CHECK(chorus != nullptr && !chorus->enabled);
    CHECK(chorus->params.chorus == 0.0f);
}

// オートメーションの当て先: 最初の「有効」ユニットだけに当たる
TEST(fxchain_automation_targets_first_enabled_unit) {
    FxParams gp;
    gp.granular = 0.5f;
    TrackFx fx;
    fx.prepare(kRate, 256);
    FxChainState chain;
    chain.units[0] = unitOf(FxUnitType::Granular, gp, false); // 無効
    chain.units[1] = unitOf(FxUnitType::Granular, gp, true);  // 有効
    chain.count = 2;
    fx.setChain(chain, FxParams{});
    CHECK(fx.setParamAutomated(MDAW_FX_GRANULAR_PITCH, 7.0f));
    CHECK(fx.chain().units[0].params.granularPitch == 0.0f); // 無効な方には当たらない
    CHECK(fx.chain().units[1].params.granularPitch == 7.0f);
    // 全部無効なら当てる先が無い
    FxChainState off;
    off.units[0] = unitOf(FxUnitType::Granular, gp, false);
    off.count = 1;
    fx.setChain(off, FxParams{});
    CHECK(!fx.setParamAutomated(MDAW_FX_GRANULAR_PITCH, 3.0f));
}

// 移行の仕上げ: レーンがあるパラメータのユニットは、量が 0 でも有効になる
TEST(fxchain_migration_lane_enables_unit) {
    const std::string json = R"JSON({
      "format": "mobiledaw-project", "version": 1, "title": "lane", "tempo": 120,
      "tracks": [{"id": "0000000000001001", "name": "t", "instrument": {"type": "synth", "params": {}},
                  "fx": {"reverb": 0}, "mixer": {"gain": 0.8}}],
      "clips": [{"id": "0000000000002001", "trackId": "0000000000001001", "lengthTicks": 3840,
                 "notes": [{"id": "0000000000003001", "tick": 0, "length": 960, "pitch": 60, "velocity": 0.8}],
                 "automation": [{"param": "reverb", "points": [[0, 0.6], [1920, 0.2]]}]}],
      "placements": [{"id": "0000000000004001", "clipId": "0000000000002001", "trackId": "0000000000001001", "startBar": 0, "lengthBars": 1}]
    })JSON";
    Project p;
    std::string error;
    CHECK(projectFromJson(json, p, error));
    const auto* reverb = findUnit(p.tracks[0], FxUnitType::Reverb);
    CHECK(reverb != nullptr);
    CHECK(reverb->enabled); // 量 0 でもレーンがあるので有効（旧形式ではレーンが必ず当たっていた）
}
