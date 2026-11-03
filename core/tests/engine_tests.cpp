// PC上で動かすコアのテスト。音声デバイスは使わず、オフラインで描画して確かめる。
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "engine.h"
#include "mdaw.h"

namespace {

int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("  FAILED: %s (%s:%d)\n", #cond, __FILE__, __LINE__);       \
            ++failures;                                                             \
        }                                                                           \
    } while (0)

constexpr double kRate = 48000.0;

std::vector<float> renderMono(mdaw::Engine& engine, int frames, int block = 192) {
    std::vector<float> stereo(static_cast<size_t>(block) * 2);
    std::vector<float> out;
    out.reserve(static_cast<size_t>(frames));
    for (int done = 0; done < frames; done += block) {
        const int n = std::min(block, frames - done);
        engine.render(stereo.data(), n, 2);
        for (int i = 0; i < n; ++i)
            out.push_back(stereo[static_cast<size_t>(i) * 2]);
    }
    return out;
}

float peak(const std::vector<float>& x, size_t from = 0) {
    float p = 0.0f;
    for (size_t i = from; i < x.size(); ++i)
        p = std::max(p, std::abs(x[i]));
    return p;
}

bool allFinite(const std::vector<float>& x) {
    for (float v : x)
        if (!std::isfinite(v))
            return false;
    return true;
}

void test_silence_without_notes() {
    mdaw::Engine e;
    e.prepare(kRate);
    auto out = renderMono(e, 4800);
    CHECK(peak(out) == 0.0f);
}

void test_note_on_makes_sound() {
    mdaw::Engine e;
    e.prepare(kRate);
    e.noteOn(60, 1.0f);
    auto out = renderMono(e, 4800);
    CHECK(peak(out) > 0.05f);
    CHECK(peak(out) <= 1.0f);
    CHECK(allFinite(out));
    CHECK(e.activeVoices() == 1);
}

void test_note_off_releases_to_silence() {
    mdaw::Engine e;
    e.prepare(kRate);
    e.setParam(MDAW_PARAM_RELEASE_S, 0.05f);
    e.noteOn(60, 1.0f);
    renderMono(e, 4800);
    e.noteOff(60);
    auto out = renderMono(e, 9600); // 200ms：リリース50msより十分長い
    CHECK(peak(out, 4800) == 0.0f);
    CHECK(e.activeVoices() == 0);
}

// 音程が合っているか：自己相関で周期を求める
void test_pitch_is_correct() {
    mdaw::Engine e;
    e.prepare(kRate);
    e.setParam(MDAW_PARAM_DETUNE_CENTS, 0.0f);
    e.noteOn(69, 1.0f); // A4 = 440Hz（周期 約109サンプル）
    auto out = renderMono(e, 48000);
    const size_t start = 24000, len = 8192;
    int bestLag = 0;
    double best = -1.0;
    for (int lag = 60; lag <= 160; ++lag) {
        double sum = 0.0;
        for (size_t i = start; i < start + len; ++i)
            sum += static_cast<double>(out[i]) * out[i + static_cast<size_t>(lag)];
        if (sum > best) {
            best = sum;
            bestLag = lag;
        }
    }
    const double hz = kRate / bestLag;
    std::printf("  measured %.1f Hz\n", hz);
    CHECK(std::abs(hz - 440.0) < 440.0 * 0.01);
}

void test_voice_stealing_keeps_working() {
    mdaw::Engine e;
    e.prepare(kRate);
    for (int n = 0; n < 20; ++n)
        e.noteOn(48 + n, 0.8f);
    auto out = renderMono(e, 4800);
    CHECK(allFinite(out));
    CHECK(peak(out) <= 1.0f);
    CHECK(e.activeVoices() == mdaw::Synth::kNumVoices);
    e.allNotesOff();
    e.setParam(MDAW_PARAM_RELEASE_S, 0.01f);
    renderMono(e, 4800);
    CHECK(e.activeVoices() == 0);
}

void test_large_blocks_are_chunked() {
    mdaw::Engine e;
    e.prepare(kRate);
    e.noteOn(64, 1.0f);
    auto out = renderMono(e, 10000, 3000); // kMaxBlock を超えるブロック
    CHECK(allFinite(out));
    CHECK(peak(out) > 0.05f);
    CHECK(e.framesRendered() == 10000);
}

void test_lower_cutoff_is_darker() {
    // カットオフを下げると高い成分（隣のサンプルとの差の2乗和）が減る
    auto roughness = [](float cutoff) {
        mdaw::Engine e;
        e.prepare(kRate);
        e.setParam(MDAW_PARAM_CUTOFF_HZ, cutoff);
        e.noteOn(48, 1.0f);
        auto out = renderMono(e, 24000);
        double sum = 0.0;
        for (size_t i = 12001; i < out.size(); ++i)
        {
            const double d = out[i] - out[i - 1];
            sum += d * d;
        }
        return sum;
    };
    CHECK(roughness(400.0f) < roughness(8000.0f) * 0.5);
}

void test_c_api_without_audio_device() {
    mdaw_engine* e = mdaw_create();
    CHECK(e != nullptr);
    CHECK(mdaw_start(e) == MDAW_ERR_NO_AUDIO_DEVICE);
    CHECK(mdaw_note_on(e, 60, 1.0f) == 1);
    CHECK(mdaw_set_param(e, MDAW_PARAM_CUTOFF_HZ, 1000.0f) == 1);
    CHECK(mdaw_output_latency_ms(e) < 0.0);
    mdaw_stop(e);
    mdaw_destroy(e);
}

void test_bad_input_is_ignored() {
    mdaw::Engine e;
    e.prepare(kRate);
    e.noteOn(-5, 1.0f);
    e.noteOn(200, 1.0f);
    e.setParam(MDAW_PARAM_CUTOFF_HZ, NAN);
    e.setParam(99, 1.0f);
    auto out = renderMono(e, 4800);
    CHECK(peak(out) == 0.0f);
    e.noteOn(60, 1.0f);
    out = renderMono(e, 4800);
    CHECK(allFinite(out));
    CHECK(peak(out) > 0.05f);
}

} // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"silence_without_notes", test_silence_without_notes},
        {"note_on_makes_sound", test_note_on_makes_sound},
        {"note_off_releases_to_silence", test_note_off_releases_to_silence},
        {"pitch_is_correct", test_pitch_is_correct},
        {"voice_stealing_keeps_working", test_voice_stealing_keeps_working},
        {"large_blocks_are_chunked", test_large_blocks_are_chunked},
        {"lower_cutoff_is_darker", test_lower_cutoff_is_darker},
        {"c_api_without_audio_device", test_c_api_without_audio_device},
        {"bad_input_is_ignored", test_bad_input_is_ignored},
    };
    for (const auto& [name, fn] : tests) {
        const int before = failures;
        std::printf("%s\n", name.c_str());
        fn();
        std::printf("  %s\n", failures == before ? "ok" : "NG");
    }
    std::printf("\n%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
