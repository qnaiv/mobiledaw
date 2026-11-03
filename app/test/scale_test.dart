import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/scale.dart';

void main() {
  test('C minor from octave 4 gives 8 notes up to the next C', () {
    const scale = Scale(0, Scale.minorIntervals);
    expect(scale.notesFrom(4), [60, 62, 63, 65, 67, 68, 70, 72]);
  });

  test('contains works across octaves', () {
    const scale = Scale(0, Scale.minorIntervals);
    expect(scale.contains(63), isTrue); // E♭4
    expect(scale.contains(64), isFalse); // E4
    expect(scale.contains(39), isTrue); // E♭2
  });

  test('note names use flats', () {
    expect(noteName(61), 'D♭');
    expect(noteName(60, withOctave: true), 'C4');
    expect(noteName(70, withOctave: true), 'B♭4');
  });
}
