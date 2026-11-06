import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/music/scale.dart';
import 'package:mobiledaw/piano_roll/roll_math.dart';

const _cMinor = Scale(0, Scale.minorIntervals);

ClipData _clip(List<NoteData> notes) => ClipData(id: 1, trackId: 1, lengthTicks: 3840, notes: notes);

NoteData _n(int id, int tick, int length, int pitch) =>
    NoteData(id: id, tick: tick, length: length, pitch: pitch, velocity: 0.8);

RollGeometry _geometry({bool chromatic = false}) => RollGeometry(
      columns: rollColumns(_cMinor, chromatic: chromatic),
      colWidth: 40,
      step: 480, // 1/8
      rowHeight: 30,
      lengthTicks: 3840,
    );

void main() {
  test('columns cover the whole range: scale notes only, or all 128', () {
    final folded = rollColumns(_cMinor, chromatic: false);
    expect(folded.first, 0);
    expect(folded.last, 127); // G9 は C minor のスケール音
    expect(folded.where((p) => p >= 60 && p <= 72), [60, 62, 63, 65, 67, 68, 70, 72]);
    expect(rollColumns(_cMinor, chromatic: true).length, 128);
  });

  test('geometry maps positions to pitch and snapped tick', () {
    final g = _geometry();
    expect(g.rows, 8);
    final c60 = g.columnOf(60)!;
    expect(g.colAt(g.colX(c60) + 5), c60);
    expect(g.colAt(-1), isNull);
    expect(g.tickAt(0), 0);
    expect(g.tickAt(29), 0);
    expect(g.tickAt(31), 480);
    expect(g.tickAt(10000), 3360); // クリップの中に収めてグリッドに切り捨て
    expect(g.nearestColumn(61), c60); // スケール外は下のスケール音の列
  });

  test('scroll target centers the pitch', () {
    final g = _geometry();
    final x = g.scrollToCenter(60, 200);
    expect(x + 100, closeTo(g.colX(g.columnOf(60)!) + 20, 0.001));
    expect(g.scrollToCenter(0, 200), 0); // 端より外へは行かない
  });

  test('finds the note under the finger and its grips', () {
    final g = _geometry();
    final clip = _clip([_n(1, 960, 960, 63)]); // 3〜4行目、E♭4
    final col = g.columnOf(63)!;
    final x = g.colX(col) + 20;
    expect(noteAt(clip, g, x, g.tickY(960) + 5)?.id, 1);
    expect(noteAt(clip, g, x, g.tickY(1920) + 5), isNull);
    final top = handleAt(clip.notes, g, x + 6, g.tickY(960) - 8);
    expect(top?.handle, NoteHandle.start);
    final bottom = handleAt(clip.notes, g, x - 4, g.tickY(1920) + 10);
    expect(bottom?.handle, NoteHandle.end);
    expect(handleAt(clip.notes, g, x, g.tickY(1440)), isNull); // 真ん中はつまみではない
  });

  test('marquee selects notes it touches', () {
    final g = _geometry();
    final clip = _clip([_n(1, 0, 480, 60), _n(2, 960, 480, 63), _n(3, 2880, 480, 72)]);
    final x0 = g.colX(g.columnOf(60)!), x1 = g.colX(g.columnOf(65)!);
    expect(notesInRect(clip, g, x0, 0, x1, g.tickY(1440)), [1, 2]);
  });

  test('moving the start keeps notes inside the clip and above the minimum length', () {
    final notes = [_n(1, 480, 960, 60), _n(2, 960, 480, 62)];
    expect(clampStartDelta(notes, -960, 240), -480); // 1つ目は 0 より前に出られない
    expect(clampStartDelta(notes, 960, 240), 240); // 2つ目は 480−60 まで → グリッドで 240
    expect(clampStartDelta(notes, 0, 240), 0);
  });

  test('busiest octave and grid labels', () {
    final clip = _clip([_n(1, 0, 480, 48), _n(2, 0, 480, 50), _n(3, 0, 480, 75)]);
    expect(bestOctave(clip, _cMinor), 3);
    expect(bestOctave(_clip([]), _cMinor), 4);
    expect(gridSteps.map(gridLabel), ['1/4', '1/8', '1/16']);
    expect(snapDown(719, 240), 480);
  });

  group('rollTapAction: タップ判定の組み合わせ', () {
    RollTapAction tap({
      bool pasteReady = false,
      bool hasHit = false,
      bool outside = false,
      bool chordMode = false,
      bool hasSelection = false,
    }) =>
        rollTapAction(
          pasteReady: pasteReady,
          hasHit: hasHit,
          outside: outside,
          chordMode: chordMode,
          hasSelection: hasSelection,
        );

    test('貼り付け待ちは何より優先（選択があっても空きマスでも貼る）', () {
      expect(tap(pasteReady: true, hasSelection: true), RollTapAction.paste);
      expect(tap(pasteReady: true, hasHit: true, hasSelection: true), RollTapAction.paste);
    });

    test('既存ノートのタップは選択＋試聴（選択の有無によらない）', () {
      expect(tap(hasHit: true), RollTapAction.selectNote);
      expect(tap(hasHit: true, hasSelection: true), RollTapAction.selectNote);
    });

    test('選択あり＋空きマス → 選択解除だけ（置かない）', () {
      expect(tap(hasSelection: true), RollTapAction.clearSelectionOnly);
    });

    test('選択なし＋空きマス → 従来どおりノートを置く', () {
      expect(tap(), RollTapAction.placeNote);
    });

    test('グリッド外は選択解除だけ（選択の有無によらない）', () {
      expect(tap(outside: true), RollTapAction.clearSelectionOnly);
      expect(tap(outside: true, hasSelection: true), RollTapAction.clearSelectionOnly);
    });

    test('コードモードは選択があってもコード配置を優先する', () {
      expect(tap(chordMode: true), RollTapAction.placeChord);
      expect(tap(chordMode: true, hasSelection: true), RollTapAction.placeChord);
    });
  });
}
