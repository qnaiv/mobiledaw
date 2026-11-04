// 音作り（ステレオ・ユニゾン・エフェクト・サイドチェイン・曲全体のリミッター）のテスト
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <memory>
#include <vector>

#include "engine.h"
#include "fx.h"
#include "mdaw.h"
#include "playback.h"
#include "project_json.h"
#include "synth.h"
#include "test_util.h"

namespace {

using namespace mdaw;

constexpr double kRate = 48000.0;

struct Stereo {
    std::vector<float> l, r;
};

Stereo renderSynth(Synth& s, int frames) {
    Stereo out{std::vector<float>(static_cast<size_t>(frames)), std::vector<float>(static_cast<size_t>(frames))};
    for (int done = 0; done < frames; done += 256) {
        const int n = std::min(256, frames - done);
        s.render(out.l.data() + done, out.r.data() + done, n);
    }
    return out;
}

Stereo renderEngine(Engine& e, int frames) {
    std::vector<float> buf(static_cast<size_t>(frames) * 2);
    for (int done = 0; done < frames; done += 256) {
        const int n = std::min(256, frames - done);
        e.render(buf.data() + static_cast<size_t>(done) * 2, n, 2);
    }
    Stereo out;
    for (int i = 0; i < frames; ++i) {
        out.l.push_back(buf[static_cast<size_t>(i) * 2]);
        out.r.push_back(buf[static_cast<size_t>(i) * 2 + 1]);
    }
    return out;
}

float rms(const std::vector<float>& x, size_t from = 0, size_t to = SIZE_MAX) {
    to = std::min(to, x.size());
    double sum = 0.0;
    for (size_t i = from; i < to; ++i)
        sum += static_cast<double>(x[i]) * x[i];
    return to > from ? static_cast<float>(std::sqrt(sum / static_cast<double>(to - from))) : 0.0f;
}

float peakAbs(const std::vector<float>& x, size_t from = 0, size_t to = SIZE_MAX) {
    to = std::min(to, x.size());
    float p = 0.0f;
    for (size_t i = from; i < to; ++i)
        p = std::max(p, std::abs(x[i]));
    return p;
}

// 左右の差（0 = モノラル）
float sideRatio(const Stereo& s) {
    std::vector<float> side(s.l.size()), mid(s.l.size());
    for (size_t i = 0; i < s.l.size(); ++i) {
        side[i] = 0.5f * (s.l[i] - s.r[i]);
        mid[i] = 0.5f * (s.l[i] + s.r[i]);
    }
    return rms(side) / std::max(rms(mid), 1e-9f);
}

TEST(synth_unison_widens_and_keeps_level) {
    auto play = [](float unison, float width) {
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.unison = unison;
        p.width = width;
        p.detuneCents = 40.0f;
        p.sustain = 1.0f;
        s.setParams(p);
        s.noteOn(57, 1.0f);
        return renderSynth(s, 24000);
    };
    const auto mono = play(1, 1.0f);
    const auto wide = play(16, 1.0f);
    const auto narrow = play(16, 0.0f);
    std::printf("  side/mid: 1本 %.3f, 16本 %.3f, 16本(幅0) %.3f\n", sideRatio(mono), sideRatio(wide), sideRatio(narrow));
    CHECK(sideRatio(mono) < 0.01f);
    CHECK(sideRatio(narrow) < 0.01f);
    CHECK(sideRatio(wide) > 0.3f);
    // 本数を増やしても大きさは大きく変わらない（±6dB 以内）
    const float ratio = rms(wide.l) / rms(mono.l);
    std::printf("  16本/1本 の大きさ %.2f\n", ratio);
    CHECK(ratio > 0.5f && ratio < 2.0f);
}

TEST(synth_new_params_clamp_and_roundtrip) {
    SynthParams p;
    CHECK(setSynthParam(p, MDAW_PARAM_UNISON, 40.0f));
    CHECK(p.unison == 16.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_UNISON, 3.4f));
    CHECK(p.unison == 3.0f);
    CHECK(!setSynthParam(p, MDAW_PARAM_COUNT, 1.0f));
    CHECK(!setSynthParam(p, MDAW_PARAM_WIDTH, NAN));
    FxParams f;
    CHECK(setFxParam(f, MDAW_FX_REVERB, 0.4f));
    CHECK(f.reverb == 0.4f);
    CHECK(setFxParam(f, MDAW_FX_LOWCUT_HZ, 5.0f));
    CHECK(f.lowCutHz == 20.0f);
    CHECK(!setFxParam(f, MDAW_PARAM_CUTOFF_HZ, 100.0f));

