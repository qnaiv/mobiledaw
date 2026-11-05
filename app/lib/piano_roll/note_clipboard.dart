// ピアノロールのノートのコピペ（画面に依存しない計算）。
// コピーは「一番早いノートの位置、その時刻にある一番低い音」を原点にした相対位置で覚える。
// 貼り付けは、タップした位置（tick と音程）に原点が来るように相対配置のまま置く。
import 'dart:math' as math;

import '../model/project.dart';
import '../music/voicing.dart';

/// ノートの長さの最短（コアの ResizeNotes::kMinLength = ppq / 16 と揃える）
const int minNoteLength = ticksPerBeat ~/ 16;

/// コピーしたノート1つ（原点からの相対位置で持つ）
class CopiedNote {
  const CopiedNote({required this.tick, required this.pitch, required this.length, required this.velocity});

  /// 原点の tick からの差（0以上）
  final int tick;

  /// 原点の音程からの差（半音）
  final int pitch;

  final int length;
  final double velocity;
}

/// ノートのコピー一式。画面をまたいで（別のクリップを開いても）使えるよう、コントローラが保持する
class NoteClipboard {
  const NoteClipboard(this.notes);

  final List<CopiedNote> notes;

  bool get isEmpty => notes.isEmpty;
  bool get isNotEmpty => notes.isNotEmpty;

  /// 貼ったときの全体の長さ（原点から最後のノートの終わりまで）
  int get spanTicks => notes.fold(0, (m, n) => math.max(m, n.tick + n.length));
}

/// [notes]（1つのクリップの中のノート）をコピー一式にする。ノートが無ければ null。
/// 原点は tick = 一番早いノートの tick、音程 = その tick にある一番低いノートの音程
NoteClipboard? copyNotesOf(Iterable<NoteData> notes) {
  final list = notes.toList();
  if (list.isEmpty) return null;
  var startTick = list.first.tick;
  for (final n in list) {
    startTick = math.min(startTick, n.tick);
  }
  var anchorPitch = 128;
  for (final n in list) {
    if (n.tick == startTick) anchorPitch = math.min(anchorPitch, n.pitch);
  }
  final copied = [
    for (final n in list)
      CopiedNote(tick: n.tick - startTick, pitch: n.pitch - anchorPitch, length: n.length, velocity: n.velocity),
  ]..sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.pitch.compareTo(b.pitch));
  return NoteClipboard(copied);
}

/// [clipboard] を、原点が [anchorTick]・[anchorPitch] に来るように貼ったときのノート列。
/// クリップの終わり（[clipLengthTicks]）を超える位置のノートは入れず、はみ出す長さは終わりに合わせて詰める
/// （詰めて最短より短くなるノートは入れない）。音域（0〜127）から外れるノートも入れない
List<NoteSpec> pasteNoteSpecs(
  NoteClipboard clipboard, {
  required int anchorTick,
  required int anchorPitch,
  required int clipLengthTicks,
}) {
  final out = <NoteSpec>[];
  for (final n in clipboard.notes) {
    final tick = anchorTick + n.tick;
    if (tick < 0 || tick >= clipLengthTicks) continue;
    final pitch = anchorPitch + n.pitch;
    if (pitch < 0 || pitch > 127) continue;
    final length = math.min(n.length, clipLengthTicks - tick);
    if (length < minNoteLength) continue;
    out.add(NoteSpec(tick, length, pitch, n.velocity));
  }
  out.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.pitch.compareTo(b.pitch));
  return out;
}
