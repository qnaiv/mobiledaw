// libmdaw.so（core/）の C API を dart:ffi で呼ぶ薄いラッパー。
// 定数は core/include/mdaw.h と揃えること。
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../model/project.dart';

final class _MdawEngine extends Opaque {}

typedef _EnginePtr = Pointer<_MdawEngine>;

abstract final class MdawParam {
  static const cutoffHz = 0;
  static const resonance = 1;
  static const attackS = 2;
  static const decayS = 3;
  static const sustain = 4;
  static const releaseS = 5;
  static const detuneCents = 6;
  static const masterGain = 7;
  static const unison = 8;
  static const width = 9;
  static const blend = 10;
  static const sub = 11;
  static const noise = 12;
  static const drive = 13;
  static const filterEnv = 14;
  static const filterEnvDecayS = 15;
  static const pitchEnv = 16;
  static const pitchEnvDecayS = 17;
  static const wave = 18;
  static const osc = 19;
  static const wtTable = 20;
  static const wtPos = 21;
  static const wtWarp = 22;
  static const wtWarpAmount = 23;
  static const wtLfoRate = 24;
  static const wtLfoAmount = 25;

  // トラックのエフェクト（setTrackParam で同じように変えられる）
  static const fxLowCutHz = 32;
  static const fxSaturation = 33;
  static const fxChorus = 34;
  static const fxOtt = 35;
  static const fxDelay = 36;
  static const fxDelayFeedback = 37;
  static const fxReverb = 38;
  static const fxReverbSize = 39;
  static const fxSidechain = 40;
  static const fxSidechainReleaseS = 41;
  static const fxSidechainSource = 42;

  // オートメーション専用の対象：トラック音量（ミキサーの gain、0〜2）。setTrackParam では使わない
  static const trackGain = 48;
}

abstract final class MdawResult {
  static const ok = 0;
  static const noAudioDevice = -1;
  static const openFailed = -2;
  static const startFailed = -3;
  static const fileError = -4;
}

/// 保存・読み込みの失敗
/// mdaw.h の MDAW_EXPORT_* と同じ並び
enum ExportState { idle, running, done, failed, cancelled }

class MdawFileException implements Exception {
  const MdawFileException(this.message);
  final String message;

  @override
  String toString() => 'MdawFileException: $message';
}

class EngineStatus {
  const EngineStatus({
    required this.sampleRate,
    required this.framesPerBurst,
    required this.bufferSizeFrames,
    required this.outputLatencyMs,
    required this.xruns,
    required this.activeVoices,
  });

  final int sampleRate;
  final int framesPerBurst;
  final int bufferSizeFrames;
  final double outputLatencyMs;
  final int xruns;
  final int activeVoices;

  /// バッファ1周分の長さ（ミリ秒）
  double get bufferMs => sampleRate > 0 ? bufferSizeFrames * 1000 / sampleRate : 0;
}

