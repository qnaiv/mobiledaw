#include "exporter.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

#include <juce_audio_formats/juce_audio_formats.h>

#include "engine.h"
#include "playback.h"

namespace mdaw {

Exporter::~Exporter() {
    cancel();
    join();
}

void Exporter::join() {
    if (thread_.joinable())
        thread_.join();
}

bool Exporter::start(const Project& project, const std::string& path, Id trackId) {
    if (state() == Running)
        return false;
    join();
    cancel_.store(false);
    progress_.store(0.0f);
    error_.clear();
    state_.store(Running);
    thread_ = std::thread([this, copy = project, path, trackId]() {
        std::string error;
        const bool ok = render(copy, path, trackId, &cancel_, &progress_, error);
        error_ = error;
        if (ok)
            progress_.store(1.0f);
        state_.store(ok ? Done : (cancel_.load() ? Cancelled : Failed));
    });
    return true;
}

bool Exporter::render(const Project& project, const std::string& path, Id trackId, const std::atomic<bool>* cancel,
                      std::atomic<float>* progress, std::string& error) {
    auto snap = buildSnapshot(project);
    const bool stem = trackId != kNoId;
    if (stem) {
        bool found = false;
        for (auto& t : snap->tracks) {
            t.audible = t.id == trackId;
            found = found || t.audible;
        }
        if (!found) {
            error = "トラックがありません";
            return false;
        }
    }
    if (project.placements.empty()) {
        error = "曲が空です（クリップを置いてから書き出してください）";
        return false;
    }

    const double songSeconds = static_cast<double>(snap->loopEndTicks) / kPpq * 60.0 / snap->tempo;
    const auto songFrames = static_cast<int64_t>(std::ceil(songSeconds * kSampleRate));
    const auto maxTailFrames = static_cast<int64_t>(8.0 * kSampleRate);  // 残響は最大8秒
    const auto quietFrames = static_cast<int64_t>(0.5 * kSampleRate);    // 0.5秒静かなら終わり

    // 書き込み先：一時ファイルに書いてから置き換える（途中で止めても壊れたファイルを残さない）
    const juce::File out(juce::String::fromUTF8(path.c_str()));
    const auto tmp = out.getSiblingFile(out.getFileName() + ".part");
    out.getParentDirectory().createDirectory();
    tmp.deleteFile();
    std::unique_ptr<juce::OutputStream> stream = tmp.createOutputStream();
    if (stream == nullptr) {
        error = "書き込めません: " + path;
        return false;
    }
    juce::WavAudioFormat wav;
    auto writer = wav.createWriterFor(
        stream, juce::AudioFormatWriterOptions{}.withSampleRate(kSampleRate).withNumChannels(2).withBitsPerSample(24));
    if (writer == nullptr) {
        error = "wav を作れません";
        return false;
    }

    auto engine = std::make_unique<Engine>();
    engine->prepare(kSampleRate);
    engine->setMasterEnabled(!stem);
    engine->publish(std::move(snap));
    engine->play();

    constexpr int kBlock = 1024;
    std::vector<float> interleaved(kBlock * 2);
    juce::AudioBuffer<float> buffer(2, kBlock);
    int64_t done = 0, quiet = 0;
    bool stopped = false;
    const int64_t total = songFrames + maxTailFrames;
    while (done < total) {
        if (cancel != nullptr && cancel->load()) {
            writer.reset();
            tmp.deleteFile();
            error = "やめました";
            return false;
        }
        int n = static_cast<int>(std::min<int64_t>(kBlock, total - done));
        if (!stopped && done + n > songFrames)
            n = static_cast<int>(songFrames - done); // 曲の終わりちょうどで止める（ループさせない）
        if (n <= 0) {
            engine->stop();
            stopped = true;
            continue;
        }
        engine->render(interleaved.data(), n, 2);
        float peak = 0.0f;
        for (int i = 0; i < n; ++i) {
            const float l = interleaved[static_cast<size_t>(i) * 2];
            const float r = interleaved[static_cast<size_t>(i) * 2 + 1];
            buffer.setSample(0, i, l);
            buffer.setSample(1, i, r);
            peak = std::max(peak, std::max(std::abs(l), std::abs(r)));
        }
        if (!writer->writeFromAudioSampleBuffer(buffer, 0, n)) {
            writer.reset();
            tmp.deleteFile();
            error = "書き込みに失敗しました（空き容量を確かめてください）";
            return false;
        }
        done += n;
        if (stopped) {
            quiet = peak < 1e-4f ? quiet + n : 0;
            if (quiet >= quietFrames)
                break;
        }
        if (progress != nullptr)
            progress->store(static_cast<float>(std::min(0.99, static_cast<double>(done) / static_cast<double>(songFrames))));
    }
    writer.reset(); // ここでヘッダーが確定する
    if (!tmp.moveFileTo(out)) {
        tmp.deleteFile();
        error = "書き込みに失敗しました: " + path;
        return false;
    }
    return true;
}

} // namespace mdaw
