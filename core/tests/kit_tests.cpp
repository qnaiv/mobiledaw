// ドラムキット（kit.json と wav の読み込み、発音、チョーク、保存、書き出し）のテスト
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include <juce_audio_formats/juce_audio_formats.h>

#include "engine.h"
#include "kit.h"
#include "mdaw.h"
#include "playback.h"
#include "project_json.h"
#include "sampler.h"
#include "session.h"
#include "test_util.h"

namespace {

using namespace mdaw;

// 一時フォルダに小さなキットを作る：36 = 1秒の 220Hz サイン（44.1kHz）、42・46 = チョーク 1
struct TempKit {
    juce::File root = juce::File::getSpecialLocation(juce::File::tempDirectory)
                          .getChildFile("mdaw_kits_" + juce::String(juce::Random::getSystemRandom().nextInt()));
    juce::File dir = root.getChildFile("test-kit");

    TempKit() {
        dir.createDirectory();
        writeTone("tone.wav", 220.0, 1.0);
        writeTone("hat_c.wav", 3000.0, 0.5);
        writeTone("hat_o.wav", 5000.0, 1.0);
        dir.getChildFile("kit.json").replaceWithText(R"({
          "name": "Test Kit",
          "sounds": [
            {"file": "tone.wav", "name": "Tone", "note": 36},
            {"file": "hat_c.wav", "name": "Closed", "note": 42, "choke": 1},
            {"file": "hat_o.wav", "name": "Open", "note": 46, "choke": 1, "gain": 0.5}
          ]})");
    }
    ~TempKit() { root.deleteRecursively(); }

    void writeTone(const char* name, double hz, double seconds) {
        const double sr = 44100.0;
        juce::AudioBuffer<float> buf(1, static_cast<int>(sr * seconds));
        for (int i = 0; i < buf.getNumSamples(); ++i)
            buf.setSample(0, i, 0.5f * static_cast<float>(std::sin(2.0 * 3.14159265 * hz * i / sr)));
        juce::WavAudioFormat wav;
        std::unique_ptr<juce::OutputStream> out = dir.getChildFile(name).createOutputStream();
        auto w = wav.createWriterFor(out, juce::AudioFormatWriterOptions{}.withSampleRate(sr).withNumChannels(1).withBitsPerSample(16));
        w->writeFromAudioSampleBuffer(buf, 0, buf.getNumSamples());
    }
};

float peakOf(const std::vector<float>& v, size_t from, size_t to) {
    float p = 0.0f;
    for (size_t i = from; i < std::min(to, v.size()); ++i)
        p = std::max(p, std::abs(v[i]));
    return p;
}

TEST(kit_loads_and_rejects_bad_ids) {
    TempKit k;
    std::string error;
    auto kit = loadKit(k.dir.getFullPathName().toStdString(), "test-kit", error);
    CHECK(kit != nullptr);
    if (kit == nullptr)
        return;
    CHECK(kit->name == "Test Kit");
    CHECK(kit->sounds.size() == 3);
    CHECK(kit->sounds[0].sampleRate == 44100.0);
    CHECK(kit->sounds[0].frames() == 44100);
    CHECK(kit->sounds[2].gain == 0.5f);
    CHECK(isValidKitId("future-bass"));
    CHECK(!isValidKitId("../etc"));
    CHECK(!isValidKitId("Future"));
    CHECK(!isValidKitId(""));

    KitCache cache;
    cache.setRoot(k.root.getFullPathName().toStdString());
    CHECK(cache.get("test-kit") == cache.get("test-kit")); // 使い回す
    CHECK(cache.get("missing-kit") == nullptr);
    CHECK(!cache.error("missing-kit").empty());
}