    Project proj;
    Track t;
    t.id = 7;
    t.name = "Chords";
    t.synth.unison = 9.0f;
    t.synth.filterEnv = 0.5f;
    t.fx.ott = 0.7f;
    t.fx.sidechain = 0.8f;
    proj.tracks.push_back(t);
    Project back;
    std::string error;
    CHECK(projectFromJson(projectToJson(proj), back, error));
    CHECK(back.tracks.size() == 1);
    CHECK(back.tracks[0].synth == t.synth);
    CHECK(back.tracks[0].fx == t.fx);

    // 古いファイル（新しい項目がない）は既定値で読める
    Project old;
    CHECK(projectFromJson(R"({"format":"mobiledaw-project","version":1,"tempo":120,
        "tracks":[{"id":"0000000000000001","name":"A","color":"ffffffff",
        "instrument":{"type":"synth","params":{"cutoffHz":900}}}]})",
                          old, error));
    CHECK(old.tracks.size() == 1);
    CHECK(old.tracks[0].synth.cutoffHz == 900.0f);
    CHECK(old.tracks[0].synth.unison == SynthParams{}.unison);
    CHECK(old.tracks[0].fx == FxParams{});
}

TEST(fx_reverb_and_delay_leave_a_tail) {
    TrackFx fx;
    fx.prepare(kRate, 256);
    FxParams p;
    p.reverb = 0.6f;
    p.delay = 0.4f;
    fx.setParams(p);
    fx.setTempo(150.0);
    std::vector<float> l(256), r(256);
    float tail = 0.0f;
    for (int block = 0; block < 400; ++block) {
        std::fill(l.begin(), l.end(), 0.0f);
        std::fill(r.begin(), r.end(), 0.0f);
        if (block == 0)
            l[0] = r[0] = 1.0f; // インパルス
        fx.process(l.data(), r.data(), 256);
        if (block > 40) // 0.2秒より後
            tail = std::max(tail, std::max(peakAbs(l), peakAbs(r)));
    }
    std::printf("  0.2秒後の残響 %.4f / 残る長さ %.1f秒\n", tail, fx.tailSeconds());
    CHECK(tail > 0.001f);
    CHECK(fx.tailSeconds() > 1.0);
}

TEST(fx_ott_lifts_quiet_and_tames_loud) {
    auto level = [](float amp, float depth) {
        TrackFx fx;
        fx.prepare(kRate, 256);
        FxParams p;
        p.ott = depth;
        fx.setParams(p);
        std::vector<float> l(256), r(256);
        float out = 0.0f;
        double phase = 0.0;
        for (int block = 0; block < 200; ++block) {
            for (int i = 0; i < 256; ++i) {
                l[static_cast<size_t>(i)] = r[static_cast<size_t>(i)] = amp * static_cast<float>(std::sin(phase));
                phase += 2.0 * 3.14159265 * 800.0 / kRate;
            }
            fx.process(l.data(), r.data(), 256);
            if (block > 100)
                out = std::max(out, rms(l));
        }
        return out / (amp * 0.7071f);
    };
    const float quiet = level(0.003f, 1.0f), loud = level(0.8f, 1.0f), bypass = level(0.3f, 0.0f);
    std::printf("  OTT 倍率：小さい音 %.2f / 大きい音 %.2f / なし %.2f\n", quiet, loud, bypass);
    CHECK(quiet > 2.0f);
    CHECK(loud < 0.7f);
    CHECK(std::abs(bypass - 1.0f) < 0.02f);
}

