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
}

abstract final class MdawResult {
  static const ok = 0;
  static const noAudioDevice = -1;
  static const openFailed = -2;
  static const startFailed = -3;
  static const fileError = -4;
}

/// 保存・読み込みの失敗
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
  late final _isPlaying = _lib
      .lookupFunction<Int32 Function(_EnginePtr), int Function(_EnginePtr)>('mdaw_transport_is_playing', isLeaf: true);
  late final _position = _lib.lookupFunction<Int64 Function(_EnginePtr), int Function(_EnginePtr)>(
      'mdaw_transport_position_ticks',
      isLeaf: true);

  void play() => _play(_handle);

  /// 止めて曲頭へ戻る
  void stopPlayback() => _stopPlayback(_handle);
  void seek(int tick) => _seek(_handle, tick);
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

  late final _addTrack = _lib.lookupFunction<Uint64 Function(_EnginePtr, Pointer<Utf8>, Uint32),
      int Function(_EnginePtr, Pointer<Utf8>, int)>('mdaw_add_track');
  late final _createClip = _lib.lookupFunction<Uint64 Function(_EnginePtr, Uint64, Int32, Int32, Pointer<Uint64>),
      int Function(_EnginePtr, int, int, int, Pointer<Uint64>)>('mdaw_create_clip');
  late final _placeClip = _lib.lookupFunction<Uint64 Function(_EnginePtr, Uint64, Int32),
      int Function(_EnginePtr, int, int)>('mdaw_place_clip');
  late final _removePlacement = _lib.lookupFunction<Int32 Function(_EnginePtr, Uint64), int Function(_EnginePtr, int)>(
      'mdaw_remove_placement');
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

  /// 音色の確定（Undo できる）。スライダーを動かしている間は [setTrackParamLive]、離した時にこれ
  bool setTrackParam(int trackId, int paramId, double value) => _setTrackParam(_handle, trackId, paramId, value) != 0;
  bool setTrackParamLive(int trackId, int paramId, double value) =>
      _setTrackParamLive(_handle, trackId, paramId, value) != 0;

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
