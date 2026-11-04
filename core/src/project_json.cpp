#include "project_json.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>

#include <juce_core/juce_core.h>

#include "mdaw.h"

namespace mdaw {

namespace {

using juce::var;

juce::String idToString(Id id) {
    char buf[17];
    std::snprintf(buf, sizeof(buf), "%016" PRIx64, id);
    return juce::String(buf);
}

Id idFromVar(const var& v) {
    const auto s = v.toString();
    if (s.length() != 16 || !s.containsOnly("0123456789abcdefABCDEF"))
        return kNoId;
    return static_cast<Id>(std::strtoull(s.toRawUTF8(), nullptr, 16));
}

var object() { return var(new juce::DynamicObject()); }

void put(var& obj, const char* key, const var& value) { obj.getDynamicObject()->setProperty(key, value); }

var get(const var& obj, const char* key) { return obj.getProperty(key, var()); }

double num(const var& obj, const char* key, double fallback) {
    const auto v = get(obj, key);
    return (v.isInt() || v.isInt64() || v.isDouble()) ? static_cast<double>(v) : fallback;
}

int64_t integer(const var& obj, const char* key, int64_t fallback) {
    const auto v = get(obj, key);
    return (v.isInt() || v.isInt64() || v.isDouble()) ? static_cast<int64_t>(static_cast<juce::int64>(v)) : fallback;
}

bool boolean(const var& obj, const char* key, bool fallback) {
    const auto v = get(obj, key);
    return v.isBool() ? static_cast<bool>(v) : fallback;
}

template <typename Params, typename Spec>
var paramsToVar(const Params& params, const Spec* specs, int count) {
    auto o = object();
    for (int i = 0; i < count; ++i)
        put(o, specs[i].key, params.*(specs[i].member));
    return o;
}

// 欠けている項目（古いファイル）は既定値のまま。範囲外は丸める
template <typename Params, typename Spec, typename Setter>
Params paramsFromVar(const var& o, const Spec* specs, int count, Setter set) {
    Params p;
    for (int i = 0; i < count; ++i)
        set(p, specs[i].id, static_cast<float>(num(o, specs[i].key, p.*(specs[i].member))));
    return p;
}

var synthToVar(const SynthParams& s) { return paramsToVar(s, kSynthParamSpecs, kNumSynthParamSpecs); }
SynthParams synthFromVar(const var& o) {
    return paramsFromVar<SynthParams>(o, kSynthParamSpecs, kNumSynthParamSpecs, setSynthParam);
}
var fxToVar(const FxParams& f) { return paramsToVar(f, kFxParamSpecs, kNumFxParamSpecs); }
FxParams fxFromVar(const var& o) { return paramsFromVar<FxParams>(o, kFxParamSpecs, kNumFxParamSpecs, setFxParam); }

} // namespace

//==============================================================================
std::string projectToJson(const Project& p) {
    auto root = object();
    put(root, "format", "mobiledaw-project");
    put(root, "version", Project::kVersion);
    put(root, "title", juce::String::fromUTF8(p.title.c_str()));
    put(root, "tempo", p.tempo);
    juce::Array<var> sig{p.timeSigNumerator, p.timeSigDenominator};
    put(root, "timeSig", sig);
    auto key = object();
    put(key, "root", p.keyRoot);
    put(key, "scale", juce::String(p.scale));
    put(root, "key", key);

    juce::Array<var> tracks;
    for (const auto& t : p.tracks) {
        auto o = object();
        put(o, "id", idToString(t.id));
        put(o, "name", juce::String::fromUTF8(t.name.c_str()));
        put(o, "color", juce::String::toHexString(static_cast<juce::int64>(t.color)).paddedLeft('0', 8));
        auto instrument = object();
        put(instrument, "type", "synth");
        put(instrument, "params", synthToVar(t.synth));
        put(o, "instrument", instrument);
        put(o, "fx", fxToVar(t.fx));
        auto mixer = object();
        put(mixer, "gain", t.mixer.gain);
        put(mixer, "pan", t.mixer.pan);
        put(mixer, "mute", t.mixer.mute);
        put(mixer, "solo", t.mixer.solo);
        put(o, "mixer", mixer);
        tracks.add(o);
    }
    put(root, "tracks", tracks);

    juce::Array<var> clips;
    for (const auto& c : p.clips) {
        auto o = object();
        put(o, "id", idToString(c.id));
        put(o, "trackId", idToString(c.trackId));
        put(o, "lengthTicks", static_cast<juce::int64>(c.lengthTicks));
        juce::Array<var> notes;
        for (const auto& n : c.notes) {
            auto no = object();
            put(no, "id", idToString(n.id));
            put(no, "tick", static_cast<juce::int64>(n.tick));
            put(no, "length", static_cast<juce::int64>(n.length));
            put(no, "pitch", n.pitch);
            put(no, "velocity", n.velocity);
            notes.add(no);
        }
        put(o, "notes", notes);
        clips.add(o);
    }
    put(root, "clips", clips);

    juce::Array<var> placements;
    for (const auto& pl : p.placements) {
        auto o = object();
        put(o, "id", idToString(pl.id));
        put(o, "clipId", idToString(pl.clipId));
        put(o, "trackId", idToString(pl.trackId));
        put(o, "startBar", pl.startBar);
        put(o, "lengthBars", pl.lengthBars);
        placements.add(o);
    }
    put(root, "placements", placements);

    return juce::JSON::toString(root, juce::JSON::FormatOptions{}.withSpacing(juce::JSON::Spacing::multiLine))
        .toStdString();
}

//==============================================================================
bool projectFromJson(const std::string& json, Project& out, std::string& error) {
    var root;
    const auto parsed = juce::JSON::parse(juce::String::fromUTF8(json.c_str()), root);
    if (parsed.failed() || !root.isObject()) {
        error = "JSONとして読めません: " + parsed.getErrorMessage().toStdString();
        return false;
    }
    if (get(root, "format").toString() != "mobiledaw-project") {
        error = "mobiledaw のプロジェクトファイルではありません";
        return false;
    }
    const auto version = integer(root, "version", 0);
    if (version < 1 || version > Project::kVersion) {
        error = "対応していない版です（version " + std::to_string(version) + "）";
        return false;
    }

    Project p;
    p.tempo = std::clamp(num(root, "tempo", 120.0), 20.0, 300.0);
    if (const auto* sig = get(root, "timeSig").getArray(); sig != nullptr && sig->size() == 2) {
        const int numr = static_cast<int>((*sig)[0]), den = static_cast<int>((*sig)[1]);
        if (numr >= 1 && numr <= 16 && (den == 2 || den == 4 || den == 8 || den == 16)) {
            p.timeSigNumerator = numr;
            p.timeSigDenominator = den;
        }
    }
    const auto key = get(root, "key");
    if (const auto title = get(root, "title").toString().trim(); title.isNotEmpty())
        p.title = title.substring(0, 64).toStdString();
    p.keyRoot = static_cast<int>(std::clamp<int64_t>(integer(key, "root", 0), 0, 11));
    if (const auto scale = get(key, "scale").toString(); scale.isNotEmpty())
        p.scale = scale.toStdString();

    if (const auto* tracks = get(root, "tracks").getArray()) {
        for (const auto& o : *tracks) {
            Track t;
            t.id = idFromVar(get(o, "id"));
            if (t.id == kNoId)
                continue;
            t.name = get(o, "name").toString().toStdString();
            t.color = static_cast<uint32_t>(get(o, "color").toString().getHexValue64());
            t.synth = synthFromVar(get(get(o, "instrument"), "params"));
            t.fx = fxFromVar(get(o, "fx"));
            const auto m = get(o, "mixer");
            t.mixer.gain = static_cast<float>(std::clamp(num(m, "gain", 0.8), 0.0, 2.0));
            t.mixer.pan = static_cast<float>(std::clamp(num(m, "pan", 0.0), -1.0, 1.0));
            t.mixer.mute = boolean(m, "mute", false);
            t.mixer.solo = boolean(m, "solo", false);
            if (static_cast<int>(p.tracks.size()) < Project::kMaxTracks)
                p.tracks.push_back(std::move(t));
        }
    }

    if (const auto* clips = get(root, "clips").getArray()) {
        for (const auto& o : *clips) {
            Clip c;
            c.id = idFromVar(get(o, "id"));
            c.trackId = idFromVar(get(o, "trackId"));
            c.lengthTicks = integer(o, "lengthTicks", p.ticksPerBar());
            if (c.id == kNoId || p.findTrack(c.trackId) == nullptr || c.lengthTicks <= 0)
                continue;
            if (const auto* notes = get(o, "notes").getArray()) {
                for (const auto& no : *notes) {
                    Note n;
                    n.id = idFromVar(get(no, "id"));
                    n.tick = integer(no, "tick", -1);
                    n.length = integer(no, "length", 0);
                    n.pitch = static_cast<int>(integer(no, "pitch", -1));
                    n.velocity = static_cast<float>(std::clamp(num(no, "velocity", 0.8), 0.0, 1.0));
                    if (n.id == kNoId || n.tick < 0 || n.tick >= c.lengthTicks || n.length <= 0 || n.pitch < 0
                        || n.pitch > 127)
                        continue; // 壊れたノートは捨てる
                    c.notes.push_back(n);
                }
            }
            c.sortNotes();
            p.clips.push_back(std::move(c));
        }
    }

    if (const auto* placements = get(root, "placements").getArray()) {
        for (const auto& o : *placements) {
            Placement pl;
            pl.id = idFromVar(get(o, "id"));
            pl.clipId = idFromVar(get(o, "clipId"));
            pl.trackId = idFromVar(get(o, "trackId"));
            pl.startBar = static_cast<int>(integer(o, "startBar", -1));
            pl.lengthBars = static_cast<int>(integer(o, "lengthBars", 0));
            const auto* clip = p.findClip(pl.clipId);
            if (pl.id == kNoId || clip == nullptr || clip->trackId != pl.trackId || pl.startBar < 0 || pl.lengthBars < 1)
                continue;
            p.placements.push_back(pl);
        }
    }

    if (p.tracks.empty()) {
        error = "トラックが1本もありません";
        return false;
    }
    out = std::move(p);
    return true;
}

//==============================================================================
bool saveProjectFile(const Project& project, const std::string& path, std::string& error) {
    const juce::File target(juce::String::fromUTF8(path.c_str()));
    if (!target.getParentDirectory().createDirectory()) {
        error = "保存先のフォルダを作れません";
        return false;
    }
    juce::TemporaryFile temp(target);
    if (!temp.getFile().replaceWithText(juce::String::fromUTF8(projectToJson(project).c_str()), false, false, "\n")) {
        error = "一時ファイルに書けません";
        return false;
    }
    if (!temp.overwriteTargetFileWithTemporary()) {
        error = "保存先に差し替えられません";
        return false;
    }
    return true;
}

bool loadProjectFile(const std::string& path, Project& project, std::string& error) {
    const juce::File file(juce::String::fromUTF8(path.c_str()));
    if (!file.existsAsFile()) {
        error = "ファイルがありません";
        return false;
    }
    return projectFromJson(file.loadFileAsString().toStdString(), project, error);
}

} // namespace mdaw
