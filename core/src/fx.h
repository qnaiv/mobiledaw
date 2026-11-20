#pragma once

// トラックごとのエフェクト（Phase 1: FX チェーン基盤）。
// 各段（ローカット／EQ／飽和／コーラス／コンプ／OTT／クラッシュ／スタッター／
// グラニュラー／ディレイ／リバーブ）は「ユニット」になり、トラックごとに
// 順序付きチェーン（最大 12 個、同種の複数可）として持つ。
// 旧プロジェクトは移行で「現行の固定順フルチェーン」になり、音は変わらない。
// サイドチェイン（キックで引っ込む）とセンドの足し込みはトラック直属のまま
// （エンジンが処理する）で、チェーンには入らない。

#include <array>
#include <cstdint>
#include <vector>

#include <juce_audio_basics/juce_audio_basics.h>

#include "synth.h"

#include "grain_engine.h"

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
    // グラニュラー。granular（混ぜ）が 0 のときは素通し（バッファにも書かない）
    float granular = 0.0f;
    float granularSizeMs = 120.0f;
    float granularDensity = 24.0f;
    float granularPositionS = 0.35f;
    float granularSpray = 0.3f;
    float granularPitch = 0.0f;
    float granularPitchSpread = 0.0f;
    // グラニュラーの追加（Phase 1 で ID 87/88 を割り当て。表引きルーティング前提）
    float granularFreeze = 0.0f;   // 0/1: リングへの書き込みを止め、粒だけ回し続ける
    float granularFeedback = 0.25f; // 粒の出力をリング入力へ戻す量 0〜0.9
    // グラニュラーの質感まわり（Phase 2、ID 89〜94。Clouds／GrainBrick 解析に基づく）
    float granularTexture = 0.6f;      // 包絡の形（〜0.75）と後段ディフューザー（0.75〜）
    float granularTimingRandom = 0.7f; // 粒発生を確率的にする割合 0〜1
    float granularSizeRandom = 0.3f;   // 粒ごとの長さのばらつき 0〜1
    float granularReverseChance = 0.0f; // 粒が逆再生になる確率 0〜1
    float granularRoam = 0.0f;          // 拾う位置の自律走査の深さ 0〜1
    float granularRoamSpeed = 0.07f;    // 走査の速さ 0.01〜0.5 Hz
    // シマーリバーブ。shimmer（混ぜ）が 0 のときは素通し
    float shimmer = 0.0f;
    float shimmerSize = 0.65f;
    float shimmerAmount = 0.5f; // +12 半音シフトをリバーブ入力へ戻す量
    float shimmerTone = 0.6f;   // 戻し経路のローパス（明るさ）
    // テープ。tape（混ぜ）が 0 のときは素通し
    float tape = 0.0f;
    float tapeWow = 0.4f;
    float tapeSat = 0.3f;
    float tapeHiss = 0.0f;
    // ディレイの拡張（Phase 2）。既定（付点8分・ピンポンなし）で従来と同一
    float delayDiv = 1.0f;      // 0=4分 1=付点8分 2=8分 3=16分 4=1小節
    float delayPingpong = 0.0f; // 0/1
};

bool operator==(const FxParams& a, const FxParams& b) noexcept;
inline bool operator!=(const FxParams& a, const FxParams& b) noexcept { return !(a == b); }

// チェーンのユニット種別。並びは旧来の固定順（移行チェーンの順序）と一致させる
enum class FxUnitType : int {
    LowCut = 0,
    Eq = 1,
    Saturation = 2,
    Chorus = 3,
    Comp = 4,
    Ott = 5,
    Bitcrush = 6,
    Stutter = 7,
    Granular = 8,
    Delay = 9,
    Reverb = 10,
    Shimmer = 11, // Phase 2 追加（末尾に足すので移行チェーンの既存順は変わらない）
    Tape = 12,
};
constexpr int kNumFxUnitTypes = 13;
constexpr int kMaxFxUnits = 16; // 1 トラックのチェーン上限（全種デフォルトチェーン 13 個＋追加分）

// チェーンの 1 ユニット。params のうち、この種別が担当する項目だけが意味を持つ
// （他は既定値のままにしておく。FxParams の == は全項目を見るので、担当外を
// 触ると別ユニット扱いになってしまう点に注意）。
struct FxUnit {
    FxUnitType type = FxUnitType::LowCut;
    bool enabled = true;
    FxParams params;

    bool operator==(const FxUnit& o) const noexcept {
        return type == o.type && enabled == o.enabled && params == o.params;
    }
    bool operator!=(const FxUnit& o) const noexcept { return !(*this == o); }
};

// 音声スレッドへ渡せる固定長チェーン（確保なしでコピーできる）
struct FxChainState {
    std::array<FxUnit, kMaxFxUnits> units{};
    int count = 0;

