#pragma once

// ドラムキットを鳴らす（ワンショット）。ノートオフでは止まらず、最後まで鳴る。
// チョーク（同じ番号の音どうしで止め合う）はハイハットの開閉用。音声スレッド専用。

#include <algorithm>
#include <array>
#include <cstdint>
#include <memory>
#include <vector>

#include "grain_engine.h"
#include "kit.h"
#include "model.h"
#include "synth.h"

namespace mdaw {

// グラニュラー楽器のパラメータ仕様表（ID・保存キー・範囲・丸めの単一の情報源。
// FX の kFxParamSpecs と同じ流儀）。member は GranularSamplerSettings の float 項目。
struct GranularSamplerParamSpec : ParamSpec {
    float GranularSamplerSettings::*member;
};

extern const GranularSamplerParamSpec kGranularSamplerParamSpecs[];
extern const int kNumGranularSamplerParamSpecs;

bool isGranularSamplerParamId(int paramId) noexcept;
bool getGranularSamplerParam(const GranularSamplerSettings& g, int paramId, float& out) noexcept;
// 仕様表の範囲で丸めてから書く。対象外の ID なら false
bool setGranularSamplerParam(GranularSamplerSettings& g, int paramId, float value) noexcept;

class DrumSampler {
public:
    static constexpr int kVoices = 24;

    void prepare(double sampleRate) noexcept { sampleRate_ = sampleRate; }
    // キットが変わったら、鳴っている音はすぐ止める（古いキットの音を読み続けないため）
    void setKit(const Kit* kit) noexcept;
    const Kit* kit() const noexcept { return kit_; }
    void noteOn(int note, float velocity) noexcept;
    void stopAll() noexcept; // すぐ（5ms で）消す
    // left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;
    int activeVoices() const noexcept;

private:
    struct Voice {
        const KitSound* sound = nullptr;
        double pos = 0.0;
        double inc = 1.0;
        float gain = 0.0f;
        float fade = 1.0f;     // 1 = 普通に鳴っている
        float fadeStep = 0.0f; // 止めるときに毎サンプル引く量
        uint64_t age = 0;
        bool active() const noexcept { return sound != nullptr; }
    };

    void choke(int group) noexcept;

    double sampleRate_ = 48000.0;
    const Kit* kit_ = nullptr;
    std::array<Voice, kVoices> voices_{};
    uint64_t ageCounter_ = 0;
};

// メロディックサンプラー（4つ目の楽器）：キットの音を1つ借り、鍵盤の音程で鳴らす。
// ピッチは再生速度比（線形補間は DrumSampler と同じ）。ループはせず、
// ノートオフではリリース（既定 60ms）で減衰し、素材が終われば自然に消える。
// 音声スレッド専用。確保・ロックなし。
class MelodicSampler {
public:
    static constexpr int kVoices = 16;
    static constexpr double kReleaseSeconds = 0.06; // ノートオフから消えるまで
    static constexpr double kRetriggerSeconds = 0.005; // 同じ音の連打で前の音を落とす速さ

    // 雲の配列はヒープに置く（粒プールが大きく、エンジンのスロット×32 で
    // スタックに乗せると溢れるため）
    MelodicSampler() : clouds_(std::make_unique<CloudVoice[]>(kClouds)) {}

    void prepare(double sampleRate);
    // 素材や設定が変わったら、鳴っている音はすぐ止める（古い素材を読み続けないため）
    void setSound(const KitSound* sound, int rootNote, float gain, float start) noexcept;
    const KitSound* sound() const noexcept { return sound_; }
    int rootNote() const noexcept { return rootNote_; }
    void noteOn(int note, float velocity) noexcept;
    void noteOff(int note) noexcept;
    void stopAll() noexcept; // すぐ（5ms で）消す
    // left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;
    int activeVoices() const noexcept;

    // note を鳴らしたときの再生速度比（素材のサンプルレート換算込み）。テスト用
    double incrementFor(int note) const noexcept;

