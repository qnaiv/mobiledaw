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
    MDAW_PARAM_WT_TABLE = 20,      /* ウェーブテーブル 0 = 従来オシレーター、1 = Basic Shapes、2 = Harmonic、3 = Formant、4 = Digital、5 = Spectral Saw、6 = Pulse Morph、7 = Choir */
    MDAW_PARAM_WT_POS = 21,        /* テーブル内のフレーム位置 0〜1 */
    MDAW_PARAM_WT_WARP = 22,       /* 位相ワープ 0 = なし、1 = bend、2 = squeeze、3 = sync */
    MDAW_PARAM_WT_WARP_AMOUNT = 23, /* ワープの量 0〜1 */
    MDAW_PARAM_WT_LFO_RATE = 24,   /* WT_POS を揺らす LFO の速さ（Hz、0.01〜30） */
    MDAW_PARAM_WT_LFO_AMOUNT = 25, /* LFO の深さ 0〜1（0 = 揺らさない） */
    MDAW_PARAM_KEY_TRACK = 26,     /* フィルターのキートラッキング 0〜1（ピッチ64 で等倍、半音ごとに 2^(量/12) 倍） */
    MDAW_PARAM_GLIDE_S = 27,       /* グライド（ポルタメント）の時間 0〜0.4 秒（0 = なし） */
    MDAW_PARAM_MONO = 28,          /* 1 = モノフォニック（重なったノートはレガート＋グライドでつなぐ） */
    MDAW_PARAM_LFO_WAVE = 29,      /* LFO の波形 0 = 正弦、1 = 三角、2 = 矩形、3 = のこぎり */
    MDAW_PARAM_LFO_SYNC = 30,      /* 1 = LFO をテンポ同期にする（速さは LFO_DIV、位相は曲位置） */
    MDAW_PARAM_LFO_DIV = 31,       /* テンポ同期の分周 0 = 1小節、1 = 4分、2 = 付点8分、3 = 8分、4 = 16分 */
    MDAW_PARAM_LFO_CUTOFF = 32,    /* LFO でカットオフを揺らす量 0〜1（最大 ±2 オクターブ） */
    MDAW_PARAM_LFO_PITCH = 33,     /* LFO で音程を揺らす量 0〜1（最大 ±2 半音、ビブラート） */
    MDAW_PARAM_COUNT = 34,

    /* シンセの追加（40番台はエフェクトが使っているので、80番台に置く）。
       既定はすべて「効かない」。保存は名前ベース。 */
    MDAW_PARAM_EXT_FIRST = 80,
    MDAW_PARAM_LFO_AMP = 80,       /* LFO で音量を揺らす（トレモロ）0〜1。0 = なし */
    MDAW_PARAM_LFO_RETRIG = 81,    /* 1 = テンポ同期 LFO をノートごとに位相 0 からやり直す */
    MDAW_PARAM_FM = 82,            /* FM の深さ 0〜1。0 = 従来オシレーターのまま */
    MDAW_PARAM_FM_RATIO = 83,      /* モジュレーターの周波数比 0.5〜8 */
    MDAW_PARAM_FORMANT = 84,       /* 固定Hzのフォルマント（母音）の混ぜ 0〜1。0 = なし */
    MDAW_PARAM_FORMANT_VOWEL = 85, /* 0=ア 1=エ 2=イ 3=オ 4=ウ。音程が上がってもHzは動かない */
    MDAW_PARAM_EXT_END = 86,

    /* トラックのエフェクト（mdaw_set_track_param のみ）。
       番号はシンセ側の拡張（〜33）のあとに置く。保存ファイルは名前ベースなので番号変更の影響はない */
    MDAW_FX_FIRST = 40,
    MDAW_FX_LOWCUT_HZ = 40,        /* 20（なし）〜12000 */
    MDAW_FX_SATURATION = 41,       /* 0〜1 */
    MDAW_FX_CHORUS = 42,           /* 0〜1 */
    MDAW_FX_OTT = 43,              /* 3帯域の上下圧縮の深さ 0〜1 */
    MDAW_FX_DELAY = 44,            /* 付点8分ディレイの量 0〜1 */
    MDAW_FX_DELAY_FEEDBACK = 45,   /* 0〜0.9 */
    MDAW_FX_REVERB = 46,           /* 0〜1 */
    MDAW_FX_REVERB_SIZE = 47,      /* 0〜1 */
    MDAW_FX_SIDECHAIN = 48,        /* キックで引っ込む深さ 0〜1 */
    MDAW_FX_SIDECHAIN_RELEASE_S = 49, /* 戻るまでの時間 0.03〜1 */
    MDAW_FX_SIDECHAIN_SOURCE = 50, /* 1 = このトラックの発音で他を引っ込める（キック） */
    MDAW_FX_EQ_LOW_DB = 51,        /* ローシェルフ -18〜+18 dB（0 = なし） */
    MDAW_FX_EQ_LOW_HZ = 52,        /* 40〜400 */
    MDAW_FX_EQ_MID_DB = 53,        /* ピーク -18〜+18 dB */
    MDAW_FX_EQ_MID_HZ = 54,        /* 200〜8000 */
    MDAW_FX_EQ_MID_Q = 55,         /* 0.4〜6 */
    /* 56 は MDAW_PARAM_TRACK_GAIN（オートメーション専用） */
    MDAW_FX_EQ_HIGH_DB = 57,       /* ハイシェルフ -18〜+18 dB */
    MDAW_FX_EQ_HIGH_HZ = 58,       /* 1500〜16000 */
    MDAW_FX_COMP = 59,             /* コンプの混ぜ 0〜1（0 = なし） */
    MDAW_FX_COMP_THRESHOLD_DB = 60,/* -40〜0 */
    MDAW_FX_COMP_RATIO = 61,       /* 1〜20 */
    MDAW_FX_COMP_ATTACK_MS = 62,   /* 0.2〜80 */
    MDAW_FX_COMP_RELEASE_MS = 63,  /* 20〜400 */
    MDAW_FX_COMP_MAKEUP_DB = 64,   /* 0〜18 */
    MDAW_FX_SEND_REVERB = 65,      /* AUX リバーブへのセンド 0〜1 */
    MDAW_FX_SEND_DELAY = 66,       /* AUX ディレイへのセンド 0〜1 */
    MDAW_FX_BITCRUSH = 67,         /* ビットクラッシュ 0〜1（0 = なし） */
    MDAW_FX_STUTTER = 68,          /* テンポ同期スタッター 0〜1（0 = なし） */
    MDAW_FX_STUTTER_DIV = 69,      /* 0=2分 1=4分 2=付点8分 3=8分 4=16分 */
    MDAW_FX_SIDECHAIN_ATTACK_S = 70, /* 引っ込むまでの時間。既定 0.002 で従来と同じ */
    MDAW_FX_SIDECHAIN_HOLD_S = 71,   /* 引っ込んだまま保つ時間。既定 0 */
    MDAW_FX_SIDECHAIN_CURVE = 72,    /* 戻りの形。2 = (1-x)^2 で従来と同じ。小さいほど直線 */
    MDAW_FX_END = 73,

    /* オートメーション専用の対象：トラック音量（ミキサーの gain、0〜2）。
       mdaw_set_track_param では使わず、クリップのオートメーションの対象としてだけ使う */
    MDAW_PARAM_TRACK_GAIN = 56
};

