import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/music/scale.dart';
import 'package:mobiledaw/piano_roll/roll_math.dart';

const _cMinor = Scale(0, Scale.minorIntervals);

ClipData _clip(List<NoteData> notes) => ClipData(id: 1, trackId: 1, lengthTicks: 3840, notes: notes);

NoteData _n(int id, int tick, int length, int pitch) =>
    NoteData(id: id, tick: tick, length: length, pitch: pitch, velocity: 0.8);

RollGeometry _geometry({bool chromatic = false}) => RollGeometry(
      width: 22 + 8 * 40.0, // 8列なら1列 40px
      columns: rollColumns(_cMinor, 4, chromatic: chromatic),
      step: 480, // 1/8
      rowHeight: 30,
      lengthTicks: 3840,
    );

void main() {
  test('folded columns are the scale, chromatic shows all 13', () {
    expect(rollColumns(_cMinor, 4, chromatic: false), [60, 62, 63, 65, 67, 68, 70, 72]);
    final all = rollColumns(_cMinor, 4, chromatic: true);
    expect(all.length, 13);
    expect(all.first, 60);
    expect(all.last, 72);
  });

  test('geometry maps taps to pitch and snapped tick', () {
    final g = _geometry();
    expect(g.rows, 8);
    expect(g.colAt(10), isNull); // 目盛りの帯
    expect(g.colAt(22 + 40 * 2 + 5), 2);
    expect(g.columns[2], 63);
    expect(g.tickAt(0), 0);
    expect(g.tickAt(29), 0);
    expect(g.tickAt(31), 480);
    expect(g.tickAt(10000), 3839 ~/ 480 * 480); // クリップの中に収める
  });

  test('finds the note under the finger and its bottom edge', () {
    final g = _geometry();
    final clip = _clip([_n(1, 960, 960, 63)]); // 3〜4行目、E♭
    final x = g.colX(2) + 10;
    expect(noteAt(clip, g, x, g.tickY(960) + 5)?.id, 1);
    expect(noteAt(clip, g, x, g.tickY(1920) + 5), isNull);
    expect(noteAt(clip, g, g.colX(3) + 10, g.tickY(960) + 5), isNull);
    final note = clip.notes.single;
    expect(isNearBottom(note, g, g.tickY(1920) - 4), isTrue);
    expect(isNearBottom(note, g, g.tickY(960) + 4), isFalse);
  });

  test('marquee selects notes it touches', () {
    final g = _geometry();
    final clip = _clip([_n(1, 0, 480, 60), _n(2, 960, 480, 63), _n(3, 2880, 480, 72)]);
    final ids = notesInRect(clip, g, g.colX(0), 0, g.colX(3), g.tickY(1440));
    expect(ids, [1, 2]);
  });

  test('octave hint counts hidden notes and picks the busiest octave', () {
    final clip = _clip([_n(1, 0, 480, 48), _n(2, 0, 480, 50), _n(3, 0, 480, 75)]);
    expect(hiddenNotes(clip, rollColumns(_cMinor, 4, chromatic: false)), (2, 1));
    expect(bestOctave(clip, _cMinor), 3);
    expect(bestOctave(_clip([]), _cMinor), 4);
  });

  test('grid labels and snapping', () {
    expect(gridSteps.map(gridLabel), ['1/4', '1/8', '1/16']);
    expect(snapDown(719, 240), 480);
    expect(snapDown(-3, 240), 0);
  });
}
