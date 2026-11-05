#include "automation.h"

#include <cmath>
#include <cstring>

#include "fx.h"
#include "mdaw.h"
#include "synth.h"

namespace mdaw {

namespace {

// パラメータ ID から仕様（範囲とキー）を引く。シンセ／FX の仕様表が正。
// トラック音量だけは仕様表に無いのでここで扱う。
const ParamSpec* specOf(int paramId) noexcept {
    for (int i = 0; i < kNumSynthParamSpecs; ++i)
        if (kSynthParamSpecs[i].id == paramId)
            return &kSynthParamSpecs[i];
    for (int i = 0; i < kNumFxParamSpecs; ++i)
        if (kFxParamSpecs[i].id == paramId)
            return &kFxParamSpecs[i];
    return nullptr;
}

} // namespace

bool isAutomationParam(int paramId) noexcept {
    return paramId == MDAW_PARAM_TRACK_GAIN || specOf(paramId) != nullptr;
}

bool clampAutomationValue(int paramId, float& value) noexcept {
    if (!std::isfinite(value))
        return false;
    if (paramId == MDAW_PARAM_TRACK_GAIN) {
        value = std::clamp(value, 0.0f, 2.0f);
        return true;
    }
    const auto* spec = specOf(paramId);
    if (spec == nullptr)
        return false;
    value = std::clamp(value, spec->min, spec->max);
    if (spec->integer)
        value = std::round(value);
    return true;
}

const char* automationParamKey(int paramId) noexcept {
    if (paramId == MDAW_PARAM_TRACK_GAIN)
        return "gain";
    const auto* spec = specOf(paramId);
    return spec != nullptr ? spec->key : nullptr;
}

bool automationParamFromKey(const char* key, int& paramId) noexcept {
    if (key == nullptr)
        return false;
    if (std::strcmp(key, "gain") == 0) {
        paramId = MDAW_PARAM_TRACK_GAIN;
        return true;
    }
    for (int i = 0; i < kNumSynthParamSpecs; ++i)
        if (std::strcmp(key, kSynthParamSpecs[i].key) == 0) {
            paramId = kSynthParamSpecs[i].id;
            return true;
        }
    for (int i = 0; i < kNumFxParamSpecs; ++i)
        if (std::strcmp(key, kFxParamSpecs[i].key) == 0) {
            paramId = kFxParamSpecs[i].id;
            return true;
        }
    return false;
}

void normalizeAutomationLane(AutomationLane& lane, int64_t lengthTicks) {
    auto& pts = lane.points;
    pts.erase(std::remove_if(pts.begin(), pts.end(),
                             [&](const AutomationPoint& p) {
                                 return p.tick < 0 || (lengthTicks >= 0 && p.tick > lengthTicks)
                                        || !std::isfinite(p.value);
                             }),
              pts.end());
    std::stable_sort(pts.begin(), pts.end(),
                     [](const AutomationPoint& a, const AutomationPoint& b) { return a.tick < b.tick; });
    // 同じ tick は後勝ち（並べ替えが安定なので、後ろのものを残す）
    std::vector<AutomationPoint> out;
    out.reserve(pts.size());
    for (const auto& p : pts) {
        if (!out.empty() && out.back().tick == p.tick)
            out.back() = p;
        else
            out.push_back(p);
    }
    pts = std::move(out);
    for (auto& p : pts)
        clampAutomationValue(lane.paramId, p.value); // 対象外の ID なら値はそのまま（呼ぶ側で弾く）
}

} // namespace mdaw
