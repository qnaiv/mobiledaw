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
#include "wavetable.h"
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

TEST(synth_wavetable_params_clamp_and_roundtrip) {
    SynthParams p;
    CHECK(setSynthParam(p, MDAW_PARAM_WT_TABLE, 9.0f));
    CHECK(p.wtTable == 7.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_TABLE, 2.4f));
    CHECK(p.wtTable == 2.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_POS, 1.5f));
    CHECK(p.wtPos == 1.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_WARP, -1.0f));
    CHECK(p.wtWarp == 0.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_WARP, 2.6f));
    CHECK(p.wtWarp == 3.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_WARP_AMOUNT, 0.5f));
    CHECK(p.wtWarpAmount == 0.5f);

    Project proj;
    Track t;
    t.id = 7;
    t.name = "WT";
    t.synth.wtTable = 3.0f;
    t.synth.wtPos = 0.25f;
    t.synth.wtWarp = 1.0f;
    t.synth.wtWarpAmount = 0.75f;
    proj.tracks.push_back(t);
    Project back;
    std::string error;
    CHECK(projectFromJson(projectToJson(proj), back, error));
    CHECK(back.tracks.size() == 1);
    CHECK(back.tracks[0].synth == t.synth);

    // 古いファイル（wt〜 の項目がない）は既定値（従来オシレーター）で読める
    Project oldProj;
    CHECK(projectFromJson(R"({"format":"mobiledaw-project","version":1,"tempo":120,
        "tracks":[{"id":"0000000000000001","name":"A","color":"ffffffff",
        "instrument":{"type":"synth","params":{"cutoffHz":900}}}]})",
                          oldProj, error));
    CHECK(oldProj.tracks.size() == 1);
    CHECK(oldProj.tracks[0].synth.wtTable == 0.0f);
    CHECK(oldProj.tracks[0].synth.wtPos == 0.0f);
}

TEST(synth_wavetable_table0_keeps_legacy_waveform) {
    auto renderWith = [](float table, float pos, float warp, float amount) {
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.sustain = 1.0f;
        p.wtTable = table;
        p.wtPos = pos;
        p.wtWarp = warp;
        p.wtWarpAmount = amount;
        s.setParams(p);
        s.noteOn(57, 1.0f);
        return renderSynth(s, 4800);
    };
    const auto legacy = renderWith(0.0f, 0.0f, 0.0f, 0.0f);
    const auto legacyWithWtKnobs = renderWith(0.0f, 0.8f, 3.0f, 1.0f);
    // WT_TABLE=0 では WT_POS／ワープは効かず、従来と1サンプルも違わない
    CHECK(legacy.l == legacyWithWtKnobs.l);
    CHECK(legacy.r == legacyWithWtKnobs.r);
    CHECK(rms(legacy.l) > 0.01f);
}

