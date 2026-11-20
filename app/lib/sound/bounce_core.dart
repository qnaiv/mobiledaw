// バウンスの共通処理（Phase 2.6）: BounceSection（サンプラー側から作る）と
// GranularizeSection（素材化したいトラック側から作る）が共有する。
// キット ID の発行、小節→秒の換算、部分バウンスの切り出し、kit.json の書き込み。
import 'dart:convert';
import 'dart:io';

import '../model/project.dart';
import 'wav_trim.dart';

/// キット ID は [a-z0-9-] のみ・48 字以内（コアの isValidKitId に合わせる）
String newBounceKitId(String? projectId) {
  var base = (projectId ?? 'project')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'project';
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  var id = 'bounce-$base-$stamp';
  if (id.length > 48) id = id.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  return id;
}

/// 小節番号（0 始まり）→ 曲頭からの秒数
double barToSeconds(int bar, ProjectData project) =>
    bar * project.ticksPerBar / ticksPerBeat * 60.0 / project.tempo;

/// トラックの配置を小節順に並べたもの（部分バウンスの範囲選択用）
List<PlacementData> placementsOf(ProjectData project, int trackId) {
  final list = project.placementsOn(trackId).toList();
  list.sort((a, b) => a.startBar.compareTo(b.startBar));
  return list;
}

/// 配置の表示名（例: 「3〜6小節」）
String placementLabel(PlacementData p) => '${p.startBar + 1}〜${p.endBar}小節';

/// 書き出し済み WAV を [startBar, endBar) の区間だけに切り詰める（部分バウンス）。
/// 切り出しに失敗したら false（呼び出し側は全体を素材にするか失敗扱いにする）。
Future<bool> trimWavFileToBars(File wav, ProjectData project, int startBar, int endBar) async {
  try {
    final bytes = await wav.readAsBytes();
    final trimmed = trimWavBytes(bytes, barToSeconds(startBar, project), barToSeconds(endBar, project));
    if (trimmed == null) return false;
    await wav.writeAsBytes(trimmed, flush: true);
    return true;
  } on Object {
    return false;
  }
}

/// バウンス素材のキット（phrase.wav 1 音だけ）を dir に登録する
Future<void> writeBounceKitJson(Directory dir, String soundName) async {
  await File('${dir.path}/kit.json').writeAsString(jsonEncode({
    'name': 'バウンス素材',
    'version': 1,
    'sounds': [
      {'name': soundName, 'file': 'phrase.wav', 'note': 60, 'gain': 1.0},
    ],
  }));
}
