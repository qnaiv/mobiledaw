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

  group('sections', () {
    const diatonic = {'I', 'ii', 'iii', 'IV', 'V', 'vi'};
    const bannedSuffixA = {'M9', '9', '11', '6', '69', '°', 'ø', '°7'};
    const bannedSuffixB = {'11', '69', '°', 'ø', '°7'}; // Bメロは M9・9・6 まで許可

    GenProgression fake(List<GenChord> chords) => GenProgression(genStyles.first, chords, const []);

    test('validator catches section violations', () {
      // 先頭コード
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('IV', '', 4), const GenChord('V', '', 4)]), GenSection.verseA),
          isFalse);
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('I', '', 4), const GenChord('V', '', 4)]), GenSection.verseA),
          isTrue);
      // ダイアトニック外のコード
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('I', '', 4), const GenChord('♭VII', '', 4)]), GenSection.verseA),
          isFalse);
      // 色づけの上限（9th は Aメロ不可、M7・m7 は可）
      expect(progressionSatisfiesSection(fake([const GenChord('I', '9', 4)]), GenSection.verseA), isFalse);
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('I', 'M7', 4), const GenChord('vi', '7', 4)]), GenSection.verseA),
          isTrue);
      // Bメロ：借用 iv は1つまで
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('I', '', 4), const GenChord('iv', '7', 4), const GenChord('V', '7', 4)]),
              GenSection.verseB),
          isTrue);
      expect(
          progressionSatisfiesSection(
              fake([const GenChord('I', '', 4), const GenChord('iv', '7', 2), const GenChord('iv', '7', 2)]),
              GenSection.verseB),
          isFalse);
      // イントロは I 始まりのみ
      expect(progressionSatisfiesSection(fake([const GenChord('vi', '', 4)]), GenSection.intro), isFalse);
      expect(progressionSatisfiesSection(fake([const GenChord('I', '', 4)]), GenSection.intro), isTrue);
      // 指定なし・サビは制約なし
      expect(progressionSatisfiesSection(fake([const GenChord('♭VI', '9', 4)]), GenSection.none), isTrue);
      expect(progressionSatisfiesSection(fake([const GenChord('♭VI', '9', 4)]), GenSection.chorus), isTrue);
    });

    test('verse A: first chord, diatonic only, plain colors, no 2-beat changes', () {
      final gen = ProgressionGenerator(rng: math.Random(42));
      for (final style in genStyles) {
        for (final bars in [4, 8]) {
          final props = gen.generate(style: style, bars: bars, section: GenSection.verseA, tries: 60);
          expect(props.length, 4, reason: '${style.id} ${bars}bars');
          for (final p in props) {
            expect(p.beats, bars * 4, reason: '${style.id} ${p.signature}');
            expect(progressionSatisfiesSection(p, GenSection.verseA), isTrue,
                reason: '${style.id} ${p.signature}');
            expect(p.chords.first.base, anyOf('I', 'vi'), reason: '${style.id} ${p.signature}');
            for (final c in p.chords) {
              expect(diatonic.contains(c.base), isTrue, reason: '${style.id} ${c.roman}');
              expect(bannedSuffixA.contains(c.suffix), isFalse, reason: '${style.id} ${c.roman}');
              expect(c.beats, greaterThanOrEqualTo(4), reason: '${style.id} ${p.signature}');
            }
          }
        }
      }
    });

    test('verse B: first chord, diatonic plus at most one borrowed iv', () {
      final gen = ProgressionGenerator(rng: math.Random(43));
      for (final style in genStyles) {
        final props = gen.generate(style: style, section: GenSection.verseB, tries: 60);
        expect(props.length, 4, reason: style.id);
        for (final p in props) {
          expect(progressionSatisfiesSection(p, GenSection.verseB), isTrue,
              reason: '${style.id} ${p.signature}');
          expect(p.chords.first.base, anyOf('I', 'vi', 'IV'), reason: '${style.id} ${p.signature}');
          expect(p.chords.where((c) => c.base == 'iv').length, lessThanOrEqualTo(1),
              reason: '${style.id} ${p.signature}');
          for (final c in p.chords) {
            expect(diatonic.contains(c.base) || c.base == 'iv', isTrue, reason: '${style.id} ${c.roman}');
            expect(bannedSuffixB.contains(c.suffix), isFalse, reason: '${style.id} ${c.roman}');
          }
        }
      }
    });

    test('intro: starts on I only, diatonic, slow changes', () {
      final gen = ProgressionGenerator(rng: math.Random(44));
      for (final style in genStyles) {
        final props = gen.generate(style: style, section: GenSection.intro, tries: 60);
        expect(props.length, 4, reason: style.id);
        for (final p in props) {
          expect(progressionSatisfiesSection(p, GenSection.intro), isTrue,
              reason: '${style.id} ${p.signature}');
          expect(p.chords.first.base, 'I', reason: '${style.id} ${p.signature}');
          for (final c in p.chords) {
            expect(diatonic.contains(c.base), isTrue, reason: '${style.id} ${c.roman}');
            expect(c.beats, greaterThanOrEqualTo(4), reason: '${style.id} ${p.signature}');
          }
        }
      }
    });

    test('chorus: still generates full proposals', () {
      final gen = ProgressionGenerator(rng: math.Random(45));
      final props = gen.generate(style: styleById('jpop'), section: GenSection.chorus, tries: 60);
      expect(props.length, 4);
      for (final p in props) {
        expect(p.beats, 16);
        expect(progressionSatisfiesSection(p, GenSection.chorus), isTrue);
      }
    });

    // 着地の型（実装側の分類と同じ物差し）
    String cadenceOf(GenProgression p) {
      final b = p.bases;
      if (b.length >= 2 && b[b.length - 2] == 'iii' && b.last == 'vi') return 'iii-vi';
      if (b.length >= 2 && b[b.length - 2] == 'IV' && b.last == 'I') return 'plagal';
      return switch (b.last) {
        'I' => 'toI',
        'vi' => 'toVi',
        'V' => 'half',
        _ => 'other',
      };
    }

    test('verse A: sus colors appear, only on major-side chords, banned suffixes stay out', () {
      final gen = ProgressionGenerator(rng: math.Random(123));
      var sus = 0;
      for (final style in genStyles) {
        for (var i = 0; i < 12; i++) {
          for (final p in gen.generate(style: style, bars: 4, section: GenSection.verseA, tries: 60)) {
            for (final c in p.chords) {
              expect(bannedSuffixA.contains(c.suffix), isFalse, reason: '${style.id} ${c.roman}');
              if (c.suffix == 'sus2' || c.suffix == 'sus4') {
                sus++;
                // sus は長調側（I・IV・V）にだけ付く。短調側（ii・iii・vi）には付かない
                expect(['I', 'IV', 'V'].contains(c.base), isTrue, reason: '${style.id} ${c.roman}');
              }
            }
          }
        }
      }
      expect(sus, greaterThan(0));
    });

    test('verse A: sus reaches styles whose color tables have none (jpop I/IV)', () {
      final gen = ProgressionGenerator(rng: math.Random(124));
      var susOnMaj = 0;
      for (var i = 0; i < 40; i++) {
        for (final p in gen.generate(style: styleById('jpop'), bars: 4, section: GenSection.verseA, tries: 60)) {
          for (final c in p.chords) {
            if ((c.base == 'I' || c.base == 'IV') && (c.suffix == 'sus2' || c.suffix == 'sus4')) susOnMaj++;
          }
        }
      }
      expect(susOnMaj, greaterThan(0));
    });

    test('second-half substitution: fires in sections, never leaks into no-section/chorus', () {
      final gen = ProgressionGenerator(rng: math.Random(125));
      var tagged = 0;
      for (var i = 0; i < 40; i++) {
        for (final p in gen.generate(style: styleById('jpop'), bars: 8, section: GenSection.verseA, tries: 60)) {
          // 置換が起きてもセクション制約と先頭は崩れない
          expect(progressionSatisfiesSection(p, GenSection.verseA), isTrue, reason: p.signature);
          expect(p.chords.first.base, anyOf('I', 'vi'), reason: p.signature);
          if (p.tags.contains('後半で代理コード')) tagged++;
        }
      }
      expect(tagged, greaterThan(0));
      final gen2 = ProgressionGenerator(rng: math.Random(126));
      for (var i = 0; i < 20; i++) {
        for (final p in gen2.generate(tries: 60)) {
          expect(p.tags.contains('後半で代理コード'), isFalse);
        }
        for (final p in gen2.generate(section: GenSection.chorus, tries: 60)) {
          expect(p.tags.contains('後半で代理コード'), isFalse);
        }
      }
    });

    test('verse A: returned proposals spread across cadence types', () {
      final gen = ProgressionGenerator(rng: math.Random(127));
      final counts = <String, int>{};
      var total = 0;
      var spreadCalls = 0;
      for (var i = 0; i < 40; i++) {
        final props = gen.generate(style: styleById('jpop'), bars: 4, section: GenSection.verseA, tries: 60);
        if (props.map(cadenceOf).toSet().length >= 3) spreadCalls++;
        for (final p in props) {
          counts[cadenceOf(p)] = (counts[cadenceOf(p)] ?? 0) + 1;
          total++;
        }
      }
      expect(counts.keys.length, greaterThanOrEqualTo(4), reason: '$counts');
      expect(counts['half']! / total, lessThan(0.45), reason: '$counts');
      expect(spreadCalls, greaterThan(20), reason: '$counts');
    });

    test('section motifs: new stock patterns seed verse A proposals', () {
      final gen = ProgressionGenerator(rng: math.Random(128));
      var hit4 = 0; // I vi IV V（どのスタイルのモチーフ表にも無い形）
      var hit6 = 0; // I V vi iii IV V で始まる形
      for (final style in genStyles) {
        for (var i = 0; i < 15; i++) {
          for (final p in gen.generate(style: style, bars: 4, section: GenSection.verseA, tries: 60)) {
            if (p.bases.length == 4 && p.bases.join(' ') == 'I vi IV V') hit4++;
          }
          for (final p in gen.generate(style: style, bars: 8, section: GenSection.verseA, tries: 60)) {
            if (p.bases.length >= 6 && p.bases.sublist(0, 6).join(' ') == 'I V vi iii IV V') hit6++;
          }
        }
      }
      expect(hit4 + hit6, greaterThan(0), reason: 'hit4=$hit4 hit6=$hit6');
    });

    test('no section: generation stays diverse (borrowings etc. still appear)', () {
      final gen = ProgressionGenerator(rng: math.Random(9));
      final bases = <String>{};
      for (var i = 0; i < 30; i++) {
        for (final p in gen.generate(tries: 60)) {
          bases.addAll(p.bases);
        }
      }
      expect(bases.intersection({'♭VII', '♭VI', 'iv', 'II', 'III'}), isNotEmpty);
    });
  });
}
