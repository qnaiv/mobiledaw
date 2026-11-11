#pragma once

// トラックごとのエフェクト（設計：バックログ「音の厚みとエフェクト」）。
// 並び：ローカット → EQ → サチュレーション → コーラス → コンプ → OTT →
//       ビットクラッシュ → スタッター → ディレイ → リバーブ。
// 新しい段（EQ・コンプ・クラッシュ・スタッター・センド）は既定値だと処理しない。
// サイドチェイン（キックで引っ込む）とセンドの足し込みはエンジンが行う。

#include <vector>

#include <juce_audio_basics/juce_audio_basics.h>

#include "synth.h"

namespace mdaw {

struct FxParams {
    float lowCutHz = 20.0f;
    float saturation = 0.0f;
    float chorus = 0.0f;
    float ott = 0.0f;
    float delay = 0.0f;
    float delayFeedback = 0.35f;
    float reverb = 0.0f;
    float reverbSize = 0.6f;
    float sidechain = 0.0f;
    float sidechainReleaseS = 0.25f;
    float sidechainSource = 0.0f;
    // 既定（アタック 2ms・ホールド 0・カーブ 2）は従来の (1-x)^2 と同じ形
    float sidechainAttackS = 0.002f;
    float sidechainHoldS = 0.0f;
    float sidechainCurve = 2.0f;
    // 3バンド EQ。ゲインが全部 0 のときは素通し（古い曲の音は変わらない）
    float eqLowDb = 0.0f;
    float eqLowHz = 120.0f;
    float eqMidDb = 0.0f;
    float eqMidHz = 1000.0f;
    float eqMidQ = 1.0f;
    float eqHighDb = 0.0f;
    float eqHighHz = 8000.0f;
    // コンプレッサー。comp（混ぜ）が 0 のときは素通し
    float comp = 0.0f;
    float compThresholdDb = -18.0f;
    float compRatio = 4.0f;
    float compAttackMs = 10.0f;
    float compReleaseMs = 120.0f;
    float compMakeupDb = 0.0f;
    // センド（0 なら AUX には何も送らない）
    float sendReverb = 0.0f;
    float sendDelay = 0.0f;
    // ビットクラッシュとテンポ同期のスタッター。0 なら素通し
    float bitcrush = 0.0f;
    float stutter = 0.0f;
    float stutterDiv = 3.0f; // 0=2分, 1=4分, 2=付点8分, 3=8分, 4=16分
};

// 曲全体の仕上げ。既定値は、以前ハードコードしていた +10 dB / グルー / ソフトクリップ / リミッターと同じ。
struct MasterParams {
    float gain = 3.2f;          // 入力ゲイン（直線）。3.2 ≒ +10 dB
    float glue = 1.0f;          // グルーコンプの効き 0〜1（1 = 従来どおり）
    float thresholdDb = -12.0f; // グルーのしきい値
    float ratio = 1.6f;         // グルーの比
    float softClip = 1.0f;      // ソフトクリップの強さ 0〜1（1 = 従来の膝 0.6）
    float ceiling = 0.944f;     // リミッターの天井（直線）。0.944 ≒ -0.5 dBFS

    bool operator==(const MasterParams& o) const noexcept {
        return gain == o.gain && glue == o.glue && thresholdDb == o.thresholdDb && ratio == o.ratio
               && softClip == o.softClip && ceiling == o.ceiling;
    }
    bool operator!=(const MasterParams& o) const noexcept { return !(*this == o); }
};

// 2本の AUX（リバーブ / ディレイ）。センドが全部 0 のあいだはエンジンが処理しない。
struct AuxParams {
    float reverbReturn = 1.0f;   // 0〜2
    float reverbSize = 0.65f;     // 0〜1
    float delayReturn = 0.8f;     // 0〜2
    float delayFeedback = 0.35f;  // 0〜0.9

