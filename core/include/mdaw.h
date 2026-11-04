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

/* トラック・クリップ・ノートなどの ID。0 は「なし／失敗」。project.json では16桁の16進文字列。 */
typedef uint64_t mdaw_id;

/* 戻り値 */
enum {
    MDAW_OK = 0,
    MDAW_ERR_NO_AUDIO_DEVICE = -1, /* この環境には音声出力がない（PC上のテストなど） */
    MDAW_ERR_OPEN_FAILED = -2,
    MDAW_ERR_START_FAILED = -3,
    MDAW_ERR_FILE = -4             /* 保存・読み込みに失敗（理由は mdaw_last_error） */
};

/* パラメータID（mdaw_set_param / mdaw_set_track_param）。保存ファイルには名前で残る */
enum {
    /* シンセ */
    MDAW_PARAM_CUTOFF_HZ = 0,      /* 20〜20000 */
    MDAW_PARAM_RESONANCE = 1,      /* 0.5〜10（Q） */
    MDAW_PARAM_ATTACK_S = 2,       /* 秒 */
    MDAW_PARAM_DECAY_S = 3,        /* 秒 */
    MDAW_PARAM_SUSTAIN = 4,        /* 0〜1 */
    MDAW_PARAM_RELEASE_S = 5,      /* 秒 */
    MDAW_PARAM_DETUNE_CENTS = 6,   /* ユニゾンの一番外側どうしの開き（0〜100 セント） */
    MDAW_PARAM_MASTER_GAIN = 7,    /* 0〜1 */
    MDAW_PARAM_UNISON = 8,         /* 重ねる本数 1〜16 */
    MDAW_PARAM_WIDTH = 9,          /* ユニゾンの左右の広がり 0〜1 */
    MDAW_PARAM_BLEND = 10,         /* 外側の音の大きさ（中央に対して）0〜1 */
    MDAW_PARAM_SUB = 11,           /* 1オクターブ下のサイン波 0〜1 */
    MDAW_PARAM_NOISE = 12,         /* ノイズ 0〜1 */
    MDAW_PARAM_DRIVE = 13,         /* フィルター前の歪み 0〜1 */
    MDAW_PARAM_FILTER_ENV = 14,    /* 鳴らした瞬間にカットオフを上げる量 0〜1（最大7オクターブ） */
    MDAW_PARAM_FILTER_ENV_DECAY_S = 15,
    MDAW_PARAM_PITCH_ENV = 16,     /* 鳴らした瞬間に音程を上げる量（半音 0〜48）。キックやザップ */
    MDAW_PARAM_PITCH_ENV_DECAY_S = 17,
    MDAW_PARAM_WAVE = 18,          /* 0 = のこぎり、1 = 矩形 */
    MDAW_PARAM_OSC = 19,           /* のこぎり／矩形の音量 0〜1（0 にするとサブとノイズだけ：ハイハットなど） */
    MDAW_PARAM_COUNT = 20,