    bool operator==(const FxChainState& o) const noexcept {
        if (count != o.count)
            return false;
        for (int i = 0; i < count; ++i)
            if (units[static_cast<size_t>(i)] != o.units[static_cast<size_t>(i)])
                return false;
        return true;
    }
    bool operator!=(const FxChainState& o) const noexcept { return !(*this == o); }
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
    int unit; // 所属ユニット（FxUnitType の値）。-1 = トラック直属（サイドチェイン／センド）
};

extern const FxParamSpec kFxParamSpecs[];
extern const int kNumFxParamSpecs;

bool getFxParam(const FxParams& f, int paramId, float& out) noexcept;
bool setFxParam(FxParams& f, int paramId, float value) noexcept;

// パラメータの振り分けは「範囲」ではなくこの表引きで決める（87/88 のような
// 飛び ID でも黙って効かなくならないように）。
bool isFxParamId(int paramId) noexcept;                        // FX のパラメータか
bool fxParamUnit(int paramId, FxUnitType& out) noexcept;       // チェーン項目なら所属ユニットを返す
bool isTrackLevelFxParam(int paramId) noexcept;                // トラック直属の FX パラメータか

// ユニット種別と JSON キー（"granular" 等）の相互変換
const char* fxUnitTypeKey(FxUnitType type) noexcept;
bool fxUnitTypeFromKey(const char* key, FxUnitType& out) noexcept;

// その段が今の値で実際に音へ効くか（移行時の enabled 判定、フラット書き込み時の
// 自動有効化に使う）。量 > 0、EQ はゲイン ≠ 0、ローカットは > 20Hz、コンプは混ぜ > 0。
bool fxStageAffectsSound(FxUnitType type, const FxParams& p) noexcept;

// フラットな値からユニット 1 個を作る（担当項目だけ flatSource から写し、他は既定）
FxUnit makeFxUnit(FxUnitType type, const FxParams& flatSource);
// 旧形式（フラット）の値から現行の固定順フルチェーンを作る。
// forceEnabled = false なら enabled は fxStageAffectsSound で決める（移行用）。
// true なら全段有効（TrackFx::setParams の互換動作。各段は量 0 で内部バイパスする）。
FxChainState defaultFxChain(const FxParams& flat, bool forceEnabled);
// モデルの vector 形式と音声スレッド向け固定長形式の相互変換（上限で切り詰める）
std::vector<FxUnit> fxChainToVector(const FxChainState& chain);
FxChainState fxChainFromVector(const std::vector<FxUnit>& units);
// フラット互換ビューへチェーンの値を重ねる: チェーン担当項目は「各種別の最初の
// ユニット」の値で上書きし、トラック直属の項目は flat のまま残す。
void mergeChainIntoFlat(FxParams& flat, const std::vector<FxUnit>& chain);

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
    // 互換 API: フラットな値で「固定順フルチェーン（全段有効）+ トラック直属」を設定する。
    // 既存の呼び出し（テスト含む）はこの経路で従来どおり鳴る。
    void setParams(const FxParams& params) noexcept;
    // トラック直属パラメータ（サイドチェイン／センド）。チェーン項目は含まない
    const FxParams& params() const noexcept { return trackLevel_; }
    void setChain(const FxChainState& chain, const FxParams& trackLevel) noexcept;
    const FxChainState& chain() const noexcept { return chain_; }
    // ライブ変更（スライダー等）: トラック直属なら直属へ、チェーン項目なら
    // 「そのパラメータを持つ最初のユニット」へ（有効・無効を問わない）。
    void setParam(int paramId, float value) noexcept;
    // オートメーション用: 仕様（DESIGN.md）として、paramId のレーンは
    // 「そのパラメータを持つ最初の "有効" ユニット」にだけ当てる。
    // 対象ユニットが無い（全部無効）場合は何もせず false を返す
    // （素の値への復帰は resetAutomatedSlots 側の仕事）。
    bool setParamAutomated(int paramId, float value) noexcept;
    void setTempo(double bpm) noexcept { tempo_ = bpm; }
    // left/right をその場で書き換える。音が止まっても残響が残る間は呼び続けること
    void process(float* left, float* right, int n) noexcept;
    // 残響の尾の長さ（秒）。チェーンの実効の尾として有効ユニットの合計にする
    double tailSeconds() const noexcept;

