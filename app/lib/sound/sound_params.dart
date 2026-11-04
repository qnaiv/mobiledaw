// 音色・エフェクトのパラメータ表とプリセット。
// コア（synth.cpp / fx.cpp の kSynthParamSpecs / kFxParamSpecs）と同じ範囲・既定値にそろえる。
import 'dart:math' as math;

import '../engine/mdaw_ffi.dart';
import '../model/project.dart';

enum ParamScale { linear, log, integer, toggle }

class SoundParam {
  const SoundParam(this.id, this.key, this.label, this.min, this.max, this.def,
      {this.scale = ParamScale.linear, this.unit = ''});

  final int id;
  final String key; // 保存ファイルでの名前
  final String label;
  final double min, max, def;
  final ParamScale scale;
  final String unit; // 'Hz', 's', '%', 'st'（半音）, 'ct'（セント）

  bool get isFx => id >= MdawParam.fxLowCutHz;

  double valueOf(TrackData t) => (isFx ? t.fx[key] : t.synth[key]) ?? def;

  /// スライダーの位置（0〜1）と値の変換
  double toUnit(double v) {
    final c = v.clamp(min, max).toDouble();
    if (scale == ParamScale.log) return math.log(c / min) / math.log(max / min);
    return max == min ? 0 : (c - min) / (max - min);
  }

  double fromUnit(double u) {
    final x = u.clamp(0.0, 1.0);
    final v = scale == ParamScale.log ? min * math.pow(max / min, x) : min + (max - min) * x;
    return scale == ParamScale.integer || scale == ParamScale.toggle ? v.roundToDouble() : v.toDouble();
  }

  String format(double v) {
    switch (unit) {
      case 'Hz':
        return v >= 1000 ? '${(v / 1000).toStringAsFixed(1)} kHz' : '${v.round()} Hz';
      case 's':
        return v >= 1 ? '${v.toStringAsFixed(2)} s' : '${(v * 1000).round()} ms';
      case '%':
        return '${(v * 100).round()}%';
      case 'st':
        return '${v.round()} 半音';
      case 'ct':
        return '${v.round()} セント';
      default:
        return scale == ParamScale.integer ? '${v.round()}' : v.toStringAsFixed(2);
    }
  }
}

const synthParams = <SoundParam>[
  SoundParam(MdawParam.wave, 'wave', '波形（のこぎり／矩形）', 0, 1, 0, scale: ParamScale.toggle),
  SoundParam(MdawParam.unison, 'unison', '重ねる本数', 1, 16, 2, scale: ParamScale.integer),
  SoundParam(MdawParam.detuneCents, 'detuneCents', 'ずらし幅（デチューン）', 0, 100, 7, unit: 'ct'),
  SoundParam(MdawParam.width, 'width', '左右の広がり', 0, 1, 0.5, unit: '%'),
  SoundParam(MdawParam.blend, 'blend', '外側の音量（ブレンド）', 0, 1, 0.8, unit: '%'),
  SoundParam(MdawParam.osc, 'osc', 'のこぎり／矩形の音量', 0, 1, 1, unit: '%'),
  SoundParam(MdawParam.sub, 'sub', 'サブ（1オクターブ下のサイン）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.noise, 'noise', 'ノイズ', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.drive, 'drive', '歪み（ドライブ）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.cutoffHz, 'cutoffHz', '明るさ（カットオフ）', 20, 20000, 6000, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.resonance, 'resonance', 'クセ（レゾナンス）', 0.5, 10, 0.9, scale: ParamScale.log),
  SoundParam(MdawParam.filterEnv, 'filterEnv', '鳴らした瞬間に開く量', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.filterEnvDecayS, 'filterEnvDecayS', '閉じるまでの時間', 0.005, 5, 0.3,
      scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.pitchEnv, 'pitchEnv', '音程の落ち込み（キック・ザップ）', 0, 48, 0, unit: 'st'),
  SoundParam(MdawParam.pitchEnvDecayS, 'pitchEnvDecayS', '音程が戻るまでの時間', 0.002, 2, 0.05,
      scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.attackS, 'attackS', 'アタック', 0.0005, 10, 0.005, scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.decayS, 'decayS', 'ディケイ', 0.0005, 10, 0.25, scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.sustain, 'sustain', 'サステイン', 0, 1, 0.7, unit: '%'),
  SoundParam(MdawParam.releaseS, 'releaseS', 'リリース', 0.002, 10, 0.3, scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.masterGain, 'masterGain', '音色の音量', 0, 1, 0.6, unit: '%'),
];