    // ---- グラニュラーモード（Phase 2.5） -----------------------------------
    // 設定を差し替える。モードを切ったら雲はすぐ落とす。それ以外の変更は
    // 鳴っている雲にも次の粒から効く（素材の差し替えとは違い、音は止めない）。
    void setGranularSettings(const GranularSamplerSettings& g) noexcept;
    const GranularSamplerSettings& granularSettings() const noexcept { return granular_; }
    bool granularEnabled() const noexcept { return granular_.enabled >= 0.5f; }
    // 曲の再生位置（0〜1。曲全体に対する割合）。positionMode=曲位置同期で使う。
    // エンジンがブロックごとに渡す（止まっている間は最後の値のまま）
    void setSongPosition(double fraction) noexcept { songPos_ = std::clamp(fraction, 0.0, 1.0); }
    double songPosition() const noexcept { return songPos_; }
    int activeClouds() const noexcept; // テスト用

private:
    struct Voice {
        int note = -1;
        double pos = 0.0;
        double inc = 1.0;
        float gain = 0.0f;
        float fade = 1.0f;     // 1 = 普通に鳴っている
        float fadeStep = 0.0f; // 消すときに毎サンプル引く量（リリース／連打／全停止）
        uint64_t age = 0;
        bool active() const noexcept { return note >= 0; }
    };

    // グラニュラーの雲 1 つ（ノート 1 つ分）。粒プールと拡散段を雲ごとに持つ。
    // 粒の状態型・窓・乱数・正規化は FX グラニュラーと共有（grain_engine.h）。
    struct CloudVoice {
        static constexpr int kGrains = 48; // 密度 80/秒 × 粒 0.5 秒 = 同時 40 個を賄う
        int note = -1;
        double centre = 0.0;   // 読み中心（素材フレーム単位）
        double centreDir = 1.0; // 往復（ピンポン）モードの進行方向（+1/-1）
        double baseRate = 1.0; // ノートの音程比（素材レート換算込み）
        float gain = 0.0f;
        float fade = 1.0f;
        float fadeStep = 0.0f;
        GrainSlot grains[kGrains];
        std::uint32_t rng = 0x9E3779B9u;
        float spawnAcc = 0.0f;  // 周期発生のアキュムレータ
        float norm = 1.0f;      // 実効粒数ベースの正規化（平滑化済み）
        double roamPhase = 0.0; // 位置の自律走査（三角波 LFO の位相、サイクル）
        double driftPhase = 0.0; // ピッチドリフトの位相（サイクル。roam と位相をずらす）
        float freezeLp = 0.0f;  // フリーズ量のワンポール
        float fbHpL = 0.0f, fbHpR = 0.0f;     // フィードバック保護ハイパスの状態
        float prevWetL = 0.0f, prevWetR = 0.0f; // フィードバック用（前サンプルの雲の出力）
        // 後段ディフューザー（左右 4 段ずつ。prepare で確保）
        std::vector<float> diffL[4], diffR[4];
        int diffPosL[4] = {0, 0, 0, 0}, diffPosR[4] = {0, 0, 0, 0};
        uint64_t age = 0;
        bool active() const noexcept { return note >= 0; }
    };

    Voice* allocate(int note) noexcept;
    CloudVoice* allocateCloud(int note) noexcept;
    void renderClouds(float* left, float* right, int numSamples) noexcept;
    float fadeStepFor(double seconds) const noexcept;

    double sampleRate_ = 48000.0;
    const KitSound* sound_ = nullptr;
    int rootNote_ = 60;
    float gain_ = 1.0f;
    float start_ = 0.0f;
    std::array<Voice, kVoices> voices_{};
    uint64_t ageCounter_ = 0;

    // グラニュラーモードの状態
    static constexpr int kClouds = 8;
    static constexpr double kCloudReleaseSeconds = 0.4; // 雲のリリース（従来の 60ms より長く霞を残す）
    GranularSamplerSettings granular_{};
    double songPos_ = 0.0;
    std::unique_ptr<CloudVoice[]> clouds_; // コンストラクタで kClouds 個を確保
    // フィードバック用の素材時間軸バッファ（雲の出力を素材と同じ時間軸へ書き戻し、
    // 粒が source + feedback として拾う「素材内循環」）。prepare で 4 秒分を確保し、
    // 実際に使う長さは素材に合わせて fbLen_ で決める
    std::vector<float> fbL_, fbR_;
    int fbLen_ = 0;
};

} // namespace mdaw