TEST(sampler_plays_resampled_and_chokes) {
    TempKit k;
    std::string error;
    auto kit = loadKit(k.dir.getFullPathName().toStdString(), "test-kit", error);
    DrumSampler s;
    s.prepare(48000.0);
    s.setKit(kit.get());
    s.noteOn(36, 1.0f);
    std::vector<float> l(48000 * 2, 0.0f), r(48000 * 2, 0.0f);
    for (int i = 0; i < 96000; i += 512)
        s.render(l.data() + i, r.data() + i, std::min(512, 96000 - i));
    // 44.1kHz の1秒は 48kHz でも1秒（音程はそのまま）
    CHECK(peakOf(l, 0, 47000) > 0.4f);
    CHECK(peakOf(l, 48200, 96000) == 0.0f);
    CHECK(s.activeVoices() == 0);

    // 開いたハットを閉じたハットで止める
    s.noteOn(46, 1.0f);
    std::fill(l.begin(), l.end(), 0.0f);
    s.render(l.data(), r.data(), 1000);
    s.noteOn(42, 1.0f);
    CHECK(s.activeVoices() == 2);
    for (int i = 0; i < 2000; i += 500)
        s.render(l.data() + 1000 + i, r.data() + 1000 + i, 500);
    CHECK(s.activeVoices() == 1); // 開いたほうは 5ms で消えた
    s.setKit(nullptr);
    CHECK(s.activeVoices() == 0);
}

TEST(session_kit_track_plays_and_saves) {
    TempKit k;
    Engine engine;
    engine.prepare(48000.0);
    Session session(engine);
    session.setKitsRoot(k.root.getFullPathName().toStdString());
    const Id track = session.project().tracks.front().id;
    CHECK(session.execute(std::make_unique<SetTrackKit>(track, "test-kit")));
    CHECK(!session.execute(std::make_unique<SetTrackKit>(track, "Bad/Id")));
    auto create = std::make_unique<CreateClip>(track, 0, 1);
    auto* raw = create.get();
    CHECK(session.execute(std::move(create)));
    Note n;
    n.tick = kPpq; // 2拍目（120 BPM で 0.5 秒）
    n.length = ResizeNotes::kMinLength; // 短くても最後まで鳴る（ワンショット）
    n.pitch = 36;
    n.velocity = 1.0f;
    CHECK(session.execute(std::make_unique<AddNotes>(raw->clipId(), std::vector<Note>{n})));
    CHECK(session.kitError("test-kit").empty());

    engine.play();
    std::vector<float> buf(48000 * 2 * 2);
    for (int i = 0; i < 96000; i += 256)
        engine.render(buf.data() + static_cast<size_t>(i) * 2, 256, 2);
    long first = -1;
    float lateEnd = 0.0f;
    for (long i = 0; i < 96000; ++i) {
        if (first < 0 && buf[static_cast<size_t>(i) * 2] != 0.0f)
            first = i;
        if (i > 24000 + 30000 && i < 24000 + 44000)
            lateEnd = std::max(lateEnd, std::abs(buf[static_cast<size_t>(i) * 2]));
    }
    std::printf("  鳴り始め %ld / 0.7秒後 %.3f\n", first, lateEnd);
    CHECK(first >= 24000 && first < 24010);
    CHECK(lateEnd > 0.1f); // ノートは短いがキットの音は1秒続く

    // 保存すると kit の ID が残る
    const auto json = projectToJson(session.project());
    CHECK(json.find("\"kit\"") != std::string::npos && json.find("test-kit") != std::string::npos);
    Project back;
    std::string error;
    CHECK(projectFromJson(json, back, error));
    CHECK(back.tracks.front().kitId == "test-kit");

    // 元に戻すとシンセに
    CHECK(session.undo() && session.undo() && session.undo());
    CHECK(session.project().tracks.front().kitId.empty());
    CHECK(!session.kitError("nothing-here").empty());
}

// ---- サンプラー楽器 ---------------------------------------------------------

// メモリ上で KitSound を作る（220Hz サイン、44.1kHz、1秒、モノラル。ファイルは使わない）
KitSound makeToneSound(double hz = 220.0, double seconds = 1.0, double sr = 44100.0) {
    KitSound s;
    s.name = "Tone";
    s.note = 60;
    s.gain = 1.0f;
    s.sampleRate = sr;
    const int n = static_cast<int>(sr * seconds);
    s.left.resize(static_cast<size_t>(n));
    for (int i = 0; i < n; ++i)
        s.left[static_cast<size_t>(i)] = 0.5f * static_cast<float>(std::sin(2.0 * 3.14159265 * hz * i / sr));
    return s;
}

