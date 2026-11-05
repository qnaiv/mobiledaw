// オートメーションのパラメータ定義と、画面に依存しない計算。
// 旧 automation_sheet.dart の定義（対象・値域・ログ目盛り）をここへ移して、
// ピアノロールのオートメーションモードとアレンジ画面の両方から使う。
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../sound/sound_params.dart';

/// トラック音量のレーン。シンセ/FX のパラメータではない（コア側は仮想 ID）のでここで定義する。
/// 値はミキサーの gain と同じ 0〜2（1 = ±0 dB）
const SoundParam automationGainParam =
    SoundParam(MdawParam.trackGain, 'gain', '音量', 0, 2, 1, unit: '%');

SoundParam _byKey(String key) => allSoundParams.firstWhere((p) => p.key == key);

/// 画面に出す代表の対象（音量＋シンセ/FX から5種）
final List<SoundParam> automationTargets = [
  automationGainParam,
  _byKey('cutoffHz'),
  _byKey('wtPos'),
  _byKey('masterGain'),
  _byKey('reverb'),
  _byKey('delay'),
];

/// 保存キーからパラメータ定義を引く。'gain' はトラック音量。対応表に無いキーは null
SoundParam? automationParamFor(String key) {
  if (key == automationGainParam.key) return automationGainParam;
  for (final p in allSoundParams) {
    if (p.key == key) return p;
  }
  return null;
}

/// チップや小タグ用の短い名前
String automationShortLabel(String key) => switch (key) {
      'gain' => '音量',
      'cutoffHz' => 'カットオフ',
      'wtPos' => 'WT位置',
      'masterGain' => '音色の音量',
      'reverb' => 'リバーブ',
      'delay' => 'ディレイ',
      _ => key,
    };

/// [tick] でのレーンの値。最初の点より前は未確定（null、コアの評価と同じ）、
/// 点と点の間は直線でつなぎ、最後の点より後は最後の値のまま
double? automationValueAt(List<(int, double)> points, int tick) {
  if (points.isEmpty || tick < points.first.$1) return null;
  var value = points.first.$2;
  for (var i = 0; i < points.length; i++) {
    final (t, v) = points[i];
    if (tick == t) return v;
    if (tick < t) {
      final (pt, pv) = points[i - 1];
      return pv + (v - pv) * (tick - pt) / (t - pt);
    }
    value = v;
  }
  return value;
}

/// [start]〜[end] の範囲に描くポリラインの点（tick, 値）。範囲の両端は補間した値でつなぐので、
/// 小節ごとに区切って描いても線がつながる。範囲が最初の点より前なら空
List<(int, double)> automationSegment(List<(int, double)> points, int start, int end) {
  if (points.isEmpty) return const [];
  final out = <(int, double)>[];
  final startValue = automationValueAt(points, start);
  if (startValue != null) out.add((start, startValue));
  for (final p in points) {
    if (p.$1 > start && p.$1 < end) out.add(p);
  }
  final endValue = automationValueAt(points, end);
  if (endValue != null && (out.isEmpty || out.last.$1 != end)) out.add((end, endValue));
  return out;
}

/// コピーの中身：クリップのレーン一式を複製する（元のリストをあとで触っても影響しない）
List<AutomationLaneData> copyAutomationLanes(ClipData clip) => [
      for (final lane in clip.automation)
        AutomationLaneData(param: lane.param, points: List.of(lane.points)),
    ];

/// 貼り付け・消去の計画：(パラメータID, 点列) の操作列。点列が空 = そのレーンを消す。
/// コントローラはこの計画を1つの Undo にまとめて実行する。ID に直せないキーは飛ばす
typedef AutomationPlan = List<(int, List<(int, double)>)>;

/// 貼り付け：対象クリップのレーンをコピー元で丸ごと差し替える
/// （対象にあってコピー元に無いレーンは消す。長さの違いはコア側の正規化に任せる）
AutomationPlan automationPastePlan({
  required List<AutomationLaneData> current,
  required List<AutomationLaneData> clipboard,
}) {
  final plan = <(int, List<(int, double)>)>[];
  final copiedKeys = {for (final lane in clipboard) lane.param};
  for (final lane in current) {
    if (copiedKeys.contains(lane.param)) continue;
    final p = automationParamFor(lane.param);
    if (p != null) plan.add((p.id, const []));
  }
  for (final lane in clipboard) {
    final p = automationParamFor(lane.param);
    if (p != null) plan.add((p.id, List.of(lane.points)));
  }
  return plan;
}

/// 消去：今あるレーンを全部消す
AutomationPlan automationClearPlan(List<AutomationLaneData> current) => [
      for (final lane in current)
        if (automationParamFor(lane.param) case final p?) (p.id, const <(int, double)>[]),
    ];
