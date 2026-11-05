import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/chords.dart';
import 'package:mobiledaw/music/progression_gen.dart';
import 'package:mobiledaw/music/progressions.dart';
import 'package:mobiledaw/music/scale.dart';

Scale atC(String id) => Scale.of(0, scaleKindOf(id));

void main() {
  test('scale kinds: 7 kinds, ids round-trip, unknown falls back to minor', () {
    expect(scaleKinds.map((k) => k.id),
        ['major', 'minor', 'dorian', 'mixolydian', 'harmonicMinor', 'majorPentatonic', 'minorPentatonic']);
    for (final k in scaleKinds) {
      expect(scaleKindOf(k.id), k);
      expect(kindOfScale(Scale.of(5, k)), k);
    }
    expect(scaleKindOf('major').label, 'メジャー');
    expect(scaleKindOf('something-else').id, 'minor'); // 昔の扱い（major 以外は minor）
    expect(scaleKindOf('dorian').intervals, [0, 2, 3, 5, 7, 9, 10]);
  });

  test('major and natural minor are unchanged', () {
    final major = scaleChords(atC('major'));
    expect(major.map((c) => c.name), ['C', 'Dm', 'Em', 'F', 'G', 'Am', 'B°']);
    expect(major.map((c) => c.roman), ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°']);
    final minor = scaleChords(atC('minor'));
    expect(minor.map((c) => c.name), ['Cm', 'D°', 'E♭', 'Fm', 'G', 'A♭', 'B♭']);
    expect(minor.map((c) => c.roman), ['i', 'ii°', '♭III', 'iv', 'V', '♭VI', '♭VII']);
    expect(minor[4].seventhName, 'G7'); // V は長三和音のまま
  });

  test('dorian chords are stacked from the scale', () {
    final chords = scaleChords(atC('dorian'));
    expect(chords.map((c) => c.name), ['Cm', 'Dm', 'E♭', 'F', 'Gm', 'A°', 'B♭']);
    expect(chords.map((c) => c.roman), ['i', 'ii', '♭III', 'IV', 'v', 'vi°', '♭VII']);
    expect(chords[3].seventhName, 'F7'); // IV がドミナント7th になるのがドリアンの味
  });

  test('mixolydian chords are stacked from the scale', () {
    final chords = scaleChords(atC('mixolydian'));
    expect(chords.map((c) => c.name), ['C', 'Dm', 'E°', 'F', 'Gm', 'Am', 'B♭']);
    expect(chords.map((c) => c.roman), ['I', 'ii', 'iii°', 'IV', 'v', 'vi', '♭VII']);
    expect(chords[0].seventhName, 'C7');
  });

  test('harmonic minor chords are stacked from the scale (V and vii° are strong)', () {
    final chords = scaleChords(atC('harmonicMinor'));
    expect(chords.map((c) => c.name), ['Cm', 'D°', 'E♭+', 'Fm', 'G', 'A♭', 'B°']);
    expect(chords.map((c) => c.roman), ['i', 'ii°', '♭III+', 'iv', 'V', '♭VI', 'vii°']);
    expect(chords[4].seventhName, 'G7');
    expect(chords[6].seventhName, 'Bdim7');
  });

  test('pentatonic chords come from the parent scale, roots inside the scale only', () {
    final ma = scaleChords(atC('majorPentatonic'));
    expect(ma.map((c) => c.name), ['C', 'Dm', 'Em', 'G', 'Am']);
    expect(ma.map((c) => c.roman), ['I', 'ii', 'iii', 'V', 'vi']);
    expect(ma.map((c) => c.degree), [0, 1, 2, 3, 4]); // 一覧の中の位置は詰める
    final mi = scaleChords(atC('minorPentatonic'));
    expect(mi.map((c) => c.name), ['Cm', 'E♭', 'Fm', 'G', 'B♭']);
    expect(mi.map((c) => c.roman), ['i', '♭III', 'iv', 'V', '♭VII']);
  });

  test('chords transpose with the root', () {
    final a = scaleChords(Scale.of(9, scaleKindOf('dorian'))); // A dorian
    expect(a.map((c) => c.name), ['Am', 'Bm', 'C', 'D', 'Em', 'G♭°', 'G']); // 音名は ♭ 表記に統一
    expect(a[0].pitchesNear(57), [57, 60, 64]); // A2 から Am
  });

  test('suggestions stay inside the chord list for every scale', () {
    for (final k in scaleKinds) {
      final scale = Scale.of(0, k);
      final chords = scaleChords(scale);
      for (var i = 0; i < chords.length; i++) {
        final next = suggestNextForScale(scale, i);
        expect(next, isNotEmpty, reason: '${k.id} degree $i');
        for (final d in next) {
          expect(d, inInclusiveRange(0, chords.length - 1), reason: '${k.id} degree $i');
        }
      }
    }
    // ドリアンの i の次は IV が筆頭
    expect(suggestNextForScale(atC('dorian'), 0).first, 3);
    // マイナーペンタの i（位置0）の次は、残っているコードの位置で返る
    final mi = atC('minorPentatonic');
    expect(suggestNextForScale(mi, 0), contains(4)); // ♭VII（B♭）は位置4
  });

  test('roman labels use flats against the major scale', () {
    expect(romanLabel(10, 0, const [0, 4, 7]), '♭VII');
    expect(romanLabel(3, 0, const [0, 3, 7]), '♭iii');
    expect(romanLabel(6, 0, const [0, 3, 6]), '♯iv°');
    expect(romanLabel(7, 0, const [0, 4, 7], suffix: '7'), 'V7');
  });

  test('borrowed chords per scale', () {
    final major = borrowedChords(atC('major'));
    expect(major.map((b) => b.chord.name), ['Fm', 'B♭', 'D7', 'E7']);
    expect(major.map((b) => b.chord.roman), ['iv', '♭VII', 'II7', 'III7']);
    // 借用コードはダイアトニックと重ならない
    final dia = scaleChords(atC('major')).map((c) => c.name).toSet();
    expect(major.every((b) => !dia.contains(b.chord.name)), isTrue);

    final minor = borrowedChords(atC('minor'));
    expect(minor.map((b) => b.chord.name), ['G7', 'F', 'D7', 'D♭']);
    expect(minor.map((b) => b.chord.roman), ['V7', 'IV', 'II7', '♭II']);

    final dorian = borrowedChords(atC('dorian'));
    expect(dorian.map((b) => b.chord.name), ['G7', 'C7', 'Fm']);
    expect(dorian.map((b) => b.chord.roman), ['V7', 'I7', 'iv']);

    // どのスケールでも、借用コードは置ける形（3音以上）になっている
    for (final k in scaleKinds) {
      for (final b in borrowedChords(Scale.of(0, k))) {
        expect(b.chord.pitchesNear(60).length, greaterThanOrEqualTo(3), reason: '${k.id} ${b.chord.roman}');
      }
    }
  });

  test('generation frame: minor-like scales use the parallel major, others their own root', () {
    expect(genFrameOf(atC('major')), (majorRoot: 0, minorKey: false));
    expect(genFrameOf(atC('mixolydian')), (majorRoot: 0, minorKey: false));
    expect(genFrameOf(atC('majorPentatonic')), (majorRoot: 0, minorKey: false));
    expect(genFrameOf(atC('minor')), (majorRoot: 3, minorKey: true));
    expect(genFrameOf(atC('harmonicMinor')), (majorRoot: 3, minorKey: true));
    expect(genFrameOf(atC('minorPentatonic')), (majorRoot: 3, minorKey: true));
    // A ドリアンは C メジャーの物差しで、主音 Am は vi として中心に来る
    expect(genFrameOf(Scale.of(9, scaleKindOf('dorian'))), (majorRoot: 0, minorKey: true));
  });
}
