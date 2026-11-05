// 気分で選ぶコード進行と、サイコロで作るコード進行（画面に依存しない部分）。
// 進行は「キーの中の何番目か」をローマ数字で持ち、曲のキーに合わせて実際のコードにする。
import 'dart:math' as math;

import 'chords.dart';
import 'scale.dart';

class ProgressionPreset {
  const ProgressionPreset(this.name, this.mood, this.romans);
  final String name;
  final String mood;
  final List<String> romans; // 例：♭VI ♭VII v i（短調は主音から見た位置を ♭ で書く）
}

const minorPresets = [
  ProgressionPreset('切ない王道', '泣きのサビ', ['♭VI', '♭VII', 'v', 'i']),
  ProgressionPreset('疾走感', '前へ進む', ['i', '♭VI', '♭III', '♭VII']),
  ProgressionPreset('落ち着く', 'しっとり', ['i', 'iv', 'i', 'V']),
  ProgressionPreset('ちょい不思議', '夜っぽい', ['i', '♭II', '♭VII', 'i']),
  ProgressionPreset('盛り上げきる', '最後のサビ', ['iv', '♭VII', '♭III', '♭VI']),
  ProgressionPreset('フューチャーベース', 'きらきら切ない', ['♭VIM7', '♭VII', 'v7', 'i9']),
];

const majorPresets = [
  ProgressionPreset('王道', 'キラキラ切ない', ['IV', 'V', 'iii', 'vi']),
  ProgressionPreset('小室', '90年代の疾走', ['vi', 'IV', 'V', 'I']),
  ProgressionPreset('前向き', '明るく元気', ['I', 'V', 'vi', 'IV']),
  ProgressionPreset('落ち着く', 'やさしい', ['I', 'IV', 'I', 'V']),
  ProgressionPreset('カノン', 'ゆったり8つ', ['I', 'V', 'vi', 'iii', 'IV', 'I', 'IV', 'V']),
  ProgressionPreset('フューチャーベース', 'きらきら切ない', ['IVM7', 'V', 'iii7', 'vi9']),
];

const _numerals = {'I': 0, 'II': 1, 'III': 2, 'IV': 3, 'V': 4, 'VI': 5, 'VII': 6};
const _majorSteps = [0, 2, 4, 5, 7, 9, 11];

/// ローマ数字（♭VI、v7、IVM7、i9、ii° など）を、そのキーのコードにする。読めなければ null
Chord? chordFromRoman(String roman, Scale scale) {
  final m = RegExp(r'^([♭b#♯]?)(VII|VI|V|IV|III|II|I|vii|vi|v|iv|iii|ii|i)(°|M7|M9|7|9)?$').firstMatch(roman);
  if (m == null) return null;
  final acc = m.group(1)!;
  final numeral = m.group(2)!;
  final suffix = m.group(3) ?? '';
  final degree = _numerals[numeral.toUpperCase()]!;
  var semis = _majorSteps[degree];
  if (acc == '♭' || acc == 'b') semis -= 1;
  if (acc == '#' || acc == '♯') semis += 1;
  final minorQuality = numeral == numeral.toLowerCase();
  final dim = suffix == '°';
  final intervals = dim ? [0, 3, 6] : (minorQuality ? [0, 3, 7] : [0, 4, 7]);
  final ext = switch (suffix) {
    'M7' => [11],
    'M9' => [11, 14],
    '7' => [10],
    '9' => [10, 14],
    _ => <int>[],
  };
  return Chord(
    degree: -1,
    root: (scale.root + semis) % 12,
    intervals: intervals,
    seventh: 10,
    mood: '',
    extensions: ext,
  );
}

/// 借用コード（キーの外だけど、そのスケールで定番の味付けになるコード）
class BorrowedChord {
  const BorrowedChord(this.chord, this.origin);

  final Chord chord;

  /// 由来（「並行マイナーから」など）
  final String origin;
}

/// スケールごとの借用コードの定番（度数表記、由来。由来はボタンに出るので短く）
const _borrowedSpecs = <String, List<(String, String)>>{
  'major': [
    ('iv', 'マイナーから'),
    ('♭VII', 'ミクソから'),
    ('II7', 'V/V'),
    ('III7', 'V/vi'),
  ],
  'minor': [
    ('V7', 'ハーモニック'),
    ('IV', 'ドリアンから'),
    ('II7', 'V/V'),
    ('♭II', 'フリジアン'),
  ],
  'dorian': [
    ('V7', 'ハーモニック'),
    ('I7', 'ドミナント化'),
    ('iv', 'マイナーから'),
  ],
  'mixolydian': [
    ('♭III', 'マイナーから'),
    ('iv', 'マイナーから'),
    ('II7', 'V/V'),
    ('V7', 'メジャーから'),
  ],
  'harmonicMinor': [
    ('IV', 'ドリアンから'),
    ('ii7', 'ドリアンから'),
    ('♭II', 'フリジアン'),
  ],
};