private:
    // グラニュラー：粒のプール（prepare で確保し、process では確保しない）。
    // 粒の読み位置はリングへの絶対位置で持ち、読むときに剰余を取る。
    // 粒の状態型はグラニュラー楽器と共有（grain_engine.h の GrainSlot）
    using Grain = GrainSlot;

    // ユニット 1 個分の DSP 状態。軽い状態はここに内蔵し、長いディレイラインは
    // TrackFx 共有のアリーナから切り分ける（チェーンの種別列だけで割り当てが
    // 決定的に決まるので、パラメータだけの変更では状態はリセットされない）。
    struct UnitState {
        FxUnitType type = FxUnitType::LowCut;
        bool assigned = false;
        int segStart = -1; // アリーナの開始セグメント番号（-1 = ラインなし／不足でバイパス）
        int segCount = 0;
        int bufLen = 0;    // ラインの論理長（従来のバッファ長と一致させる）

        Svf lowCutL, lowCutR;
        Biquad eqLowL, eqLowR, eqMidL, eqMidR, eqHighL, eqHighR;
        float compEnv = 0.0f;
        int crushHold = 0;
        float crushL = 0.0f, crushR = 0.0f;
        Ott ott;
        // コーラス（0.05 秒と短いのでユニットごとに持つ）
        std::vector<float> chorusL, chorusR;
        int chorusPos = 0;
        float chorusPhase = 0.0f;
        // スタッター
        int stutterPos = 0;
        int stutterClock = 0;
        // グラニュラー
        Grain grains[96];
        std::int64_t grainWrite = 0; // 書き込んだ総サンプル数（絶対位置）
        float grainSpawn = 0.0f;     // 次の粒が出るまでの蓄積
        std::uint32_t grainRng = 0x9E3779B9u;
        float prevWetL = 0.0f, prevWetR = 0.0f; // フィードバック用（前サンプルの粒出力）
        float freezeLp = 0.0f;   // フリーズ量のワンポール（フィードバック消衰と拡散ブースト用）
        float fbHpL = 0.0f, fbHpR = 0.0f; // フィードバック保護ハイパスのローパス側の状態
        float grainNorm = 1.0f;  // 実効粒数ベースの正規化（平滑化済み）
        double roamPhase = 0.0;  // 位置の自律走査（三角波 LFO の位相、サイクル）
        // 後段ディフューザー（左右 4 段ずつのオールパス。prepare で確保）
        std::vector<float> diffL[4], diffR[4];
        int diffPosL[4] = {0, 0, 0, 0}, diffPosR[4] = {0, 0, 0, 0};
        // シマー（リバーブは上の reverb を使う。前ブロックのウェットをシフトして戻す）
        std::vector<float> shimPrevL, shimPrevR; // 前ブロックのリバーブ出力
        std::vector<float> shimInL, shimInR;     // リバーブ入力（入力＋戻し）の作業バッファ
        std::vector<float> shimBufL, shimBufR;   // ピッチシフターの循環バッファ
        int shimPos = 0, shimPosR = 0;
        float shimPhase = 0.0f, shimPhaseR = 0.0f; // シフターの窓位相 0〜1（左右独立）
        float shimLpL = 0.0f, shimLpR = 0.0f;    // 戻し経路のトーン（ローパス）の状態
        float shimHpL = 0.0f, shimHpR = 0.0f;    // 戻し経路のハイパス（DC ラッチ防止）の状態
        // テープ（ディレイラインはコーラスの chorusL/R を流用する。スロットは単一種別専用）
        float tapeWowPhase = 0.0f;   // ワウ（遅い揺れ）の位相
        float tapeDriftPhase = 0.0f; // さらに遅い漂いの位相（独立に回す）
        float tapeEnv = 0.0f;        // ヒスのゲート（入力レベルの追随）
        float tapeLpL = 0.0f, tapeLpR = 0.0f; // テープの暗さ（ローパス）の状態
        std::uint32_t tapeRng = 0x2545F491u;
        // ディレイ
        int delayPos = 0;
        float delayLpL = 0.0f, delayLpR = 0.0f;
        // リバーブ（ウェット用バッファはユニットごとに持つ）
        juce::Reverb reverb;
        std::vector<float> wetL, wetR;

        void resetDsp() noexcept;
    };

    double sampleRate_ = 48000.0;
    double tempo_ = 120.0;
    FxChainState chain_;
    FxParams trackLevel_;
    std::array<UnitState, kMaxFxUnits> slots_;

    // ディレイライン用アリーナ: 1 セグメント = 従来の 2 秒ライン 1 本分。
    // グラニュラーは 2 セグメント（4 秒）、ディレイ／スタッターは 1 本ずつ使う。
    // 合計を超える分はそのユニットがバイパスになる（12 ユニット上限内での割り切り）。
    static constexpr int kArenaSegments = 6;
    int segLen_ = 0;
    std::vector<float> arenaL_, arenaR_;

    float* lineL(UnitState& s) noexcept { return s.segStart >= 0 ? arenaL_.data() + s.segStart * segLen_ : nullptr; }
    float* lineR(UnitState& s) noexcept { return s.segStart >= 0 ? arenaR_.data() + s.segStart * segLen_ : nullptr; }
    void resetSlot(int i) noexcept;
    void applyUnitParams(UnitState& s, const FxParams& p) noexcept;
    float grainRand(UnitState& s) noexcept; // 0〜1（決定的な xorshift。レンダーを再現可能にする）
    void processUnit(UnitState& s, FxUnitType type, const FxParams& p, float* left, float* right, int n) noexcept;
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
