// mdaw.h — Flutter（dart:ffi）から呼ぶ C API。
// UIスレッド（Dartのメインisolate）1本から呼ぶ前提。音声スレッドとはロックフリーキューでやり取りする。
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(MDAW_BUILDING_LIBRARY)
 #define MDAW_API __attribute__((visibility("default")))
#else
 #define MDAW_API
#endif

typedef struct mdaw_engine mdaw_engine;

/* 戻り値 */
enum {
    MDAW_OK = 0,
    MDAW_ERR_NO_AUDIO_DEVICE = -1, /* この環境には音声出力がない（PC上のテストなど） */
    MDAW_ERR_OPEN_FAILED = -2,
    MDAW_ERR_START_FAILED = -3
};

/* パラメータID（mdaw_set_param） */
enum {
    MDAW_PARAM_CUTOFF_HZ = 0,    /* 20〜20000 */
    MDAW_PARAM_RESONANCE = 1,    /* 0.5〜10 */
    MDAW_PARAM_ATTACK_S = 2,     /* 秒 */
    MDAW_PARAM_DECAY_S = 3,      /* 秒 */
    MDAW_PARAM_SUSTAIN = 4,      /* 0〜1 */
    MDAW_PARAM_RELEASE_S = 5,    /* 秒 */
    MDAW_PARAM_DETUNE_CENTS = 6, /* 2つ目のオシレーターのずらし量 */
    MDAW_PARAM_MASTER_GAIN = 7,  /* 0〜1 */
    MDAW_PARAM_COUNT = 8
};

MDAW_API mdaw_engine* mdaw_create(void);
MDAW_API void mdaw_destroy(mdaw_engine* engine);

/* 音声出力を開いて鳴らし始める／止める。 */
MDAW_API int32_t mdaw_start(mdaw_engine* engine);
MDAW_API void mdaw_stop(mdaw_engine* engine);

/* 発音。戻り値 1 = キューに積めた、0 = キューが満杯で捨てた。 */
MDAW_API int32_t mdaw_note_on(mdaw_engine* engine, int32_t note, float velocity);
MDAW_API int32_t mdaw_note_off(mdaw_engine* engine, int32_t note);
MDAW_API int32_t mdaw_all_notes_off(mdaw_engine* engine);
MDAW_API int32_t mdaw_set_param(mdaw_engine* engine, int32_t param_id, float value);

/* 再生操作（曲の中身は M2 の「プロジェクト操作」で渡す）。戻り値 1 = キューに積めた。
   stop は止めて曲頭へ戻る。position は 960 PPQ の tick。 */
MDAW_API int32_t mdaw_transport_play(mdaw_engine* engine);
MDAW_API int32_t mdaw_transport_stop(mdaw_engine* engine);
MDAW_API int32_t mdaw_transport_seek(mdaw_engine* engine, int64_t tick);
MDAW_API int32_t mdaw_transport_is_playing(mdaw_engine* engine);
MDAW_API int64_t mdaw_transport_position_ticks(mdaw_engine* engine);

/* 状態の取得（表示用）。 */
MDAW_API int32_t mdaw_sample_rate(mdaw_engine* engine);
MDAW_API int32_t mdaw_frames_per_burst(mdaw_engine* engine);
MDAW_API int32_t mdaw_buffer_size_frames(mdaw_engine* engine);
MDAW_API double mdaw_output_latency_ms(mdaw_engine* engine); /* 不明なら -1 */
MDAW_API int64_t mdaw_frames_rendered(mdaw_engine* engine);
MDAW_API int32_t mdaw_xrun_count(mdaw_engine* engine);       /* 不明なら -1 */
MDAW_API int32_t mdaw_active_voices(mdaw_engine* engine);

#ifdef __cplusplus
}
#endif
