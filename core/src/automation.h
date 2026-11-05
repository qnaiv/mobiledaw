#pragma once

// クリップ単位のパラメータ・オートメーション（設計：バックログ「オートメーション」）。
// ・レーンはクリップが持ち、ポイント列はクリップ先頭からの相対 tick で並べる
// ・ポイント間は線形補間。最初のポイントより前は「掛かっていない」（素の値のまま）
// ・対象はパラメータ ID で持つ：シンセ（MDAW_PARAM_*）／FX（MDAW_FX_*）／トラック音量（MDAW_PARAM_TRACK_GAIN）
// このヘッダーは純粋な型と補間だけ（JUCE 非依存）。値域の丸めは automation.cpp が仕様表でやる。

#include <algorithm>
#include <cstdint>
#include <vector>

namespace mdaw {

struct AutomationPoint {
    int64_t tick = 0;   // クリップ先頭からの位置
    float value = 0.0f; // パラメータの実値（カットオフなら Hz、音量なら 0〜2）

    bool operator==(const AutomationPoint& o) const noexcept { return tick == o.tick && value == o.value; }
    bool operator!=(const AutomationPoint& o) const noexcept { return !(*this == o); }
};

// ポイント列（tick 昇順・同じ tick は1つ）から tick の値を線形補間で求める。
// ポイントが無い／tick が最初のポイントより前なら false（＝オートメーションは掛かっていない）。
// 最後のポイントより後ろは最後の値を保つ。
inline bool automationValueAt(const std::vector<AutomationPoint>& points, double tick, float& out) noexcept {
    if (points.empty() || tick < static_cast<double>(points.front().tick))
        return false;
    if (tick >= static_cast<double>(points.back().tick)) {
        out = points.back().value;
        return true;
    }
    const auto it = std::upper_bound(points.begin(), points.end(), tick,
                                     [](double t, const AutomationPoint& p) { return t < static_cast<double>(p.tick); });
    const auto& b = *it;       // tick < b.tick な最初のポイント
    const auto& a = *(it - 1); // a.tick <= tick
    const double span = static_cast<double>(b.tick - a.tick);
    const double f = span > 0.0 ? (tick - static_cast<double>(a.tick)) / span : 0.0;
    out = static_cast<float>(static_cast<double>(a.value) + (static_cast<double>(b.value) - a.value) * f);
    return true;
}

struct AutomationLane {
    int paramId = 0;
    std::vector<AutomationPoint> points; // tick 昇順に整えておく（normalizeAutomationLane）

    bool empty() const noexcept { return points.empty(); }
    bool valueAt(double tick, float& out) const noexcept { return automationValueAt(points, tick, out); }

    bool operator==(const AutomationLane& o) const noexcept { return paramId == o.paramId && points == o.points; }
    bool operator!=(const AutomationLane& o) const noexcept { return !(*this == o); }
};

// 対象にできるパラメータか（シンセ／FX の仕様表にあるもの＋トラック音量）
bool isAutomationParam(int paramId) noexcept;
// 値をそのパラメータの範囲に丸める。対象外なら false（value は変えない）
bool clampAutomationValue(int paramId, float& value) noexcept;
// 保存ファイルでのキー（例 "cutoffHz"、音量は "gain"）。対象外なら nullptr
const char* automationParamKey(int paramId) noexcept;
// キーからパラメータ ID を引く。無ければ false
bool automationParamFromKey(const char* key, int& paramId) noexcept;

// レーンを整える：tick 昇順に並べ、同じ tick は後勝ち、tick が [0, lengthTicks] の外は捨て、
// 値はパラメータの範囲に丸める。lengthTicks < 0 なら tick の上限なし（上限だけ確認したいとき用）。
void normalizeAutomationLane(AutomationLane& lane, int64_t lengthTicks);

} // namespace mdaw
