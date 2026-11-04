import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/chords.dart';
import 'package:mobiledaw/music/progression_gen.dart';
import 'package:mobiledaw/music/scale.dart';

void main() {
  test('every style makes valid, full-length, distinct proposals', () {
    final gen = ProgressionGenerator(rng: math.Random(1));
    for (final style in genStyles) {
      for (final bars in [4, 8]) {
        final props = gen.generate(style: style, bars: bars, tries: 120);
        expect(props.length, 4, reason: style.id);
        expect(props.map((p) => p.signature).toSet().length, 4, reason: style.id);
        for (final p in props) {
          expect(p.beats, bars * 4, reason: '${style.id} ${p.signature}');
          for (final c in p.chords) {
            expect(realize(c, 0), isNotNull, reason: '${style.id}: ${c.roman}');
            expect(c.beats, greaterThan(0));
          }
        }
      }
    }
  });

  test('pressing again keeps giving new progressions', () {
    final gen = ProgressionGenerator(rng: math.Random(7));
    final seen = <String>{};
    var total = 0;
    for (var i = 0; i < 25; i++) {
      for (final p in gen.generate(style: styleById('future-bass'), tries: 120)) {
        seen.add(p.signature);
        total++;
      }
    }
    // 100案のうち、ほとんどが違う
    expect(seen.length, greaterThan(total * 0.85));
  });

  test('random style mixes styles', () {
    final gen = ProgressionGenerator(rng: math.Random(3));
    final styles = <String>{};
    for (var i = 0; i < 10; i++) {
      styles.addAll(gen.generate(tries: 80).map((p) => p.style.id));
    }
    expect(styles.length, greaterThan(5));
  });

  test('locked chords stay where they are', () {
    final gen = ProgressionGenerator(rng: math.Random(5));
    final first = gen.generate(style: styleById('jpop'), tries: 80).first;
    final keep = first.chords.first;
    for (final p in gen.generate(style: styleById('jpop'), keepRhythmOf: first.chords, locked: {0: keep}, tries: 80)) {
      expect(p.chords.first.base, keep.base);
      expect(p.beats, first.beats);
    }
  });

  test('context: continues naturally from the chord before', () {
    final gen = ProgressionGenerator(rng: math.Random(11));
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i < 10; i++) {
      for (final p in gen.generate(style: styleById('jpop'), context: const GenContext(before: 'ii'), tries: 100)) {
        sum += flowWeight('ii', p.chords.first.base);
        n++;
      }
    }
    // ii の次として自然なもの（V・iii・IV など）から始まる
    expect(sum / n, greaterThan(0.45));
  });

  test('names, keys and reading chords back', () {
    expect(chordName(const GenChord('IV', 'M7', 4), 0), 'FM7');
    expect(chordName(const GenChord('vi', '9', 4), 0), 'Am9');
    expect(chordName(const GenChord('V', '7sus4', 4), 0), 'G7sus4');
    expect(chordName(const GenChord('♭VII', '', 4), 0), 'B♭');
    expect(chordName(const GenChord('♯iv°', '°7', 4), 0), 'G♭dim7');
    // C minor の曲は E♭ major として扱う：IV = A♭
    final eb = majorRootOf(const Scale(0, Scale.minorIntervals), minor: true);
    expect(chordName(const GenChord('IV', 'M7', 4), eb), 'A♭M7');
    expect(baseOf(analyzeChord([57, 60, 64])!, 0), 'vi');
    expect(baseOf(analyzeChord([58, 62, 65])!, 0), '♭VII');
    expect(baseOf(analyzeChord([53, 56, 60])!, 0), 'iv');
    expect(baseOf(analyzeChord([59, 62, 65])!, 0), 'vii°');
    // 鳴らすと名前どおりの音
    final c = realize(const GenChord('ii', '9', 4), 0)!;
    expect(chordNameOf(c.pitchesNear(62)), 'Dm9');
  });
}
