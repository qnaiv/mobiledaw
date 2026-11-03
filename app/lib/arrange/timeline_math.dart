// 縦タイムラインの計算（画面に依存しない部分。テストしやすいように分けてある）
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

/// そのトラックで start 以降に lengthBars 小節ぶん空いている最初の小節
int nextFreeBar(ProjectData p, int trackId, int start, int lengthBars) {
  var bar = start < 0 ? 0 : start;
  while (true) {
    final hit = p.placementsOn(trackId).where((pl) => pl.startBar < bar + lengthBars && bar < pl.endBar);
    if (hit.isEmpty) return bar;
    bar = hit.map((pl) => pl.endBar).reduce((a, b) => a > b ? a : b);
  }
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
