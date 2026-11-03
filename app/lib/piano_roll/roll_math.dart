// 縦ピアノロールの計算（画面に依存しない部分）。
// 列 = 音の高さ（左が低い）、行 = 時間（下へ進む）。行の単位はグリッド（1/4・1/8・1/16）。
import '../model/project.dart';
import '../music/scale.dart';

/// プロジェクトのキーとスケール
Scale scaleOf(ProjectData p) =>
    Scale(p.keyRoot, p.scale == 'major' ? Scale.majorIntervals : Scale.minorIntervals);

/// 画面に並べる音。スケール外を畳むならスケール音＋上のルート（短調なら8列）、
/// 全音表示ならルートから1オクターブ上のルートまでの13列
List<int> rollColumns(Scale scale, int octave, {required bool chromatic}) {
  if (!chromatic) return scale.notesFrom(octave);
  final base = (octave + 1) * 12 + scale.root;
  return [for (var i = 0; i <= 12; i++) base + i];
}

/// ノートが多く入るオクターブ（開いたときの初期位置）。ノートが無ければ 4
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

/// 行と列の寸法
class RollGeometry {
  RollGeometry({
    required this.width,
    required this.columns,
    required this.step,
    required this.rowHeight,
    required this.lengthTicks,
  });

  static const double labelWidth = 22;

  final double width;
  final List<int> columns; // 各列の音程
  final int step;
  final double rowHeight;
  final int lengthTicks;

  double get colWidth => (width - labelWidth) / columns.length;
  int get rows => (lengthTicks + step - 1) ~/ step;
  double get height => rows * rowHeight;

  double colX(int col) => labelWidth + col * colWidth;
  double tickY(num tick) => tick / step * rowHeight;

  /// x にある列（ラベルの上や外なら null）
  int? colAt(double x) {
    if (x < labelWidth || x >= width) return null;
    return ((x - labelWidth) / colWidth).floor().clamp(0, columns.length - 1);
  }

  /// y の位置の tick（グリッドに切り捨て）
  int tickAt(double y) => snapDown((y / rowHeight * step).floor().clamp(0, lengthTicks - 1), step);

  int? columnOf(int pitch) {
    final i = columns.indexOf(pitch);
    return i < 0 ? null : i;
  }
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

/// ノートの下端をつまんだか（長さを変える操作）。下端から 14px か、ノートの下 1/3
bool isNearBottom(NoteData n, RollGeometry g, double y) {
  final bottom = g.tickY(n.endTick);
  final h = bottom - g.tickY(n.tick);
  return bottom - y <= (h / 3).clamp(10, 14);
}

/// 範囲選択（2点で囲んだ四角）に入るノート
List<int> notesInRect(ClipData clip, RollGeometry g, double x0, double y0, double x1, double y1) {
  final left = x0 < x1 ? x0 : x1, right = x0 < x1 ? x1 : x0;
  final top = y0 < y1 ? y0 : y1, bottom = y0 < y1 ? y1 : y0;
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

/// 今のオクターブの外にあって見えないノートの数（上・下）
(int below, int above) hiddenNotes(ClipData clip, List<int> columns) {
  var below = 0, above = 0;
  for (final n in clip.notes) {
    if (n.pitch < columns.first) {
      below++;
    } else if (n.pitch > columns.last) {
      above++;
    }
  }
  return (below, above);
}