class MdawEngine {
  MdawEngine._(DynamicLibrary lib)
      : _lib = lib,
        _create = lib.lookupFunction<_EnginePtr Function(), _EnginePtr Function()>('mdaw_create'),
        _destroy = lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_destroy'),
        _start = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_start'),
        _stop = lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_stop'),
        _noteOn = lib.lookupFunction<Int32 Function(_EnginePtr, Int32, Float), int Function(_EnginePtr, int, double)>(
            'mdaw_note_on',
            isLeaf: true),
        _noteOff = lib.lookupFunction<Int32 Function(_EnginePtr, Int32), int Function(_EnginePtr, int)>('mdaw_note_off',
            isLeaf: true),
        _allNotesOff = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_all_notes_off',
            isLeaf: true),
        _setParam = lib.lookupFunction<Int32 Function(_EnginePtr, Int32, Float), int Function(_EnginePtr, int, double)>(
            'mdaw_set_param',
            isLeaf: true),
        _sampleRate = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_sample_rate'),
        _framesPerBurst = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_frames_per_burst'),
        _bufferSize = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_buffer_size_frames'),
        _latency = lib.lookupFunction<Double Function(_EnginePtr), double Function(_EnginePtr)>('mdaw_output_latency_ms'),
        _xruns = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_xrun_count'),
        _activeVoices = lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_active_voices',
            isLeaf: true) {
    _handle = _create();
  }

  /// Android 上では MainActivity が読み込み済みの libmdaw.so を開く。
  factory MdawEngine.open() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('mdaw は今のところ Android 専用です');
    }
    return MdawEngine._(DynamicLibrary.open('libmdaw.so'));
  }

  final DynamicLibrary _lib;
  late final _EnginePtr _handle;
  bool _disposed = false;

  final _EnginePtr Function() _create;
  final void Function(_EnginePtr) _destroy;
  final int Function(_EnginePtr) _start;
  final void Function(_EnginePtr) _stop;
  final int Function(_EnginePtr, int, double) _noteOn;
  final int Function(_EnginePtr, int) _noteOff;
  final int Function(_EnginePtr) _allNotesOff;
  final int Function(_EnginePtr, int, double) _setParam;
  final int Function(_EnginePtr) _sampleRate;
  final int Function(_EnginePtr) _framesPerBurst;
  final int Function(_EnginePtr) _bufferSize;
  final double Function(_EnginePtr) _latency;
  final int Function(_EnginePtr) _xruns;
  final int Function(_EnginePtr) _activeVoices;

  int start() => _start(_handle);
  void stop() => _stop(_handle);

  void noteOn(int note, double velocity) => _noteOn(_handle, note, velocity);
  void noteOff(int note) => _noteOff(_handle, note);
  void allNotesOff() => _allNotesOff(_handle);
  void setParam(int id, double value) => _setParam(_handle, id, value);

  EngineStatus status() => EngineStatus(
        sampleRate: _sampleRate(_handle),
        framesPerBurst: _framesPerBurst(_handle),
        bufferSizeFrames: _bufferSize(_handle),
        outputLatencyMs: _latency(_handle),
        xruns: _xruns(_handle),
        activeVoices: _activeVoices(_handle),
      );

  // ---- 再生操作 ----------------------------------------------------------

  late final _play = _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_transport_play',
      isLeaf: true);
  late final _stopPlayback = _lib
      .lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_transport_stop', isLeaf: true);
  late final _seek = _lib.lookupFunction<Int32 Function(_EnginePtr, Int64), int Function(_EnginePtr, int)>(
      'mdaw_transport_seek',
      isLeaf: true);
  late final _setLoop = _lib.lookupFunction<Int32 Function(_EnginePtr, Int64, Int64), int Function(_EnginePtr, int, int)>(
      'mdaw_transport_set_loop',
      isLeaf: true);
  late final _isPlaying = _lib
      .lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_transport_is_playing', isLeaf: true);
  late final _position = _lib.lookupFunction<Int64 Function(_EnginePtr), int Function(_EnginePtr)>(
      'mdaw_transport_position_ticks',
      isLeaf: true);

  void play() => _play(_handle);

  /// 止めて曲頭へ戻る
  void stopPlayback() => _stopPlayback(_handle);
  void seek(int tick) => _seek(_handle, tick);

  /// ループする範囲を [start, end) の tick に絞る（ピアノロールでクリップだけを繰り返す）
  void setLoop(int start, int end) => _setLoop(_handle, start, end);

  /// 曲全体のループに戻す
  void clearLoop() => _setLoop(_handle, 0, 0);
  bool get isPlaying => _isPlaying(_handle) != 0;

  /// 再生位置（tick）。画面のフレームごとに読んでよい
  int get positionTicks => _position(_handle);

  // ---- プロジェクト --------------------------------------------------------

  late final _projectNew =
      _lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_project_new');
  late final _projectLoad = _lib.lookupFunction<Int32 Function(_EnginePtr, Pointer<Utf8>),
      int Function(_EnginePtr, Pointer<Utf8>)>('mdaw_project_load');
  late final _projectSave = _lib.lookupFunction<Int32 Function(_EnginePtr, Pointer<Utf8>),
      int Function(_EnginePtr, Pointer<Utf8>)>('mdaw_project_save');
  late final _projectJson = _lib.lookupFunction<Pointer<Utf8> Function(_EnginePtr), Pointer<Utf8> Function(_EnginePtr)>(
      'mdaw_project_json');
  late final _lastError = _lib.lookupFunction<Pointer<Utf8> Function(_EnginePtr), Pointer<Utf8> Function(_EnginePtr)>(
      'mdaw_last_error');
  late final _projectVersion = _lib
      .lookupFunction<Uint64 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_project_version', isLeaf: true);
  late final _isDirty = _lib
      .lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_project_is_dirty', isLeaf: true);

  late final _setProjectTitle = _lib.lookupFunction<Int32 Function(_EnginePtr, Pointer<Utf8>),
      int Function(_EnginePtr, Pointer<Utf8>)>('mdaw_set_project_title');
  late final _setKitsDir =
      _lib.lookupFunction<Void Function(_EnginePtr, Pointer<Utf8>), void Function(_EnginePtr, Pointer<Utf8>)>('mdaw_set_kits_dir');
  late final _reloadKits =
      _lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_reload_kits');
  late final _setTrackKit = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Pointer<Utf8>),
      int Function(_EnginePtr, int, Pointer<Utf8>)>('mdaw_set_track_kit');
  late final _setTrackSampler = _lib.lookupFunction<
      Int32 Function(_EnginePtr, Uint64, Pointer<Utf8>, Pointer<Utf8>, Int32, Float, Float),
      int Function(_EnginePtr, int, Pointer<Utf8>, Pointer<Utf8>, int, double, double)>('mdaw_set_track_sampler');
  late final _kitError = _lib.lookupFunction<Pointer<Utf8> Function(_EnginePtr, Pointer<Utf8>),
      Pointer<Utf8> Function(_EnginePtr, Pointer<Utf8>)>('mdaw_kit_error');
  late final _exportStart = _lib.lookupFunction<Int32 Function(_EnginePtr, Pointer<Utf8>, Uint64),
      int Function(_EnginePtr, Pointer<Utf8>, int)>('mdaw_export_start');
  late final _exportState =
      _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_export_state', isLeaf: true);
  late final _exportProgress = _lib
      .lookupFunction<Float Function(_EnginePtr), double Function(_EnginePtr)>('mdaw_export_progress', isLeaf: true);
  late final _exportCancel =
      _lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_export_cancel', isLeaf: true);
  late final _exportError = _lib.lookupFunction<Pointer<Utf8> Function(_EnginePtr),
      Pointer<Utf8> Function(_EnginePtr)>('mdaw_export_error');
  late final _addTrack = _lib.lookupFunction<Uint64 Function(_EnginePtr, Pointer<Utf8>, Uint32),
      int Function(_EnginePtr, Pointer<Utf8>, int)>('mdaw_add_track');
  late final _renameTrack = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Pointer<Utf8>),
      int Function(_EnginePtr, int, Pointer<Utf8>)>('mdaw_rename_track');
  late final _setTrackMixer = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Float, Float, Int32, Int32),
      int Function(_EnginePtr, int, double, double, int, int)>('mdaw_set_track_mixer');
  late final _createClip = _lib.lookupFunction<Uint64 Function(_EnginePtr, Uint64, Int32, Int32, Pointer<Uint64>),
      int Function(_EnginePtr, int, int, int, Pointer<Uint64>)>('mdaw_create_clip');
  late final _placeClip = _lib.lookupFunction<Uint64 Function(_EnginePtr, Uint64, Int32),
      int Function(_EnginePtr, int, int)>('mdaw_place_clip');
  late final _removePlacement = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64), int Function(_EnginePtr, int)>(
      'mdaw_remove_placement');
  late final _setClipLength = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Int32),
      int Function(_EnginePtr, int, int)>('mdaw_set_clip_length');
  late final _movePlacement = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Int32),
      int Function(_EnginePtr, int, int)>('mdaw_move_placement');
  late final _addNote = _lib.lookupFunction<Uint64 Function(_EnginePtr, Uint64, Int64, Int64, Int32, Float),
      int Function(_EnginePtr, int, int, int, int, double)>('mdaw_add_note');
  late final _deleteNotes = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Pointer<Uint64>, Int32),
      int Function(_EnginePtr, int, Pointer<Uint64>, int)>('mdaw_delete_notes');
  late final _moveNotes = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Pointer<Uint64>, Int32, Int64, Int32),
      int Function(_EnginePtr, int, Pointer<Uint64>, int, int, int)>('mdaw_move_notes');
  late final _resizeNotes = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Pointer<Uint64>, Int32, Int64),
      int Function(_EnginePtr, int, Pointer<Uint64>, int, int)>('mdaw_resize_notes');
  late final _setTempo = _lib
      .lookupFunction<Int32 Function(_EnginePtr, Double), int Function(_EnginePtr, double)>('mdaw_set_tempo');
  late final _setKey = _lib.lookupFunction<Int32 Function(_EnginePtr, Int32, Pointer<Utf8>),
      int Function(_EnginePtr, int, Pointer<Utf8>)>('mdaw_set_key');
  late final _setClipAutomation = _lib.lookupFunction<
      Int32 Function(_EnginePtr, Uint64, Int32, Pointer<Int64>, Pointer<Float>, Int32),
      int Function(_EnginePtr, int, int, Pointer<Int64>, Pointer<Float>, int)>('mdaw_set_clip_automation');
  late final _setTrackParam = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Int32, Float),
      int Function(_EnginePtr, int, int, double)>('mdaw_set_track_param');
  late final _setTrackParamLive = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64, Int32, Float),
      int Function(_EnginePtr, int, int, double)>('mdaw_set_track_param_live', isLeaf: true);
  late final _beginGroup =
      _lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_begin_edit_group');
  late final _endGroup =
      _lib.lookupFunction<Void Function(_EnginePtr), void Function(_EnginePtr)>('mdaw_end_edit_group');
  late final _undo = _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_undo');
  late final _redo = _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_redo');
  late final _canUndo =
      _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_can_undo', isLeaf: true);
  late final _canRedo =
      _lib.lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_can_redo', isLeaf: true);
  late final _previewTrack = _lib
      .lookupFunction<Void Function(_EnginePtr, Uint64), void Function(_EnginePtr, int)>('mdaw_preview_track');

  void newProject() => _projectNew(_handle);

  /// 読めなければ [MdawFileException]。そのときプロジェクトは変わらない
  void loadProject(String path) => _withPath(path, _projectLoad);
  void saveProject(String path) => _withPath(path, _projectSave);

  void _withPath(String path, int Function(_EnginePtr, Pointer<Utf8>) call) {
    final p = path.toNativeUtf8();
    try {
      if (call(_handle, p) != MdawResult.ok) {
        throw MdawFileException(_lastError(_handle).toDartString());
      }
    } finally {
      malloc.free(p);
    }
  }

  /// 中身が変わるたびに増える番号。これが変わったら [project] を読み直す
  int get projectVersion => _projectVersion(_handle);
  bool get isDirty => _isDirty(_handle) != 0;

  /// 今のプロジェクトの中身（呼ぶたびに作り直すので、projectVersion が変わったときだけ読む）
  ProjectData get project => ProjectData.parse(_projectJson(_handle).toDartString());

  // 編集。ID を返すものは失敗すると 0、bool を返すものは適用できたら true。

  int addTrack(String name, int colorArgb) {
    final p = name.toNativeUtf8();
    try {
      return _addTrack(_handle, p, colorArgb);
    } finally {
      malloc.free(p);
    }
  }

  /// 曲の名前（Undo できる）。空・長すぎ・同じなら false
  bool setProjectTitle(String title) {
    final p = title.toNativeUtf8();
    try {
      return _setProjectTitle(_handle, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  /// ドラムキットを探す場所（filesDir/kits）
  void setKitsDir(String dir) {
    final p = dir.toNativeUtf8();
    try {
      _setKitsDir(_handle, p);
    } finally {
      malloc.free(p);
    }
  }

  /// キットをダウンロード・削除したあとに呼ぶ（読み直して鳴らし直す）
  void reloadKits() => _reloadKits(_handle);

  /// トラックの音源をキットにする（空ならシンセに戻す）。Undo できる
  bool setTrackKit(int trackId, String kitId) {
    final p = kitId.toNativeUtf8();
    try {
      return _setTrackKit(_handle, trackId, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  /// トラックの楽器をサンプラーにする（kitId が空ならサンプラーをやめる）。Undo できる
  bool setTrackSampler(int trackId, String kitId, String soundName, int rootNote, double gain, double start) {
    final pk = kitId.toNativeUtf8();
    final ps = soundName.toNativeUtf8();
    try {
      return _setTrackSampler(_handle, trackId, pk, ps, rootNote, gain, start) != 0;
    } finally {
      malloc.free(pk);
      malloc.free(ps);
    }
  }

  /// キットが読めなければ理由、読めれば ''
  String kitError(String kitId) {
    final p = kitId.toNativeUtf8();
    try {
      return _kitError(_handle, p).toDartString();
    } finally {
      malloc.free(p);
    }
  }

  /// 書き出しを始める（別スレッド）。[trackId] が 0 なら曲全体、それ以外はそのトラックだけ
  bool exportStart(String path, {int trackId = 0}) {
    final p = path.toNativeUtf8();
    try {
      return _exportStart(_handle, p, trackId) != 0;
    } finally {
      malloc.free(p);
    }
  }

  ExportState get exportState => ExportState.values[_exportState(_handle).clamp(0, ExportState.values.length - 1)];
  double get exportProgress => _exportProgress(_handle);
  void exportCancel() => _exportCancel(_handle);
  String get exportError => _exportError(_handle).toDartString();

  bool renameTrack(int trackId, String name) {
    final p = name.toNativeUtf8();
    try {
      return _renameTrack(_handle, trackId, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  /// 音量（0〜2）・パン（-1〜1）・ミュート・ソロ。変わらなければ false
  bool setTrackMixer(int trackId, {required double gain, required double pan, required bool mute, required bool solo}) =>
      _setTrackMixer(_handle, trackId, gain, pan, mute ? 1 : 0, solo ? 1 : 0) != 0;

  /// 新しいクリップを作って置く。戻り値は (clipId, placementId)
  (int, int) createClip(int trackId, int startBar, {int lengthBars = 1}) {
    final out = calloc<Uint64>();
    try {
      final clip = _createClip(_handle, trackId, startBar, lengthBars, out);
      return (clip, out.value);
    } finally {
      calloc.free(out);
    }
  }

  /// 同じクリップをもう一つ置く（複製）。戻り値は placementId
  int placeClip(int clipId, int startBar) => _placeClip(_handle, clipId, startBar);
  bool removePlacement(int placementId) => _removePlacement(_handle, placementId) != 0;
  /// クリップの長さ（小節）。複製もすべて同じ長さに。縮めてはみ出したノートは消える
  bool setClipLength(int clipId, int lengthBars) => _setClipLength(_handle, clipId, lengthBars) != 0;
  bool movePlacement(int placementId, int newStartBar) => _movePlacement(_handle, placementId, newStartBar) != 0;

  int addNote(int clipId, {required int tick, required int length, required int pitch, double velocity = 0.8}) =>
      _addNote(_handle, clipId, tick, length, pitch, velocity);

  bool deleteNotes(int clipId, List<int> noteIds) =>
      _withIds(noteIds, (p, n) => _deleteNotes(_handle, clipId, p, n));

  bool moveNotes(int clipId, List<int> noteIds, {int deltaTicks = 0, int deltaPitch = 0}) =>
      _withIds(noteIds, (p, n) => _moveNotes(_handle, clipId, p, n, deltaTicks, deltaPitch));

  bool resizeNotes(int clipId, List<int> noteIds, int deltaTicks) =>
      _withIds(noteIds, (p, n) => _resizeNotes(_handle, clipId, p, n, deltaTicks));

  bool _withIds(List<int> ids, int Function(Pointer<Uint64>, int) call) {
    if (ids.isEmpty) return false;
    final p = calloc<Uint64>(ids.length);
    try {
      for (var i = 0; i < ids.length; i++) {
        p[i] = ids[i];
      }
      return call(p, ids.length) != 0;
    } finally {
      calloc.free(p);
    }
  }

  bool setTempo(double bpm) => _setTempo(_handle, bpm) != 0;

  /// 曲のキー（Undo できる）。[scale] は保存名（"major" / "dorian" など）。同じ・不正なら false
  bool setKey(int root, String scale) {
    final p = scale.toNativeUtf8();
    try {
      return _setKey(_handle, root, p) != 0;
    } finally {
      malloc.free(p);
    }
  }

  /// クリップのオートメーション：[paramId] のレーンを丸ごと差し替える（Undo できる）。
  /// [points] は (tick, 値) の組（tick はクリップ先頭から）。空ならレーンを消す。変わらなければ false
  bool setClipAutomation(int clipId, int paramId, List<(int, double)> points) {
    final ticks = calloc<Int64>(points.length);
    final values = calloc<Float>(points.length);
    try {
      for (var i = 0; i < points.length; i++) {
        ticks[i] = points[i].$1;
        values[i] = points[i].$2;
      }
      return _setClipAutomation(_handle, clipId, paramId, ticks, values, points.length) != 0;
    } finally {
      calloc.free(ticks);
      calloc.free(values);
    }
  }

  /// 音色の確定（Undo できる）。スライダーを動かしている間は [setTrackParamLive]、離した時にこれ
  bool setTrackParam(int trackId, int paramId, double value) => _setTrackParam(_handle, trackId, paramId, value) != 0;
  bool setTrackParamLive(int trackId, int paramId, double value) =>
      _setTrackParamLive(_handle, trackId, paramId, value) != 0;

  /// スライダーのように始まりと終わりが別のイベントになる操作用。必ず [endEditGroup] と対で
  void beginEditGroup() => _beginGroup(_handle);
  void endEditGroup() => _endGroup(_handle);

  /// [edits] の中の編集を1つの Undo にまとめる（1ジェスチャー＝1 Undo）
  T editGroup<T>(T Function() edits) {
    _beginGroup(_handle);
    try {
      return edits();
    } finally {
      _endGroup(_handle);
    }
  }

  bool undo() => _undo(_handle) != 0;
  bool redo() => _redo(_handle) != 0;
  bool get canUndo => _canUndo(_handle) != 0;
  bool get canRedo => _canRedo(_handle) != 0;

  /// 試聴鍵盤（[noteOn]）をそのトラックの音色で鳴らす
  void previewTrack(int trackId) => _previewTrack(_handle, trackId);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
  }
}
