#include "mdaw.h"

#include <memory>
#include <vector>

#include "audio_output.h"
#include "commands.h"
#include "engine.h"
#include "exporter.h"
#include "session.h"

namespace mdaw {
#if !MDAW_HAS_OBOE
std::unique_ptr<AudioOutput> createPlatformAudioOutput() { return nullptr; }
#endif
} // namespace mdaw

struct mdaw_engine {
    mdaw::Engine engine;
    mdaw::Session session{engine};
    mdaw::Exporter exporter;
    std::string kitError; // mdaw_kit_error が返す文字列の置き場
    std::unique_ptr<mdaw::AudioOutput> output = mdaw::createPlatformAudioOutput();
};

namespace {

std::vector<mdaw::Id> idList(const mdaw_id* ids, int32_t count) {
    std::vector<mdaw::Id> out;
    if (ids != nullptr && count > 0)
        out.assign(ids, ids + count);
    return out;
}

int32_t run(mdaw_engine* e, mdaw::CommandPtr command) {
    return e != nullptr && e->session.execute(std::move(command)) ? 1 : 0;
}

// コマンドを実行し、成功したら getId(コマンド) を返す
template <typename T, typename GetId>
mdaw_id runForId(mdaw_engine* e, std::unique_ptr<T> command, GetId getId) {
    if (e == nullptr)
        return 0;
    T* raw = command.get();
    if (!e->session.execute(std::move(command)))
        return 0;
    return getId(*raw); // 適用済みのコマンドは履歴が持っているので raw はまだ有効
}

} // namespace

