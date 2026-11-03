#pragma once

#include <memory>

namespace mdaw {

class Engine;

// OSの音声出力。Android では Oboe、それ以外（PC上のテスト）では出力なし。
class AudioOutput {
public:
    virtual ~AudioOutput() = default;
    virtual int start(Engine& engine) = 0; // mdaw.h の MDAW_OK / MDAW_ERR_*
    virtual void stop() = 0;
    virtual int sampleRate() const = 0;
    virtual int framesPerBurst() const = 0;
    virtual int bufferSizeFrames() const = 0;
    virtual double latencyMs() const = 0; // 不明なら -1
    virtual int xrunCount() const = 0;    // 不明なら -1
};

// このプラットフォームの出力を作る。出力がない環境では nullptr。
std::unique_ptr<AudioOutput> createPlatformAudioOutput();

} // namespace mdaw