    bool operator==(const AuxParams& o) const noexcept {
        return reverbReturn == o.reverbReturn && reverbSize == o.reverbSize && delayReturn == o.delayReturn
               && delayFeedback == o.delayFeedback;
    }
    bool operator!=(const AuxParams& o) const noexcept { return !(*this == o); }
};

struct FxParamSpec : ParamSpec {
    float FxParams::*member;
};

extern const FxParamSpec kFxParamSpecs[];
extern const int kNumFxParamSpecs;

bool operator==(const FxParams& a, const FxParams& b) noexcept;
inline bool operator!=(const FxParams& a, const FxParams& b) noexcept { return !(a == b); }
bool getFxParam(const FxParams& f, int paramId, float& out) noexcept;
bool setFxParam(FxParams& f, int paramId, float value) noexcept;

// 直接形 II のバイクアッド（EQ 用）
struct Biquad {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;
    float z1 = 0.0f, z2 = 0.0f;
    void reset() noexcept { z1 = z2 = 0.0f; }
    float process(float x) noexcept {
        const float y = b0 * x + z1;
        z1 = b1 * x - a1 * y + z2;
        z2 = b2 * x - a2 * y;
        return y;
    }
};

// 3帯域の上下圧縮（OTT 風）。小さい音を持ち上げ、大きい音を抑えて、派手で密度のある音にする
class Ott {
public:
    void prepare(double sampleRate);
    void reset() noexcept;
    void process(float* left, float* right, int n, float depth) noexcept;

private:
    struct Band {
        float env = 0.0f;
        float gain = 1.0f;
    };
    double sampleRate_ = 48000.0;
    Svf lowL_, lowR_, highL_, highR_; // 2回かけて 24dB/oct 相当にする
    Svf lowL2_, lowR2_, highL2_, highR2_;
    Band bands_[3];
    float attack_ = 0.0f, release_ = 0.0f;
};

class TrackFx {
public:
    void prepare(double sampleRate, int maxBlock);
    void reset() noexcept;
    void setParams(const FxParams& params) noexcept;
    const FxParams& params() const noexcept { return p_; }
    void setTempo(double bpm) noexcept { tempo_ = bpm; }
    // left/right をその場で書き換える。音が止まっても残響が残る間は呼び続けること
    void process(float* left, float* right, int n) noexcept;
    // リバーブ・ディレイの尾が残る長さ（秒）
    double tailSeconds() const noexcept;

private:
    double sampleRate_ = 48000.0;
    double tempo_ = 120.0;
    FxParams p_;

    Svf lowCutL_, lowCutR_;
    Biquad eqLowL_, eqLowR_, eqMidL_, eqMidR_, eqHighL_, eqHighR_;
    float compEnv_ = 0.0f;
    int crushHold_ = 0;
    float crushL_ = 0.0f, crushR_ = 0.0f;
    std::vector<float> stutterL_, stutterR_;
    int stutterPos_ = 0;
    int stutterClock_ = 0;

    // コーラス
    std::vector<float> chorusL_, chorusR_;
    int chorusPos_ = 0;
    float chorusPhase_ = 0.0f;

    Ott ott_;

    // ディレイ（付点8分、左右で少しずらす）
    std::vector<float> delayL_, delayR_;
    int delayPos_ = 0;
    float delayLpL_ = 0.0f, delayLpR_ = 0.0f;

    juce::Reverb reverb_;
    std::vector<float> wetL_, wetR_;
};

// 曲全体の仕上げ：ゆるいコンプでまとめ、リミッターで 0 dBFS を超えないようにする
class MasterBus {
public:
    void prepare(double sampleRate);
    void setParams(const MasterParams& params) noexcept { p_ = params; }
    const MasterParams& params() const noexcept { return p_; }
    void process(float* left, float* right, int n) noexcept;

private:
    double sampleRate_ = 48000.0;
    MasterParams p_;
    float glueEnv_ = 0.0f, glueGain_ = 1.0f;
    float limGain_ = 1.0f;
    float glueAttack_ = 0.0f, glueRelease_ = 0.0f, limRelease_ = 0.0f;
};

// リバーブとディレイのリターン。入力はセンドの合計、出力は 100% ウェット。
class AuxReturn {
public:
    void prepare(double sampleRate, int maxBlock);
    void reset() noexcept;
    void setTempo(double bpm) noexcept { tempo_ = bpm; }
    void setParams(const AuxParams& params) noexcept;
    // in* を消費し、out へウェットを足す（out は消さない）
    void process(const float* revL, const float* revR, const float* dlyL, const float* dlyR, float* outL, float* outR,
                 int n) noexcept;
    double tailSeconds() const noexcept;

private:
    double sampleRate_ = 48000.0;
    double tempo_ = 120.0;
    AuxParams p_;
    juce::Reverb reverb_;
    std::vector<float> wetL_, wetR_;
    std::vector<float> delayL_, delayR_;
    int delayPos_ = 0;
    float delayLpL_ = 0.0f, delayLpR_ = 0.0f;
};

} // namespace mdaw