const fxParams = <SoundParam>[
  SoundParam(MdawParam.fxLowCutHz, 'lowCutHz', 'ローカット（低音を削る）', 20, 12000, 20, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.fxSaturation, 'saturation', 'サチュレーション（太く歪ませる）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxChorus, 'chorus', 'コーラス（揺らして広げる）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxOtt, 'ott', 'OTT（派手に・密度を出す）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxDelay, 'delay', 'ディレイ（付点8分）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxDelayFeedback, 'delayFeedback', 'ディレイの繰り返し', 0, 0.9, 0.35, unit: '%'),
  SoundParam(MdawParam.fxReverb, 'reverb', 'リバーブ', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxReverbSize, 'reverbSize', 'リバーブの広さ', 0, 1, 0.6, unit: '%'),
  SoundParam(MdawParam.fxSidechain, 'sidechain', 'パンプ（キックで引っ込む）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxSidechainReleaseS, 'sidechainReleaseS', 'パンプの戻り', 0.03, 1, 0.25,
      scale: ParamScale.log, unit: 's'),
  SoundParam(MdawParam.fxSidechainSource, 'sidechainSource', 'このトラックをキックにする（他を引っ込める）', 0, 1, 0,
      scale: ParamScale.toggle),
];

final allSoundParams = [...synthParams, ...fxParams];
final _byKey = {for (final p in allSoundParams) p.key: p};

/// 大きいつまみ。1本で複数のパラメータを動かす
class SoundMacro {
  const SoundMacro(this.label, this.hint, this.read, this.write);

  final String label;
  final String hint;
  final double Function(TrackData t) read; // 今の値 → 0〜1
  final Map<int, double> Function(double u) write; // 0〜1 → 変える値

  static double _p(TrackData t, String key) => _byKey[key]!.valueOf(t);
}

final soundMacros = <SoundMacro>[
  SoundMacro('明るさ', 'フィルターを開く', (t) => math.log(SoundMacro._p(t, 'cutoffHz').clamp(200, 16000) / 200) / math.log(80),
      (u) => {MdawParam.cutoffHz: 200 * math.pow(80, u).toDouble()}),
  SoundMacro('厚み', '重ねる本数とずらし幅', (t) => (SoundMacro._p(t, 'unison') - 1) / 15,
      (u) => {MdawParam.unison: (1 + 15 * u).roundToDouble(), MdawParam.detuneCents: 5 + 45 * u}),
  SoundMacro('広がり', '左右の広がりとコーラス', (t) => SoundMacro._p(t, 'width'),
      (u) => {MdawParam.width: u, MdawParam.fxChorus: 0.5 * u}),
  SoundMacro('余韻', 'リリースとリバーブ', (t) => (SoundMacro._p(t, 'reverb') / 0.6).clamp(0.0, 1.0),
      (u) => {MdawParam.releaseS: 0.02 * math.pow(100, u).toDouble(), MdawParam.fxReverb: 0.6 * u}),
  SoundMacro('パンプ', 'キックに合わせて引っ込む', (t) => SoundMacro._p(t, 'sidechain'),
      (u) => {MdawParam.fxSidechain: u}),
];

class SoundPreset {
  const SoundPreset(this.name, this.category, this.values);

  final String name;
  final String category; // 'コード' 'ベース' 'リード' 'ドラム' 'FX'
  final Map<String, double> values; // 書いていない項目は既定値

  /// プリセットを当てるときに送る値（すべての項目。書いていないものは既定値に戻す）
  Map<int, double> get allValues => {for (final p in allSoundParams) p.id: values[p.key] ?? p.def};
}

