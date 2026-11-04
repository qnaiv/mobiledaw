// プロジェクトファイル（project.json）を wav に書き出す。音作りの確認用（アプリには入らない）。
//   mdaw_render <project.json> <out.wav> [繰り返し回数=1]
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include <juce_audio_formats/juce_audio_formats.h>

#include "engine.h"
#include "playback.h"
#include "project_json.h"

using namespace mdaw;

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: %s <project.json> <out.wav> [loops]\n", argv[0]);
        return 2;
    }
    const juce::File in(juce::File::getCurrentWorkingDirectory().getChildFile(argv[1]));
    const juce::File out(juce::File::getCurrentWorkingDirectory().getChildFile(argv[2]));
    const int loops = argc > 3 ? std::max(1, std::atoi(argv[3])) : 1;

    Project project;
    std::string error;
    if (!projectFromJson(in.loadFileAsString().toStdString(), project, error)) {
        std::fprintf(stderr, "読めません: %s\n", error.c_str());
        return 1;
    }

    constexpr double kRate = 48000.0;
    Engine engine;
    engine.prepare(kRate);
    auto snap = buildSnapshot(project);
    const double seconds = static_cast<double>(snap->loopEndTicks) / kPpq * 60.0 / snap->tempo * loops + 3.0;
    engine.publish(std::move(snap));
    engine.play();

    const int frames = static_cast<int>(seconds * kRate);
    const int songEnd = frames - static_cast<int>(3.0 * kRate);
    juce::AudioBuffer<float> buffer(2, frames);
    std::vector<float> block(512 * 2);
    for (int done = 0; done < frames;) {
        int n = std::min(512, frames - done);
        if (done < songEnd)
            n = std::min(n, songEnd - done); // 曲の終わりちょうどで止める（頭に戻って鳴らさない）
        if (done == songEnd)
            engine.stop(); // 最後の3秒は残響だけ
        engine.render(block.data(), n, 2);
        for (int i = 0; i < n; ++i) {
            buffer.setSample(0, done + i, block[static_cast<size_t>(i) * 2]);
            buffer.setSample(1, done + i, block[static_cast<size_t>(i) * 2 + 1]);
        }
        done += n;
    }

    // 大きさの目安（全体の RMS とピーク、帯域ごとはしない）
    double sum = 0.0;
    float peak = 0.0f;
    for (int c = 0; c < 2; ++c)
        for (int i = 0; i < frames; ++i) {
            const float v = buffer.getSample(c, i);
            sum += static_cast<double>(v) * v;
            peak = std::max(peak, std::abs(v));
        }
    std::printf("%.1f 秒  peak %.3f  rms %.1f dBFS\n", seconds, peak, 10.0 * std::log10(sum / (2.0 * frames) + 1e-12));

    out.deleteFile();
    juce::WavAudioFormat wav;
    std::unique_ptr<juce::OutputStream> stream = out.createOutputStream();
    if (stream == nullptr) {
        std::fprintf(stderr, "書き込めません: %s\n", argv[2]);
        return 1;
    }
    auto writer = wav.createWriterFor(stream, juce::AudioFormatWriterOptions{}.withSampleRate(kRate).withNumChannels(2).withBitsPerSample(16));
    if (writer == nullptr)
        return 1;
    writer->writeFromAudioSampleBuffer(buffer, 0, frames);
    return 0;
}
