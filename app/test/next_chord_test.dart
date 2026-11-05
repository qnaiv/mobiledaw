import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/music/chords.dart';
import 'package:mobiledaw/music/progressions.dart';
import 'package:mobiledaw/music/scale.dart';

String _key(Chord c) => '${c.root}|${c.intervals.join(',')}|${c.extensions.join(',')}';

void main() {
  final cMajor = Scale.of(0, scaleKindOf('major'));
  final aMinor = Scale.of(9, scaleKindOf('minor'));

  group('Cメジャーで C のあと', () {
    final groups = nextChordSuggestions(scaleChords(cMajor)[0], cMajor);

    test('グループは王道から始まり、見出しは4分類のどれか', () {
      expect(groups.first.mood, '王道・安定');
      for (final g in groups) {
        expect(['王道・安定', '切ない', 'おしゃれ', 'ドラマチック'], contains(g.mood));
        expect(g.chords.length, inInclusiveRange(1, 3));
      }
    });

    test('王道は既存の suggestNext と同じ F・G・Am', () {
      final staple = groups.firstWhere((g) => g.mood == '王道・安定');
      expect(staple.chords.map((c) => c.root).toSet(), {5, 7, 9}); // F, G, Am
    });

    test('直前と同じコード（三和音の C）はどこにも出ない', () {
      for (final g in groups) {
        for (final c in g.chords) {
          expect(c.root == 0 && c.intervals.join(',') == '0,4,7' && c.extensions.isEmpty, isFalse,
              reason: '${g.mood} に直前の C が出ている');
        }
      }
    });

    test('候補は重複せず、ダイアトニック／借用／7th違いの範囲内', () {
      final allowed = <String>{
        for (final c in scaleChords(cMajor)) _key(c),
        for (final b in borrowedChords(cMajor)) _key(b.chord),
        for (final c in scaleChords(cMajor))
          '${c.root}|${c.intervals.join(',')}|${c.seventh}',
      };
      final seen = <String>{};
      for (final g in groups) {
        for (final c in g.chords) {
          expect(allowed, contains(_key(c)), reason: '${c.name} は候補プールの外');
          expect(seen.add(_key(c)), isTrue, reason: '${c.name} が重複している');
        }
      }
    });

    test('切ないは短和音だけ、おしゃれは7thなどの拡張つきだけ', () {
      final emo = groups.firstWhere((g) => g.mood == '切ない');
      for (final c in emo.chords) {
        expect(c.intervals[1], 3);
      }
      final stylish = groups.firstWhere((g) => g.mood == 'おしゃれ');
      for (final c in stylish.chords) {
        expect(c.extensions, isNotEmpty);
      }
    });
  });

  test('Aマイナーで Am のあとの王道は F・Dm・G（既存のマイナー表と一致）', () {
    final groups = nextChordSuggestions(scaleChords(aMinor)[0], aMinor);
    final staple = groups.firstWhere((g) => g.mood == '王道・安定');
    expect(staple.chords.map((c) => c.root).toSet(), {5, 2, 7}); // F, Dm, G
  });

  test('7thつきを置いたあと、その同じ7thコードは候補に出ない', () {
    const g7 = Chord(degree: 4, root: 7, intervals: [0, 4, 7], seventh: 10, mood: '', extensions: [10]);
    final groups = nextChordSuggestions(g7, cMajor);
    for (final g in groups) {
      for (final c in g.chords) {
        expect(_key(c) == _key(g7), isFalse);
      }
    }
  });

  test('借用コード（Fm）を置いたあとも候補が出て、王道に主和音が入る', () {
    final fm = borrowedChords(cMajor).firstWhere((b) => b.chord.root == 5 && b.chord.intervals[1] == 3).chord;
    final groups = nextChordSuggestions(fm, cMajor);
    expect(groups, isNotEmpty);
    final staple = groups.firstWhere((g) => g.mood == '王道・安定');
    expect(staple.chords.map((c) => c.root), contains(0)); // C（主和音）へ戻れる
  });

  test('何度呼んでも同じ結果（決定的）', () {
    final a = nextChordSuggestions(scaleChords(cMajor)[4], cMajor);
    final b = nextChordSuggestions(scaleChords(cMajor)[4], cMajor);
    expect(a.map((g) => (g.mood, g.chords.map(_key).join(';'))).toList(),
        b.map((g) => (g.mood, g.chords.map(_key).join(';'))).toList());
  });
}
