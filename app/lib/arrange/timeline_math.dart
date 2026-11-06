// 縦タイムラインの計算（画面に依存しない部分。テストしやすいように分けてある）
import 'dart:math' as math;

import '../model/project.dart';

/// 再生位置の表示「小節.拍.16分」（すべて1始まり）。例：曲頭は 1.1.1
String formatPosition(int ticks, int ticksPerBar) {
  final t = ticks < 0 ? 0 : ticks;
  final bar = t ~/ ticksPerBar + 1;
  final inBar = t % ticksPerBar;
  final beat = inBar ~/ ticksPerBeat + 1;
  final sixteenth = (inBar % ticksPerBeat) ~/ (ticksPerBeat ~/ 4) + 1;
  return '$bar.$beat.$sixteenth';
}

/// クリップに A, B, C… の名前を振る。曲の上（早い小節）、左（トラック順）から出てきた順
Map<int, String> clipLabels(ProjectData p) {
  final trackOrder = {for (var i = 0; i < p.tracks.length; i++) p.tracks[i].id: i};
  final sorted = [...p.placements]..sort((a, b) {
      final byBar = a.startBar.compareTo(b.startBar);
      return byBar != 0 ? byBar : (trackOrder[a.trackId] ?? 0).compareTo(trackOrder[b.trackId] ?? 0);
    });
  final labels = <int, String>{};
  for (final pl in sorted) {
    labels.putIfAbsent(pl.clipId, () => _letters(labels.length));
  }
  return labels;
}

String _letters(int n) {
  // A..Z, AA..AZ, BA..
  var s = '';
  var i = n;
  do {
    s = String.fromCharCode(65 + i % 26) + s;
    i = i ~/ 26 - 1;
  } while (i >= 0);
  return s;
}

/// 隙間なく隣り合った同じクリップの配置を、見た目をつなげるためにまとめる。
/// 返り値は開始小節順のグループ（各グループは開始小節順の配置リスト）。
/// 間に小節が空いていたり、違うクリップだったりすればそこで切れる
List<List<PlacementData>> joinedClipGroups(List<PlacementData> placements) {
  final sorted = [...placements]..sort((a, b) => a.startBar.compareTo(b.startBar));
  final groups = <List<PlacementData>>[];
  for (final pl in sorted) {
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && last.last.clipId == pl.clipId && last.last.endBar == pl.startBar) {
      last.add(pl);
    } else {
      groups.add([pl]);
    }
  }
  return groups;
}

// ---- ピンチズーム（ソング画面） ---------------------------------------------------

/// ズーム倍率 1 のときの1小節の高さ
const double baseBarHeight = 40;

/// 小節の高さの倍率の下限・上限（高さで 16〜120dp になる範囲）
double clampRowZoom(double zoom) => zoom.clamp(0.4, 3.0).toDouble();

/// 倍率から1小節の高さを求める（16〜120dp に収まる）
double barHeightForZoom(double zoom) => baseBarHeight * clampRowZoom(zoom);

/// 列幅の倍率の下限・上限
double clampColZoom(double zoom) => zoom.clamp(0.3, 4.0).toDouble();

/// 倍率から列幅を求める。細くなりすぎ・太くなりすぎを防ぐため 28〜320dp に収める
double colWidthForZoom(double baseWidth, double zoom) =>
    (baseWidth * clampColZoom(zoom)).clamp(28.0, 320.0).toDouble();

/// そのトラックで start 以降に lengthBars 小節ぶん空いている最初の小節
int nextFreeBar(ProjectData p, int trackId, int start, int lengthBars) {
  var bar = start < 0 ? 0 : start;
  while (true) {
    final hit = p.placementsOn(trackId).where((pl) => pl.startBar < bar + lengthBars && bar < pl.endBar);
    if (hit.isEmpty) return bar;
    bar = hit.map((pl) => pl.endBar).reduce((a, b) => a > b ? a : b);
  }
}

// ---- ループ範囲（小節ルーラーのドラッグで指定） --------------------------------

/// ドラッグの両端の小節から、ループ範囲 [start, end) に整える。
/// 逆向きにドラッグしてもよく、曲の長さ（最低1小節）の中に収める
({int start, int end}) loopRangeBars(int a, int b, int lengthBars) {
  final last = math.max(lengthBars, 1);
  final start = math.min(a, b).clamp(0, last - 1);
  final end = (math.max(a, b) + 1).clamp(start + 1, last);
  return (start: start, end: end);
}

/// ループ範囲（小節）をエンジンへ渡す tick に直す
({int startTick, int endTick}) loopRangeTicks(int startBar, int endBar, int ticksPerBar) =>
    (startTick: startBar * ticksPerBar, endTick: endBar * ticksPerBar);

// ---- 再生ヘッド追従とドラッグ端の自動スクロール -----------------------------------

/// 再生ヘッド追従（ページ送り式）：ヘッド（中身の y）が見えている間は null（動かさない）。
/// 下端からはみ出したら（と、ループで先頭へ戻ったら）ヘッドが画面の先頭に来る位置を返す
double? followScrollTarget({
  required double headY,
  required double offset,
  required double viewportHeight,
  required double maxExtent,
}) {
  if (headY >= offset && headY < offset + viewportHeight) return null;
  return headY.clamp(0.0, maxExtent).toDouble();
}

/// ドラッグ中に指がビューポートの端へ寄ったときの自動スクロールの速度（px/秒）。
/// 端から [edge] px 以内に入ると 0 から [maxSpeed] まで線形に速くなる。
/// 符号は「中身の座標が増える方向（右・下）へ流す」が +
({double dx, double dy}) edgeScrollVelocity({
  required double posX,
  required double posY,
  required double width,
  required double height,
  double edge = 48,
  double maxSpeed = 420,
}) {
  double axis(double p, double len) {
    if (len <= 0) return 0;
    if (p < edge) return -maxSpeed * (1 - p / edge).clamp(0.0, 1.0);
    if (p > len - edge) return maxSpeed * (1 - (len - p) / edge).clamp(0.0, 1.0);
    return 0;
  }

  return (dx: axis(posX, width), dy: axis(posY, height));
}

/// ある小節に入るクリップのノート（その小節の頭からの tick に直したもの）。配置がクリップより長ければ繰り返す
Iterable<NoteData> notesInBar(ClipData clip, PlacementData pl, int bar, int ticksPerBar) sync* {
  if (clip.lengthTicks <= 0) return;
  final barStart = (bar - pl.startBar) * ticksPerBar; // 配置の頭から
  final barEnd = barStart + ticksPerBar;
  for (var rep = 0; rep < pl.lengthBars * ticksPerBar; rep += clip.lengthTicks) {
    if (rep >= barEnd) break;
    for (final n in clip.notes) {
      final on = rep + n.tick;
      if (on >= barStart && on < barEnd) {
        yield NoteData(id: n.id, tick: on - barStart, length: n.length, pitch: n.pitch, velocity: n.velocity);
      }
    }
  }
}