// tools/demos/future_bass.py の音色と同じもの＋よく使う形
const soundPresets = <SoundPreset>[
  SoundPreset('Future Bass Chords', 'コード', {
    'cutoffHz': 12000, 'resonance': 0.8, 'attackS': 0.004, 'decayS': 0.6, 'sustain': 0.75, 'releaseS': 0.22,
    'detuneCents': 42, 'masterGain': 0.55, 'unison': 9, 'width': 0.95, 'blend': 0.75, 'noise': 0.03,
    'drive': 0.15, 'filterEnv': 0.25, 'filterEnvDecayS': 0.25,
    'lowCutHz': 180, 'saturation': 0.15, 'chorus': 0.35, 'ott': 0.55, 'reverb': 0.3, 'reverbSize': 0.7,
    'sidechain': 0.9, 'sidechainReleaseS': 0.32,
  }),
  SoundPreset('Supersaw Pad', 'コード', {
    'cutoffHz': 4500, 'attackS': 0.35, 'decayS': 1.0, 'sustain': 0.85, 'releaseS': 1.2, 'detuneCents': 35,
    'masterGain': 0.5, 'unison': 7, 'width': 1.0, 'blend': 0.8, 'noise': 0.05,
    'lowCutHz': 200, 'chorus': 0.5, 'ott': 0.3, 'reverb': 0.65, 'reverbSize': 0.85, 'sidechain': 0.6,
    'sidechainReleaseS': 0.35,
  }),
  SoundPreset('Pluck', 'リード', {
    'cutoffHz': 500, 'resonance': 1.2, 'attackS': 0.001, 'decayS': 0.22, 'sustain': 0, 'releaseS': 0.18,
    'detuneCents': 18, 'masterGain': 0.7, 'unison': 3, 'width': 0.6, 'blend': 0.7, 'filterEnv': 0.62,
    'filterEnvDecayS': 0.12,
    'lowCutHz': 250, 'chorus': 0.2, 'ott': 0.4, 'delay': 0.35, 'delayFeedback': 0.4, 'reverb': 0.35,
    'sidechain': 0.5,
  }),
  SoundPreset('Square Lead', 'リード', {
    'cutoffHz': 6000, 'resonance': 1.0, 'attackS': 0.004, 'decayS': 0.3, 'sustain': 0.6, 'releaseS': 0.15,
    'detuneCents': 16, 'masterGain': 0.6, 'unison': 4, 'width': 0.45, 'blend': 0.7, 'filterEnv': 0.2,
    'filterEnvDecayS': 0.15, 'wave': 1,
    'lowCutHz': 300, 'saturation': 0.2, 'ott': 0.35, 'delay': 0.3, 'reverb': 0.3, 'sidechain': 0.45,
  }),
  SoundPreset('Supersaw Lead', 'リード', {
    'cutoffHz': 9000, 'attackS': 0.003, 'decayS': 0.4, 'sustain': 0.8, 'releaseS': 0.2, 'detuneCents': 30,
    'masterGain': 0.55, 'unison': 7, 'width': 0.7, 'blend': 0.6, 'drive': 0.2,
    'lowCutHz': 250, 'ott': 0.5, 'delay': 0.25, 'reverb': 0.3, 'sidechain': 0.4,
  }),
  SoundPreset('Sub Bass', 'ベース', {
    'cutoffHz': 420, 'resonance': 0.9, 'attackS': 0.003, 'decayS': 0.3, 'sustain': 0.85, 'releaseS': 0.06,
    'detuneCents': 10, 'masterGain': 0.8, 'unison': 2, 'width': 0, 'blend': 1, 'sub': 0.7, 'drive': 0.3,
    'filterEnv': 0.15, 'filterEnvDecayS': 0.1, 'osc': 0.8,
    'saturation': 0.25, 'sidechain': 0.85, 'sidechainReleaseS': 0.28,
  }),
  SoundPreset('Growl Bass', 'ベース', {
    'cutoffHz': 900, 'resonance': 3.5, 'attackS': 0.002, 'decayS': 0.4, 'sustain': 0.8, 'releaseS': 0.08,
    'detuneCents': 20, 'masterGain': 0.7, 'unison': 4, 'width': 0.3, 'sub': 0.5, 'drive': 0.7,
    'filterEnv': 0.4, 'filterEnvDecayS': 0.18, 'wave': 1,
    'saturation': 0.6, 'ott': 0.7, 'sidechain': 0.7,
  }),
  SoundPreset('Kick', 'ドラム', {
    'cutoffHz': 40, 'resonance': 0.7, 'attackS': 0.0005, 'decayS': 0.32, 'sustain': 0, 'releaseS': 0.05,
    'detuneCents': 0, 'masterGain': 1.0, 'unison': 1, 'width': 0, 'sub': 1.0, 'filterEnv': 0.8,
    'filterEnvDecayS': 0.025, 'pitchEnv': 30, 'pitchEnvDecayS': 0.035, 'osc': 0.5,
    'saturation': 0.35, 'sidechainSource': 1,
  }),
  SoundPreset('Snare', 'ドラム', {
    'cutoffHz': 1600, 'resonance': 0.9, 'attackS': 0.0005, 'decayS': 0.17, 'sustain': 0, 'releaseS': 0.08,
    'detuneCents': 0, 'masterGain': 1.0, 'unison': 1, 'noise': 1.0, 'filterEnv': 0.55, 'filterEnvDecayS': 0.06,
    'pitchEnv': 12, 'pitchEnvDecayS': 0.02, 'wave': 1, 'osc': 0.35,
    'lowCutHz': 160, 'saturation': 0.55, 'reverb': 0.35, 'reverbSize': 0.5,
  }),
  SoundPreset('Hi-hat', 'ドラム', {
    'cutoffHz': 16000, 'resonance': 0.7, 'attackS': 0.0005, 'decayS': 0.045, 'sustain': 0, 'releaseS': 0.03,
    'unison': 1, 'noise': 1.0, 'osc': 0, 'masterGain': 1.0,
    'lowCutHz': 6000, 'reverb': 0.12, 'reverbSize': 0.3, 'sidechain': 0.3, 'sidechainReleaseS': 0.15,
  }),
  SoundPreset('Noise Riser', 'FX', {
    'cutoffHz': 5000, 'resonance': 1.5, 'attackS': 3.0, 'decayS': 1.0, 'sustain': 1.0, 'releaseS': 0.4,
    'unison': 1, 'noise': 1.0, 'osc': 0, 'masterGain': 0.6,
    'lowCutHz': 400, 'reverb': 0.5, 'reverbSize': 0.8,
  }),
  SoundPreset('Basic Saw', 'その他', {}),
];
