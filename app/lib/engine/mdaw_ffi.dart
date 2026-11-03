// libmdaw.so（core/）の C API を dart:ffi で呼ぶ薄いラッパー。
// 定数は core/include/mdaw.h と揃えること。
import 'dart:ffi';
import 'dart:io';

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
      : _create = lib.lookupFunction<_EnginePtr Function(), _EnginePtr Function()>('mdaw_create'),
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

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_handle);
  }
}
