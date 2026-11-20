// グラニュラー楽器（Phase 2.5）: サンプラーのグラニュラーモードのテスト。
// モード OFF のビット一致、鍵盤追従、位置モード 3 種、有界性、保存往復を見る。
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "commands.h"
#include "engine.h"
#include "mdaw.h"
#include "project_json.h"
#include "sampler.h"
#include "session.h"
#include "test_util.h"

namespace {

using namespace mdaw;

KitSound makeSineSound(double hz, double seconds, double sr = 44100.0) {
    KitSound s;
    s.name = "Tone";
    s.note = 60;
    s.gain = 1.0f;
    s.sampleRate = sr;
    const int n = static_cast<int>(sr * seconds);
    s.left.resize(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i)
        s.left[static_cast<size_t>(i)] = 0.5f * static_cast<float>(std::sin(2.0 * 3.14159265 * hz * i / sr));
    return s;
}

// 前半 110Hz・後半 330Hz の 2 秒素材（位置モードの検証用）
KitSound makeTwoToneSound(double sr = 44100.0) {
    KitSound s;
    s.name = "TwoTone";
    s.note = 60;
    s.gain = 1.0f;
    s.sampleRate = sr;
    const int half = static_cast<int>(sr);
    s.left.resize(static_cast<size_t>(half * 2));
    for (int i = 0; i < half * 2; ++i) {
        const double hz = i < half ? 110.0 : 330.0;
        s.left[static_cast<size_t>(i)] = 0.5f * static_cast<float>(std::sin(2.0 * 3.14159265 * hz * i / sr));
    }
    return s;
}

// 決定的なノイズ素材（フィードバックの有界性検証用）
KitSound makeNoiseSound(double seconds, double sr = 44100.0) {
    KitSound s;
    s.name = "Noise";
    s.note = 60;
    s.gain = 1.0f;
    s.sampleRate = sr;
    const int n = static_cast<int>(sr * seconds);
    s.left.resize(static_cast<size_t>(n));
    std::uint32_t rng = 0x1234567u;
    for (int i = 0; i < n; ++i) {
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        s.left[static_cast<size_t>(i)] = (static_cast<float>(rng >> 8) * (1.0f / 16777216.0f) * 2.0f - 1.0f) * 0.4f;
    }
    return s;
}

std::vector<float> renderStereo(MelodicSampler& s, int frames, std::vector<float>* rightOut = nullptr) {
    std::vector<float> l(static_cast<size_t>(frames), 0.0f), r(static_cast<size_t>(frames), 0.0f);
    for (int i = 0; i < frames; i += 512) {
        const int n = std::min(512, frames - i);
        s.render(l.data() + i, r.data() + i, n);
    }
    if (rightOut != nullptr)
        *rightOut = r;
    return l;
}

float peakOf(const std::vector<float>& v, size_t from, size_t to) {
    float p = 0.0f;
    for (size_t i = from; i < std::min(to, v.size()); ++i)
        p = std::max(p, std::abs(v[i]));
    return p;
}

double rmsOf(const std::vector<float>& v, size_t from, size_t to) {
    double sum = 0.0;
    const size_t end = std::min(to, v.size());
    for (size_t i = from; i < end; ++i)
        sum += static_cast<double>(v[i]) * v[i];
    return end > from ? std::sqrt(sum / static_cast<double>(end - from)) : 0.0;
}

double estimateHz(const std::vector<float>& v, size_t from, size_t to, double sr) {
    int crossings = 0;
    const size_t end = std::min(to, v.size());
    for (size_t i = from + 1; i < end; ++i)
        if ((v[i - 1] < 0.0f) != (v[i] < 0.0f))
            ++crossings;
    const double seconds = static_cast<double>(end - from) / sr;
    return seconds > 0.0 ? crossings / 2.0 / seconds : 0.0;
}

// 雲の基本設定（決定的に寄せる: 確率発生オフ・ばらつき最小・フィードバックなし）
GranularSamplerSettings cloudSettings() {
    GranularSamplerSettings g;
    g.enabled = 1.0f;
    g.sizeMs = 200.0f;
    g.density = 60.0f;
    g.position = 0.0f;
    g.spray = 0.0f;
    g.texture = 0.3f;
    g.pitchSpread = 0.0f;
    g.timingRandom = 0.0f;
    g.sizeRandom = 0.0f;
    g.reverseChance = 0.0f;
    g.positionMode = 0.0f;
    g.roam = 0.0f;
    g.feedback = 0.0f;
    return g;
}

} // namespace

