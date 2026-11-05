#pragma once

#include <array>
#include <cstdint>

#include <juce_audio_basics/juce_audio_basics.h>

namespace mdaw {

// シンセの音色。保存・読み込み・範囲の丸めは kSynthParamSpecs の表で一括して扱う
struct SynthParams {
    float cutoffHz = 6000.0f;
    float resonance = 0.9f;
    float attackS = 0.005f;
    float decayS = 0.25f;
    float sustain = 0.7f;
    float releaseS = 0.3f;
    float detuneCents = 7.0f;
    float masterGain = 0.6f;
    float unison = 2.0f;
    float width = 0.5f;
    float blend = 0.8f;
    float sub = 0.0f;
    float noise = 0.0f;
    float drive = 0.0f;
    float filterEnv = 0.0f;
    float filterEnvDecayS = 0.3f;
    float pitchEnv = 0.0f;
    float pitchEnvDecayS = 0.05f;
    float wave = 0.0f;
    float osc = 1.0f;
    float wtTable = 0.0f;     // 0 = 従来オシレーター（旧プロジェクトの音は不変）
    float wtPos = 0.0f;       // ウェーブテーブルのフレーム位置 0〜1
    float wtWarp = 0.0f;      // 位相ワープ 0=なし、1=bend、2=squeeze、3=sync
    float wtWarpAmount = 0.0f;
    float wtLfoRate = 1.0f;   // WT_POS を揺らす LFO の速さ（Hz）
    float wtLfoAmount = 0.0f; // LFO の深さ 0〜1（0 = 従来と完全一致）
    float keyTrack = 0.0f;    // フィルターのキートラッキング 0〜1（0 = 従来と完全一致）
    float glideS = 0.0f;      // グライドの時間（秒、0 = なし）
    float mono = 0.0f;        // 1 = モノフォニック（レガート＋グライド）
    float lfoWave = 0.0f;     // LFO 波形 0=正弦、1=三角、2=矩形、3=のこぎり
    float lfoSync = 0.0f;     // 1 = テンポ同期（速さは lfoDiv、位相は曲位置）
    float lfoDiv = 1.0f;      // 同期の分周 0=1小節、1=4分、2=付点8分、3=8分、4=16分
    float lfoCutoff = 0.0f;   // LFO→カットオフの量 0〜1（最大 ±2 オクターブ）
    float lfoPitch = 0.0f;    // LFO→音程の量 0〜1（最大 ±2 半音）
};

struct ParamSpec {
    int id;
    const char* key; // 保存ファイルでの名前
    float min, max;
    bool integer;
};

struct SynthParamSpec : ParamSpec {
    float SynthParams::*member;
};

extern const SynthParamSpec kSynthParamSpecs[];
extern const int kNumSynthParamSpecs;

bool operator==(const SynthParams& a, const SynthParams& b) noexcept;
inline bool operator!=(const SynthParams& a, const SynthParams& b) noexcept { return !(a == b); }

// SynthParams を mdaw.h の MDAW_PARAM_* で読み書きする（範囲外の値は丸める）
bool getSynthParam(const SynthParams& s, int paramId, float& out) noexcept;
bool setSynthParam(SynthParams& s, int paramId, float value) noexcept;

// 2次の状態変数フィルター（TPT）。係数は呼ぶ側が間引いて更新する
struct Svf {
    float g = 0.0f, k = 1.0f, a1 = 0.0f, a2 = 0.0f, a3 = 0.0f;
    float ic1 = 0.0f, ic2 = 0.0f;
    void set(float cutoffHz, float q, double sampleRate) noexcept;
    void reset() noexcept { ic1 = ic2 = 0.0f; }
    // 戻り値はローパス。high を渡すとハイパスも返す
    float process(float x, float* high = nullptr) noexcept {
        const float v3 = x - ic2;
        const float v1 = a1 * ic1 + a2 * v3;
        const float v2 = ic2 + a2 * ic1 + a3 * v3;
        ic1 = 2.0f * v1 - ic1;
        ic2 = 2.0f * v2 - ic2;
        if (high != nullptr)
            *high = x - k * v1 - v2;
        return v2;
    }
};

class Voice {
public:
    static constexpr int kMaxUnison = 16;

