#include "kit.h"

#include <algorithm>
#include <cmath>

#include <juce_audio_formats/juce_audio_formats.h>

namespace mdaw {

namespace {
constexpr double kMaxSeconds = 30.0; // 1音の長さの上限（メモリを守る）
constexpr size_t kMaxSounds = 64;
} // namespace

bool isValidKitId(const std::string& id) noexcept {
    if (id.empty() || id.size() > 48)
        return false;
    for (const char c : id)
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
            return false;
    return id.front() != '-';
}

KitPtr loadKit(const std::string& dirPath, const std::string& id, std::string& error) {
    const juce::File dir(juce::String::fromUTF8(dirPath.c_str()));
    const auto metaFile = dir.getChildFile("kit.json");
    if (!metaFile.existsAsFile()) {
        error = "キットがありません（ダウンロードしてください）: " + id;
        return nullptr;
    }
    juce::var meta;
    if (juce::JSON::parse(metaFile.loadFileAsString(), meta).failed() || !meta.isObject()) {
        error = "kit.json を読めません: " + id;
        return nullptr;
    }
    const auto* sounds = meta.getProperty("sounds", juce::var()).getArray();
    if (sounds == nullptr || sounds->isEmpty()) {
        error = "kit.json に sounds がありません: " + id;
        return nullptr;
    }

    juce::AudioFormatManager formats;
    formats.registerBasicFormats();

    auto kit = std::make_shared<Kit>();
    kit->id = id;
    kit->name = meta.getProperty("name", juce::String(id)).toString().toStdString();
    int index = 0;
    for (const auto& s : *sounds) {
        if (kit->sounds.size() >= kMaxSounds)
            break;
        const auto rel = s.getProperty("file", "").toString();
        const auto file = dir.getChildFile(rel);
        if (rel.isEmpty() || !file.isAChildOf(dir) || !file.existsAsFile()) {
            error = "wav がありません: " + rel.toStdString();
            return nullptr;
        }
        std::unique_ptr<juce::AudioFormatReader> reader(formats.createReaderFor(file));
        if (reader == nullptr || reader->sampleRate <= 0.0 || reader->lengthInSamples <= 0) {
            error = "wav を読めません: " + rel.toStdString();
            return nullptr;
        }
        const auto frames = static_cast<int>(std::min<juce::int64>(
            reader->lengthInSamples, static_cast<juce::int64>(kMaxSeconds * reader->sampleRate)));
        const int channels = std::min(2, static_cast<int>(reader->numChannels));
        juce::AudioBuffer<float> buf(std::max(channels, 1), frames);
        reader->read(&buf, 0, frames, 0, true, channels > 1);

        KitSound sound;
        sound.name = s.getProperty("name", rel).toString().toStdString();
        sound.note = std::clamp(static_cast<int>(s.getProperty("note", 36 + index)), 0, 127);
        sound.gain = std::clamp(static_cast<float>(static_cast<double>(s.getProperty("gain", 1.0))), 0.0f, 2.0f);
        sound.choke = std::max(0, static_cast<int>(s.getProperty("choke", 0)));
        sound.sampleRate = reader->sampleRate;
        sound.left.assign(buf.getReadPointer(0), buf.getReadPointer(0) + frames);
        if (channels > 1)
            sound.right.assign(buf.getReadPointer(1), buf.getReadPointer(1) + frames);
        kit->sounds.push_back(std::move(sound));
        ++index;
    }
    return kit;
}

void KitCache::setRoot(std::string root) {
    if (root == root_)
        return;
    root_ = std::move(root);
    clear();
}

KitPtr KitCache::get(const std::string& id) {
    if (!isValidKitId(id) || root_.empty())
        return nullptr;
    if (auto it = loaded_.find(id); it != loaded_.end())
        return it->second;
    if (errors_.count(id) != 0)
        return nullptr; // 読めなかったものは clear() まで試さない
    std::string error;
    auto kit = loadKit(root_ + "/" + id, id, error);
    if (kit == nullptr) {
        errors_[id] = error;
        return nullptr;
    }
    loaded_[id] = kit;
    return kit;
}

std::string KitCache::error(const std::string& id) const {
    if (auto it = errors_.find(id); it != errors_.end())
        return it->second;
    return {};
}

void KitCache::clear() {
    loaded_.clear();
    errors_.clear();
}

} // namespace mdaw
