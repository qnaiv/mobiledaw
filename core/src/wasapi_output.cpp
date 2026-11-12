// Windows の音声出力（WASAPI 共有モード、イベント駆動）。
// 構造は oboe_output.cpp に倣う：AudioOutput の実装＋createPlatformAudioOutput()。
// 違いは WASAPI にコールバックが無いので、専用スレッドがイベントを待って
// Engine::render を呼ぶことと、COM の初期化からデバイスの片付けまでを
// そのスレッドの中で完結させること（COM アパートメントを混ぜないため）。
//
// 対応フォーマットは float のみ。まず 48kHz / float / ステレオを
// AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM で要求し、無理ならデバイスの
// ミックスフォーマット（float のときだけ）をそのまま使う。
// デバイスが消えたら（ヘッドホンの抜き差し等）少し待って開き直す（Oboe と同じ方針）。
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <audioclient.h>
#include <avrt.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <atomic>
#include <cstdint>
#include <cstring>
#include <future>
#include <memory>
#include <mutex>
#include <thread>

#include "audio_output.h"
#include "engine.h"
#include "mdaw.h"

namespace mdaw {

namespace {

using Microsoft::WRL::ComPtr;

// KSDATAFORMAT_SUBTYPE_IEEE_FLOAT（ksmedia.h を引かずに済むよう値で持つ）
constexpr GUID kSubtypeIeeeFloat = {0x00000003, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};

bool isFloatFormat(const WAVEFORMATEX* format) {
    if (format == nullptr)
        return false;
    if (format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT)
        return true;
    if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
        const auto* ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format);
        return ext->SubFormat == kSubtypeIeeeFloat;
    }
    return false;
}

void fillDesiredFormat(WAVEFORMATEXTENSIBLE* format) {
    std::memset(format, 0, sizeof(*format));
    format->Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    format->Format.nChannels = 2;
    format->Format.nSamplesPerSec = 48000;
    format->Format.wBitsPerSample = 32;
    format->Format.nBlockAlign = static_cast<WORD>(format->Format.nChannels * format->Format.wBitsPerSample / 8);
    format->Format.nAvgBytesPerSec = format->Format.nSamplesPerSec * format->Format.nBlockAlign;
    format->Format.cbSize = sizeof(*format) - sizeof(format->Format);
    format->Samples.wValidBitsPerSample = 32;
    format->dwChannelMask = 0x3; // SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT（ksmedia.h を引かない）
    format->SubFormat = kSubtypeIeeeFloat;
}

class WasapiOutput final : public AudioOutput {
public:
    ~WasapiOutput() override { stop(); }

    int start(Engine& engine) override {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked(); // 起動中なら作り直す（Oboe の openAndStart と同じ）
        engine_ = &engine;
        stopRequested_ = false;
        wakeEvent_ = CreateEventW(nullptr, FALSE, FALSE, nullptr); // 自動リセット
        if (wakeEvent_ == nullptr)
            return MDAW_ERR_OPEN_FAILED;
        auto initResult = std::make_shared<std::promise<int>>();
        auto future = initResult->get_future();
        thread_ = std::thread([this, initResult] { threadMain(initResult); });
        const int rc = future.get();
        if (rc != MDAW_OK) {
            if (thread_.joinable())
                thread_.join();
            closeWakeEvent();
            engine_ = nullptr;
        }
        return rc;
    }

    void stop() override {
        std::lock_guard<std::mutex> lock(mutex_);
        stopLocked();
    }

    int sampleRate() const override { return sampleRate_.load(); }
    int framesPerBurst() const override { return framesPerBurst_.load(); }
    int bufferSizeFrames() const override { return bufferSize_.load(); }

    double latencyMs() const override { return hasStream_.load() ? latencyMs_.load() : -1.0; }
    int xrunCount() const override { return hasStream_.load() ? xruns_.load() : -1; }

private:
    enum class SessionEnd { initFailed, deviceLost, stopped };

    void stopLocked() {
        stopRequested_ = true;
        if (wakeEvent_ != nullptr)
            SetEvent(wakeEvent_); // 待ちに入っているスレッドを起こす
        if (thread_.joinable())
            thread_.join();
        closeWakeEvent();
        engine_ = nullptr;
    }