    void prepare(double sampleRate);
    void start(int note, float velocity, const SynthParams& params, uint64_t age, uint32_t seed);
    // モノ時のレガート：エンベロープや位相は鳴らし直さず、音程だけを目標へ滑らせる
    void legato(int note, const SynthParams& params) noexcept;
    void release() noexcept;
    void kill() noexcept;
    void applyParams(const SynthParams& params) noexcept;
    void setCutoff(float hz) noexcept { cutoffHz_ = hz; }
    // テンポ同期 LFO の位相（この render 呼び出しの頭の周期位置と、制御ブロックごとの進み）。
    // Synth が曲位置から計算して渡す。sync でないときは使われない
    void setLfoSyncPhase(double baseCycles, double incPerBlock) noexcept {
        lfoSyncBase_ = baseCycles;
        lfoSyncInc_ = incPerBlock;
    }
    // 自分の音を left/right に足し込む
    void render(float* left, float* right, int numSamples) noexcept;

    bool isActive() const noexcept { return adsr_.isActive(); }
    bool isHeld() const noexcept { return held_; }
    int note() const noexcept { return note_; }
    uint64_t age() const noexcept { return age_; }

private:
    void layoutUnison() noexcept;
    void updateIncrements(float pitchOffsetSemis) noexcept;

    double sampleRate_ = 48000.0;
    SynthParams p_;
    juce::ADSR adsr_;
    Svf filterL_, filterR_;

    int unison_ = 1;
    float phase_[kMaxUnison] = {};
    float inc_[kMaxUnison] = {};
    float detune_[kMaxUnison] = {}; // 半音
    float gainL_[kMaxUnison] = {};
    float gainR_[kMaxUnison] = {};
    float subPhase_ = 0.0f, subInc_ = 0.0f;
    uint32_t noise_ = 1;

    float cutoffHz_ = 6000.0f;
    float wtPos_ = 0.0f; // 平滑化した WT_POS（control block 単位で追従）
    float lfoPhase_ = 0.0f;                 // LFO の位相 0〜1（発音ごとに 0 から。決定的）
    double lfoSyncBase_ = 0.0, lfoSyncInc_ = 0.0; // テンポ同期時の位相（Synth から渡される）
    float pitchSemis_ = 0.0f;               // いま鳴っている音程（ノート番号の実数。グライドで遷移する）
    float glideFrom_ = 0.0f, glideTarget_ = 0.0f, glidePos_ = 1.0f, glideStep_ = 0.0f; // グライドの進行
    float wtSpread_[kMaxUnison] = {};       // 新テーブル（5〜）用：サブボイスごとの WT_POS のずらし
    float filterEnv_ = 0.0f, filterEnvCoef_ = 0.0f;
    float pitchEnv_ = 0.0f, pitchEnvCoef_ = 0.0f;
    float gain_ = 0.0f;
    int note_ = -1;
    bool held_ = false;
    uint64_t age_ = 0;
};

// 16ボイスのポリフォニックシンセ（ステレオ・ユニゾン最大16本）。音声スレッド専用。
class Synth {
public:
    static constexpr int kNumVoices = 16;

    void prepare(double sampleRate, int maxBlock);
    void noteOn(int note, float velocity) noexcept;
    void noteOff(int note) noexcept;
    void allNotesOff() noexcept;
    void setParam(int id, float value) noexcept;
    void setParams(const SynthParams& params) noexcept;
    // テンポ同期 LFO 用の時計：曲位置（tick）と tick の進み（tick/サンプル）をエンジンが毎回渡す。
    // 渡されなければ内部の自由進行（120 BPM 相当）で位相を進める
    void setLfoClock(double positionTicks, double ticksPerSample) noexcept {
        lfoClockPos_ = positionTicks;
        lfoClockInc_ = ticksPerSample;
        lfoClockValid_ = true;
    }
    // left/right を上書きする
    void render(float* left, float* right, int numSamples) noexcept;

    int activeVoices() const noexcept;
    const SynthParams& params() const noexcept { return params_; }

private:
    Voice* findVoiceFor(int note) noexcept;
    void clearMonoStack() noexcept { monoStackSize_ = 0; }

    std::array<Voice, kNumVoices> voices_;
    SynthParams params_;
    float smoothedCutoff_ = 6000.0f;
    float smoothedGain_ = 0.6f;
    double sampleRate_ = 48000.0;
    uint64_t ageCounter_ = 0;
    uint32_t seed_ = 0x9E3779B9u;

    // モノフォニック用：押さえているノートの積み重ね（最後に押した音が鳴る）
    static constexpr int kMonoStackMax = 32;
    int monoStack_[kMonoStackMax] = {};
    int monoStackSize_ = 0;

    // テンポ同期 LFO の時計（エンジンから渡される曲位置。無ければ内部で進める）
    double lfoClockPos_ = 0.0, lfoClockInc_ = 0.0;
    bool lfoClockValid_ = false;
    double lfoFreePos_ = 0.0; // 時計が無いときの自由進行位置（tick）
};

} // namespace mdaw
