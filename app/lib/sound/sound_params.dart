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
      case 'dB':
        return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB';
      case 'ms':
        return '${v >= 10 ? v.round() : v.toStringAsFixed(1)} ms';
      default:
        return scale == ParamScale.integer ? '${v.round()}' : v.toStringAsFixed(2);
    }
  }
}

const synthParams = <SoundParam>[
  SoundParam(MdawParam.wave, 'wave', '波形（のこぎり／矩形）', 0, 1, 0, scale: ParamScale.toggle),
  SoundParam(MdawParam.wtTable, 'wtTable', 'ウェーブテーブル（0=従来、1=基本、2=倍音、3=フォルマント、4=デジタル、5=スペクトルソー、6=パルス、7=クワイア）', 0, 7, 0,
      scale: ParamScale.integer),
  SoundParam(MdawParam.wtPos, 'wtPos', 'テーブルの位置', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.wtWarp, 'wtWarp', 'ワープ（0=なし、1=曲げる、2=絞る、3=シンク）', 0, 3, 0, scale: ParamScale.integer),
  SoundParam(MdawParam.wtWarpAmount, 'wtWarpAmount', 'ワープの量', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.wtLfoRate, 'wtLfoRate', '揺らし速さ（LFO）', 0.01, 30, 1, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.wtLfoAmount, 'wtLfoAmount', '揺らし量（LFO）', 0, 1, 0, unit: '%'),
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
  SoundParam(MdawParam.keyTrack, 'keyTrack', 'キートラッキング（音程にカットオフが連動）', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.glideS, 'glideS', 'グライド（音程の滑り）', 0, 0.4, 0, unit: 's'),
  SoundParam(MdawParam.mono, 'mono', 'モノ（単音でレガートにつなぐ）', 0, 1, 0, scale: ParamScale.toggle),
  SoundParam(MdawParam.lfoWave, 'lfoWave', 'LFOの波形（0=正弦、1=三角、2=矩形、3=のこぎり）', 0, 3, 0,
      scale: ParamScale.integer),
  SoundParam(MdawParam.lfoSync, 'lfoSync', 'LFOをテンポに合わせる', 0, 1, 0, scale: ParamScale.toggle),
  SoundParam(MdawParam.lfoDiv, 'lfoDiv', 'LFOの周期（同期時：0=1小節、1=4分、2=付点8分、3=8分、4=16分）', 0, 4, 1,
      scale: ParamScale.integer),
  SoundParam(MdawParam.lfoCutoff, 'lfoCutoff', 'LFOで明るさを揺らす量', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.lfoPitch, 'lfoPitch', 'LFOで音程を揺らす量（ビブラート）', 0, 1, 0, unit: '%'),
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
  SoundParam(MdawParam.fxEqLowDb, 'eqLowDb', 'EQ 低音', -18, 18, 0, unit: 'dB'),
  SoundParam(MdawParam.fxEqLowHz, 'eqLowHz', 'EQ 低音の周波数', 40, 400, 120, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.fxEqMidDb, 'eqMidDb', 'EQ 中音', -18, 18, 0, unit: 'dB'),
  SoundParam(MdawParam.fxEqMidHz, 'eqMidHz', 'EQ 中音の周波数', 200, 8000, 1000, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.fxEqMidQ, 'eqMidQ', 'EQ 中音の狭さ', 0.4, 6, 1, scale: ParamScale.log),
  SoundParam(MdawParam.fxEqHighDb, 'eqHighDb', 'EQ 高音', -18, 18, 0, unit: 'dB'),
  SoundParam(MdawParam.fxEqHighHz, 'eqHighHz', 'EQ 高音の周波数', 1500, 16000, 8000, scale: ParamScale.log, unit: 'Hz'),
  SoundParam(MdawParam.fxComp, 'comp', 'コンプレッサー', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxCompThresholdDb, 'compThresholdDb', 'コンプのしきい値', -40, 0, -18, unit: 'dB'),
  SoundParam(MdawParam.fxCompRatio, 'compRatio', 'コンプの比', 1, 20, 4, scale: ParamScale.log),
  SoundParam(MdawParam.fxCompAttackMs, 'compAttackMs', 'コンプのアタック', 0.2, 80, 10, scale: ParamScale.log, unit: 'ms'),
  SoundParam(MdawParam.fxCompReleaseMs, 'compReleaseMs', 'コンプのリリース', 20, 400, 120, scale: ParamScale.log, unit: 'ms'),
  SoundParam(MdawParam.fxCompMakeupDb, 'compMakeupDb', 'コンプのメイクアップ', 0, 18, 0, unit: 'dB'),
  SoundParam(MdawParam.fxSendReverb, 'sendReverb', 'センド リバーブ', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxSendDelay, 'sendDelay', 'センド ディレイ', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxBitcrush, 'bitcrush', 'ビットクラッシュ', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxStutter, 'stutter', 'スタッター', 0, 1, 0, unit: '%'),
  SoundParam(MdawParam.fxStutterDiv, 'stutterDiv', 'スタッターの長さ（0=2分、1=4分、2=付点8分、3=8分、4=16分）', 0, 4, 3,
      scale: ParamScale.integer),
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

  /// ウェーブテーブルを使うプリセットか（音色画面の楽器ごとの振り分けに使う）
  bool get isWavetable => (values['wtTable'] ?? 0) >= 1;
}