// キックのトラックが鳴ると、他のトラックが引っ込んで戻る
TEST(engine_sidechain_ducks_other_tracks) {
    Project p;
    Track pad, kick;
    pad.id = 1;
    pad.synth.sustain = 1.0f;
    pad.synth.unison = 1.0f; // うなりで大きさが揺れないように
    pad.fx.sidechain = 1.0f;
    pad.fx.sidechainReleaseS = 0.2f;
    kick.id = 2;
    kick.fx.sidechainSource = 1.0f;
    kick.mixer.mute = true; // パッドの音だけを見る
    p.tracks = {pad, kick};
    Clip padClip;
    padClip.id = 10;
    padClip.trackId = 1;
    padClip.lengthTicks = kPpq * 4;
    Note n;
    n.id = 100;
    n.tick = 0;
    n.length = kPpq * 4;
    n.pitch = 60;
    padClip.notes.push_back(n);
    Clip kickClip = padClip;
    kickClip.id = 11;
    kickClip.trackId = 2;
    kickClip.notes[0].id = 101;
    kickClip.notes[0].tick = kPpq; // 2拍目（120 BPM で 0.5 秒）
    kickClip.notes[0].length = kPpq / 4;
    p.clips = {padClip, kickClip};
    p.placements = {{1000, 10, 1, 0, 1}, {1001, 11, 2, 0, 1}};
    p.tempo = 120.0;

    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(p));
    e.play();
    const auto out = renderEngine(e, 48000);
    const float before = rms(out.l, 20000, 24000);
    const float ducked = rms(out.l, 24300, 25500);
    const float after = rms(out.l, 36000, 40000);
    std::printf("  キック前 %.4f / 直後 %.4f / 0.25秒後 %.4f\n", before, ducked, after);
    CHECK(ducked < before * 0.25f);
    CHECK(after > before * 0.8f);
}

TEST(engine_master_never_clips) {
    Project p;
    for (int i = 0; i < 8; ++i) {
        Track t;
        t.id = static_cast<Id>(i + 1);
        t.synth.unison = 16.0f;
        t.synth.masterGain = 1.0f;
        t.synth.sustain = 1.0f;
        t.mixer.gain = 2.0f;
        t.fx.saturation = 1.0f;
        t.fx.ott = 1.0f;
        p.tracks.push_back(t);
        Clip c;
        c.id = static_cast<Id>(100 + i);
        c.trackId = t.id;
        c.lengthTicks = kPpq * 4;
        for (int v = 0; v < 8; ++v) {
            Note n;
            n.id = static_cast<Id>(1000 + i * 10 + v);
            n.tick = 0;
            n.length = kPpq * 4;
            n.pitch = 40 + v * 5;
            n.velocity = 1.0f;
            c.notes.push_back(n);
        }
        p.clips.push_back(c);
        p.placements.push_back({static_cast<Id>(5000 + i), c.id, t.id, 0, 1});
    }
    Engine e;
    e.prepare(kRate);
    e.publish(buildSnapshot(p));
    e.play();
    const auto t0 = std::chrono::steady_clock::now();
    const auto out = renderEngine(e, 48000);
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    const float pk = std::max(peakAbs(out.l), peakAbs(out.r));
    // 8トラック × 8音 × 16本 ＋ 全エフェクト（リバーブ以外）を1秒分。処理時間の目安も出す
    std::printf("  最大 %.3f / 1秒分の処理 %.0f ms（PC、最適化 %s）\n", pk, ms,
#ifdef NDEBUG
                "あり"
#else
                "なし"
#endif
    );
    CHECK(pk <= 0.95f);
    CHECK(pk > 0.5f);
}

} // namespace
