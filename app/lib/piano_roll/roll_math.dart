// 縦ピアノロールの計算（画面に依存しない部分）。
// 列 = 音の高さ（左が低い。全音域を横スクロール）、行 = 時間（下へ進む）。行の単位はグリッド（1/4・1/8・1/16）。
// 座標はロールの中身の座標（左上が最低音・クリップ先頭）。画面の座標にはスクロール量を足して変換する。
import 'dart:math' as math;

import '../model/project.dart';
import '../music/scale.dart';

/// プロジェクトのキーとスケール
Scale scaleOf(ProjectData p) =>
    Scale(p.keyRoot, p.scale == 'major' ? Scale.majorIntervals : Scale.minorIntervals);

/// 並べる音（MIDI 0〜127）。スケール外を畳むならスケール音だけ、全音表示なら全部
List<int> rollColumns(Scale scale, {required bool chromatic}) =>
    [for (var p = 0; p < 128; p++) if (chromatic || scale.contains(p)) p];

/// ノートが多く入るオクターブ（開いたときに見せる場所）。ノートが無ければ 4（C4 のあたり）
int bestOctave(ClipData clip, Scale scale) {
  if (clip.notes.isEmpty) return 4;
  final counts = <int, int>{};
  for (final n in clip.notes) {
    final oct = (n.pitch - scale.root) ~/ 12 - 1;
    counts[oct] = (counts[oct] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key.clamp(0, 8);
}

/// グリッドの選択肢（tick）
const gridSteps = [ticksPerBeat, ticksPerBeat ~/ 2, ticksPerBeat ~/ 4];

String gridLabel(int step) => switch (step) {
      ticksPerBeat => '1/4',
      480 => '1/8',
      240 => '1/16',
      _ => '$step',
    };

/// tick をグリッドへ切り捨てる
int snapDown(int tick, int step) => tick < 0 ? 0 : tick ~/ step * step;

/// 行と列の寸法（中身の座標）
class RollGeometry {
  RollGeometry({
    required this.columns,
    required this.colWidth,
    required this.step,
    required this.rowHeight,
    required this.lengthTicks,
  });

  final List<int> columns; // 各列の音程（低い順）
  final double colWidth;
  final int step;
  final double rowHeight;
  final int lengthTicks;

  double get width => columns.length * colWidth;
  int get rows => (lengthTicks + step - 1) ~/ step;
  double get height => rows * rowHeight;

  double colX(int col) => col * colWidth;
  double tickY(num tick) => tick / step * rowHeight;

  /// x にある列（外なら null）
  int? colAt(double x) {
    if (x < 0 || x >= width) return null;
    return (x / colWidth).floor().clamp(0, columns.length - 1);
  }

  /// y の位置の tick（グリッドに切り捨て、クリップの中に収める）
  int tickAt(double y) => snapDown((y / rowHeight * step).floor().clamp(0, lengthTicks - 1), step);

  int? columnOf(int pitch) {
    final i = columns.indexOf(pitch);
    return i < 0 ? null : i;
  }

  /// その音が入る列。畳んでいてスケール外の音なら、すぐ下のスケール音の列
  int nearestColumn(int pitch) {
    var best = 0;
    for (var i = 0; i < columns.length; i++) {
      if (columns[i] <= pitch) best = i;
    }
    return best;
  }

  /// ある音程の列の真ん中が画面の真ん中に来るスクロール量
  double scrollToCenter(int pitch, double viewportWidth) =>
      (colX(nearestColumn(pitch)) + colWidth / 2 - viewportWidth / 2).clamp(0, math.max(0.0, width - viewportWidth)).toDouble();
}

/// その位置にあるノート（後に描いたもの＝上に重なっているものを優先）
NoteData? noteAt(ClipData clip, RollGeometry g, double x, double y) {
  final col = g.colAt(x);
  if (col == null) return null;
  final pitch = g.columns[col];
  final tick = y / g.rowHeight * g.step;
  for (final n in clip.notes.reversed) {
    if (n.pitch == pitch && tick >= n.tick && tick < n.endTick) return n;
  }
  return null;
}

/// ノートのつまみ（上端・下端）
enum NoteHandle { start, end }

/// つまみの真ん中の位置
({double x, double y}) handlePoint(NoteData n, RollGeometry g, NoteHandle h) {
  final col = g.columnOf(n.pitch) ?? 0;
  return (x: g.colX(col) + g.colWidth / 2, y: g.tickY(h == NoteHandle.start ? n.tick : n.endTick));
}

/// 指が触れたつまみ（指の太さを見込んで半径 [radius] まで）。上下両方に近ければ近い方
({NoteData note, NoteHandle handle})? handleAt(Iterable<NoteData> notes, RollGeometry g, double x, double y,
    {double radius = 24}) {
  ({NoteData note, NoteHandle handle})? best;
  var bestDist = radius;
  for (final n in notes) {
    if (g.columnOf(n.pitch) == null) continue;
    for (final h in NoteHandle.values) {
      final p = handlePoint(n, g, h);
      final d = math.sqrt(math.pow(p.x - x, 2) + math.pow(p.y - y, 2));
      if (d <= bestDist) {
        bestDist = d;
        best = (note: n, handle: h);
      }
    }
  }
  return best;
}

/// 範囲選択（2点で囲んだ四角）に入るノート
List<int> notesInRect(ClipData clip, RollGeometry g, double x0, double y0, double x1, double y1) {
  final left = math.min(x0, x1), right = math.max(x0, x1);
  final top = math.min(y0, y1), bottom = math.max(y0, y1);
  final ids = <int>[];
  for (final n in clip.notes) {
    final col = g.columnOf(n.pitch);
    if (col == null) continue;
    final nx0 = g.colX(col), nx1 = nx0 + g.colWidth;
    final ny0 = g.tickY(n.tick), ny1 = g.tickY(n.endTick);
    if (nx1 > left && nx0 < right && ny1 > top && ny0 < bottom) ids.add(n.id);
  }
  return ids;
}

/// 上端のつまみを dt 動かしたときに、実際に動かせる量（グリッド単位、終わりは固定）。
/// 先頭より前には出ず、どのノートも最短の長さ（[minLength]）は残す
int clampStartDelta(Iterable<NoteData> notes, int dt, int step, {int minLength = 60}) {
  var lo = -1 << 30, hi = 1 << 30;
  for (final n in notes) {
    lo = math.max(lo, -n.tick);
    hi = math.min(hi, n.length - minLength);
  }
  if (lo > hi) return 0;
  final clamped = dt.clamp(lo, hi);
  // グリッドの倍数に寄せる（範囲の中で）
  final snapped = (clamped / step).truncate() * step;
  return snapped.clamp(lo, hi);
}