/// そのスケールで使える借用コード。ペンタトニックは親スケールのものを出す
List<BorrowedChord> borrowedChords(Scale scale) {
  final kind = scale.kind;
  final specs = _borrowedSpecs[kind.parentId ?? kind.id] ?? const <(String, String)>[];
  final out = <BorrowedChord>[];
  for (final (roman, origin) in specs) {
    final c = chordFromRoman(roman, scale);
    if (c == null) continue;
    out.add(BorrowedChord(
      Chord(
        degree: -1,
        root: c.root,
        intervals: c.intervals,
        seventh: c.seventh,
        mood: c.mood,
        extensions: c.extensions,
        roman: roman,
      ),
      origin,
    ));
  }
  return out;
}

/// 次のコードの候補（雰囲気のグループ分け）。コードモードで1個ずつ置くときのサジェスト用
class NextChordGroup {
  const NextChordGroup(this.mood, this.chords);

  /// グループの見出し（王道・安定／切ない／おしゃれ／ドラマチック）
  final String mood;

  /// 候補（1〜3個）
  final List<Chord> chords;
}

/// コードの構成音（音名の集合、0〜11）
Set<int> _pcSetOf(Chord c) => {
      for (final i in c.intervals) (c.root + i) % 12,
      for (final e in c.extensions) (c.root + e) % 12,
    };

String _chordKey(Chord c) => '${c.root}|${c.intervals.join(',')}|${c.extensions.join(',')}';

/// [previous] の次に自然に続くコードを、雰囲気ごとに数個ずつ返す（コードモードの単発サジェスト）。
/// 候補プールはそのスケールのダイアトニック＋借用コード＋ダイアトニックの7th違いで、
/// 直前と同じコードは出さない。グループ間で重複したら前のグループを優先する。
/// 並びはボイスリーディングの滑らかさ（共通音の多さと各音の移動量）で決める
List<NextChordGroup> nextChordSuggestions(Chord previous, Scale scale) {
  final diatonic = scaleChords(scale);
  final borrowed = borrowedChords(scale);
  final prevPcs = _pcSetOf(previous);

  bool isPrevious(Chord c) {
    final pcs = _pcSetOf(c);
    return pcs.length == prevPcs.length && pcs.containsAll(prevPcs);
  }

  bool isMinor(Chord c) => c.intervals.length > 1 && c.intervals[1] == 3;
  bool isDiminished(Chord c) => c.intervals.length > 2 && c.intervals[1] == 3 && c.intervals[2] == 6;

  // 滑らかさ（小さいほど滑らか）。共通音は1つあたり 2 引いて優遇する
  int vlCost(Chord c) {
    final pcs = _pcSetOf(c);
    var cost = 0;
    for (final pc in pcs) {
      var best = 6;
      for (final q in prevPcs) {
        final d = (pc - q).abs();
        best = math.min(best, math.min(d, 12 - d));
      }
      cost += best;
    }
    return cost - pcs.intersection(prevPcs).length * 2;
  }

  List<Chord> smooth(Iterable<Chord> pool) {
    final list = pool.toList();
    list.sort((a, b) {
      final byCost = vlCost(a).compareTo(vlCost(b));
      return byCost != 0 ? byCost : a.root.compareTo(b.root);
    });
    return list;
  }

  // 7th違い（三和音にそのコードの7度を足した形）
  Chord seventhOf(Chord c) => Chord(
        degree: c.degree,
        root: c.root,
        intervals: c.intervals,
        seventh: c.seventh,
        mood: c.mood,
        extensions: [c.seventh],
        roman: c.roman,
      );

  final prevPos = previous.degree >= 0 && previous.degree < diatonic.length
      ? (diatonic[previous.degree].root == previous.root ? previous.degree : -1)
      : -1;

  final groups = <NextChordGroup>[];
  final used = <String>{};
  void addGroup(String mood, List<Chord> candidates, int max) {
    final picked = <Chord>[];
    for (final c in candidates) {
      if (picked.length >= max) break;
      if (isPrevious(c)) continue;
      if (!used.add(_chordKey(c))) continue;
      picked.add(c);
    }
    if (picked.isNotEmpty) groups.add(NextChordGroup(mood, picked));
  }

  // 王道・安定：既存の「次に合うコード」の並びをそのまま使う。直前が借用コードなら主音と属和音へ
  if (prevPos >= 0) {
    addGroup('王道・安定', [for (final pos in suggestNextForScale(scale, prevPos)) diatonic[pos]], 3);
  } else {
    final tonic = diatonic.where((c) => c.root == scale.root);
    final dominant = diatonic.where((c) => c.root == (scale.root + 7) % 12 && !isMinor(c));
    addGroup('王道・安定', [...tonic, ...dominant], 3);
  }

  // 切ない：短和音を、雰囲気が「切ない」ものを先に、滑らかな順で
  final minorPool = smooth([
    ...diatonic.where(isMinor),
    for (final b in borrowed) if (isMinor(b.chord)) b.chord,
  ]);
  minorPool.sort((a, b) {
    final byMood = (b.mood == '切ない' ? 1 : 0).compareTo(a.mood == '切ない' ? 1 : 0);
    return byMood != 0 ? byMood : vlCost(a).compareTo(vlCost(b));
  });
  addGroup('切ない', minorPool, 2);

  // おしゃれ：7thを足した形と、拡張のある借用コードを滑らかな順で
  addGroup(
      'おしゃれ',
      smooth([
        for (final c in diatonic) if (!c.extensions.any((e) => e % 12 == c.seventh % 12)) seventhOf(c),
        for (final b in borrowed) if (b.chord.extensions.isNotEmpty) b.chord,
      ]),
      3);

  // ドラマチック：減和音・属和音（7th含む）・緊張感のある借用（二次ドミナント、♭II、ハーモニック由来）
  const dramaticOrigins = {'ハーモニック', 'フリジアン', 'V/V', 'V/vi'};
  addGroup(
      'ドラマチック',
      smooth([
        ...diatonic.where(isDiminished),
        ...diatonic.where((c) => c.root == (scale.root + 7) % 12 && !isMinor(c) && !isDiminished(c)),
        for (final c in diatonic)
          if (c.root == (scale.root + 7) % 12 && !isMinor(c)) seventhOf(c),
        for (final b in borrowed)
          if (dramaticOrigins.contains(b.origin) || b.chord.roman.startsWith('♭II')) b.chord,
      ]),
      2);

  return groups;
}