TEST(synth_wavetable_sounds_and_pos_changes_timbre) {
    auto renderWith = [](float table, float pos, int note) {
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.sustain = 1.0f;
        p.cutoffHz = 18000.0f; // テーブルの音をフィルターで潰さない
        p.wtTable = table;
        p.wtPos = pos;
        s.setParams(p);
        s.noteOn(note, 1.0f);
        return renderSynth(s, 12000);
    };
    for (int table = 1; table <= 4; ++table) {
        const auto out = renderWith(static_cast<float>(table), 0.5f, 57);
        const float r = rms(out.l, 4000, 12000);
        const float pk = peakAbs(out.l, 4000, 12000);
        std::printf("  テーブル %d: RMS %.4f / 最大 %.3f\n", table, r, pk);
        CHECK(r > 0.01f);  // 無音でない
        CHECK(pk < 0.6f);  // 1ボ이스ではクリップしない
        // 高い音でも壊れない（帯域制限バンドの確認を兼ねる）
        const auto high = renderWith(static_cast<float>(table), 0.5f, 108);
        CHECK(std::isfinite(rms(high.l)));
        CHECK(peakAbs(high.l) < 0.6f);
    }
    // WT_POS を動かすと波形が変わる（テーブル1：サイン寄り → のこぎり寄り）
    const auto a = renderWith(1.0f, 0.0f, 57);
    const auto b = renderWith(1.0f, 1.0f, 57);
    double diff = 0.0;
    for (size_t i = 4000; i < a.l.size(); ++i) {
        const double d = static_cast<double>(a.l[i]) - b.l[i];
        diff += d * d;
    }
    const float diffRms = static_cast<float>(std::sqrt(diff / 8000.0));
    std::printf("  WT_POS 0→1 の差の RMS %.4f（元の RMS %.4f）\n", diffRms, rms(a.l, 4000, 12000));
    CHECK(diffRms > 0.3f * rms(a.l, 4000, 12000));
    // ワープでも波形が変わる
    Synth s;
    s.prepare(kRate, 256);
    SynthParams p;
    p.sustain = 1.0f;
    p.cutoffHz = 18000.0f;
    p.wtTable = 1.0f;
    p.wtPos = 0.5f;
    p.wtWarp = 3.0f;
    p.wtWarpAmount = 1.0f;
    s.setParams(p);
    s.noteOn(57, 1.0f);
    const auto warped = renderSynth(s, 12000);
    const auto plain = renderWith(1.0f, 0.5f, 57);
    double wdiff = 0.0;
    for (size_t i = 4000; i < plain.l.size(); ++i) {
        const double d = static_cast<double>(plain.l[i]) - warped.l[i];
        wdiff += d * d;
    }
    CHECK(static_cast<float>(std::sqrt(wdiff / 8000.0)) > 0.2f * rms(plain.l, 4000, 12000));
}

TEST(synth_wavetable_new_tables_sound) {
    auto renderWith = [](float table, float pos, int note) {
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.sustain = 1.0f;
        p.cutoffHz = 18000.0f;
        p.wtTable = table;
        p.wtPos = pos;
        s.setParams(p);
        s.noteOn(note, 1.0f);
        return renderSynth(s, 12000);
    };
    for (int table = 5; table <= 7; ++table) {
        const auto out = renderWith(static_cast<float>(table), 0.5f, 57);
        const float r = rms(out.l, 4000, 12000);
        const float pk = peakAbs(out.l, 4000, 12000);
        std::printf("  新テーブル %d: RMS %.4f / 最大 %.3f\n", table, r, pk);
        CHECK(r > 0.01f); // 無音でない
        CHECK(pk < 0.6f); // 1ボイスではクリップしない
        const auto high = renderWith(static_cast<float>(table), 0.5f, 108);
        CHECK(std::isfinite(rms(high.l)));
        CHECK(peakAbs(high.l) < 0.6f);
        // ユニゾンの WT_POS ばらけ（新テーブル用）があっても壊れない
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.sustain = 1.0f;
        p.cutoffHz = 18000.0f;
        p.wtTable = static_cast<float>(table);
        p.wtPos = 0.5f;
        p.unison = 9.0f;
        p.detuneCents = 40.0f;
        p.width = 0.8f;
        s.setParams(p);
        s.noteOn(57, 1.0f);
        const auto uni = renderSynth(s, 12000);
        CHECK(std::isfinite(rms(uni.l)));
        CHECK(peakAbs(uni.l) < 1.0f);
    }
    // パルスモーフ（6）は位置で波形が大きく変わる（矩形 → 細いパルス）
    const auto a = renderWith(6.0f, 0.0f, 57);
    const auto b = renderWith(6.0f, 1.0f, 57);
    double diff = 0.0;
    for (size_t i = 4000; i < a.l.size(); ++i) {
        const double d = static_cast<double>(a.l[i]) - b.l[i];
        diff += d * d;
    }
    const float diffRms = static_cast<float>(std::sqrt(diff / 8000.0));
    std::printf("  パルスモーフ 位置0→1 の差の RMS %.4f（元の RMS %.4f）\n", diffRms, rms(a.l, 4000, 12000));
    CHECK(diffRms > 0.3f * rms(a.l, 4000, 12000));
}