/* 書き出しの状態（mdaw_export_state） */
enum { MDAW_EXPORT_IDLE = 0, MDAW_EXPORT_RUNNING = 1, MDAW_EXPORT_DONE = 2, MDAW_EXPORT_FAILED = 3, MDAW_EXPORT_CANCELLED = 4 };

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
MDAW_API int32_t mdaw_set_project_title(mdaw_engine* engine, const char* title); /* 曲の名前（1〜64バイト） */
/* ドラムキット。kits_dir/<kit_id>/kit.json を読む。kit_id が空（"" か NULL）ならシンセに戻す（Undo できる） */
MDAW_API void mdaw_set_kits_dir(mdaw_engine* engine, const char* kits_dir);
MDAW_API void mdaw_reload_kits(mdaw_engine* engine); /* ダウンロード・削除したあとに呼ぶ */
MDAW_API int32_t mdaw_set_track_kit(mdaw_engine* engine, mdaw_id track_id, const char* kit_id);
MDAW_API const char* mdaw_kit_error(mdaw_engine* engine, const char* kit_id); /* 読めなければ理由、読めれば "" */
/* サンプラー楽器。kit_id が空ならサンプラーをやめる（そのトラックのシンセ／キットの設定に戻る）。
   sound_name は kit.json の音の名前、root_note は基準音程（0〜127）、gain は 0〜2、start は開始位置 0〜1。
   設定一式の差し替えで Undo できる */
