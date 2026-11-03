import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/chords.dart';
import 'package:mobiledaw/music/scale.dart';

void main() {
  test('C minor gives the seven chords used in pop (V as a major chord)', () {
    final chords = diatonicChords(const Scale(0, Scale.minorIntervals), minor: true);
    expect(chords.map((c) => c.name), ['Cm', 'D°', 'E♭', 'Fm', 'G', 'A♭', 'B♭']);
    expect(chords[0].seventhName, 'Cm7');
    expect(chords[4].seventhName, 'G7');
    expect(chords[5].mood, '広がる');
  });

  test('C major gives I ii iii IV V vi vii°', () {
    final chords = diatonicChords(const Scale(0, Scale.majorIntervals), minor: false);
    expect(chords.map((c) => c.name), ['C', 'Dm', 'Em', 'F', 'G', 'Am', 'B°']);
    expect(chords[3].seventhName, 'FM7');
  });

  test('chord notes are stacked from the root at or below the tapped pitch', () {
    final ab = diatonicChords(const Scale(0, Scale.minorIntervals), minor: true)[5];
    expect(ab.pitchesNear(60), [56, 60, 63]); // C4 をタップ → A♭3 から
    expect(ab.pitchesNear(68), [68, 72, 75]); // A♭4 をタップ → そこから
    expect(ab.pitchesNear(68, withSeventh: true), [68, 72, 75, 79]);
  });

  test('suggestions follow common progressions', () {
    expect(suggestNext(5, minor: true), [6, 0, 3]); // A♭ → B♭ Cm Fm
    expect(suggestNext(4, minor: false), [0, 5, 3]); // G → C Am F
  });

  test('chord names are detected from placed notes, including inversions', () {
    expect(chordNameOf([56, 60, 63]), 'A♭');
    expect(chordNameOf([60, 63, 68]), 'A♭/C');
    expect(chordNameOf([60, 63, 67, 70]), 'Cm7');
    expect(chordNameOf([67, 71, 74, 77]), 'G7');
    expect(chordNameOf([60, 62]), isNull);
    expect(chordNameOf([60, 61, 62]), isNull);
  });
}