    void closeWakeEvent() {
        if (wakeEvent_ != nullptr) {
            CloseHandle(wakeEvent_);
            wakeEvent_ = nullptr;
        }
    }

    // レンダースレッド本体。COM の初期化から片付けまでここで完結する。
    // initResult には最初のセッションの成否を1回だけ入れる。
    void threadMain(std::shared_ptr<std::promise<int>> initResult) {
        const HRESULT coHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        const bool coOk = SUCCEEDED(coHr);
        bool promised = false;
        const auto fulfill = [&](int rc) {
            if (!promised) {
                promised = true;
                initResult->set_value(rc);
            }
        };

        DWORD taskIndex = 0;
        HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);

        int lastError = MDAW_ERR_OPEN_FAILED;
        while (!stopRequested_.load()) {
            int sessionError = MDAW_OK;
            const SessionEnd end = runSession(sessionError);
            if (end == SessionEnd::initFailed) {
                lastError = sessionError;
                break;
            }
            fulfill(MDAW_OK);
            if (end == SessionEnd::stopped || stopRequested_.load())
                break;
            // デバイスが消えた。少し待ってから開き直す
            WaitForSingleObject(wakeEvent_, 300);
        }
        fulfill(lastError);

        if (mmcss != nullptr)
            AvRevertMmThreadCharacteristics(mmcss);
        if (coOk)
            CoUninitialize();
    }

    // 1回ぶんのデバイス利用（列挙→初期化→再生→片付け）。
    // 初期化に失敗したら SessionEnd::initFailed を返し error に MDAW_ERR_* を入れる。
    SessionEnd runSession(int& error) {
        ComPtr<IMMDeviceEnumerator> enumerator;
        HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                      __uuidof(IMMDeviceEnumerator), reinterpret_cast<void**>(enumerator.GetAddressOf()));
        if (FAILED(hr)) {
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }
        ComPtr<IMMDevice> device;
        hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, device.GetAddressOf());
        if (FAILED(hr)) {
            error = MDAW_ERR_NO_AUDIO_DEVICE;
            return SessionEnd::initFailed;
        }
        ComPtr<IAudioClient> client;
        hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                              reinterpret_cast<void**>(client.GetAddressOf()));
        if (FAILED(hr)) {
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }

        // フォーマット決め：希望（48kHz float ステレオ、変換あり）→
        // IsFormatSupported の近似 → デバイスのミックスフォーマット（float のみ）
        WAVEFORMATEXTENSIBLE desired;
        fillDesiredFormat(&desired);
        WAVEFORMATEX* closest = nullptr;
        const HRESULT supported = client->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &desired.Format, &closest);
        const WAVEFORMATEX* format = nullptr;
        WAVEFORMATEX* mixFormat = nullptr;
        DWORD streamFlags = AUDCLNT_STREAMFLAGS_EVENTCALLBACK;
        if (supported == S_OK) {
            format = &desired.Format;
            streamFlags |= AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY;
        } else if (supported == S_FALSE && isFloatFormat(closest)) {
            format = closest;
        } else {
            if (FAILED(client->GetMixFormat(&mixFormat)) || !isFloatFormat(mixFormat)) {
                CoTaskMemFree(closest);
                CoTaskMemFree(mixFormat);
                error = MDAW_ERR_OPEN_FAILED;
                return SessionEnd::initFailed;
            }
            format = mixFormat;
        }

        HANDLE frameEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (frameEvent == nullptr) {
            CoTaskMemFree(closest);
            CoTaskMemFree(mixFormat);
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }

        hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED, streamFlags, 0, 0, format, nullptr);
        const int channels = format->nChannels;
        const int sampleRate = static_cast<int>(format->nSamplesPerSec);
        CoTaskMemFree(closest);
        CoTaskMemFree(mixFormat);
        if (FAILED(hr)) {
            CloseHandle(frameEvent);
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }
        if (FAILED(client->SetEventHandle(frameEvent))) {
            CloseHandle(frameEvent);
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }

        ComPtr<IAudioRenderClient> render;
        hr = client->GetService(__uuidof(IAudioRenderClient), reinterpret_cast<void**>(render.GetAddressOf()));
        if (FAILED(hr)) {
            CloseHandle(frameEvent);
            error = MDAW_ERR_OPEN_FAILED;
            return SessionEnd::initFailed;
        }

        UINT32 bufferFrames = 0;
        client->GetBufferSize(&bufferFrames);
        REFERENCE_TIME defaultPeriod = 0;
        REFERENCE_TIME minimumPeriod = 0;
        client->GetDevicePeriod(&defaultPeriod, &minimumPeriod);
        REFERENCE_TIME latency = 0;
        client->GetStreamLatency(&latency);

        sampleRate_ = sampleRate;
        bufferSize_ = static_cast<int>(bufferFrames);
        framesPerBurst_ = defaultPeriod > 0 ? static_cast<int>(defaultPeriod * sampleRate / 10000000) : static_cast<int>(bufferFrames);
        latencyMs_ = latency > 0 ? static_cast<double>(latency) / 10000.0 : -1.0;
        xruns_ = 0;
        channels_ = channels;

        // 止まっている間に準備（Oboe と同じく Start の前に呼ぶ）
        if (preparedRate_ != sampleRate) {
            engine_->prepare(sampleRate);
            preparedRate_ = sampleRate;
        }

        hr = client->Start();
        if (FAILED(hr)) {
            CloseHandle(frameEvent);
            error = MDAW_ERR_START_FAILED;
            return SessionEnd::initFailed;
        }
        hasStream_ = true;

        SessionEnd end = SessionEnd::stopped;
        HANDLE waits[2] = {frameEvent, wakeEvent_};
        while (!stopRequested_.load()) {
            const DWORD waited = WaitForMultipleObjects(2, waits, FALSE, 2000);
            if (stopRequested_.load())
                break;
            if (waited == WAIT_TIMEOUT)
                continue;
            if (waited != WAIT_OBJECT_0)
                break; // 停止イベント or 異常。ループを抜けて片付ける
            UINT32 padding = 0;
            hr = client->GetCurrentPadding(&padding);
            if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
                end = SessionEnd::deviceLost;
                break;
            }
            if (FAILED(hr) || padding >= bufferFrames)
                continue;
            const UINT32 available = bufferFrames - padding;
            BYTE* data = nullptr;
            DWORD flags = 0;
            hr = render->GetBuffer(available, &data, &flags, nullptr, nullptr);
            if (hr == AUDCLNT_E_DEVICE_INVALIDATED) {
                end = SessionEnd::deviceLost;
                break;
            }
            if (FAILED(hr) || data == nullptr)
                continue;
            if ((flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0)
                xruns_.fetch_add(1); // WASAPI には xrun 相当が無いので不連続の回数で代える
            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0) {
                std::memset(data, 0, static_cast<size_t>(available) * channels * sizeof(float));
                render->ReleaseBuffer(available, 0);
            } else {
                engine_->render(reinterpret_cast<float*>(data), static_cast<int>(available), channels);
                render->ReleaseBuffer(available, 0);
            }
        }

        client->Stop();
        hasStream_ = false;
        CloseHandle(frameEvent);
        return end;
    }

    mutable std::mutex mutex_;
    std::thread thread_;
    HANDLE wakeEvent_ = nullptr; // start() が作り stop() が起こす。スレッドの待ちを兼ねる
    Engine* engine_ = nullptr;
    std::atomic<bool> stopRequested_{false};
    std::atomic<bool> hasStream_{false};
    std::atomic<int> sampleRate_{0};
    std::atomic<int> framesPerBurst_{0};
    std::atomic<int> bufferSize_{0};
    std::atomic<int> xruns_{0};
    std::atomic<double> latencyMs_{-1.0};
    int channels_ = 2;      // レンダースレッドだけが触る
    int preparedRate_ = 0;  // 同上
};

} // namespace

std::unique_ptr<AudioOutput> createPlatformAudioOutput() {
    return std::make_unique<WasapiOutput>();
}

} // namespace mdaw
