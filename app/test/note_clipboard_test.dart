import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/piano_roll/note_clipboard.dart';

NoteData _note(int tick, int pitch, {int length = 240, double velocity = 0.8}) =>
    NoteData(id: tick * 1000 + pitch, tick: tick, length: length, pitch: pitch, velocity: velocity);

void main() {
  group('copyNotesOf', () {
    test('空なら null', () {
      expect(copyNotesOf(const []), isNull);
    });

    test('原点は一番早い tick と、その時刻の一番低い音', () {
      final cb = copyNotesOf([
        _note(480, 65, velocity: 0.9),
        _note(0, 62),
        _note(0, 58),
        _note(240, 60),
      ])!;
      // 原点 (0, 58)。相対位置の並びは tick → 音程の順
      expect(cb.notes.map((n) => (n.tick, n.pitch)).toList(), [(0, 0), (0, 4), (240, 2), (480, 7)]);
      expect(cb.notes.last.velocity, 0.9); // 音量も覚える
      expect(cb.notes.first.length, 240);
      expect(cb.spanTicks, 480 + 240);
    });
  });

  group('pasteNoteSpecs', () {
    final cb = copyNotesOf([
      _note(0, 58),
      _note(0, 62),
      _note(480, 65, length: 480),
    ])!;

    test('タップした位置に原点が来て、相対配置のまま置ける', () {
      final specs = pasteNoteSpecs(cb, anchorTick: 960, anchorPitch: 60, clipLengthTicks: 3840);
      expect(specs.map((n) => (n.tick, n.pitch, n.length)).toList(), [
        (960, 60, 240),
        (960, 64, 240),
        (1440, 67, 480),
      ]);
    });

    test('別の場所（音程違い）へも貼れる', () {
      final specs = pasteNoteSpecs(cb, anchorTick: 0, anchorPitch: 48, clipLengthTicks: 3840);
      expect(specs.map((n) => n.pitch).toList(), [48, 52, 55]);
    });

    test('クリップの終わりを超えるノートは入れず、はみ出す長さは詰める', () {
      // 原点を 3360 に置くと、相対 480 のノートは 3840（終わり）に重なるので入らない
      final specs = pasteNoteSpecs(cb, anchorTick: 3360, anchorPitch: 60, clipLengthTicks: 3840);
      expect(specs.map((n) => (n.tick, n.length)).toList(), [(3360, 240), (3360, 240)]);
      // 終わり近くでは長さが詰まる
      final clamped = pasteNoteSpecs(cb, anchorTick: 3700, anchorPitch: 60, clipLengthTicks: 3840);
      expect(clamped.first.length, 140);
    });

    test('詰めて最短（60）より短くなるノートは入れない', () {
      final specs = pasteNoteSpecs(cb, anchorTick: 3800, anchorPitch: 60, clipLengthTicks: 3840);
      expect(specs, isEmpty); // 残り 40 tick しかない
    });

    test('音域から外れるノートは入れない', () {
      final specs = pasteNoteSpecs(cb, anchorTick: 0, anchorPitch: 124, clipLengthTicks: 3840);
      // 原点 124 は入るが、+4 → 128 と +7 → 131 は外れる
      expect(specs.map((n) => n.pitch).toList(), [124]);
    });
  });
}
