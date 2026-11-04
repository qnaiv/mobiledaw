#pragma once

// トラックごとのエフェクト（設計：バックログ「音の厚みとエフェクト」）。
// 並び：ローカット → サチュレーション → コーラス → OTT → ディレイ → リバーブ。
// サイドチェイン（キックで引っ込む）はエンジンが全トラックにまとめてかける。

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
    void process(float* left, float* right, int n) noexcept;

private:
    double sampleRate_ = 48000.0;
    float glueEnv_ = 0.0f, glueGain_ = 1.0f;
    float limGain_ = 1.0f;
    float glueAttack_ = 0.0f, glueRelease_ = 0.0f, limRelease_ = 0.0f;
};

} // namespace mdaw