TEST(granular_sampler_off_is_bit_identical) {
    auto sound = makeSineSound(220.0, 2.0);
    auto renderWith = [&](bool callSetter, const GranularSamplerSettings& g) {
        MelodicSampler s;
        s.prepare(48000.0);
        s.setSound(&sound, 60, 1.0f, 0.0f);
        if (callSetter)
            s.setGranularSettings(g);
        s.noteOn(60, 0.9f);
        auto l = renderStereo(s, 24000);
        s.noteOff(60);
        auto tail = renderStereo(s, 24000);
        l.insert(l.end(), tail.begin(), tail.end());
        return l;
    };
    const auto plain = renderWith(false, GranularSamplerSettings{});
    const auto withDefaults = renderWith(true, GranularSamplerSettings{});
    GranularSamplerSettings tweaked = cloudSettings();
    tweaked.enabled = 0.0f; // 値を変えても OFF の間は従来どおり
    tweaked.sizeMs = 90.0f;
    tweaked.feedback = 0.8f;
    const auto offTweaked = renderWith(true, tweaked);
    CHECK(plain == withDefaults);
    CHECK(plain == offTweaked);
    CHECK(peakOf(plain, 0, plain.size()) > 0.3f); // 鳴ってはいる
}

TEST(granular_sampler_cloud_sounds_and_follows_pitch) {
    auto sound = makeSineSound(220.0, 3.0);
    auto playHz = [&](int note) {
        MelodicSampler s;
        s.prepare(48000.0);
        s.setSound(&sound, 60, 1.0f, 0.0f);
        s.setGranularSettings(cloudSettings());
        s.noteOn(note, 1.0f);
        const auto l = renderStereo(s, 48000 * 2);
        CHECK(s.activeClouds() == 1);
        CHECK(rmsOf(l, 24000, 48000) > 0.05); // 雲が鳴っている
        return estimateHz(l, 24000, 72000, 48000.0);
    };
    const double fRoot = playHz(60);
    const double fUp = playHz(72);
    std::printf("  雲 基準 %.1f Hz / +12 %.1f Hz\n", fRoot, fUp);
    CHECK(fRoot > 180.0 && fRoot < 270.0);
    CHECK(fUp > 360.0 && fUp < 540.0);
    CHECK(fUp > fRoot * 1.7); // 鍵盤追従で音程が上がる
}

TEST(granular_sampler_position_modes) {
    auto sound = makeTwoToneSound();
    auto renderMode = [&](float mode, float position, double songPos, int frames) {
        MelodicSampler s;
        s.prepare(48000.0);
        s.setSound(&sound, 60, 1.0f, 0.0f);
        auto g = cloudSettings();
        g.positionMode = mode;
        g.position = position;
        s.setGranularSettings(g);
        s.setSongPosition(songPos);
        s.noteOn(60, 1.0f);
        return renderStereo(s, frames);
    };
    // 狭域ループ（position=0）: ずっと前半の 110Hz だけ
    const auto loop = renderMode(2.0f, 0.0f, 0.0, 48000 * 2);
    const double loopHz = estimateHz(loop, 48000, 90000, 48000.0);
    // 全体クロール: 前半は 110Hz、中心が後半へ進んだら 330Hz
    const auto crawl = renderMode(0.0f, 0.0f, 0.0, 48000 * 2);
    const double crawlEarly = estimateHz(crawl, 4800, 24000, 48000.0);
    const double crawlLate = estimateHz(crawl, 60000, 90000, 48000.0);
    // 曲位置同期: 割合 0.8 なら後半の 330Hz、0.1 なら前半の 110Hz
    const auto syncLate = renderMode(1.0f, 0.0f, 0.8, 48000);
    const double syncLateHz = estimateHz(syncLate, 12000, 42000, 48000.0);
    const auto syncEarly = renderMode(1.0f, 0.0f, 0.1, 48000);
    const double syncEarlyHz = estimateHz(syncEarly, 12000, 42000, 48000.0);
    std::printf("  ループ %.0f / クロール前 %.0f 後 %.0f / 同期 0.8: %.0f 0.1: %.0f Hz\n", loopHz, crawlEarly,
                crawlLate, syncLateHz, syncEarlyHz);
    CHECK(loopHz > 80.0 && loopHz < 160.0);
    CHECK(crawlEarly > 80.0 && crawlEarly < 160.0);
    CHECK(crawlLate > 260.0 && crawlLate < 400.0);
    CHECK(syncLateHz > 260.0 && syncLateHz < 400.0);
    CHECK(syncEarlyHz > 80.0 && syncEarlyHz < 160.0);
}

TEST(granular_sampler_feedback_and_freeze_stay_bounded) {
    auto sound = makeNoiseSound(2.0);
    MelodicSampler s;
    s.prepare(48000.0);
    s.setSound(&sound, 60, 1.0f, 0.0f);
    auto g = cloudSettings();
    g.sizeMs = 500.0f;
    g.density = 80.0f;
    g.texture = 0.9f;
    g.timingRandom = 0.7f;
    g.sizeRandom = 0.5f;
    g.feedback = 0.9f;
    s.setGranularSettings(g);
    s.noteOn(60, 1.0f);
    auto l = renderStereo(s, 48000 / 2);
    // 途中でフリーズさせてから 10 秒回す（フィードバックが暴れないこと）
    g.freeze = 1.0f;
    s.setGranularSettings(g);
    l = renderStereo(s, 48000 * 10);
    bool finite = true;
    for (const float v : l)
        finite = finite && std::isfinite(v);
    CHECK(finite);
    CHECK(peakOf(l, 0, l.size()) < 4.0f);
    CHECK(rmsOf(l, 48000 * 9, 48000 * 10) > 0.001); // フリーズしても雲は残る
    std::printf("  fb0.9+freeze 10秒: peak %.3f / 最終秒 RMS %.4f\n", peakOf(l, 0, l.size()),
                rmsOf(l, 48000 * 9, 48000 * 10));
}