TEST(synth_wavetable_lfo_params_clamp_and_roundtrip) {
    SynthParams p;
    CHECK(setSynthParam(p, MDAW_PARAM_WT_LFO_RATE, 100.0f));
    CHECK(p.wtLfoRate == 30.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_LFO_RATE, 0.001f));
    CHECK(p.wtLfoRate == 0.01f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_LFO_RATE, 2.5f));
    CHECK(p.wtLfoRate == 2.5f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_LFO_AMOUNT, 1.5f));
    CHECK(p.wtLfoAmount == 1.0f);
    CHECK(setSynthParam(p, MDAW_PARAM_WT_LFO_AMOUNT, -0.5f));
    CHECK(p.wtLfoAmount == 0.0f);

    Project proj;
    Track t;
    t.id = 7;
    t.name = "WT-LFO";
    t.synth.wtTable = 5.0f;
    t.synth.wtPos = 0.4f;
    t.synth.wtLfoRate = 3.25f;
    t.synth.wtLfoAmount = 0.6f;
    proj.tracks.push_back(t);
    Project back;
    std::string error;
    CHECK(projectFromJson(projectToJson(proj), back, error));
    CHECK(back.tracks.size() == 1);
    CHECK(back.tracks[0].synth == t.synth);

    // 古いファイル（wtLfo〜 の項目がない）は既定値で読める
    Project oldProj;
    CHECK(projectFromJson(R"({"format":"mobiledaw-project","version":1,"tempo":120,
        "tracks":[{"id":"0000000000000001","name":"A","color":"ffffffff",
        "instrument":{"type":"synth","params":{"wtTable":2}}}]})",
                          oldProj, error));
    CHECK(oldProj.tracks.size() == 1);
    CHECK(oldProj.tracks[0].synth.wtLfoRate == SynthParams{}.wtLfoRate);
    CHECK(oldProj.tracks[0].synth.wtLfoAmount == 0.0f);
}

TEST(synth_wavetable_lfo_moves_pos) {
    auto renderWith = [](float rate, float amount) {
        Synth s;
        s.prepare(kRate, 256);
        SynthParams p;
        p.sustain = 1.0f;
        p.cutoffHz = 18000.0f;
        p.wtTable = 2.0f; // 倍音テーブルは位置の変化が音に大きく出る
        p.wtPos = 0.5f;
        p.wtLfoRate = rate;
        p.wtLfoAmount = amount;
        s.setParams(p);
        s.noteOn(57, 1.0f);
        return renderSynth(s, 24000);
    };
    // amount=0 では LFO の速さを変えても従来と1サンプルも違わない
    const auto off = renderWith(1.0f, 0.0f);
    const auto offFast = renderWith(17.0f, 0.0f);
    CHECK(off.l == offFast.l);
    CHECK(off.r == offFast.r);
    // amount>0 では波形が時間で変化する（LFO なしとの差が大きい）し、決定的（2回とも同じ）
    const auto on = renderWith(2.5f, 0.8f);
    const auto onAgain = renderWith(2.5f, 0.8f);
    CHECK(on.l == onAgain.l);
    double diff = 0.0;
    for (size_t i = 4000; i < off.l.size(); ++i) {
        const double d = static_cast<double>(off.l[i]) - on.l[i];
        diff += d * d;
    }
    const float diffRms = static_cast<float>(std::sqrt(diff / 20000.0));
    std::printf("  LFO あり/なし の差の RMS %.4f（元の RMS %.4f）\n", diffRms, rms(off.l, 4000, 24000));
    CHECK(diffRms > 0.25f * rms(off.l, 4000, 24000));
    CHECK(peakAbs(on.l) < 0.6f);
}


} // namespace