/// ウェーブテーブルのテーブル一覧（音色画面のチップ用）。コアのテーブル番号と対応
const wtTableNames = <(int, String)>[
  (1, '基本'),
  (2, '倍音'),
  (3, 'フォルマント'),
  (4, 'デジタル'),
  (5, 'スペクトルソー'),
  (6, 'パルス'),
  (7, 'クワイア'),
];

/// 音色画面のセクション用にパラメータをキーで引く
List<SoundParam> pickParams(List<String> keys) => [for (final k in keys) _byKey[k]!];

/// アナログ・シンセのオシレーター節（波形トグルは別に大きく出す）
final analogOscParams = pickParams(['unison', 'detuneCents', 'width', 'blend', 'osc', 'sub', 'noise', 'drive']);

/// ウェーブテーブル・シンセのユニゾン節
final unisonParams = pickParams(['unison', 'detuneCents', 'width', 'blend']);

/// フィルター節（両シンセ共通）
final filterParams = pickParams(['cutoffHz', 'resonance', 'filterEnv', 'filterEnvDecayS', 'keyTrack']);

/// エンベロープ節（両シンセ共通。音量もここ）
final envParams = pickParams(['attackS', 'decayS', 'sustain', 'releaseS', 'pitchEnv', 'pitchEnvDecayS', 'masterGain']);

/// 演奏節（両シンセ共通）：グライドとモノ／レガート
final playParams = pickParams(['glideS', 'mono']);

/// LFO 節（両シンセ共通）：波形・テンポ同期・宛先（カットオフ／音程）。
/// 速さと WT_POS への量は従来どおり wtLfoRate／wtLfoAmount（ウェーブテーブルパネルに表示）
final lfoParams = pickParams(['lfoWave', 'lfoSync', 'lfoDiv', 'lfoCutoff', 'lfoPitch']);