    /* トラックのエフェクト（mdaw_set_track_param のみ） */
    MDAW_FX_FIRST = 32,
    MDAW_FX_LOWCUT_HZ = 32,        /* 20（なし）〜12000 */
    MDAW_FX_SATURATION = 33,       /* 0〜1 */
    MDAW_FX_CHORUS = 34,           /* 0〜1 */
    MDAW_FX_OTT = 35,              /* 3帯域の上下圧縮の深さ 0〜1 */
    MDAW_FX_DELAY = 36,            /* 付点8分ディレイの量 0〜1 */
    MDAW_FX_DELAY_FEEDBACK = 37,   /* 0〜0.9 */
    MDAW_FX_REVERB = 38,           /* 0〜1 */
    MDAW_FX_REVERB_SIZE = 39,      /* 0〜1 */
    MDAW_FX_SIDECHAIN = 40,        /* キックで引っ込む深さ 0〜1 */
    MDAW_FX_SIDECHAIN_RELEASE_S = 41, /* 戻るまでの時間 0.03〜1 */
    MDAW_FX_SIDECHAIN_SOURCE = 42, /* 1 = このトラックの発音で他を引っ込める（キック） */
    MDAW_FX_END = 43
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

/* 再生操作（曲の中身は下のプロジェクト操作で決まる）。戻り値 1 = キューに積めた。
   stop は止めて曲頭へ戻る。position は 960 PPQ の tick。 */
MDAW_API int32_t mdaw_transport_play(mdaw_engine* engine);
MDAW_API int32_t mdaw_transport_stop(mdaw_engine* engine);
MDAW_API int32_t mdaw_transport_seek(mdaw_engine* engine, int64_t tick);
/* ループする範囲を [start_tick, end_tick) に絞る（ピアノロールでクリップだけを繰り返す）。end <= start で曲全体に戻す */
MDAW_API int32_t mdaw_transport_set_loop(mdaw_engine* engine, int64_t start_tick, int64_t end_tick);
MDAW_API int32_t mdaw_transport_is_playing(mdaw_engine* engine);
MDAW_API int64_t mdaw_transport_position_ticks(mdaw_engine* engine);

/* ---- プロジェクト ---------------------------------------------------------
   編集は UI スレッドからこの関数群で行い、適用のたびにコアが再生用データを作り直して音に反映する。
   画面はプロジェクトの中身を mdaw_project_json で JSON（project.json と同じ形）として読む。 */

MDAW_API void mdaw_project_new(mdaw_engine* engine);
MDAW_API int32_t mdaw_project_load(mdaw_engine* engine, const char* path); /* MDAW_OK / MDAW_ERR_FILE */
MDAW_API int32_t mdaw_project_save(mdaw_engine* engine, const char* path); /* MDAW_OK / MDAW_ERR_FILE */
/* 戻り値はエンジンが持つ UTF-8 文字列。次にこの関数を呼ぶか編集するまで有効 */
MDAW_API const char* mdaw_project_json(mdaw_engine* engine);
MDAW_API const char* mdaw_last_error(mdaw_engine* engine);
/* 中身が変わるたびに増える番号。画面の読み直しと自動保存の判定に使う */
MDAW_API uint64_t mdaw_project_version(mdaw_engine* engine);
MDAW_API int32_t mdaw_project_is_dirty(mdaw_engine* engine); /* 最後の保存・読み込みから変わったか */

/* 編集。ID を返すものは 0 で失敗、それ以外は 1 = 適用した、0 = 適用できなかった（対象がない・はみ出す など）。 */
MDAW_API mdaw_id mdaw_add_track(mdaw_engine* engine, const char* name, uint32_t color_argb);
MDAW_API int32_t mdaw_rename_track(mdaw_engine* engine, mdaw_id track_id, const char* name); /* 1〜64バイト */
/* トラックの音量（0〜2、1 = そのまま）・パン（-1 左〜1 右）・ミュート・ソロ。変わらなければ 0 */
MDAW_API int32_t mdaw_set_track_mixer(mdaw_engine* engine, mdaw_id track_id, float gain, float pan, int32_t mute,
                                      int32_t solo);
/* 新しいクリップを作って置く。out_placement_id は NULL でもよい */
MDAW_API mdaw_id mdaw_create_clip(mdaw_engine* engine, mdaw_id track_id, int32_t start_bar, int32_t length_bars,
                                  mdaw_id* out_placement_id);
MDAW_API mdaw_id mdaw_place_clip(mdaw_engine* engine, mdaw_id clip_id, int32_t start_bar); /* 複製を置く */
MDAW_API int32_t mdaw_remove_placement(mdaw_engine* engine, mdaw_id placement_id);
/* クリップの長さ（小節、1〜64）。その複製もすべて同じ長さになる。縮めてはみ出したノートは消える */
MDAW_API int32_t mdaw_set_clip_length(mdaw_engine* engine, mdaw_id clip_id, int32_t length_bars);
MDAW_API int32_t mdaw_move_placement(mdaw_engine* engine, mdaw_id placement_id, int32_t new_start_bar);
MDAW_API mdaw_id mdaw_add_note(mdaw_engine* engine, mdaw_id clip_id, int64_t tick, int64_t length, int32_t pitch,
                               float velocity);
MDAW_API int32_t mdaw_delete_notes(mdaw_engine* engine, mdaw_id clip_id, const mdaw_id* note_ids, int32_t count);
MDAW_API int32_t mdaw_move_notes(mdaw_engine* engine, mdaw_id clip_id, const mdaw_id* note_ids, int32_t count,
                                 int64_t delta_ticks, int32_t delta_pitch);
MDAW_API int32_t mdaw_resize_notes(mdaw_engine* engine, mdaw_id clip_id, const mdaw_id* note_ids, int32_t count,
                                   int64_t delta_ticks);
MDAW_API int32_t mdaw_set_tempo(mdaw_engine* engine, double bpm);
/* 音色の確定（Undo できる）。動かしている最中は mdaw_set_track_param_live で音だけ変え、離した時にこれを呼ぶ */
MDAW_API int32_t mdaw_set_track_param(mdaw_engine* engine, mdaw_id track_id, int32_t param_id, float value);
MDAW_API int32_t mdaw_set_track_param_live(mdaw_engine* engine, mdaw_id track_id, int32_t param_id, float value);

/* 1ジェスチャーの間の編集を1つの Undo にまとめる（入れ子可） */
MDAW_API void mdaw_begin_edit_group(mdaw_engine* engine);
MDAW_API void mdaw_end_edit_group(mdaw_engine* engine);

MDAW_API int32_t mdaw_undo(mdaw_engine* engine);
MDAW_API int32_t mdaw_redo(mdaw_engine* engine);
MDAW_API int32_t mdaw_can_undo(mdaw_engine* engine);
MDAW_API int32_t mdaw_can_redo(mdaw_engine* engine);

/* 試聴鍵盤（mdaw_note_on）をそのトラックの音色で鳴らす */
MDAW_API void mdaw_preview_track(mdaw_engine* engine, mdaw_id track_id);

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