/// 進行のコードを、なめらかにつながる高さで並べる（1つ目は [center] のあたり、2つ目からは前のコードに寄せる）
List<List<int>> voiceProgression(List<Chord> chords, {int center = 60}) {
  final out = <List<int>>[];
  for (final c in chords) {
    if (out.isEmpty) {
      out.add(c.pitchesNear(center));
      continue;
    }
    // 根音の位置を変えた候補から、前のコードとの距離が一番小さいものを選ぶ
    final prev = out.last;
    final prevCenter = prev.reduce((a, b) => a + b) / prev.length;
    List<int>? best;
    var bestCost = double.infinity;
    for (var near = center - 12; near <= center + 12; near++) {
      final cand = c.pitchesNear(near);
      for (var inv = 0; inv < cand.length; inv++) {
        final v = [...cand];
        for (var k = 0; k < inv; k++) {
          v.sort();
          v[0] += 12;
        }
        v.sort();
        final cost = (v.reduce((a, b) => a + b) / v.length - prevCenter).abs() + (v.first - prev.first).abs() * 0.3;
        if (cost < bestCost && v.first >= 36 && v.last <= 96) {
          bestCost = cost;
          best = v;
        }
      }
    }
    out.add(best ?? c.pitchesNear(center));
  }
  return out;
}

/// サイコロで4つのコードを作る（キーの中の番号）。[locked] の null でない所はそのまま残す。
/// [brightness] 0〜1：明るい（長三和音）を選びやすく。[surprise] 0〜1：おすすめの2位・3位やそれ以外も選びやすく
List<int> rollProgression({
  required bool minor,
  required double brightness,
  required double surprise,
  required List<int?> locked,
  required math.Random rng,
  required List<Chord> chords,
}) {
  final out = <int>[];
  bool isMajor(int d) => chords[d].intervals[1] == 4;
  bool isDim(int d) => chords[d].intervals[2] == 6;
  double tone(int d) => isMajor(d) ? 0.5 + brightness : 1.5 - brightness;

  int pick(Map<int, double> weights) {
    final total = weights.values.fold(0.0, (a, b) => a + b);
    var r = rng.nextDouble() * total;
    for (final e in weights.entries) {
      r -= e.value;
      if (r <= 0) return e.key;
    }
    return weights.keys.last;
  }

  for (var i = 0; i < locked.length; i++) {
    final fixed = locked[i];
    if (fixed != null) {
      out.add(fixed);
      continue;
    }
    final weights = <int, double>{};
    if (i == 0) {
      // 始まりは落ち着くコードか、広がるコード
      weights[0] = 1.0 * tone(0);
      weights[minor ? 5 : 3] = 0.8 * tone(minor ? 5 : 3);
      if (surprise > 0.5) weights[minor ? 3 : 5] = surprise * tone(minor ? 3 : 5);
    } else {
      final next = suggestNext(out[i - 1], minor: minor);
      final base = [0.6 - 0.35 * surprise, 0.25 + 0.1 * surprise, 0.15 + 0.1 * surprise];
      for (var k = 0; k < next.length; k++) {
        weights[next[k]] = (weights[next[k]] ?? 0) + base[k] * tone(next[k]);
      }
      // 意外さが高いほど、おすすめ以外も少し混ぜる
      for (var d = 0; d < 7; d++) {
        if (weights.containsKey(d) || d == out[i - 1]) continue;
        if (isDim(d) && surprise < 0.7) continue;
        weights[d] = 0.15 * surprise * tone(d);
      }
    }
    weights.removeWhere((_, w) => w <= 0);
    out.add(weights.isEmpty ? 0 : pick(weights));
  }
  return out;
}
