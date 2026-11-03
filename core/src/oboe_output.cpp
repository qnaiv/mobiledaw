#include <atomic>
#include <memory>
#include <mutex>

#include <android/log.h>
#include <oboe/Oboe.h>

#include "audio_output.h"
#include "engine.h"
#include "mdaw.h"

#define MDAW_LOG(...) __android_log_print(ANDROID_LOG_INFO, "mdaw", __VA_ARGS__)

namespace mdaw {

namespace {

class OboeOutput final : public AudioOutput,
                         public oboe::AudioStreamDataCallback,
                         public oboe::AudioStreamErrorCallback {
public:
    ~OboeOutput() override { stop(); }

    int start(Engine& engine) override {
        std::lock_guard<std::mutex> lock(mutex_);
        engine_ = &engine;
        wantRunning_ = true;
        return openAndStart();
    }

    void stop() override {
        std::lock_guard<std::mutex> lock(mutex_);
        wantRunning_ = false;
        closeStream();
    }

    int sampleRate() const override { return sampleRate_.load(); }
    int framesPerBurst() const override { return framesPerBurst_.load(); }
    int bufferSizeFrames() const override { return bufferSize_.load(); }

    double latencyMs() const override {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_)
            return -1.0;
        auto result = stream_->calculateLatencyMillis();
        return result ? result.value() : -1.0;
    }

    int xrunCount() const override {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!stream_)
            return -1;
        auto result = stream_->getXRunCount();
        return result ? result.value() : -1;
    }

    oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream, void* audioData, int32_t numFrames) override {
        engine_->render(static_cast<float*>(audioData), numFrames, stream->getChannelCount());
        return oboe::DataCallbackResult::Continue;
    }

    // ヘッドホンの抜き差しなどでストリームが閉じられたら開き直す
    void onErrorAfterClose(oboe::AudioStream*, oboe::Result error) override {
        MDAW_LOG("stream closed: %s", oboe::convertToText(error));
        std::lock_guard<std::mutex> lock(mutex_);
        stream_.reset();
        if (wantRunning_ && error == oboe::Result::ErrorDisconnected)
            openAndStart();
    }

private:
    int openAndStart() {
        closeStream();

        oboe::AudioStreamBuilder builder;
        builder.setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setUsage(oboe::Usage::Game)
            ->setDataCallback(this)
            ->setErrorCallback(this);

        auto result = builder.openStream(stream_);
        if (result != oboe::Result::OK) {
            MDAW_LOG("openStream failed: %s", oboe::convertToText(result));
            stream_.reset();
            return MDAW_ERR_OPEN_FAILED;
        }

        // 止まっている間に準備（ここで確保してよい）
        engine_->prepare(stream_->getSampleRate());

        // バッファはバースト2つ分（遅延と途切れにくさの釣り合い）
        stream_->setBufferSizeInFrames(stream_->getFramesPerBurst() * 2);

        sampleRate_ = stream_->getSampleRate();
        framesPerBurst_ = stream_->getFramesPerBurst();
        bufferSize_ = stream_->getBufferSizeInFrames();

        result = stream_->requestStart();
        if (result != oboe::Result::OK) {
            MDAW_LOG("requestStart failed: %s", oboe::convertToText(result));
            closeStream();
            return MDAW_ERR_START_FAILED;
        }
        MDAW_LOG("started: %d Hz, burst %d, buffer %d, api %d, exclusive %d",
                 sampleRate_.load(), framesPerBurst_.load(), bufferSize_.load(),
                 static_cast<int>(stream_->getAudioApi()),
                 stream_->getSharingMode() == oboe::SharingMode::Exclusive ? 1 : 0);
        return MDAW_OK;
    }

    void closeStream() {
        if (stream_) {
            stream_->stop();
            stream_->close();
            stream_.reset();
        }
    }

    mutable std::mutex mutex_;
    std::shared_ptr<oboe::AudioStream> stream_;
    Engine* engine_ = nullptr;
    bool wantRunning_ = false;
    std::atomic<int> sampleRate_{0};
    std::atomic<int> framesPerBurst_{0};
    std::atomic<int> bufferSize_{0};
};

} // namespace

std::unique_ptr<AudioOutput> createPlatformAudioOutput() {
    return std::make_unique<OboeOutput>();
}

} // namespace mdaw
