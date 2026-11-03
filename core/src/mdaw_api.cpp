#include "mdaw.h"

#include <memory>

#include "audio_output.h"
#include "engine.h"

namespace mdaw {
#if !MDAW_HAS_OBOE
std::unique_ptr<AudioOutput> createPlatformAudioOutput() { return nullptr; }
#endif
} // namespace mdaw

struct mdaw_engine {
    mdaw::Engine engine;
    std::unique_ptr<mdaw::AudioOutput> output = mdaw::createPlatformAudioOutput();
};

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
int32_t mdaw_transport_is_playing(mdaw_engine* e) { return e && e->engine.isPlaying() ? 1 : 0; }
int64_t mdaw_transport_position_ticks(mdaw_engine* e) { return e ? e->engine.playheadTick() : 0; }

int32_t mdaw_sample_rate(mdaw_engine* e) { return e && e->output ? e->output->sampleRate() : 0; }
int32_t mdaw_frames_per_burst(mdaw_engine* e) { return e && e->output ? e->output->framesPerBurst() : 0; }
int32_t mdaw_buffer_size_frames(mdaw_engine* e) { return e && e->output ? e->output->bufferSizeFrames() : 0; }
double mdaw_output_latency_ms(mdaw_engine* e) { return e && e->output ? e->output->latencyMs() : -1.0; }
int32_t mdaw_xrun_count(mdaw_engine* e) { return e && e->output ? e->output->xrunCount() : -1; }
int64_t mdaw_frames_rendered(mdaw_engine* e) { return e ? e->engine.framesRendered() : 0; }
int32_t mdaw_active_voices(mdaw_engine* e) { return e ? e->engine.activeVoices() : 0; }

} // extern "C"
