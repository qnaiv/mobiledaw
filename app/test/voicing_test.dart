import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/chords.dart';
import 'package:mobiledaw/music/progressions.dart';
import 'package:mobiledaw/music/scale.dart';
import 'package:mobiledaw/music/voicing.dart';

const _cMinor = Scale(0, Scale.minorIntervals);
const _ab = [56, 60, 63]; // A♭ 基本形

List<int> _apply(List<int> pitches, PitchEdit e) =>
    applyPitchEdit([for (final p in pitches) NoteSpec(0, 960, p)], e).map((n) => n.pitch).toList();

void main() {
  test('analysis knows inversions and colors', () {
    expect(analyzeChord(_ab)!.inversion, '基本形');
    expect(analyzeChord([60, 63, 68])!.inversion, '第1転回');
    expect(analyzeChord([60, 63, 67, 70])!.hasSeventh, isTrue);
    expect(analyzeChord([60, 65, 67])!.hasSus4, isTrue);
    expect(chordNameOf([60, 63, 67, 70, 74]), 'Cm9');
  });

  test('invert up and down', () {
    expect(_apply(_ab, invert(_ab, up: true)), [60, 63, 68]);
    expect(_apply(_ab, invert(_ab, up: false)), [51, 56, 60]);
  });

  test('spread opens the middle note, and closes back', () {
    final open = _apply(_ab, spreadOrClose(_ab));
    expect(open, [56, 63, 72]);
    expect(isClosed(open), isFalse);
    expect(_apply(open, spreadOrClose(open)), [56, 60, 63]);
  });

  test('bass cycles root → third → fifth → none', () {
    final withRoot = _apply(_ab, cycleBass(_ab));
    expect(withRoot, [44, 56, 60, 63]);
    final withThird = _apply(withRoot, cycleBass(withRoot));
    expect(withThird.first % 12, 0); // C（A♭/C）
    expect(chordNameOf(withThird), 'A♭/C');
    final withFifth = _apply(withThird, cycleBass(withThird));
    expect(withFifth.first % 12, 3); // E♭
    expect(_apply(withFifth, cycleBass(withFifth)), [56, 60, 63]);
  });

  test('7th, sus4 and add9 toggle on and off', () {
    final seventh = _apply(_ab, toggleSeventh(_ab, _cMinor));
    expect(chordNameOf(seventh), 'A♭M7'); // キーの中の7度（G）
    expect(_apply(seventh, toggleSeventh(seventh, _cMinor)), _ab);
    final sus = _apply(_ab, toggleSus(_ab, _cMinor, to: 5));
    expect(chordNameOf(sus), 'A♭sus4');
    expect(_apply(sus, toggleSus(sus, _cMinor, to: 5)), _ab);
    final nine = _apply(_ab, toggleNinth(_ab));
    expect(nine.contains(70), isTrue); // B♭
    expect(_apply(nine, toggleNinth(nine)), _ab);
  });

  test('voice leading moves as little as possible', () {
    const cm = [60, 63, 67];
    const fmRoot = [65, 68, 72];
    final led = _apply(fmRoot, voiceLead(cm, fmRoot));
    expect(led, [60, 65, 68]); // C は残り、E♭→F、G→A♭
  });

  test('added notes go on every strike, removed notes everywhere', () {
    final notes = [
      for (final t in [0, 480])
        for (final p in _ab) NoteSpec(t, 400, p),
    ];
    final out = applyPitchEdit(notes, const PitchEdit(remap: {63: null}, add: [67]));
    expect(out.where((n) => n.pitch == 63), isEmpty);
    expect(out.where((n) => n.pitch == 67).map((n) => n.tick), [0, 480]);
  });

  test('rhythms fill the chord length', () {
    expect(rhythmize(_ab, start: 0, length: 3840, rhythm: ChordRhythm.block).length, 3);
    expect(rhythmize(_ab, start: 0, length: 3840, rhythm: ChordRhythm.eighth).length, 8 * 3);
    final arp = rhythmize(_ab, start: 0, length: 960, rhythm: ChordRhythm.arpUp);
    expect(arp.map((n) => n.pitch), [56, 60, 63, 56]);
    final updown = rhythmize(_ab, start: 0, length: 1920, rhythm: ChordRhythm.arpUpDown);
    expect(updown.take(5).map((n) => n.pitch), [56, 60, 63, 60, 56]);
    final strum = rhythmize(_ab, start: 0, length: 960, rhythm: ChordRhythm.strum);
    expect(strum.map((n) => n.tick), [0, 40, 80]);
    final sync = rhythmize(_ab, start: 0, length: 3840, rhythm: ChordRhythm.syncopated);
    expect(sync.map((n) => n.tick).toSet(), {0, 720, 1440, 2400, 2880});
    for (final n in [...sync, ...updown]) {
      expect(n.tick + n.length <= 3840, isTrue);
    }
    // ベースはずっと伸びる
    final withBass = rhythmize([44, 56, 60, 63], start: 0, length: 1920, rhythm: ChordRhythm.eighth);
    expect(withBass.where((n) => n.pitch == 44).single.length, 1920);
  });

  test('roman numerals follow the key', () {
    expect(chordFromRoman('♭VI', _cMinor)!.name, 'A♭');
    expect(chordFromRoman('v7', _cMinor)!.name, 'Gm7');
    expect(chordFromRoman('i9', _cMinor)!.name, 'Cm9');
    expect(chordFromRoman('♭VIM7', _cMinor)!.name, 'A♭M7');
    expect(chordFromRoman('♭II', _cMinor)!.name, 'D♭');
    expect(chordFromRoman('IV', const Scale(7, Scale.majorIntervals))!.name, 'C'); // G major の IV
    expect(chordFromRoman('xyz', _cMinor), isNull);
  });

  test('progressions are voiced close together', () {
    final chords = minorPresets.first.romans.map((r) => chordFromRoman(r, _cMinor)!).toList();
    final v = voiceProgression(chords);
    expect(v.length, 4);
    for (var i = 1; i < v.length; i++) {
      expect((v[i].first - v[i - 1].first).abs() <= 7, isTrue);
    }
  });

  test('dice keeps locked chords and is repeatable with a seed', () {
    final chords = diatonicChords(_cMinor, minor: true);
    List<int> roll(int seed) => rollProgression(
        minor: true, brightness: 0.5, surprise: 0.5, locked: [0, null, null, 4], rng: math.Random(seed), chords: chords);
    final a = roll(7), b = roll(7);
    expect(a, b);
    expect(a.first, 0);
    expect(a.last, 4);
    expect(a.every((d) => d >= 0 && d < 7), isTrue);
  });
}