extern "C" {

mdaw_engine* mdaw_create(void) { return new mdaw_engine(); }

void mdaw_destroy(mdaw_engine* e) {
    if (e == nullptr)
        return;
    if (e->output)
        e->output->stop();
    delete e;
}

int32_t mdaw_start(mdaw_engine* e) {
    if (e == nullptr || !e->output)
        return MDAW_ERR_NO_AUDIO_DEVICE;
    return e->output->start(e->engine);
}

void mdaw_stop(mdaw_engine* e) {
    if (e != nullptr && e->output)
        e->output->stop();
}

int32_t mdaw_note_on(mdaw_engine* e, int32_t note, float velocity) { return e && e->engine.noteOn(note, velocity) ? 1 : 0; }
int32_t mdaw_note_off(mdaw_engine* e, int32_t note) { return e && e->engine.noteOff(note) ? 1 : 0; }
int32_t mdaw_all_notes_off(mdaw_engine* e) { return e && e->engine.allNotesOff() ? 1 : 0; }
int32_t mdaw_set_param(mdaw_engine* e, int32_t id, float value) { return e && e->engine.setParam(id, value) ? 1 : 0; }

int32_t mdaw_transport_play(mdaw_engine* e) { return e && e->engine.play() ? 1 : 0; }
int32_t mdaw_transport_stop(mdaw_engine* e) { return e && e->engine.stop() ? 1 : 0; }
int32_t mdaw_transport_seek(mdaw_engine* e, int64_t tick) { return e && e->engine.seek(tick) ? 1 : 0; }
int32_t mdaw_transport_set_loop(mdaw_engine* e, int64_t start, int64_t end) {
    return e && e->engine.setLoop(start, end) ? 1 : 0;
}
int32_t mdaw_transport_is_playing(mdaw_engine* e) { return e && e->engine.isPlaying() ? 1 : 0; }
int64_t mdaw_transport_position_ticks(mdaw_engine* e) { return e ? e->engine.playheadTick() : 0; }

void mdaw_project_new(mdaw_engine* e) {
    if (e != nullptr)
        e->session.newProject();
}

int32_t mdaw_project_load(mdaw_engine* e, const char* path) {
    if (e == nullptr || path == nullptr)
        return MDAW_ERR_FILE;
    return e->session.load(path) ? MDAW_OK : MDAW_ERR_FILE;
}

int32_t mdaw_project_save(mdaw_engine* e, const char* path) {
    if (e == nullptr || path == nullptr)
        return MDAW_ERR_FILE;
    return e->session.save(path) ? MDAW_OK : MDAW_ERR_FILE;
}

const char* mdaw_project_json(mdaw_engine* e) { return e ? e->session.json().c_str() : ""; }
const char* mdaw_last_error(mdaw_engine* e) { return e ? e->session.lastError().c_str() : ""; }
uint64_t mdaw_project_version(mdaw_engine* e) { return e ? e->session.version() : 0; }
int32_t mdaw_project_is_dirty(mdaw_engine* e) { return e && e->session.dirty() ? 1 : 0; }

int32_t mdaw_set_project_title(mdaw_engine* e, const char* title) {
    return run(e, std::make_unique<mdaw::SetProjectTitle>(title ? title : ""));
}

int32_t mdaw_export_start(mdaw_engine* e, const char* path, mdaw_id track) {
    if (e == nullptr || path == nullptr || e->exporter.state() == mdaw::Exporter::Running)
        return 0;
    return e->exporter.start(e->session.snapshot(), path, track) ? 1 : 0;
}

void mdaw_set_kits_dir(mdaw_engine* e, const char* dir) {
    if (e != nullptr && dir != nullptr)
        e->session.setKitsRoot(dir);
}

void mdaw_reload_kits(mdaw_engine* e) {
    if (e != nullptr)
        e->session.reloadKits();
}

int32_t mdaw_set_track_kit(mdaw_engine* e, mdaw_id track, const char* kit) {
    return run(e, std::make_unique<mdaw::SetTrackKit>(track, kit ? kit : ""));
}

int32_t mdaw_set_track_sampler(mdaw_engine* e, mdaw_id track, const char* kit, const char* sound, int32_t root_note,
                               float gain, float start) {
    mdaw::SamplerSettings settings;
    settings.kitId = kit ? kit : "";
    settings.soundName = sound ? sound : "";
    settings.rootNote = root_note;
    settings.gain = gain;
    settings.start = start;
    return run(e, std::make_unique<mdaw::SetTrackSampler>(track, std::move(settings)));
}

const char* mdaw_kit_error(mdaw_engine* e, const char* kit) {
    if (e == nullptr || kit == nullptr)
        return "";
    e->kitError = e->session.kitError(kit);
    return e->kitError.c_str();
}

int32_t mdaw_export_state(mdaw_engine* e) { return e ? e->exporter.state() : MDAW_EXPORT_IDLE; }
float mdaw_export_progress(mdaw_engine* e) { return e ? e->exporter.progress() : 0.0f; }
void mdaw_export_cancel(mdaw_engine* e) {
    if (e != nullptr)
        e->exporter.cancel();
}
const char* mdaw_export_error(mdaw_engine* e) {
    return e && e->exporter.state() != mdaw::Exporter::Running ? e->exporter.error().c_str() : "";
}

mdaw_id mdaw_add_track(mdaw_engine* e, const char* name, uint32_t color) {
    return runForId(e, std::make_unique<mdaw::AddTrack>(name ? name : "", color),
                    [](const mdaw::AddTrack& c) { return c.trackId(); });
}

int32_t mdaw_rename_track(mdaw_engine* e, mdaw_id track, const char* name) {
    return run(e, std::make_unique<mdaw::RenameTrack>(track, name ? name : ""));
}

int32_t mdaw_set_track_mixer(mdaw_engine* e, mdaw_id track, float gain, float pan, int32_t mute, int32_t solo) {
    mdaw::Mixer m;
    m.gain = gain;
    m.pan = pan;
    m.mute = mute != 0;
    m.solo = solo != 0;
    return run(e, std::make_unique<mdaw::SetTrackMixer>(track, m));
}

mdaw_id mdaw_create_clip(mdaw_engine* e, mdaw_id track, int32_t startBar, int32_t bars, mdaw_id* outPlacement) {
    if (outPlacement != nullptr)
        *outPlacement = 0;
    return runForId(e, std::make_unique<mdaw::CreateClip>(track, startBar, bars), [&](const mdaw::CreateClip& c) {
        if (outPlacement != nullptr)
            *outPlacement = c.placementId();
        return c.clipId();
    });
}

mdaw_id mdaw_place_clip(mdaw_engine* e, mdaw_id clip, int32_t startBar) {
    return runForId(e, std::make_unique<mdaw::PlaceClip>(clip, startBar),
                    [](const mdaw::PlaceClip& c) { return c.placementId(); });
}

mdaw_id mdaw_clone_clip(mdaw_engine* e, mdaw_id clip, int32_t startBar, mdaw_id* outPlacement) {
    if (outPlacement != nullptr)
        *outPlacement = 0;
    return runForId(e, std::make_unique<mdaw::CloneClip>(clip, startBar), [&](const mdaw::CloneClip& c) {
        if (outPlacement != nullptr)
            *outPlacement = c.placementId();
        return c.clipId();
    });
}

int32_t mdaw_remove_placement(mdaw_engine* e, mdaw_id placement) {
    return run(e, std::make_unique<mdaw::RemovePlacement>(placement));
}

int32_t mdaw_set_clip_length(mdaw_engine* e, mdaw_id clip, int32_t bars) {
    return run(e, std::make_unique<mdaw::ResizeClip>(clip, bars));
}

int32_t mdaw_move_placement(mdaw_engine* e, mdaw_id placement, int32_t newStartBar) {
    return run(e, std::make_unique<mdaw::MovePlacement>(placement, newStartBar));
}

mdaw_id mdaw_add_note(mdaw_engine* e, mdaw_id clip, int64_t tick, int64_t length, int32_t pitch, float velocity) {
    mdaw::Note n;
    n.tick = tick;
    n.length = length;
    n.pitch = pitch;
    n.velocity = velocity;
    return runForId(e, std::make_unique<mdaw::AddNotes>(clip, std::vector<mdaw::Note>{n}),
                    [](const mdaw::AddNotes& c) {
                        auto ids = c.addedIds();
                        return ids.empty() ? mdaw::kNoId : ids.front();
                    });
}

int32_t mdaw_delete_notes(mdaw_engine* e, mdaw_id clip, const mdaw_id* ids, int32_t count) {
    return run(e, std::make_unique<mdaw::DeleteNotes>(clip, idList(ids, count)));
}

int32_t mdaw_move_notes(mdaw_engine* e, mdaw_id clip, const mdaw_id* ids, int32_t count, int64_t dTicks,
                        int32_t dPitch) {
    return run(e, std::make_unique<mdaw::MoveNotes>(clip, idList(ids, count), dTicks, dPitch));
}

int32_t mdaw_resize_notes(mdaw_engine* e, mdaw_id clip, const mdaw_id* ids, int32_t count, int64_t dTicks) {
    return run(e, std::make_unique<mdaw::ResizeNotes>(clip, idList(ids, count), dTicks));
}

int32_t mdaw_set_tempo(mdaw_engine* e, double bpm) { return run(e, std::make_unique<mdaw::SetTempo>(bpm)); }

int32_t mdaw_set_key(mdaw_engine* e, int32_t root, const char* scale) {
    if (scale == nullptr)
        return 0;
    return run(e, std::make_unique<mdaw::SetKey>(root, std::string(scale)));
}

int32_t mdaw_set_clip_automation(mdaw_engine* e, mdaw_id clip, int32_t param, const int64_t* ticks, const float* values,
                                 int32_t count) {
    if (e == nullptr || count < 0 || (count > 0 && (ticks == nullptr || values == nullptr)))
        return 0;
    mdaw::AutomationLane lane;
    lane.paramId = param;
    lane.points.reserve(static_cast<size_t>(count));
    for (int32_t i = 0; i < count; ++i)
        lane.points.push_back(mdaw::AutomationPoint{ticks[i], values[i]});
    return run(e, std::make_unique<mdaw::SetClipAutomation>(clip, std::move(lane)));
}

int32_t mdaw_set_track_param(mdaw_engine* e, mdaw_id track, int32_t param, float value) {
    return run(e, std::make_unique<mdaw::SetTrackSynthParam>(track, param, value));
}

int32_t mdaw_set_track_param_live(mdaw_engine* e, mdaw_id track, int32_t param, float value) {
    return e && e->session.setTrackParamLive(track, param, value) ? 1 : 0;
}

void mdaw_begin_edit_group(mdaw_engine* e) {
    if (e != nullptr)
        e->session.beginGroup();
}

void mdaw_end_edit_group(mdaw_engine* e) {
    if (e != nullptr)
        e->session.endGroup();
}

int32_t mdaw_undo(mdaw_engine* e) { return e && e->session.undo() ? 1 : 0; }
int32_t mdaw_redo(mdaw_engine* e) { return e && e->session.redo() ? 1 : 0; }
int32_t mdaw_can_undo(mdaw_engine* e) { return e && e->session.canUndo() ? 1 : 0; }
int32_t mdaw_can_redo(mdaw_engine* e) { return e && e->session.canRedo() ? 1 : 0; }

void mdaw_preview_track(mdaw_engine* e, mdaw_id track) {
    if (e != nullptr)
        e->session.previewTrack(track);
}

int32_t mdaw_sample_rate(mdaw_engine* e) { return e && e->output ? e->output->sampleRate() : 0; }
int32_t mdaw_frames_per_burst(mdaw_engine* e) { return e && e->output ? e->output->framesPerBurst() : 0; }
int32_t mdaw_buffer_size_frames(mdaw_engine* e) { return e && e->output ? e->output->bufferSizeFrames() : 0; }
double mdaw_output_latency_ms(mdaw_engine* e) { return e && e->output ? e->output->latencyMs() : -1.0; }
int32_t mdaw_xrun_count(mdaw_engine* e) { return e && e->output ? e->output->xrunCount() : -1; }
int64_t mdaw_frames_rendered(mdaw_engine* e) { return e ? e->engine.framesRendered() : 0; }
int32_t mdaw_active_voices(mdaw_engine* e) { return e ? e->engine.activeVoices() : 0; }

} // extern "C"