MDAW_API int32_t mdaw_set_track_sampler(mdaw_engine* engine, mdaw_id track_id, const char* kit_id, const char* sound_name,
                                        int32_t root_note, float gain, float start);
MDAW_API mdaw_id mdaw_add_track(mdaw_engine* engine, const char* name, uint32_t color_argb);
MDAW_API int32_t mdaw_rename_track(mdaw_engine* engine, mdaw_id track_id, const char* name); /* 1〜64バイト */
/* トラックの音量（0〜2、1 = そのまま）・パン（-1 左〜1 右）・ミュート・ソロ。変わらなければ 0 */
MDAW_API int32_t mdaw_set_track_mixer(mdaw_engine* engine, mdaw_id track_id, float gain, float pan, int32_t mute,
                                      int32_t solo);
/* マスターバス。gain は直線（既定 3.2）、glue は 0〜1、threshold_db / ratio はグルーコンプ、
   soft_clip は 0〜1、ceiling は直線の天井（既定 0.944）。欠けている古い曲は既定＝従来の音 */
MDAW_API int32_t mdaw_set_master(mdaw_engine* engine, float gain, float glue, float threshold_db, float ratio,
                                 float soft_clip, float ceiling);
/* AUX（リバーブとディレイのリターン）。センドが 0 のあいだは音に足さない */
MDAW_API int32_t mdaw_set_aux(mdaw_engine* engine, float reverb_return, float reverb_size, float delay_return,
                              float delay_feedback);
/* 新しいクリップを作って置く。out_placement_id は NULL でもよい */
MDAW_API mdaw_id mdaw_create_clip(mdaw_engine* engine, mdaw_id track_id, int32_t start_bar, int32_t length_bars,
                                  mdaw_id* out_placement_id);
MDAW_API mdaw_id mdaw_place_clip(mdaw_engine* engine, mdaw_id clip_id, int32_t start_bar); /* 複製を置く */
/* クリップを別パターンとして複製する：中身（ノート・オートメーション）を複製した新しいクリップを作って置く
   （Undo できる）。戻り値は新しいクリップの ID、out_placement_id に配置の ID が入る（NULL でもよい）。失敗は 0 */
MDAW_API mdaw_id mdaw_clone_clip(mdaw_engine* engine, mdaw_id clip_id, int32_t start_bar,
                                 mdaw_id* out_placement_id);
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
/* 曲のキー（Undo できる）。root は 0=C … 11=B、scale は保存名（"major" / "minor" / "dorian" など。
   コアはスケール名の中身を解釈せず、そのまま保持して保存する） */
MDAW_API int32_t mdaw_set_key(mdaw_engine* engine, int32_t root, const char* scale);
/* クリップのオートメーション：param_id のレーンを丸ごと差し替える（Undo できる）。
   ticks はクリップ先頭からの相対位置（昇順でなくてもよい。コアが整える）、values はパラメータの実値。
   count が 0 ならレーンを消す。変わらなければ 0 */
MDAW_API int32_t mdaw_set_clip_automation(mdaw_engine* engine, mdaw_id clip_id, int32_t param_id, const int64_t* ticks,
                                          const float* values, int32_t count);
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

/* 書き出し：今の曲を wav（48kHz・24bit・ステレオ）にする。別スレッドで計算し、すぐ戻る。
   track_id が 0 なら曲全体（仕上げのコンプ・リミッターあり）、それ以外はそのトラックだけ（仕上げなし）。
   書き出し中は 0 を返す。進み具合は mdaw_export_progress（0〜1）、終わったかは mdaw_export_state */
MDAW_API int32_t mdaw_export_start(mdaw_engine* engine, const char* path, mdaw_id track_id);
MDAW_API int32_t mdaw_export_state(mdaw_engine* engine);
MDAW_API float mdaw_export_progress(mdaw_engine* engine);
MDAW_API void mdaw_export_cancel(mdaw_engine* engine);
MDAW_API const char* mdaw_export_error(mdaw_engine* engine); /* 状態が FAILED のときの理由 */

#ifdef __cplusplus
}
#endif