// ゼロクロッシングから大まかな周波数を数える
double estimateHz(const std::vector<float>& v, size_t from, size_t to, double sr) {
    int crossings = 0;
    const size_t end = std::min(to, v.size());
    for (size_t i = from + 1; i < end; ++i)
        if ((v[i - 1] < 0.0f) != (v[i] < 0.0f))
            ++crossings;
    const double seconds = static_cast<double>(end - from) / sr;
    return seconds > 0.0 ? crossings / 2.0 / seconds : 0.0;
}

std::vector<float> renderMelodic(MelodicSampler& s, int frames) {
    std::vector<float> l(static_cast<size_t>(frames), 0.0f), r(static_cast<size_t>(frames), 0.0f);
    for (int i = 0; i < frames; i += 512)
        s.render(l.data() + i, r.data() + i, std::min(512, frames - i));
    return l;
}

TEST(melodic_sampler_pitches_by_note) {
    auto sound = makeToneSound();
    MelodicSampler probe;
    probe.prepare(48000.0);
    probe.setSound(&sound, 60, 1.0f, 0.0f);
    // 速度比：基準音程で素材のレート換算のみ、±12 半音で 2 倍／半分
    CHECK(std::abs(probe.incrementFor(60) - 44100.0 / 48000.0) < 1e-9);
    CHECK(std::abs(probe.incrementFor(72) - 2.0 * 44100.0 / 48000.0) < 1e-9);
    CHECK(std::abs(probe.incrementFor(48) - 0.5 * 44100.0 / 48000.0) < 1e-9);

    auto playFreq = [&](int note) {
        MelodicSampler s;
        s.prepare(48000.0);
        s.setSound(&sound, 60, 1.0f, 0.0f);
        s.noteOn(note, 1.0f);
        const auto l = renderMelodic(s, 24000);
        CHECK(peakOf(l, 0, l.size()) > 0.4f); // 無音でない
        return estimateHz(l, 1000, 20000, 48000.0);
    };
    const double fRoot = playFreq(60);
    const double fUp = playFreq(72);
    const double fDown = playFreq(48);
    std::printf("  基準 %.1f Hz / +12 %.1f Hz / -12 %.1f Hz\n", fRoot, fUp, fDown);
    CHECK(fRoot > 200.0 && fRoot < 240.0);
    CHECK(fUp > 400.0 && fUp < 480.0);
    CHECK(fDown > 100.0 && fDown < 120.0);
}

TEST(melodic_sampler_noteoff_releases_and_oneshot_ends) {
    auto sound = makeToneSound();
    MelodicSampler s;
    s.prepare(48000.0);
    s.setSound(&sound, 60, 1.0f, 0.0f);

    // ノートオフでリリース（60ms）→ 無音になりボイスも消える
    s.noteOn(60, 1.0f);
    auto l = renderMelodic(s, 4800);
    CHECK(peakOf(l, 0, l.size()) > 0.4f);
    CHECK(s.activeVoices() == 1);
    s.noteOff(60);
    l = renderMelodic(s, 48000);
    CHECK(peakOf(l, 9600, 48000) == 0.0f);
    CHECK(s.activeVoices() == 0);

    // ノートオフしなくても素材が終われば消える（ワンショット。2倍速なので 0.5 秒）
    s.noteOn(72, 1.0f);
    l = renderMelodic(s, 48000);
    CHECK(peakOf(l, 30000, 48000) == 0.0f);
    CHECK(s.activeVoices() == 0);

    // 開始位置 0.5：後半だけが鳴る
    MelodicSampler s2;
    s2.prepare(48000.0);
    s2.setSound(&sound, 60, 1.0f, 0.5f);
    s2.noteOn(60, 1.0f);
    const auto l2 = renderMelodic(s2, 48000);
    CHECK(peakOf(l2, 0, 12000) > 0.3f);
    CHECK(peakOf(l2, 30000, 48000) == 0.0f);

    // 素材を差し替えると鳴っている音は止まる
    MelodicSampler s3;
    s3.prepare(48000.0);
    s3.setSound(&sound, 60, 1.0f, 0.0f);
    s3.noteOn(60, 1.0f);
    CHECK(s3.activeVoices() == 1);
    s3.setSound(nullptr, 60, 1.0f, 0.0f);
    CHECK(s3.activeVoices() == 0);
}