TEST(granular_sampler_quantize_and_drift_change_output) {
    auto sound = makeSineSound(220.0, 3.0);
    auto renderWith = [&](const GranularSamplerSettings& g) {
        MelodicSampler s;
        s.prepare(48000.0);
        s.setSound(&sound, 60, 1.0f, 0.0f);
        s.setGranularSettings(g);
        s.noteOn(60, 1.0f);
        return renderStereo(s, 48000);
    };
    const auto base = renderWith(cloudSettings());
    auto q = cloudSettings();
    q.pitchQuantize = 1.0f;
    const auto quantized = renderWith(q);
    CHECK(base != quantized); // 音程セットへの量子化で粒の並びが変わる
    auto d = cloudSettings();
    d.pitchDrift = 3.0f;
    const auto drifted = renderWith(d);
    CHECK(base != drifted); // ドリフトでも変わる
    // 決定的: 同じ設定なら 2 回とも同じ
    CHECK(base == renderWith(cloudSettings()));
}

TEST(granular_sampler_param_spec_clamps) {
    GranularSamplerSettings g;
    CHECK(isGranularSamplerParamId(MDAW_SAMPLER_GRANULAR));
    CHECK(!isGranularSamplerParamId(MDAW_FX_GRANULAR));
    CHECK(setGranularSamplerParam(g, MDAW_SAMPLER_GRANULAR_SIZE_MS, 9999.0f));
    CHECK(g.sizeMs == 500.0f);
    CHECK(setGranularSamplerParam(g, MDAW_SAMPLER_GRANULAR_POSITION_MODE, 1.6f));
    CHECK(g.positionMode == 2.0f); // 整数丸め
    CHECK(setGranularSamplerParam(g, MDAW_SAMPLER_GRANULAR, 0.4f));
    CHECK(g.enabled == 0.0f);
    CHECK(!setGranularSamplerParam(g, 9999, 1.0f));
    float out = 0.0f;
    CHECK(getGranularSamplerParam(g, MDAW_SAMPLER_GRANULAR_SIZE_MS, out) && out == 500.0f);
}

TEST(granular_sampler_session_json_roundtrip_and_undo) {
    Engine engine;
    engine.prepare(48000.0);
    Session session(engine);
    const Id track = session.project().tracks.front().id;

    SamplerSettings settings;
    settings.kitId = "test-kit";
    settings.soundName = "Tone";
    CHECK(session.execute(std::make_unique<SetTrackSampler>(track, settings)));
    CHECK(session.execute(std::make_unique<SetTrackSamplerParam>(track, MDAW_SAMPLER_GRANULAR, 1.0f)));
    CHECK(session.execute(std::make_unique<SetTrackSamplerParam>(track, MDAW_SAMPLER_GRANULAR_SIZE_MS, 333.0f)));
    CHECK(session.execute(std::make_unique<SetTrackSamplerParam>(track, MDAW_SAMPLER_GRANULAR_POSITION_MODE, 2.0f)));
    // 対象外の ID は失敗する
    CHECK(!session.execute(std::make_unique<SetTrackSamplerParam>(track, MDAW_FX_GRANULAR, 1.0f)));

    const auto& saved = session.project().tracks.front().sampler.granular;
    CHECK(saved.enabled == 1.0f && saved.sizeMs == 333.0f && saved.positionMode == 2.0f);

    // JSON に granular が載り、読み戻すと同じ値になる
    const auto json = projectToJson(session.project());
    CHECK(json.find("\"granular\"") != std::string::npos);
    Project back;
    std::string error;
    CHECK(projectFromJson(json, back, error));
    CHECK(back.tracks.front().sampler.granular == saved);

    // 既存の mdaw_set_track_sampler 相当（一式差し替え）でも granular は保たれる
    // （api 側の保持ロジックは C API テストではなく、ここでは設定一式が
    //   granular を含んで往復することだけを見る）
    SamplerSettings full = session.project().tracks.front().sampler;
    full.rootNote = 48;
    CHECK(session.execute(std::make_unique<SetTrackSampler>(track, full)));
    CHECK(session.project().tracks.front().sampler.granular == saved);

    // Undo で granular の変更が戻る
    CHECK(session.undo()); // SetTrackSampler (rootNote)
    CHECK(session.undo()); // positionMode
    CHECK(session.project().tracks.front().sampler.granular.positionMode == 0.0f);
    CHECK(session.project().tracks.front().sampler.granular.enabled == 1.0f);
}
