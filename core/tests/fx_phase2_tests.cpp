// Phase 2（アンビエントFX）のテスト：グラニュラーの質感・拡散・逆再生・漂い、
// シマーリバーブ、テープ、ディレイの長さとピンポン。
#include <cmath>
#include <vector>

#include "fx.h"
#include "mdaw.h"
#include "test_util.h"

namespace {

constexpr double kRate = 48000.0;
constexpr int kBlock = 512;

struct Stereo {
    std::vector<float> l, r;
};

Stereo renderFx(mdaw::FxParams p, const std::vector<float>& inL, const std::vector<float>& inR) {
    mdaw::TrackFx fx;
    fx.prepare(kRate, kBlock);
    fx.setParams(p);
    Stereo out{std::vector<float>(inL.size()), std::vector<float>(inR.size())};
    std::vector<float> l(kBlock), r(kBlock);
    for (size_t off = 0; off < inL.size(); off += kBlock) {
        const int n = static_cast<int>(std::min<size_t>(kBlock, inL.size() - off));
        std::copy(inL.begin() + off, inL.begin() + off + n, l.begin());
        std::copy(inR.begin() + off, inR.begin() + off + n, r.begin());
        fx.process(l.data(), r.data(), n);
        std::copy(l.begin(), l.begin() + n, out.l.begin() + off);
        std::copy(r.begin(), r.begin() + n, out.r.begin() + off);
    }
    return out;
}

float rmsRange(const std::vector<float>& x, size_t from, size_t to) {
    double s = 0;
    size_t n = 0;
    for (size_t i = from; i < std::min(to, x.size()); ++i, ++n)
        s += static_cast<double>(x[i]) * x[i];
    return n ? static_cast<float>(std::sqrt(s / static_cast<double>(n))) : 0.0f;
}

float peakRange(const std::vector<float>& x, size_t from = 0, size_t to = SIZE_MAX) {
    float p = 0;
    for (size_t i = from; i < std::min(to, x.size()); ++i)
        p = std::max(p, std::abs(x[i]));
    return p;
}

bool allFinite(const Stereo& x) {
    for (float v : x.l)
        if (!std::isfinite(v)) return false;
    for (float v : x.r)
        if (!std::isfinite(v)) return false;
    return true;
}

std::vector<float> sine(float freq, double seconds, float amp = 0.5f) {
    std::vector<float> x(static_cast<size_t>(seconds * kRate));
    for (size_t i = 0; i < x.size(); ++i)
        x[i] = amp * static_cast<float>(std::sin(2.0 * 3.14159265358979 * freq * static_cast<double>(i) / kRate));
    return x;
}

// ---- グラニュラー Phase 2 ----

TEST(fx2_texture_diffuser_changes_output) {
    // 質感を上げると（拡散が効く）同じ素材でも出力が変わる
    const auto in = sine(220.0f, 3.0);
    mdaw::FxParams base;
    base.granular = 0.9f;
    base.granularSizeMs = 200.0f;
    base.granularDensity = 50.0f;
    base.granularPositionS = 0.4f;
    base.granularSpray = 0.2f;
    base.granularTimingRandom = 0.0f;
    base.granularSizeRandom = 0.0f;
    mdaw::FxParams plain = base;
    plain.granularTexture = 0.0f;
    mdaw::FxParams cloudy = base;
    cloudy.granularTexture = 1.0f;
    const auto a = renderFx(plain, in, in);
    const auto b = renderFx(cloudy, in, in);
    double diff = 0;
    for (size_t i = 48000; i < in.size(); ++i)
        diff += std::abs(static_cast<double>(a.l[i]) - b.l[i]);
    CHECK(diff > 1.0); // 質感で音が変わっている
    CHECK(rmsRange(b.l, 48000, in.size()) > 0.01f); // 雲として鳴っている
    CHECK(allFinite(b));
}

TEST(fx2_timing_random_still_produces_grains) {
    const auto in = sine(330.0f, 3.0);
    mdaw::FxParams p;
    p.granular = 0.9f;
    p.granularSizeMs = 180.0f;
    p.granularDensity = 40.0f;
    p.granularPositionS = 0.3f;
    p.granularTimingRandom = 1.0f; // 完全ランダム発生
    const auto out = renderFx(p, in, in);
    CHECK(rmsRange(out.l, 48000, in.size()) > 0.02f);
    CHECK(peakRange(out.l) < 1.5f);
    CHECK(allFinite(out));
}

TEST(fx2_reverse_chance_reads_backwards) {
    // 非対称な素材：短いバーストの後に無音。逆再生の粒はバーストの「終わり際」から
    // 遡るので、順再生の粒より立ち上がりが遅れて広がる。
    std::vector<float> in(static_cast<size_t>(4.0 * kRate), 0.0f);
    for (size_t i = 0; i < static_cast<size_t>(0.05 * kRate); ++i)
        in[i] = 0.8f * static_cast<float>(std::sin(2.0 * 3.14159265358979 * 440.0 * static_cast<double>(i) / kRate));
    mdaw::FxParams base;
    base.granular = 1.0f;
    base.granularSizeMs = 400.0f;
    base.granularDensity = 30.0f;
    base.granularPositionS = 0.05f; // バースト直後を拾い続ける
    base.granularSpray = 0.0f;
    base.granularTimingRandom = 0.0f;
    base.granularSizeRandom = 0.0f;
    mdaw::FxParams fwd = base;
    mdaw::FxParams rev = base;
    rev.granularReverseChance = 1.0f;
    const auto a = renderFx(fwd, in, in);
    const auto b = renderFx(rev, in, in);
    double diff = 0;
    for (size_t i = 0; i < in.size(); ++i)
        diff += std::abs(static_cast<double>(a.l[i]) - b.l[i]);
    CHECK(diff > 0.5); // 逆再生で波形が変わる
    CHECK(rmsRange(b.l, 24000, 96000) > 0.005f); // 逆再生でも鳴っている
    CHECK(allFinite(b));
}

TEST(fx2_roam_moves_pickup_position) {
    // 前半は低音、後半は高音の素材。漂いを最大にすると拾う位置が動き、
    // 固定位置（素材の古い側だけを拾う）の出力と大きく違う。
    std::vector<float> in(static_cast<size_t>(6.0 * kRate));
    for (size_t i = 0; i < in.size(); ++i) {
        const double t = static_cast<double>(i) / kRate;
        const double f = t < 3.0 ? 110.0 : 880.0;
        in[i] = 0.5f * static_cast<float>(std::sin(2.0 * 3.14159265358979 * f * t));
    }
    mdaw::FxParams base;
    base.granular = 1.0f;
    base.granularSizeMs = 120.0f;
    base.granularDensity = 45.0f;
    base.granularPositionS = 2.5f; // 固定だと前半の低音しか拾えない
    base.granularSpray = 0.0f;
    base.granularTimingRandom = 0.0f;
    base.granularSizeRandom = 0.0f;
    mdaw::FxParams still = base;
    mdaw::FxParams roaming = base;
    roaming.granularRoam = 1.0f;
    roaming.granularRoamSpeed = 0.5f;
    const auto a = renderFx(still, in, in);
    const auto b = renderFx(roaming, in, in);
    double diff = 0;
    for (size_t i = 3 * 48000; i < in.size(); ++i)
        diff += std::abs(static_cast<double>(a.l[i]) - b.l[i]);
    CHECK(diff > 5.0);
    CHECK(rmsRange(b.l, 4 * 48000, in.size()) > 0.01f);
    CHECK(allFinite(b));
}

TEST(fx2_freeze_feedback_bounded_over_silence) {
    // 素材を取り込んでからフリーズする（フリーズは書き込みを止めるので、
    // 最初からオンだと何も凍らない）。フリーズ＋強いフィードバックで
    // 長く回しても発散せず、凍った雲が残り続ける。
    const auto burst = sine(261.63f, 1.5, 0.6f);
    const std::vector<float> silence(static_cast<size_t>(9.5 * kRate), 0.0f);
    mdaw::FxParams p;
    p.granular = 1.0f;
    p.granularSizeMs = 300.0f;
    p.granularDensity = 60.0f;
    p.granularPositionS = 0.5f;
    p.granularTexture = 0.9f;
    p.granularFeedback = 0.9f;
    mdaw::TrackFx fx;
    fx.prepare(kRate, kBlock);
    fx.setParams(p);
    std::vector<float> outL, outR;
    auto run = [&](const std::vector<float>& in) {
        std::vector<float> l(kBlock), r(kBlock);
        for (size_t off = 0; off < in.size(); off += kBlock) {
            const int n = static_cast<int>(std::min<size_t>(kBlock, in.size() - off));
            std::copy(in.begin() + off, in.begin() + off + n, l.begin());
            std::copy(in.begin() + off, in.begin() + off + n, r.begin());
            fx.process(l.data(), r.data(), n);
            outL.insert(outL.end(), l.begin(), l.begin() + n);
            outR.insert(outR.end(), r.begin(), r.begin() + n);
        }
    };
    run(burst); // 1.5 秒取り込む
    p.granularFreeze = 1.0f;
    fx.setParams(p);
    run(silence); // 凍らせたまま 9.5 秒
    const Stereo out{outL, outR};
    CHECK(allFinite(out));
    CHECK(peakRange(out.l) < 1.5f);
    CHECK(peakRange(out.r) < 1.5f);
    CHECK(rmsRange(out.l, 9 * 48000, 10 * 48000) > 0.005f); // 凍った雲が残っている
}

TEST(fx2_dense_large_grains_do_not_explode) {
    const auto in = sine(196.0f, 3.0, 0.7f);
    mdaw::FxParams p;
    p.granular = 1.0f;
    p.granularSizeMs = 500.0f;
    p.granularDensity = 80.0f;
    p.granularPositionS = 0.6f;
    p.granularTexture = 0.85f;
    p.granularFeedback = 0.55f;
    const auto out = renderFx(p, in, in);
    CHECK(allFinite(out));
    CHECK(peakRange(out.l) <= 1.5f);
    CHECK(peakRange(out.r) <= 1.5f);
    const float rms = rmsRange(out.l, 48000, in.size());
    CHECK(rms > 0.05f);
    CHECK(rms < 0.55f);
}

// ---- シマーリバーブ ----

TEST(fx2_shimmer_bypass_is_bit_identical) {
    const auto in = sine(440.0f, 1.0);
    mdaw::FxParams p; // shimmer = 0（既定）
    const auto out = renderFx(p, in, in);
    for (size_t i = 0; i < in.size(); ++i) {
        CHECK(out.l[i] == in[i]);
        CHECK(out.r[i] == in[i]);
    }
}

TEST(fx2_shimmer_tail_and_stability) {
    std::vector<float> in(static_cast<size_t>(16.0 * kRate), 0.0f);
    const auto burst = sine(523.25f, 0.5, 0.5f);
    std::copy(burst.begin(), burst.end(), in.begin());
    mdaw::FxParams dry;
    mdaw::FxParams shim;
    shim.shimmer = 0.8f;
    shim.shimmerSize = 0.8f;
    shim.shimmerAmount = 0.7f;
    shim.shimmerTone = 0.7f;
    const auto a = renderFx(dry, in, in);
    const auto b = renderFx(shim, in, in);
    CHECK(allFinite(b));
    CHECK(peakRange(b.l) < 1.6f);
    // 2 秒後でも残響が残る（素通しは無音）
    CHECK(rmsRange(a.l, 2 * 48000, 3 * 48000) < 0.0001f);
    CHECK(rmsRange(b.l, 2 * 48000, 3 * 48000) > 0.002f);
    // 15 秒回しても有限で、鳴り止んでいる（DC ラッチや自己持続をしない）
    CHECK(rmsRange(b.l, 14 * 48000, 15 * 48000) < 0.01f);
}

// ---- テープ ----

TEST(fx2_tape_bypass_is_bit_identical) {
    const auto in = sine(440.0f, 1.0);
    mdaw::FxParams p; // tape = 0（既定）
    const auto out = renderFx(p, in, in);
    for (size_t i = 0; i < in.size(); ++i) {
        CHECK(out.l[i] == in[i]);
        CHECK(out.r[i] == in[i]);
    }
}

int zeroCrossings(const std::vector<float>& x, size_t from, size_t to) {
    int n = 0;
    for (size_t i = from + 1; i < std::min(to, x.size()); ++i)
        if ((x[i - 1] < 0.0f) != (x[i] < 0.0f)) ++n;
    return n;
}

TEST(fx2_tape_wow_modulates_pitch) {
    const auto in = sine(440.0f, 4.0);
    mdaw::FxParams p;
    p.tape = 1.0f;
    p.tapeWow = 1.0f;
    p.tapeSat = 0.0f;
    p.tapeHiss = 0.0f;
    const auto out = renderFx(p, in, in);
    CHECK(allFinite(out));
    // 揺れでゼロクロス間隔が変わる：区間ごとのクロス数が一定でない
    const int c0 = zeroCrossings(out.l, 48000, 72000);
    const int c1 = zeroCrossings(out.l, 72000, 96000);
    const int c2 = zeroCrossings(out.l, 96000, 120000);
    const int c3 = zeroCrossings(out.l, 120000, 144000);
    CHECK(c0 > 100); // 鳴ってはいる
    CHECK(std::max({c0, c1, c2, c3}) - std::min({c0, c1, c2, c3}) >= 2);
}

TEST(fx2_tape_hiss_is_gated_and_bounded) {
    // 無音入力ではヒスも出ない（ゲート）
    const std::vector<float> silence(static_cast<size_t>(2.0 * kRate), 0.0f);
    mdaw::FxParams p;
    p.tape = 1.0f;
    p.tapeWow = 0.0f;
    p.tapeSat = 0.0f;
    p.tapeHiss = 1.0f;
    const auto quiet = renderFx(p, silence, silence);
    CHECK(peakRange(quiet.l) == 0.0f);
    // 音があるときは小さく乗る
    const auto in = sine(440.0f, 2.0, 0.4f);
    const auto out = renderFx(p, in, in);
    CHECK(allFinite(out));
    CHECK(peakRange(out.l) < 1.0f);
}

// ---- ディレイ拡張 ----

TEST(fx2_delay_divisions_change_output) {
    std::vector<float> in(static_cast<size_t>(3.0 * kRate), 0.0f);
    in[0] = 0.9f;
    in[1] = 0.9f;
    mdaw::FxParams dotted;
    dotted.delay = 0.6f;
    dotted.delayFeedback = 0.3f;
    dotted.delayDiv = 1.0f; // 付点8分（従来）
    mdaw::FxParams quarter = dotted;
    quarter.delayDiv = 0.0f; // 4分
    mdaw::FxParams sixteenth = dotted;
    sixteenth.delayDiv = 3.0f; // 16分
    const auto a = renderFx(dotted, in, in);
    const auto b = renderFx(quarter, in, in);
    const auto c = renderFx(sixteenth, in, in);
    double dab = 0, dac = 0;
    for (size_t i = 0; i < in.size(); ++i) {
        dab += std::abs(static_cast<double>(a.l[i]) - b.l[i]);
        dac += std::abs(static_cast<double>(a.l[i]) - c.l[i]);
    }
    CHECK(dab > 0.1);
    CHECK(dac > 0.1);
    // 120 BPM 既定：16分 = 0.125 秒付近に最初のエコー
    CHECK(peakRange(c.l, 5000, 7000) > 0.2f);
    // 4分 = 0.5 秒付近
    CHECK(peakRange(b.l, 23000, 25000) > 0.2f);
}

TEST(fx2_delay_pingpong_crosses_channels) {
    std::vector<float> inL(static_cast<size_t>(2.0 * kRate), 0.0f), inR = inL;
    inL[0] = 0.9f; // 左だけにインパルス
    mdaw::FxParams p;
    p.delay = 0.7f;
    p.delayFeedback = 0.5f;
    p.delayDiv = 2.0f; // 8分 = 0.25 秒 @120BPM
    p.delayPingpong = 1.0f;
    const auto out = renderFx(p, inL, inR);
    // 1 回目のエコーは右、2 回目は左に戻る（2 回目は帰路のローパスで少し痩せる）
    CHECK(peakRange(out.r, 11000, 13000) > 0.2f);
    CHECK(peakRange(out.l, 23000, 25000) > 0.05f);
    CHECK(allFinite(out));
}

} // namespace