TEST(session_sampler_track_resolves_plays_and_saves) {
    TempKit k;
    Engine engine;
    engine.prepare(48000.0);
    Session session(engine);
    session.setKitsRoot(k.root.getFullPathName().toStdString());
    const Id track = session.project().tracks.front().id;

    SamplerSettings bad;
    bad.kitId = "Bad/Id";
    CHECK(!session.execute(std::make_unique<SetTrackSampler>(track, bad)));

    SamplerSettings settings;
    settings.kitId = "test-kit";
    settings.soundName = "Tone";
    settings.rootNote = 60;
    CHECK(session.execute(std::make_unique<SetTrackSampler>(track, settings)));
    CHECK(session.project().tracks.front().isSampler());

    // スナップショットで素材（名前→添字）が解決できている。ドラム側は従来どおり空
    auto snap = session.snapshot();
    CHECK(snap->tracks.front().samplerKit != nullptr);
    CHECK(snap->tracks.front().samplerSound == 0);
    CHECK(snap->tracks.front().kit == nullptr);

    // 基準音程のノートで鳴る
    auto create = std::make_unique<CreateClip>(track, 0, 1);
    auto* raw = create.get();
    CHECK(session.execute(std::move(create)));
    Note n;
    n.tick = 0;
    n.length = kPpq * 2;
    n.pitch = 60;
    n.velocity = 1.0f;
    CHECK(session.execute(std::make_unique<AddNotes>(raw->clipId(), std::vector<Note>{n})));
    engine.play();
    std::vector<float> buf(48000 * 2 * 2, 0.0f);
    for (int i = 0; i < 96000; i += 256)
        engine.render(buf.data() + static_cast<size_t>(i) * 2, 256, 2);
    float early = 0.0f;
    for (int i = 100; i < 20000; ++i)
        early = std::max(early, std::abs(buf[static_cast<size_t>(i) * 2]));
    CHECK(early > 0.1f);

    // 保存・復元でサンプラー設定が往復する
    const auto json = projectToJson(session.project());
    CHECK(json.find("\"sampler\"") != std::string::npos);
    Project back;
    std::string error;
    CHECK(projectFromJson(json, back, error));
    CHECK(back.tracks.front().isSampler());
    CHECK(back.tracks.front().sampler.soundName == "Tone");
    CHECK(back.tracks.front().sampler.rootNote == 60);

    // 従来プロジェクト（サンプラー無し）は既定値のまま＝従来動作
    Project defBack;
    CHECK(projectFromJson(projectToJson(makeDefaultProject()), defBack, error));
    CHECK(!defBack.tracks.front().isSampler());
    CHECK(defBack.tracks.front().sampler.rootNote == 60);
    CHECK(defBack.tracks.front().sampler.gain == 1.0f);
}

// リポジトリの kits/ にあるキットが全部読める
TEST(repository_kits_all_load) {
    const auto kits = juce::File(__FILE__).getParentDirectory().getParentDirectory().getParentDirectory().getChildFile("kits");
    if (!kits.isDirectory()) {
        std::printf("  kits/ がないので省略\n");
        return;
    }
    int count = 0, sounds = 0;
    for (const auto& d : kits.findChildFiles(juce::File::findDirectories, false)) {
        if (d.getFileName().startsWith("_"))
            continue;
        std::string error;
        auto kit = loadKit(d.getFullPathName().toStdString(), d.getFileName().toStdString(), error);
        if (kit == nullptr)
            std::printf("  %s: %s\n", d.getFileName().toRawUTF8(), error.c_str());
        CHECK(kit != nullptr);
        CHECK(isValidKitId(d.getFileName().toStdString()));
        if (kit != nullptr) {
            ++count;
            sounds += static_cast<int>(kit->sounds.size());
        }
    }
    std::printf("  %d キット / %d 音\n", count, sounds);
    CHECK(count > 0);
}

} // namespace