// tools/demos/future_bass.py の音色（Chords・Lead・Bell・Bass・Kick・Clap・Hats・Riser）＋よく使う形
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
  SoundPreset('Chip Lead', 'リード', {
    'cutoffHz': 9000, 'resonance': 0.9, 'attackS': 0.002, 'decayS': 0.2, 'sustain': 0.7, 'releaseS': 0.1,
    'detuneCents': 8, 'masterGain': 0.6, 'unison': 2, 'width': 0.3, 'blend': 0.9, 'filterEnv': 0.15,
    'filterEnvDecayS': 0.12, 'wave': 1,
    'lowCutHz': 300, 'saturation': 0.1, 'ott': 0.3, 'delay': 0.25, 'delayFeedback': 0.3, 'reverb': 0.25,
    'sidechain': 0.3, 'sidechainReleaseS': 0.2,
  }),
  SoundPreset('Music Box Bell', 'リード', {
    'cutoffHz': 2200, 'resonance': 1.1, 'attackS': 0.001, 'decayS': 0.45, 'sustain': 0, 'releaseS': 0.35,
    'detuneCents': 6, 'masterGain': 0.7, 'unison': 2, 'width': 0.5, 'blend': 1.0, 'filterEnv': 0.7,
    'filterEnvDecayS': 0.15, 'wave': 1,
    'lowCutHz': 500, 'chorus': 0.25, 'ott': 0.3, 'delay': 0.3, 'reverb': 0.45, 'reverbSize': 0.7,
    'sidechain': 0.35, 'sidechainReleaseS': 0.2,
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
    'cutoffHz': 180, 'resonance': 0.7, 'attackS': 0.0005, 'decayS': 0.38, 'sustain': 0, 'releaseS': 0.05,
    'detuneCents': 0, 'masterGain': 1.0, 'unison': 1, 'width': 0, 'sub': 1.0, 'filterEnv': 0.85,
    'filterEnvDecayS': 0.03, 'pitchEnv': 36, 'pitchEnvDecayS': 0.04, 'osc': 0.62, 'drive': 0.18,
    'saturation': 0.42, 'eqLowDb': 3, 'eqLowHz': 80, 'eqMidDb': -2, 'eqMidHz': 350, 'comp': 0.35,
    'compThresholdDb': -16, 'compRatio': 4, 'sidechainSource': 1,
  }),
  SoundPreset('Snare', 'ドラム', {
    'cutoffHz': 2200, 'resonance': 0.85, 'attackS': 0.0005, 'decayS': 0.2, 'sustain': 0, 'releaseS': 0.08,
    'detuneCents': 0, 'masterGain': 1.0, 'unison': 1, 'noise': 1.0, 'filterEnv': 0.62, 'filterEnvDecayS': 0.07,
    'pitchEnv': 14, 'pitchEnvDecayS': 0.025, 'wave': 1, 'osc': 0.48,
    'lowCutHz': 140, 'saturation': 0.5, 'eqMidDb': 2.5, 'eqMidHz': 1800, 'eqHighDb': 1.5, 'eqHighHz': 7000,
    'comp': 0.3, 'compThresholdDb': -14, 'compRatio': 3.5, 'reverb': 0.22, 'reverbSize': 0.45,
    'sendReverb': 0.18,
  }),
  SoundPreset('Hi-hat', 'ドラム', {
    'cutoffHz': 14000, 'resonance': 0.9, 'attackS': 0.0005, 'decayS': 0.07, 'sustain': 0, 'releaseS': 0.04,
    'unison': 1, 'noise': 1.0, 'osc': 0.08, 'masterGain': 0.9,
    'lowCutHz': 3500, 'eqHighDb': 2, 'eqHighHz': 9000, 'reverb': 0.08, 'reverbSize': 0.3,
    'sidechain': 0.25, 'sidechainReleaseS': 0.12,
  }),
  SoundPreset('Noise Riser', 'FX', {
    'cutoffHz': 5000, 'resonance': 1.5, 'attackS': 3.0, 'decayS': 1.0, 'sustain': 1.0, 'releaseS': 0.4,
    'unison': 1, 'noise': 1.0, 'osc': 0, 'masterGain': 0.6,
    'lowCutHz': 400, 'reverb': 0.5, 'reverbSize': 0.8,
  }),
  SoundPreset('Basic Saw', 'その他', {}),
  // --- ウェーブテーブル用（wtTable を使うものだけ。音色画面ではWTシンセ側に出る） ---
  SoundPreset('WT Chords', 'コード', {
    'wtTable': 1, 'wtPos': 0.35, 'unison': 7, 'detuneCents': 38, 'width': 0.9, 'blend': 0.75,
    'cutoffHz': 9000, 'resonance': 0.8, 'attackS': 0.01, 'decayS': 0.6, 'sustain': 0.75, 'releaseS': 0.25,
    'masterGain': 0.55, 'lowCutHz': 180, 'chorus': 0.3, 'ott': 0.5, 'reverb': 0.3, 'reverbSize': 0.7,
    'sidechain': 0.85, 'sidechainReleaseS': 0.3,
  }),
  SoundPreset('Formant Lead', 'リード', {
    'wtTable': 3, 'wtPos': 0.5, 'wtWarp': 1, 'wtWarpAmount': 0.3, 'unison': 3, 'detuneCents': 12,
    'width': 0.5, 'blend': 0.85, 'cutoffHz': 5200, 'resonance': 0.9, 'attackS': 0.004, 'decayS': 0.3,
    'sustain': 0.6, 'releaseS': 0.15, 'masterGain': 0.55, 'drive': 0.08, 'filterEnv': 0.25, 'filterEnvDecayS': 0.2,
    'lowCutHz': 250, 'delay': 0.35, 'delayFeedback': 0.4, 'reverb': 0.3, 'sidechain': 0.45,
  }),
  SoundPreset('Digital Bass', 'ベース', {
    'wtTable': 4, 'wtPos': 0.65, 'wtWarp': 2, 'wtWarpAmount': 0.4, 'unison': 2, 'detuneCents': 10,
    'width': 0.1, 'sub': 0.6, 'drive': 0.35, 'cutoffHz': 1200, 'resonance': 1.4, 'attackS': 0.003,
    'decayS': 0.3, 'sustain': 0.85, 'releaseS': 0.08, 'masterGain': 0.75, 'filterEnv': 0.2, 'filterEnvDecayS': 0.1,
    'saturation': 0.3, 'sidechain': 0.7, 'sidechainReleaseS': 0.25,
  }),
  SoundPreset('Vocal Pad', 'コード', {
    'wtTable': 3, 'wtPos': 0.2, 'unison': 5, 'detuneCents': 25, 'width': 0.95, 'blend': 0.8,
    'cutoffHz': 3800, 'resonance': 0.9, 'attackS': 0.4, 'decayS': 1.0, 'sustain': 0.85, 'releaseS': 1.1,
    'masterGain': 0.5, 'lowCutHz': 200, 'chorus': 0.45, 'reverb': 0.6, 'reverbSize': 0.85, 'sidechain': 0.5,
    'sidechainReleaseS': 0.35,
  }),
  SoundPreset('Harmonic Pluck', 'リード', {
    'wtTable': 2, 'wtPos': 0.7, 'wtWarp': 1, 'wtWarpAmount': 0.2, 'unison': 2, 'detuneCents': 8,
    'width': 0.4, 'blend': 0.9, 'cutoffHz': 2600, 'resonance': 1.1, 'attackS': 0.001, 'decayS': 0.22,
    'sustain': 0, 'releaseS': 0.18, 'masterGain': 0.65, 'filterEnv': 0.6, 'filterEnvDecayS': 0.12,
    'lowCutHz': 250, 'delay': 0.3, 'delayFeedback': 0.35, 'reverb': 0.35, 'sidechain': 0.4,
  }),
  // --- フューチャーベース：ベース ---
  SoundPreset('FB Growl Bass', 'ベース', {
    'wtTable': 5, 'wtPos': 0.75, 'wtWarp': 1, 'wtWarpAmount': 0.45, 'wtLfoRate': 8, 'wtLfoAmount': 0.35,
    'unison': 3, 'detuneCents': 25, 'width': 0.3, 'blend': 0.85, 'sub': 0.55, 'drive': 0.55,
    'cutoffHz': 900, 'resonance': 3.2, 'filterEnv': 0.5, 'filterEnvDecayS': 0.16,
    'attackS': 0.003, 'decayS': 0.4, 'sustain': 0.8, 'releaseS': 0.09, 'masterGain': 0.75,
    'saturation': 0.5, 'ott': 0.6, 'sidechain': 0.85, 'sidechainReleaseS': 0.28,
  }),
  SoundPreset('FB Sub Bass', 'ベース', {
    'wtTable': 1, 'wtPos': 0.15, 'unison': 1, 'sub': 0.8, 'osc': 0.8,
    'cutoffHz': 500, 'resonance': 0.9, 'attackS': 0.003, 'decayS': 0.3, 'sustain': 0.9, 'releaseS': 0.06,
    'masterGain': 0.85, 'filterEnv': 0.15, 'filterEnvDecayS': 0.1,
    'saturation': 0.2, 'sidechain': 0.9, 'sidechainReleaseS': 0.28,
  }),
  SoundPreset('PWM Bass', 'ベース', {
    'wtTable': 6, 'wtPos': 0.65, 'wtLfoRate': 2.2, 'wtLfoAmount': 0.45,
    'unison': 2, 'detuneCents': 12, 'width': 0.2, 'sub': 0.4, 'drive': 0.3,
    'cutoffHz': 1100, 'resonance': 2.0, 'filterEnv': 0.35, 'filterEnvDecayS': 0.14,
    'attackS': 0.003, 'decayS': 0.35, 'sustain': 0.85, 'releaseS': 0.08, 'masterGain': 0.75,
    'saturation': 0.35, 'ott': 0.4, 'sidechain': 0.8, 'sidechainReleaseS': 0.26,
  }),
  SoundPreset('Spectral Reese', 'ベース', {
    'wtTable': 5, 'wtPos': 0.3, 'wtLfoRate': 0.5, 'wtLfoAmount': 0.2,
    'unison': 5, 'detuneCents': 50, 'width': 0.2, 'blend': 0.7, 'sub': 0.3, 'drive': 0.4,
    'cutoffHz': 700, 'resonance': 1.2, 'attackS': 0.005, 'decayS': 0.4, 'sustain': 0.9, 'releaseS': 0.1,
    'masterGain': 0.7, 'saturation': 0.45, 'ott': 0.5, 'sidechain': 0.7, 'sidechainReleaseS': 0.3,
  }),
  // --- フューチャーベース：コード ---
  SoundPreset('FB WT Chords', 'コード', {
    'wtTable': 5, 'wtPos': 0.55, 'wtLfoRate': 0.4, 'wtLfoAmount': 0.12,
    'unison': 9, 'detuneCents': 45, 'width': 1.0, 'blend': 0.7, 'noise': 0.03, 'drive': 0.12,
    'cutoffHz': 8500, 'resonance': 0.8, 'filterEnv': 0.25, 'filterEnvDecayS': 0.25,
    'attackS': 0.008, 'decayS': 0.6, 'sustain': 0.75, 'releaseS': 0.22, 'masterGain': 0.55,
    'lowCutHz': 180, 'chorus': 0.3, 'ott': 0.55, 'reverb': 0.3, 'reverbSize': 0.7,
    'sidechain': 0.9, 'sidechainReleaseS': 0.3,
  }),
  SoundPreset('FB Vocal Chords', 'コード', {
    'wtTable': 3, 'wtPos': 0.45, 'wtLfoRate': 1.8, 'wtLfoAmount': 0.5,
    'unison': 5, 'detuneCents': 30, 'width': 0.9, 'blend': 0.75,
    'cutoffHz': 6000, 'resonance': 0.9, 'filterEnv': 0.2, 'filterEnvDecayS': 0.3,
    'attackS': 0.01, 'decayS': 0.6, 'sustain': 0.8, 'releaseS': 0.25, 'masterGain': 0.55,
    'lowCutHz': 180, 'chorus': 0.35, 'ott': 0.4, 'reverb': 0.4, 'reverbSize': 0.75,
    'sidechain': 0.8, 'sidechainReleaseS': 0.3,
  }),
  SoundPreset('Choir Pad', 'コード', {
    'wtTable': 7, 'wtPos': 0.4, 'wtLfoRate': 0.25, 'wtLfoAmount': 0.2,
    'unison': 7, 'detuneCents': 35, 'width': 1.0, 'blend': 0.8,
    'cutoffHz': 4200, 'resonance': 0.9, 'attackS': 0.5, 'decayS': 1.0, 'sustain': 0.85, 'releaseS': 1.4,
    'masterGain': 0.5, 'lowCutHz': 200, 'chorus': 0.5, 'reverb': 0.65, 'reverbSize': 0.85,
    'sidechain': 0.4, 'sidechainReleaseS': 0.35,
  }),
  // --- フューチャーベース：リード ---
  SoundPreset('FB Formant Lead', 'リード', {
    'wtTable': 3, 'wtPos': 0.6, 'wtWarp': 1, 'wtWarpAmount': 0.35, 'wtLfoRate': 3.5, 'wtLfoAmount': 0.3,
    'unison': 3, 'detuneCents': 14, 'width': 0.5, 'blend': 0.85,
    'cutoffHz': 6500, 'resonance': 1.0, 'filterEnv': 0.25, 'filterEnvDecayS': 0.2,
    'attackS': 0.004, 'decayS': 0.3, 'sustain': 0.65, 'releaseS': 0.15, 'masterGain': 0.6,
    'lowCutHz': 250, 'chorus': 0.2, 'ott': 0.4, 'delay': 0.35, 'delayFeedback': 0.4, 'reverb': 0.3,
    'sidechain': 0.45,
  }),
  SoundPreset('FB Digital Lead', 'リード', {
    'wtTable': 4, 'wtPos': 0.55, 'wtWarp': 3, 'wtWarpAmount': 0.5,
    'unison': 4, 'detuneCents': 18, 'width': 0.6, 'blend': 0.7, 'drive': 0.15,
    'cutoffHz': 9000, 'resonance': 0.9, 'filterEnv': 0.2, 'filterEnvDecayS': 0.15,
    'attackS': 0.003, 'decayS': 0.35, 'sustain': 0.7, 'releaseS': 0.18, 'masterGain': 0.55,
    'lowCutHz': 250, 'saturation': 0.15, 'ott': 0.45, 'delay': 0.3, 'delayFeedback': 0.35, 'reverb': 0.3,
    'sidechain': 0.4,
  }),
  SoundPreset('Spectral Pluck', 'リード', {
    'wtTable': 5, 'wtPos': 0.8, 'wtWarp': 1, 'wtWarpAmount': 0.2,
    'unison': 2, 'detuneCents': 8, 'width': 0.4, 'blend': 0.9,
    'cutoffHz': 2400, 'resonance': 1.1, 'filterEnv': 0.65, 'filterEnvDecayS': 0.12,
    'attackS': 0.001, 'decayS': 0.22, 'sustain': 0, 'releaseS': 0.18, 'masterGain': 0.65,
    'lowCutHz': 250, 'chorus': 0.15, 'ott': 0.35, 'delay': 0.3, 'delayFeedback': 0.35, 'reverb': 0.35,
    'sidechain': 0.4,
  }),
  // --- 本格フューチャーベース（エンジン拡張： keyTrack／グライド／モノ／LFO拡張を使用） ---
  // コード主力： maj9 想定のスーパーソー。デチューンは両端 34ct（外側 ±17ct）と控えめ、
  // OTT はコードバス定番の 30%、キートラッキングで高音域も明るさを保つ
  SoundPreset('FB Chords 9th', 'コード', {
    'unison': 9, 'detuneCents': 34, 'width': 0.95, 'blend': 0.7, 'noise': 0.02, 'drive': 0.12,
    'cutoffHz': 10000, 'resonance': 0.8, 'keyTrack': 0.6, 'filterEnv': 0.2, 'filterEnvDecayS': 0.3,
    'attackS': 0.006, 'decayS': 0.6, 'sustain': 0.78, 'releaseS': 0.4, 'masterGain': 0.55,
    'lowCutHz': 180, 'saturation': 0.12, 'chorus': 0.3, 'ott': 0.3, 'reverb': 0.3, 'reverbSize': 0.7,
    'sidechain': 0.9, 'sidechainReleaseS': 0.3,
  }),
  // 歌うリード： モノ＋グライド 90ms、発音直後に +12 半音から落ちるスクープ、5.5Hz のビブラート
  SoundPreset('FB Vocal Lead', 'リード', {
    'wtTable': 3, 'wtPos': 0.5, 'wtWarp': 1, 'wtWarpAmount': 0.25,
    'mono': 1, 'glideS': 0.09, 'pitchEnv': 12, 'pitchEnvDecayS': 0.08,
    'wtLfoRate': 5.5, 'lfoPitch': 0.18,
    'unison': 2, 'detuneCents': 10, 'width': 0.3, 'blend': 0.9,
    'cutoffHz': 6000, 'resonance': 1.0, 'keyTrack': 0.5, 'filterEnv': 0.2, 'filterEnvDecayS': 0.2,
    'attackS': 0.004, 'decayS': 0.3, 'sustain': 0.7, 'releaseS': 0.15, 'masterGain': 0.7,
    'lowCutHz': 250, 'saturation': 0.1, 'ott': 0.35, 'delay': 0.35, 'delayFeedback': 0.4,
    'reverb': 0.3, 'reverbSize': 0.65, 'sidechain': 0.45,
  }),
  // ワブル： 付点8分に同期した矩形 LFO がカットオフと WT 位置を一緒に開閉する。
  // サブはフィルター後のサイン加算なので LFO でも汚れない
  SoundPreset('FB Wobble Bass', 'ベース', {
    'wtTable': 5, 'wtPos': 0.6, 'wtWarp': 1, 'wtWarpAmount': 0.4,
    'mono': 1, 'glideS': 0.02,
    'lfoSync': 1, 'lfoDiv': 2, 'lfoWave': 2, 'lfoCutoff': 0.65, 'wtLfoAmount': 0.45,
    'unison': 3, 'detuneCents': 22, 'width': 0.25, 'blend': 0.85, 'sub': 0.5, 'drive': 0.45,
    'cutoffHz': 850, 'resonance': 2.8, 'keyTrack': 0.3, 'filterEnv': 0.35, 'filterEnvDecayS': 0.15,
    'attackS': 0.003, 'decayS': 0.35, 'sustain': 0.85, 'releaseS': 0.08, 'masterGain': 0.75,
    'saturation': 0.5, 'ott': 0.5, 'sidechain': 0.8, 'sidechainReleaseS': 0.25,
  }),
  // リース： ±12ct に開いたソー（中央声が芯）、低い LP、1小節周期の遅いカットオフ揺れ
  SoundPreset('FB Reese Bass', 'ベース', {
    'unison': 3, 'detuneCents': 24, 'width': 0.1, 'blend': 1.0, 'sub': 0.45, 'drive': 0.25,
    'mono': 1, 'glideS': 0.03,
    'lfoSync': 1, 'lfoDiv': 0, 'lfoWave': 0, 'lfoCutoff': 0.12,
    'cutoffHz': 750, 'resonance': 1.4, 'keyTrack': 0.2,
    'attackS': 0.005, 'decayS': 0.3, 'sustain': 0.95, 'releaseS': 0.1, 'masterGain': 0.72,
    'saturation': 0.35, 'chorus': 0.15, 'ott': 0.35, 'sidechain': 0.7, 'sidechainReleaseS': 0.3,
  }),
  // プラック： キートラッキング高めで、9th アルペジオがどの音域でも抜ける
  SoundPreset('FB Pluck', 'リード', {
    'unison': 2, 'detuneCents': 10, 'width': 0.45, 'blend': 0.85,
    'cutoffHz': 1600, 'resonance': 1.1, 'keyTrack': 0.85, 'filterEnv': 0.72, 'filterEnvDecayS': 0.09,
    'attackS': 0.001, 'decayS': 0.16, 'sustain': 0, 'releaseS': 0.12, 'masterGain': 0.68,
    'lowCutHz': 250, 'chorus': 0.15, 'ott': 0.35, 'delay': 0.32, 'delayFeedback': 0.38,
    'reverb': 0.3, 'reverbSize': 0.6, 'sidechain': 0.45,
  }),
  // 厚いパッド： 12声ユニゾン＋1小節同期の微ドリフト（カットオフと WT 位置）
  SoundPreset('FB Pad Air', 'コード', {
    'wtTable': 5, 'wtPos': 0.3, 'noise': 0.015,
    'unison': 12, 'detuneCents': 30, 'width': 1.0, 'blend': 0.75,
    'lfoSync': 1, 'lfoDiv': 0, 'lfoWave': 0, 'lfoCutoff': 0.1, 'wtLfoAmount': 0.18,
    'cutoffHz': 5200, 'resonance': 0.8, 'keyTrack': 0.45,
    'attackS': 0.6, 'decayS': 1.2, 'sustain': 0.85, 'releaseS': 1.8, 'masterGain': 0.30,
    'lowCutHz': 200, 'saturation': 0.08, 'chorus': 0.45, 'ott': 0.25, 'reverb': 0.6, 'reverbSize': 0.85,
    'sidechain': 0.5, 'sidechainReleaseS': 0.35,
  }),
  // キラキラ・アルペジオ： 矩形波、低域を大きく空けて付点ディレイで跳ねる（音量は控えめ）
  SoundPreset('FB Sparkle Arp', 'リード', {
    'wave': 1, 'unison': 2, 'detuneCents': 6, 'width': 0.55, 'blend': 0.9,
    'cutoffHz': 8500, 'resonance': 0.9, 'keyTrack': 0.6, 'filterEnv': 0.35, 'filterEnvDecayS': 0.07,
    'attackS': 0.001, 'decayS': 0.13, 'sustain': 0.05, 'releaseS': 0.09, 'masterGain': 0.45,
    'lowCutHz': 800, 'chorus': 0.1, 'ott': 0.25, 'delay': 0.45, 'delayFeedback': 0.45,
    'reverb': 0.35, 'reverbSize': 0.7, 'sidechain': 0.35,
  }),
  // 喋るリード： フォルマント WT をフリー LFO で大きく往復させ、グライド 120ms でつなぐ
  // （Vocal Lead との違い： スクープとビブラート無し、動きは WT 位置主体）
  SoundPreset('FB Talking Lead', 'リード', {
    'wtTable': 3, 'wtPos': 0.45, 'wtWarp': 1, 'wtWarpAmount': 0.35,
    'mono': 1, 'glideS': 0.12, 'wtLfoRate': 2.2, 'wtLfoAmount': 0.55,
    'unison': 1, 'width': 0.15, 'blend': 1.0,
    'cutoffHz': 4200, 'resonance': 1.8, 'keyTrack': 0.35, 'filterEnv': 0.3, 'filterEnvDecayS': 0.25,
    'attackS': 0.005, 'decayS': 0.3, 'sustain': 0.7, 'releaseS': 0.12, 'masterGain': 0.6,
    'lowCutHz': 250, 'saturation': 0.15, 'ott': 0.35, 'delay': 0.3, 'delayFeedback': 0.35,
    'reverb': 0.28, 'sidechain': 0.45,
  }),
  // クリーンなサブ専用： オシレーターを切り、フィルター後のサインだけをモノで鳴らす
  SoundPreset('FB Sub Clean', 'ベース', {
    'osc': 0, 'sub': 1.0, 'unison': 1, 'width': 0, 'blend': 1.0,
    'mono': 1, 'glideS': 0.02,
    'cutoffHz': 300, 'resonance': 0.9,
    'attackS': 0.004, 'decayS': 0.2, 'sustain': 0.95, 'releaseS': 0.05, 'masterGain': 0.9,
    'saturation': 0.12,
  }),
];
