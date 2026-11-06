// コード進行を作る（設計：バックログ「進行選びの強化」）。押すたびに違う進行になるよう、
// いくつもの「ゆらぎ」を重ねて数百通り作り、点数の高いものから形の違う案を選ぶ。
//
//  1. コードの変わる間隔（1小節に1つ・2拍ずつ・最後だけ2つ・2小節伸ばす…）をランダムに
//  2. スタイルのお決まりの並び（モチーフ）を、ずらしたり途中から使ったりして種にする
//  3. 残りは「次に来やすいコード」の表（一般のつながり × スタイルの好み）で、前の2つを見ながら選ぶ。
//     選ぶときの「ばらつき」も毎回変える
//  4. 8小節なら「前半＋変化した後半」か「最後まで別の流れ」
//  5. 色づけ（M7・9th・sus4・add9 など）をスタイルの好みで
//  6. 味付け（ドミナントで次へ押す・sus4 で溜める・短調から借りる iv・経過の dim・代理）をランダムに
//  7. 前後（直前のコード・このあとのコード・ループの頭）へのつながり、繰り返しの少なさ、
//     最近出した案との違いで点数をつけ、形の違う案を選ぶ
//
// セクション（Aメロ・Bメロ・サビ・イントロ）を指定すると、その役割に合う制約を上乗せする：
// 先頭コードや使えるコード・色づけを絞り、モチーフは頭からだけ使い、味付けを止め、
// 最後に制約チェック（progressionSatisfiesSection）で違反した案を候補から外す。
// 制約で画一的にならないよう、多様性は別の軸で戻す：セクション専用の種（モチーフ）、
// 返す案の着地の型の分散、フレーズ後半だけの代理置換、sus の解禁（長調側のみ）。
// 「指定なし」は従来の生成そのまま（制約オブジェクトを使わない経路を通る）。
//
// コードはすべて「長調の中での位置（ローマ数字）」で持つ。短調の曲は平行調（短3度上の長調）として扱う
// （C minor の i は E♭ major の vi）。画面に出すときにキーの音名にする。
import 'dart:math' as math;

import 'chords.dart';
import 'scale.dart';

// ---- コード（ローマ数字）-------------------------------------------------------------

/// 長調の中での位置。例：IV, vi, ♭VII, iv, II（= V/V）, III（= V/vi）
/// [suffix] は色づけ：'' M7 M9 6 69 add9 sus2 sus4 7 9 7sus4 m7 m9 m11 madd9 ° ø °7
class GenChord {
  const GenChord(this.base, this.suffix, this.beats);

  final String base;
  final String suffix;
  final int beats; // 長さ（拍）

  GenChord withBeats(int b) => GenChord(base, suffix, b);
  GenChord withSuffix(String s) => GenChord(base, s, beats);

  String get roman => '$base$suffix';

  @override
  bool operator ==(Object other) =>
      other is GenChord && other.base == base && other.suffix == suffix && other.beats == beats;

  @override
  int get hashCode => Object.hash(base, suffix, beats);

  @override
  String toString() => '$roman:$beats';
}

const _numeralSemis = {'I': 0, 'II': 2, 'III': 4, 'IV': 5, 'V': 7, 'VI': 9, 'VII': 11};

/// base の根音（長調の主音からの半音）と、短和音・減和音か
({int semis, bool minor, bool dim})? parseBase(String base) {
  final m = RegExp(r'^([♭♯#b]?)(VII|VI|V|IV|III|II|I|vii|vi|v|iv|iii|ii|i)(°)?$').firstMatch(base);
  if (m == null) return null;
  var semis = _numeralSemis[m.group(2)!.toUpperCase()]!;
  final acc = m.group(1)!;
  if (acc == '♭' || acc == 'b') semis -= 1;
  if (acc == '♯' || acc == '#') semis += 1;
  final numeral = m.group(2)!;
  final dim = m.group(3) != null;
  return (semis: (semis + 12) % 12, minor: numeral == numeral.toLowerCase(), dim: dim);
}

/// 色づけ → 根音からの音（3和音の部分と、足す音）と表示名
({List<int> triad, List<int> ext, String symbol}) _quality(bool minor, bool dim, String suffix) {
  if (dim || suffix == '°' || suffix == 'ø' || suffix == '°7') {
    return switch (suffix) {
      'ø' => (triad: [0, 3, 6], ext: [10], symbol: 'm7♭5'),
      '°7' => (triad: [0, 3, 6], ext: [9], symbol: 'dim7'),
      _ => (triad: [0, 3, 6], ext: <int>[], symbol: 'dim'),
    };
  }
  if (minor) {
    return switch (suffix) {
      '7' || 'm7' => (triad: [0, 3, 7], ext: [10], symbol: 'm7'),
      '9' || 'm9' => (triad: [0, 3, 7], ext: [10, 14], symbol: 'm9'),
      '11' || 'm11' => (triad: [0, 3, 7], ext: [10, 14, 17], symbol: 'm11'),
      'add9' || 'madd9' => (triad: [0, 3, 7], ext: [14], symbol: 'm(add9)'),
      '6' => (triad: [0, 3, 7], ext: [9], symbol: 'm6'),
      'M7' => (triad: [0, 3, 7], ext: [11], symbol: 'mM7'),
      _ => (triad: [0, 3, 7], ext: <int>[], symbol: 'm'),
    };
  }
  return switch (suffix) {
    'M7' => (triad: [0, 4, 7], ext: [11], symbol: 'M7'),
    'M9' => (triad: [0, 4, 7], ext: [11, 14], symbol: 'M9'),
    '6' => (triad: [0, 4, 7], ext: [9], symbol: '6'),
    '69' => (triad: [0, 4, 7], ext: [9, 14], symbol: '6/9'),
    'add9' => (triad: [0, 4, 7], ext: [14], symbol: 'add9'),
    'sus2' => (triad: [0, 2, 7], ext: <int>[], symbol: 'sus2'),
    'sus4' => (triad: [0, 5, 7], ext: <int>[], symbol: 'sus4'),
    '7sus4' => (triad: [0, 5, 7], ext: [10], symbol: '7sus4'),
    '7' => (triad: [0, 4, 7], ext: [10], symbol: '7'),
    '9' => (triad: [0, 4, 7], ext: [10, 14], symbol: '9'),
    _ => (triad: [0, 4, 7], ext: <int>[], symbol: ''),
  };
}

/// [majorRoot] の長調でのコード（ピアノロールに置ける形）。読めなければ null
Chord? realize(GenChord c, int majorRoot) {
  final b = parseBase(c.base);
  if (b == null) return null;
  final q = _quality(b.minor, b.dim, c.suffix);
  return Chord(
    degree: -1,
    root: (majorRoot + b.semis) % 12,
    intervals: q.triad,
    seventh: 10,
    mood: '',
    extensions: q.ext,
  );
}

/// 画面に出す名前（例：B♭M7、Cm9、G7sus4）
String chordName(GenChord c, int majorRoot) {
  final b = parseBase(c.base);
  if (b == null) return c.roman;
  return '${noteName((majorRoot + b.semis) % 12)}${_quality(b.minor, b.dim, c.suffix).symbol}';
}

/// 置いてあるコード（[analyzeChord] の結果）を、長調 [majorRoot] の中の位置にする
String baseOf(ChordInfo info, int majorRoot) {
  const names = ['I', '♭II', 'II', '♭III', 'III', 'IV', '♯IV', 'V', '♭VI', 'VI', '♭VII', 'VII'];
  final semis = (info.root - majorRoot + 12) % 12;
  final s = info.suffix;
  final dim = s.startsWith('°') || s.contains('♭5') || s.startsWith('dim');
  final minor = dim || (s.startsWith('m') && !s.startsWith('M'));
  final n = names[semis];
  if (!minor) return n;
  final lower = n.replaceAllMapped(RegExp('[IV]+'), (m) => m[0]!.toLowerCase());
  return dim ? '$lower°' : lower;
}

// ---- つながりの表 ----------------------------------------------------------------------

/// 一般的な「次に来やすいコード」（長調の中で。ポップスでよく使う借用和音・ドミナントも含む）
const Map<String, Map<String, double>> _flow = {
  'I': {'ii': .8, 'iii': .5, 'IV': 1.2, 'V': 1.0, 'vi': 1.0, '♭VII': .3, '♭VI': .2, 'iv': .15, 'II': .25, 'III': .25, 'I': .05},
  'ii': {'V': 1.3, 'IV': .4, 'iii': .5, 'I': .3, 'vi': .3, '♭VII': .2, 'II': .1, 'vii°': .1},
  'iii': {'vi': 1.2, 'IV': 1.0, 'ii': .5, 'I': .2, 'III': .15, 'V': .2},
  'IV': {'V': 1.3, 'I': .8, 'iii': .7, 'vi': .6, 'ii': .4, 'iv': .5, '♭VII': .4, 'II': .2, 'III': .3},
  'V': {'I': 1.2, 'vi': 1.0, 'IV': .6, 'iii': .4, 'ii': .2, '♭VI': .25, 'III': .15},
  'vi': {'IV': 1.2, 'ii': .6, 'V': .7, 'iii': .5, 'I': .4, '♭VII': .2, 'III': .3, '♭VI': .1},
  'vii°': {'I': 1.0, 'iii': .6, 'vi': .3},
  '♭VII': {'I': 1.0, 'IV': .6, 'V': .3, 'vi': .4, '♭VI': .3, 'iv': .2},
  '♭VI': {'♭VII': 1.2, 'V': .6, 'I': .4, 'IV': .3, 'iv': .2},
  'iv': {'I': 1.0, 'V': .5, '♭VII': .4, 'vi': .2, 'iii': .2},
  'II': {'V': 1.0, 'IV': .5, 'ii': .2},
  'III': {'vi': 1.2, 'IV': .5, 'ii': .2},
  'VI': {'ii': 1.0, 'V': .3, 'IV': .3},
  '♭III': {'IV': .6, '♭VI': .5, '♭VII': .5, 'ii': .2},
  'v': {'I': .4, 'IV': .6, 'vi': .5, '♭VI': .3},
};

/// 表にないコード（置いてあったコードなど）から次へ
const Map<String, double> _fallbackFlow = {'I': .8, 'IV': 1.0, 'V': .8, 'vi': .8, 'ii': .5, 'iii': .4};

double flowWeight(String from, String to) => (_flow[from] ?? _fallbackFlow)[to] ?? 0.0;

// ---- セクション ------------------------------------------------------------------------

/// 進行の役割。生成の制約の強さが変わる（[GenSection.none] は従来どおり制約なし）
enum GenSection {
  none('指定なし'),
  verseA('Aメロ'),
  verseB('Bメロ'),
  chorus('サビ'),
  intro('イントロ');

  const GenSection(this.label);
  final String label;
}

/// セクションごとの制約（null の項目は制限なし）。コードはすべて長調換算のローマ数字
class _SectionRules {
  const _SectionRules({
    this.first,
    this.bases,
    this.maxIv,
    this.suffixes,
    this.headMotifOnly = false,
    this.noSeasoning = false,
    this.borrowOnlySeasoning = false,
    this.noSplit = false,
    this.longBoost = 0.0,
    this.preferFirst,
    this.preferLastDominant = false,
  });

  final Set<String>? first; // 先頭コードの許可
  final Set<String>? bases; // 使えるコード（全体）
  final int? maxIv; // 借用 iv の上限（bases に無くてもこの数まで許可）
  final Map<String, Set<String>>? suffixes; // 色づけの許可（_color の kind ごと）
  final bool headMotifOnly; // モチーフをずらさず・途中から使わず、頭からだけ置く
  final bool noSeasoning; // 味付け（代理・借用・押し出し・sus・dim）を全部止める
  final bool borrowOnlySeasoning; // 味付けは借用 iv だけ残す
  final bool noSplit; // 小節の中の分割（2拍刻み・3+1）を出さない
  final double longBoost; // 2小節伸ばす確率の下限
  final Set<String>? preferFirst; // 先頭がこれならスコア加点（サビ）
  final bool preferLastDominant; // 最後が V ならスコア加点（Bメロ）
}

/// ダイアトニック（長調換算）。vii° は減和音なのでセクション制約では使わない
const _diatonicPlain = {'I', 'ii', 'iii', 'IV', 'V', 'vi'};

/// Aメロ・イントロの色づけ：トライアド中心（M7・m7・add9 まで。9th・11th・dim 系は出さない）
/// sus2・sus4 は「溜める」地味な色として長調側（maj・dom）にだけ入れる。短調側（min）は
/// [_quality] に sus の形が無く（渡すと素の短和音に落ちて、表示名と食い違う）ため許可しない
const _suffixesVerseA = <String, Set<String>>{
  'maj': {'', 'M7', 'add9', 'sus2', 'sus4'},
  'min': {'', '7', 'add9'},
  'dom': {'', '7', 'sus2', 'sus4', '7sus4'},
  'sec': {'7'},
};

/// Bメロの色づけ：Aメロより少し自由（M9・9・6 まで。11th・dim 系は出さない）
const _suffixesVerseB = <String, Set<String>>{
  'maj': {'', 'M7', 'M9', 'add9', '6', 'sus2', 'sus4'},
  'min': {'', '7', '9', 'add9'},
  'dom': {'', '7', 'sus2', 'sus4', '7sus4'},
  'sec': {'7', '9'},
};

/// セクション指定時だけ種に足す定番の型（生成時にセクションの制約に合うものだけが
/// スタイルのモチーフへ混ざる）。すべてダイアトニックで、先頭は Aメロ（I/vi）・
/// Bメロ（I/vi/IV）・イントロ（I）の各制約に収まる。「指定なし」の生成には一切使わない
const _sectionMotifs = <List<String>>[
  // Aメロ向け：頭が I/vi の定番
  ['I', 'vi', 'IV', 'V'],
  ['I', 'iii', 'IV', 'V'],
  ['I', 'IV', 'vi', 'V'],
  ['vi', 'IV', 'ii', 'V'],
  ['vi', 'iii', 'IV', 'V'],
  ['I', 'V', 'vi', 'iii', 'IV', 'V'],
  // Bメロ向け：V で着地してサビへ押す型
  ['IV', 'iii', 'ii', 'V'],
  ['I', 'IV', 'ii', 'V'],
];

_SectionRules? _rulesFor(GenSection section) => switch (section) {
      GenSection.none => null,
      GenSection.verseA => const _SectionRules(
          first: {'I', 'vi'},
          bases: _diatonicPlain,
          suffixes: _suffixesVerseA,
          headMotifOnly: true,
          noSeasoning: true,
          noSplit: true,
        ),
      GenSection.verseB => const _SectionRules(
          first: {'I', 'vi', 'IV'},
          bases: _diatonicPlain,
          maxIv: 1,
          suffixes: _suffixesVerseB,
          headMotifOnly: true,
          borrowOnlySeasoning: true,
          preferLastDominant: true,
        ),
      // サビは従来の自由な生成のまま。先頭が IV・I の案をスコアで少し優先するだけ
      GenSection.chorus => const _SectionRules(preferFirst: {'IV', 'I'}),
      GenSection.intro => const _SectionRules(
          first: {'I'},
          bases: _diatonicPlain,
          suffixes: _suffixesVerseA,
          headMotifOnly: true,
          noSeasoning: true,
          noSplit: true,
          longBoost: 0.3,
        ),
    };

/// コードの種類（色づけの表を引くための分類。[_color] と同じ振り分け）
String _kindOf(String base) {
  final b = parseBase(base);
  if (b == null || b.dim) return 'dim';
  if (b.minor) return 'min';
  if (base == 'V') return 'dom';
  if (base == 'II' || base == 'III' || base == 'VI' || base == 'VII') return 'sec';
  return 'maj';
}

/// その案がセクションの制約（先頭・使えるコード・借用 iv の数・色づけ）を満たすか。
/// リズム（2拍刻みの有無）は生成の段階で担保するので、ここでは見ない
bool progressionSatisfiesSection(GenProgression p, GenSection section) {
  final rules = _rulesFor(section);
  if (rules == null) return true;
  if (p.chords.isEmpty) return false;
  if (rules.first != null && !rules.first!.contains(p.chords.first.base)) return false;
  var ivs = 0;
  for (var i = 0; i < p.chords.length; i++) {
    final c = p.chords[i];
    if (c.base == 'iv' && rules.maxIv != null) {
      ivs++;
    } else if (rules.bases != null && !rules.bases!.contains(c.base)) {
      return false;
    }
    final suffixes = rules.suffixes;
    if (suffixes != null) {
      final kind = _kindOf(c.base);
      if (kind == 'dim') return false;
      final allow = suffixes[kind];
      if (allow != null && !allow.contains(c.suffix)) return false;
    }
  }
  if (rules.maxIv != null && ivs > rules.maxIv!) return false;
  return true;
}

// ---- スタイル --------------------------------------------------------------------------

class GenStyle {
  const GenStyle({
    required this.id,
    required this.name,
    required this.mood,
    required this.bias,
    required this.motifs,
    required this.colors,
    this.split = .2,
    this.splitLast = .3,
    this.longChord = .05,
    this.secondary = .25,
    this.sus = .2,
    this.borrow = .2,
    this.passingDim = .05,
    this.substitute = .15,
    this.minorTonic = false,
  });

  final String id, name, mood;

  /// そのコードへ行きやすくする倍率（無いものは 1）
  final Map<String, double> bias;

  /// お決まりの並び（種）
  final List<List<String>> motifs;

  /// 色づけの好み：長三和音 'maj'・短三和音 'min'・V 'dom'・ドミナント（II・III・VI・I7 など）'sec'
  final Map<String, Map<String, double>> colors;

  final double split; // 1小節を2拍ずつにする確率
  final double splitLast; // 最後の小節だけ2つにする確率
  final double longChord; // 2小節伸ばす確率
  final double secondary; // 次のコードの前にドミナントを挟む確率
  final double sus; // V を sus4 → V にする確率
  final double borrow; // 2回目の IV を iv（短調から借りる）にする確率
  final double passingDim; // 経過の dim を挟む確率
  final double substitute; // 代理（I↔vi・IV↔ii など）にする確率
  final bool minorTonic; // 暗めのスタイル（vi を主役に）
}

const _triadish = {'': .7, 'add9': .15, 'sus2': .05, 'M7': .1};

const genStyles = <GenStyle>[
  GenStyle(
    id: 'future-bass',
    name: 'フューチャーベース',
    mood: 'きらきら切ない・厚い',
    bias: {'IV': 1.5, 'iii': 1.3, 'vi': 1.3, 'V': 1.2, 'iv': 1.4, 'II': 1.1, 'III': 1.2, '♭VII': .9},
    motifs: [
      ['IV', 'V', 'iii', 'vi'], ['IV', 'V', 'vi'], ['vi', 'IV', 'I', 'V'], ['IV', 'iv', 'I'],
      ['ii', 'V', 'iii', 'vi'], ['IV', 'V', 'III', 'vi'], ['IV', 'I', 'V', 'vi'], ['vi', 'V', 'IV', 'V'],
      ['IV', 'V', 'I', 'vi'], ['ii', 'iii', 'IV', 'V'],
    ],
    colors: {
      'maj': {'M7': .45, 'add9': .25, '': .15, '6': .05, 'M9': .1},
      'min': {'7': .35, '9': .35, '': .15, '11': .15},
      'dom': {'': .3, 'sus4': .25, '7': .15, '7sus4': .15, '9': .15},
      'sec': {'7': .7, '9': .3},
    },
    split: .15,
    splitLast: .45,
    secondary: .3,
    sus: .3,
    borrow: .35,
  ),
  GenStyle(
    id: 'kawaii',
    name: 'kawaii フューチャーベース',
    mood: '明るい・キュート',
    bias: {'IV': 1.6, 'V': 1.4, 'iii': 1.2, 'vi': 1.2, 'II': 1.2, 'III': 1.4, 'I': 1.1},
    motifs: [
      ['IV', 'V', 'iii', 'vi'], ['IV', 'V', 'I'], ['IV', 'III', 'vi'], ['ii', 'V', 'I'],
      ['I', 'III', 'IV', 'iv'], ['IV', 'V', 'iii', 'vi', 'ii', 'V', 'I'], ['I', 'V', 'vi', 'iii', 'IV', 'I', 'IV', 'V'],
      ['vi', 'IV', 'V', 'I'], ['IV', 'II', 'V', 'I'],
    ],
    colors: {
      'maj': {'add9': .35, '': .3, 'M7': .25, '6': .1},
      'min': {'7': .4, '': .4, '9': .2},
      'dom': {'sus4': .35, '': .35, '7': .3},
      'sec': {'7': 1.0},
    },
    split: .3,
    splitLast: .5,
    secondary: .4,
    sus: .4,
    borrow: .3,
    passingDim: .08,
  ),
  GenStyle(
    id: 'jpop',
    name: 'J-POP',
    mood: '王道・小室・カノン系',
    bias: {'IV': 1.3, 'V': 1.2, 'vi': 1.3, 'iii': 1.1},
    motifs: [
      ['IV', 'V', 'iii', 'vi'], ['vi', 'IV', 'V', 'I'], ['I', 'V', 'vi', 'iii', 'IV', 'I', 'IV', 'V'],
      ['IV', 'V', 'iii', 'vi', 'ii', 'V', 'I'], ['I', 'V', 'vi', 'IV'], ['vi', 'IV', 'V', 'iii', 'vi'],
      ['IV', 'V', 'vi', 'I'], ['ii', 'V', 'I', 'vi'],
    ],
    colors: {
      'maj': {'': .6, 'M7': .2, 'add9': .2},
      'min': {'': .55, '7': .45},
      'dom': {'': .5, '7': .3, 'sus4': .2},
      'sec': {'7': 1.0},
    },
    split: .25,
    splitLast: .35,
    secondary: .3,
  ),
  GenStyle(
    id: 'anison',
    name: 'アニソン疾走',
    mood: '速い・熱い',
    bias: {'vi': 1.3, 'IV': 1.3, 'V': 1.3, '♭VI': 1.2, '♭VII': 1.3, 'III': 1.2},
    motifs: [
      ['vi', 'IV', 'V', 'I'], ['IV', 'V', 'vi'], ['ii', 'V', 'iii', 'vi'], ['♭VI', '♭VII', 'I'],
      ['vi', 'IV', 'V', 'III'], ['IV', 'V', 'iii', 'vi', '♭VI', '♭VII', 'I'],
    ],
    colors: {
      'maj': {'': .65, 'add9': .2, 'M7': .15},
      'min': {'': .6, '7': .4},
      'dom': {'': .5, 'sus4': .3, '7': .2},
      'sec': {'7': 1.0},
    },
    split: .45,
    splitLast: .5,
    secondary: .4,
    sus: .25,
  ),
  GenStyle(
    id: 'lofi',
    name: 'Lo-fi',
    mood: 'まったり・ジャジー',
    bias: {'ii': 1.5, 'V': 1.1, 'I': 1.1, 'iii': 1.2, 'vi': 1.2, 'IV': 1.2, 'iv': 1.3, 'II': 1.2, 'III': 1.3},
    motifs: [
      ['ii', 'V', 'I'], ['IV', 'iii', 'ii', 'I'], ['vi', 'ii', 'V', 'I'], ['I', 'vi', 'ii', 'V'],
      ['IV', 'iv', 'iii', 'vi'], ['ii', 'V', 'iii', 'vi'], ['I', 'III', 'vi', 'II', 'ii', 'V'],
    ],
    colors: {
      'maj': {'M7': .45, 'M9': .35, '69': .1, '6': .1},
      'min': {'9': .45, '7': .35, '11': .2},
      'dom': {'9': .4, '7': .3, '7sus4': .3},
      'sec': {'7': .5, '9': .5},
    },
    split: .3,
    splitLast: .35,
    secondary: .45,
    passingDim: .15,
    substitute: .25,
  ),
  GenStyle(
    id: 'edm',
    name: 'EDM / ハウス',
    mood: 'ループ・高揚',
    bias: {'vi': 1.4, 'IV': 1.3, 'I': 1.2, 'V': 1.2},
    motifs: [
      ['vi', 'IV', 'I', 'V'], ['I', 'V', 'vi', 'IV'], ['IV', 'I', 'V', 'vi'], ['vi', 'V', 'IV', 'V'],
      ['vi', 'IV', 'V', 'V'], ['IV', 'V', 'vi', 'vi'],
    ],
    colors: {'maj': _triadish, 'min': {'': .7, '7': .3}, 'dom': {'': .6, 'sus4': .25, 'sus2': .15}, 'sec': {'7': 1.0}},
    split: .08,
    splitLast: .2,
    longChord: .12,
    secondary: .1,
    sus: .15,
    borrow: .1,
    substitute: .08,
  ),
  GenStyle(
    id: 'citypop',
    name: 'シティポップ',
    mood: 'おしゃれ・夜の街',
    bias: {'IV': 1.4, 'III': 1.6, 'vi': 1.2, 'ii': 1.3, 'II': 1.2, 'iii': 1.2, '♭VII': 1.1},
    motifs: [
      ['IV', 'III', 'vi', 'V'], ['IV', 'iii', 'ii', 'I'], ['ii', 'V', 'iii', 'vi'], ['IV', 'V', 'iii', 'vi'],
      ['IV', 'III', 'vi', 'I'], ['ii', 'III', 'vi', 'vi'], ['IV', '♭VII', 'iii', 'vi'],
    ],
    colors: {
      'maj': {'M7': .5, 'M9': .3, '6': .1, '69': .1},
      'min': {'7': .45, '9': .4, '11': .15},
      'dom': {'7': .35, '9': .35, '7sus4': .3},
      'sec': {'7': .6, '9': .4},
    },
    split: .3,
    splitLast: .4,
    secondary: .4,
    passingDim: .1,
    substitute: .2,
  ),
  GenStyle(
    id: 'rnb',
    name: 'R&B / ネオソウル',
    mood: 'スムース・大人',
    bias: {'ii': 1.4, 'iii': 1.3, 'IV': 1.3, 'iv': 1.3, '♭VII': 1.2, '♭VI': 1.2, 'vi': 1.2},
    motifs: [
      ['ii', 'V', 'I'], ['IV', 'iii', 'vi'], ['ii', 'iii', 'IV', 'V'], ['IV', 'iv', 'iii', 'vi'],
      ['vi', 'ii', 'IV', 'V'], ['I', '♭VII', 'IV', 'iv'], ['ii', 'V', 'iii', 'VI', 'ii', 'V'],
    ],
    colors: {
      'maj': {'M9': .45, 'M7': .35, '69': .2},
      'min': {'9': .45, '11': .35, '7': .2},
      'dom': {'9': .4, '7sus4': .35, '7': .25},
      'sec': {'9': .5, '7': .5},
    },
    split: .25,
    splitLast: .3,
    secondary: .35,
    borrow: .35,
    passingDim: .1,
    substitute: .25,
  ),
  GenStyle(
    id: 'ballad',
    name: 'バラード',
    mood: 'ゆったり・感動',
    bias: {'I': 1.2, 'V': 1.2, 'vi': 1.2, 'iii': 1.2, 'IV': 1.2, 'iv': 1.2},
    motifs: [
      ['I', 'V', 'vi', 'iii', 'IV', 'I', 'IV', 'V'], ['I', 'iii', 'vi', 'IV'], ['IV', 'V', 'iii', 'vi'],
      ['I', 'V', 'vi', 'IV'], ['IV', 'iv', 'I'], ['vi', 'iii', 'IV', 'I', 'ii', 'V'],
    ],
    colors: {
      'maj': {'': .4, 'add9': .3, 'M7': .3},
      'min': {'': .4, '7': .4, '9': .2},
      'dom': {'': .35, 'sus4': .4, '7': .25},
      'sec': {'7': 1.0},
    },
    split: .2,
    splitLast: .3,
    longChord: .15,
    sus: .35,
    borrow: .3,
  ),
  GenStyle(
    id: 'dark',
    name: 'ダーク / トラップ',
    mood: '暗い・重い',
    bias: {'vi': 1.8, 'IV': 1.2, 'V': 1.1, 'iii': 1.3, 'v': 1.2, '♭VI': .8, 'I': .7},
    motifs: [
      ['vi', 'IV', 'V', 'vi'], ['vi', 'iii', 'IV', 'vi'], ['vi', 'V', 'IV', 'V'], ['vi', 'IV', 'iii', 'vi'],
      ['vi', 'vi', 'IV', 'V'], ['vi', 'ii', 'iii', 'vi'],
    ],
    colors: {'maj': {'': .8, 'sus2': .2}, 'min': {'': .6, '7': .25, 'add9': .15}, 'dom': {'': .7, 'sus4': .3}, 'sec': {'7': 1.0}},
    split: .1,
    splitLast: .15,
    longChord: .2,
    secondary: .15,
    borrow: .05,
    minorTonic: true,
  ),
  GenStyle(
    id: 'chiptune',
    name: 'ゲーム / チップチューン',
    mood: 'わくわく・冒険',
    bias: {'I': 1.3, 'IV': 1.3, 'V': 1.3, '♭VII': 1.4, '♭VI': 1.3, 'vi': 1.1},
    motifs: [
      ['I', 'IV', 'V', 'I'], ['vi', 'IV', 'V', 'I'], ['I', '♭VII', 'IV', 'I'], ['IV', 'V', 'iii', 'vi'],
      ['♭VI', '♭VII', 'I'], ['I', 'V', 'IV', 'V'], ['vi', 'V', 'IV', 'V'],
    ],
    colors: {'maj': {'': .85, 'sus4': .05, 'add9': .1}, 'min': {'': .85, '7': .15}, 'dom': {'': .6, 'sus4': .2, '7': .2}, 'sec': {'7': 1.0}},
    split: .4,
    splitLast: .45,
    secondary: .3,
    sus: .2,
  ),
];

GenStyle styleById(String id) => genStyles.firstWhere((s) => s.id == id, orElse: () => genStyles.first);

// ---- 作る -----------------------------------------------------------------------------

/// 前後のつながり（どちらも長調の中の base。無ければ null）
class GenContext {
  const GenContext({this.before, this.after, this.loopHead});
  final String? before; // 入れる場所の直前のコード
  final String? after; // 入れる場所のすぐあとのコード
  final String? loopHead; // ループしたときに戻る先（クリップの最初のコード）
}

class GenProgression {
  const GenProgression(this.style, this.chords, this.tags);

  final GenStyle style;
  final List<GenChord> chords;
  final List<String> tags; // この案の特徴（画面に出す）

  int get beats => chords.fold(0, (a, c) => a + c.beats);
  String get signature => chords.map((c) => c.roman).join(' ');
  List<String> get bases => [for (final c in chords) c.base];
}

/// 最近出した案（同じような案ばかり出さないため。アプリを閉じるまで覚えておく）
final List<String> _recent = [];

class ProgressionGenerator {
  ProgressionGenerator({math.Random? rng}) : rng = rng ?? math.Random();

  final math.Random rng;

  /// [count] 案作る。[style] が null なら案ごとにスタイルもランダム。
  /// [locked] はその位置（拍の頭→コード）を残す（同じ長さの並びで作り直す）
  /// [section] を指定すると、その役割の制約を満たす案だけを返す。制約を満たす候補が
  /// 揃うまで追加で生成を試み（上限は [tries] の6倍）、不足すれば満たした分だけ返す
  List<GenProgression> generate({
    GenStyle? style,
    int bars = 4,
    bool minorKey = false,
    GenContext context = const GenContext(),
    int count = 4,
    List<GenChord>? keepRhythmOf,
    Map<int, GenChord> locked = const {},
    int tries = 260,
    GenSection section = GenSection.none,
  }) {
    final rules = _rulesFor(section);
    final scored = <(double, GenProgression)>[];
    // 指定なしは従来どおり tries 回だけ作る。セクション指定時は、制約を満たす候補が
    // 選別に足る数（count の6倍）集まるか、上限回数に達するまで作り続ける
    final maxAttempts = rules == null ? tries : tries * 6;
    final wantPool = rules == null ? tries : count * 6;
    var attempts = 0;
    while (attempts < maxAttempts && scored.length < wantPool) {
      attempts++;
      final s = style ?? genStyles[rng.nextInt(genStyles.length)];
      final p = _one(s, bars, minorKey || s.minorTonic, context, keepRhythmOf, locked, rules: rules);
      if (p == null) continue;
      if (rules != null && !progressionSatisfiesSection(p, section)) continue;
      scored.add((_score(p, context, minorKey || s.minorTonic, section) + rng.nextDouble() * 0.6, p));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final picked = <GenProgression>[];
    // セクション指定時は、返す案の「着地の型」も散らす（形の違いだけで選ぶと、
    // 着地が半終止ばかりに偏って同じ響きに聞こえるため）。Aメロ・イントロは同じ着地を
    // 1案まで、Bメロは V 終わりが持ち味なので2案まで。指定なし・サビは従来どおり
    final cadenceCap = switch (section) {
      GenSection.verseA || GenSection.intro => 1,
      GenSection.verseB => 2,
      _ => null,
    };
    final cadences = <String, int>{};
    for (final (_, p) in scored) {
      if (picked.any((q) => q.signature == p.signature || _similarity(q, p) > 0.55)) continue;
      String? cadence;
      if (cadenceCap != null) {
        cadence = _cadenceOf(p);
        if ((cadences[cadence] ?? 0) >= cadenceCap) continue;
      }
      picked.add(p);
      if (cadence != null) cadences[cadence] = (cadences[cadence] ?? 0) + 1;
      if (picked.length == count) break;
    }
    // 似たものしか残らなければ、似ていても違うものを足す
    for (final (_, p) in scored) {
      if (picked.length >= count) break;
      if (!picked.any((q) => q.signature == p.signature)) picked.add(p);
    }
    for (final p in picked) {
      _recent.add(p.signature);
    }
    while (_recent.length > 60) {
      _recent.removeAt(0);
    }
    return picked;
  }

  // ---- 1案 ----

  GenProgression? _one(GenStyle s, int bars, bool minorTonic, GenContext ctx, List<GenChord>? rhythmOf,
      Map<int, GenChord> locked, {_SectionRules? rules}) {
    final tags = <String>[];
    final beats = rhythmOf != null ? [for (final c in rhythmOf) c.beats] : _rhythm(s, bars, tags, rules: rules);
    final n = beats.length;
    final tonic = minorTonic ? 'vi' : 'I';

    // 固定された位置（拍の頭 → コード）
    final fixedAt = <int, GenChord>{};
    var pos = 0;
    for (var i = 0; i < n; i++) {
      final l = locked[pos];
      if (l != null) fixedAt[i] = l;
      pos += beats[i];
    }

    final bases = List<String?>.filled(n, null);
    fixedAt.forEach((i, c) => bases[i] = c.base);

    // 種：モチーフを、ずらしたり途中から使ったりして置く
    // セクション制約があるときは、制約に収まるモチーフだけを種にし、
    // headMotifOnly（Aメロ・Bメロ・イントロ）ではずらさず途中からも使わず、頭から置く
    if (rng.nextDouble() < 0.7 && s.motifs.isNotEmpty) {
      var pool = s.motifs;
      if (rules?.bases != null) {
        final allow = {...rules!.bases!, if (rules.maxIv != null) 'iv'};
        bool fits(List<String> m) =>
            m.every(allow.contains) && (rules.first == null || rules.first!.contains(m.first));
        pool = [
          for (final m in s.motifs)
            if (fits(m)) m,
          // セクション専用の定番型も種に足す（多様性の底上げ。指定なしでは使わない）
          for (final m in _sectionMotifs)
            if (fits(m)) m,
        ];
      }
      if (pool.isEmpty) {
        tags.add('自由な流れ');
      } else {
        var motif = pool[rng.nextInt(pool.length)];
        if (rules?.headMotifOnly != true && rng.nextDouble() < 0.35) {
          final shift = rng.nextInt(motif.length);
          motif = [...motif.sublist(shift), ...motif.sublist(0, shift)];
          tags.add('お決まりをずらして');
        } else {
          tags.add('お決まりの並びから');
        }
        final start = rules?.headMotifOnly == true
            ? 0
            : n > motif.length && rng.nextDouble() < 0.4
                ? rng.nextInt(n - motif.length + 1)
                : 0;
        for (var i = 0; i < motif.length && start + i < n; i++) {
          bases[start + i] ??= motif[i];
        }
      }
    } else {
      tags.add('自由な流れ');
    }

    // 8小節以上：前半を繰り返して後半を変えるか、最後まで別の流れか
    final half = n ~/ 2;
    final repeatHalf = bars >= 8 && n.isEven && rng.nextDouble() < 0.45;

    // 残りを流れの表で（前の2つを見る。ばらつきも毎回変える）
    // セクション制約があるときは、候補を使えるコードに絞る（借用 iv は上限まで）
    final allowedBases = rules?.bases == null ? null : {...rules!.bases!, if (rules.maxIv != null) 'iv'};
    final temperature = 0.7 + rng.nextDouble() * 0.9;
    for (var i = 0; i < n; i++) {
      if (bases[i] != null) continue;
      if (repeatHalf && i >= half && i < n - 2 && bases[i - half] != null) {
        bases[i] = bases[i - half];
        continue;
      }
      final prev = i > 0 ? bases[i - 1] : ctx.before;
      final prev2 = i > 1 ? bases[i - 2] : null;
      final next = i + 1 < n ? bases[i + 1] : (ctx.after ?? ctx.loopHead);
      var allow = allowedBases;
      if (allow != null && rules?.maxIv != null && bases.contains('iv')) {
        allow = {...allow}..remove('iv'); // 借用 iv は上限まで（既に使っていたら候補から外す）
      }
      bases[i] = _pick(s, prev, prev2, next, i == 0, i == n - 1, tonic, temperature,
          allowed: allow, firstOnly: i == 0 ? rules?.first : null);
    }
    if (repeatHalf) tags.add('前半をくり返して後半で変化');

    // 色づけと味付け
    var chords = <GenChord>[
      for (var i = 0; i < n; i++) fixedAt[i] ?? GenChord(bases[i]!, _color(s, bases[i]!, rules: rules), beats[i]),
    ];
    // セクション指定時：フレーズ後半だけ代理置換でもバリエーションを付ける
    // （コードの長さは変えないので、この後の味付けで使う固定位置はずれない）
    if (rules?.bases != null) {
      chords = _halfSubstitute(s, chords, fixedAt.keys.toSet(), tags, rules: rules);
    }
    chords = _season(s, chords, fixedAt.keys.toSet(), tags, rules: rules);
    return GenProgression(s, chords, tags);
  }

  /// コードの変わる間隔（拍の並び）
  /// セクション制約の noSplit では小節内の分割を出さず、longBoost では2小節伸ばしを増やす
  List<int> _rhythm(GenStyle s, int bars, List<String> tags, {_SectionRules? rules}) {
    final splitP = rules?.noSplit == true ? 0.0 : s.split;
    final splitLastP = rules?.noSplit == true ? 0.0 : s.splitLast;
    final longP = math.max(s.longChord, rules?.longBoost ?? 0.0);
    final out = <int>[];
    var bar = 0;
    var split = false;
    while (bar < bars) {
      final last = bar == bars - 1;
      if (!last && bar + 1 < bars && rng.nextDouble() < longP) {
        out.add(8);
        bar += 2;
        continue;
      }
      if ((last && rng.nextDouble() < splitLastP) || rng.nextDouble() < splitP) {
        out.addAll(rng.nextDouble() < 0.85 ? [2, 2] : [3, 1]);
        split = true;
      } else {
        out.add(4);
      }
      bar++;
    }
    if (split) tags.add('ところどころ2拍で');
    return out;
  }

  String _pick(GenStyle s, String? prev, String? prev2, String? next, bool first, bool last, String tonic,
      double temperature, {Set<String>? allowed, Set<String>? firstOnly}) {
    final w = <String, double>{};
    final candidates = {..._flow.keys};
    if (allowed != null) candidates.retainAll(allowed);
    if (first && firstOnly != null) candidates.retainAll(firstOnly);
    for (final c in candidates) {
      var x = prev == null
          ? (first ? (c == tonic ? 1.0 : (c == 'IV' || c == 'vi' || c == 'ii' ? 0.8 : 0.25)) : 0.5)
          : flowWeight(prev, c);
      if (x <= 0) continue;
      x *= s.bias[c] ?? 1.0;
      if (c == prev) x *= 0.08; // 同じコードが続くのは少なめ
      if (c == prev2) x *= 0.55;
      // 次（決まっているもの・ループの頭・あとのコード）へつながりやすいもの
      if (next != null) x *= 0.35 + flowWeight(c, next);
      // 最後は「頭へ戻る力」があるもの（V・IV・♭VII・ドミナント）を少し多めに
      if (last && (c == 'V' || c == 'IV' || c == '♭VII' || c == 'III' || c == 'II')) x *= 1.3;
      // めったに出ないものは、ばらつきが大きいときだけ
      if ((c == 'vii°' || c == 'v' || c == '♭III' || c == 'VI') && temperature < 1.1) x *= 0.3;
      w[c] = math.pow(x, 1 / temperature).toDouble();
    }
    final chosen = _choose(w);
    if (chosen != null) return chosen;
    // 制約で候補が尽きたときの保険：制約の内側から返す（先頭制約 → 全体制約 → 主和音）
    if (first && firstOnly != null && firstOnly.isNotEmpty) return firstOnly.first;
    if (allowed != null && allowed.isNotEmpty && !allowed.contains(tonic)) return allowed.first;
    return tonic;
  }

  String _color(GenStyle s, String base, {_SectionRules? rules}) {
    final b = parseBase(base);
    if (b == null) return '';
    if (b.dim) {
      // セクション制約があるときは dim 系の色づけ（ø）を出さない
      if (rules?.suffixes != null) return '';
      return rng.nextDouble() < 0.5 ? 'ø' : '';
    }
    final kind = _kindOf(base);
    var table = s.colors[kind] ?? const {'': 1.0};
    final allow = rules?.suffixes?[kind];
    if (allow != null) {
      table = {for (final e in table.entries) if (allow.contains(e.key)) e.key: e.value};
      // セクション指定時だけ：スタイルの表に sus が無くても、許可されている sus は
      // 控えめな重みで足す（大半のスタイルは maj の色づけに sus を持たず、
      // 許可表に入れただけでは永遠に出てこないため）
      for (final sus in const ['sus2', 'sus4']) {
        if (allow.contains(sus) && !table.containsKey(sus)) table[sus] = 0.12;
      }
      if (table.isEmpty) return '';
    }
    return _choose(table) ?? '';
  }

  /// フレーズ後半だけの代理置換（セクション指定時専用のバリエーション）。
  /// 機能が同じダイアトニック同士（iii↔vi＝トニック機能、IV↔ii＝サブドミナント機能）で
  /// 入れ替え、色づけは置換先に合わせて付け直すので、セクションの制約は崩れない。
  /// 先頭コードと最終コード（着地）は触らず、固定した位置も触らない
  List<GenChord> _halfSubstitute(GenStyle s, List<GenChord> chords, Set<int> fixed, List<String> tags,
      {_SectionRules? rules}) {
    const subs = {'iii': 'vi', 'vi': 'iii', 'IV': 'ii', 'ii': 'IV'};
    final total = chords.fold(0, (a, c) => a + c.beats);
    final out = [...chords];
    var done = 0;
    var at = 0; // そのコードが始まる拍
    for (var i = 0; i < out.length; i++) {
      final start = at;
      at += out[i].beats;
      if (done >= 2) break;
      // 後半（全体の半分以降に始まるコード）だけ。先頭と着地は除く
      if (i == 0 || i == out.length - 1 || start < total / 2) continue;
      if (fixed.contains(i)) continue;
      final sub = subs[out[i].base];
      if (sub == null) continue;
      // 置換で同じコードが隣と連続するのは避ける
      if (sub == out[i - 1].base || (i + 1 < out.length && sub == out[i + 1].base)) continue;
      if (rng.nextDouble() >= 0.45) continue;
      out[i] = GenChord(sub, _color(s, sub, rules: rules), out[i].beats);
      done++;
    }
    if (done > 0) tags.add('後半で代理コード');
    return out;
  }

  /// 味付け（ランダム）。固定した位置は触らない
  /// セクション制約：Aメロ・イントロは味付けなし、Bメロは借用 iv だけ残す
  List<GenChord> _season(GenStyle s, List<GenChord> chords, Set<int> fixed, List<String> tags,
      {_SectionRules? rules}) {
    var out = [...chords];
    if (rules?.noSeasoning == true) return out;
    if (rules?.borrowOnlySeasoning == true) {
      if (rng.nextDouble() < s.borrow) out = _borrowIv(s, out, fixed, tags, rules: rules);
      return out;
    }
    // 代理：I↔vi、IV↔ii、I↔iii（たまに）
    for (var i = 1; i < out.length - 1; i++) {
      if (fixed.contains(i) || rng.nextDouble() >= s.substitute * 0.5) continue;
      final sub = switch (out[i].base) { 'I' => 'vi', 'IV' => 'ii', 'vi' => 'IV', 'ii' => 'IV', _ => null };
      if (sub == null || sub == out[i - 1].base || sub == out[i + 1].base) continue;
      out[i] = GenChord(sub, _color(s, sub, rules: rules), out[i].beats);
      tags.add('代理コード');
      break;
    }
    // 短調から借りる iv：2回目の IV（無ければ IV の次）を iv に
    if (rng.nextDouble() < s.borrow) {
      out = _borrowIv(s, out, fixed, tags, rules: rules);
    }
    // 次のコードの前にドミナントを挟む（4拍以上のコードの後ろ半分を使う）
    const toward = {'ii': 'VI', 'iii': 'VII', 'IV': 'I', 'V': 'II', 'vi': 'III'};
    for (var i = out.length - 2; i >= 0; i--) {
      if (fixed.contains(i) || out[i].beats < 4 || rng.nextDouble() >= s.secondary) continue;
      final target = out[i + 1].base;
      final d = toward[target];
      if (d == null || out[i].base == d) continue;
      final half = out[i].beats ~/ 2;
      final suffix = d == 'I' ? '7' : _color(s, d, rules: rules);
      out = [...out.sublist(0, i), out[i].withBeats(half), GenChord(d, suffix.isEmpty ? '7' : suffix, out[i].beats - half), ...out.sublist(i + 1)];
      tags.add('${d == 'I' ? 'I7' : '${d}7'} で押し出す');
      break;
    }
    // V を sus4 → V で溜める
    for (var i = 0; i < out.length; i++) {
      if (fixed.contains(i) || out[i].base != 'V' || out[i].beats < 4 || rng.nextDouble() >= s.sus) continue;
      final half = out[i].beats ~/ 2;
      out = [...out.sublist(0, i), GenChord('V', 'sus4', half), GenChord('V', rng.nextBool() ? '' : '7', out[i].beats - half), ...out.sublist(i + 1)];
      tags.add('sus4 で溜めて解決');
      break;
    }
    // 経過の dim（I → ♯i° → ii、IV → ♯iv° → V）
    for (var i = 0; i < out.length - 1; i++) {
      if (fixed.contains(i) || out[i].beats < 4 || rng.nextDouble() >= s.passingDim) continue;
      final pass = switch ((out[i].base, out[i + 1].base)) { ('I', 'ii') => '♯i°', ('IV', 'V') => '♯iv°', _ => null };
      if (pass == null) continue;
      final half = out[i].beats ~/ 2;
      out = [...out.sublist(0, i), out[i].withBeats(half), GenChord(pass, '°7', out[i].beats - half), ...out.sublist(i + 1)];
      tags.add('経過の dim');
      break;
    }
    return out;
  }

  /// 短調から借りる iv：2回目の IV を iv に（無ければ IV を半分に割って後半を iv に）
  List<GenChord> _borrowIv(GenStyle s, List<GenChord> out, Set<int> fixed, List<String> tags,
      {_SectionRules? rules}) {
    final ivs = [for (var i = 0; i < out.length; i++) if (out[i].base == 'IV' && !fixed.contains(i)) i];
    if (ivs.length >= 2) {
      out[ivs[1]] = GenChord('iv', _color(s, 'iv', rules: rules), out[ivs[1]].beats);
      tags.add('切なさの iv');
    } else if (ivs.length == 1 && out[ivs[0]].beats >= 4) {
      final i = ivs[0];
      final half = out[i].beats ~/ 2;
      out = [
        ...out.sublist(0, i),
        out[i].withBeats(half),
        GenChord('iv', _color(s, 'iv', rules: rules), out[i].beats - half),
        ...out.sublist(i + 1)
      ];
      tags.add('IV → iv');
    }
    return out;
  }

  // ---- 点数 ----

  double _score(GenProgression p, GenContext ctx, bool minorTonic, GenSection section) {
    final b = p.bases;
    var score = 0.0;
    for (var i = 1; i < b.length; i++) {
      final f = flowWeight(b[i - 1], b[i]);
      score += math.log(0.05 + f);
      if (b[i] == b[i - 1]) score -= 0.8;
    }
    score /= math.max(1, b.length - 1);
    // 前後へのつながり
    if (ctx.before != null) score += 0.8 * math.log(0.05 + flowWeight(ctx.before!, b.first));
    final next = ctx.after ?? ctx.loopHead ?? b.first; // 何もなければ自分の頭へループ
    score += 0.9 * math.log(0.05 + flowWeight(b.last, next));
    // 色々なコードを使っている
    score += 0.6 * b.toSet().length / b.length;
    // 主役のコードがどこかにある（迷子にならない）
    final tonic = minorTonic ? 'vi' : 'I';
    if (!b.contains(tonic) && !b.contains(minorTonic ? 'I' : 'vi')) score -= 0.4;
    // セクションの好み：サビは IV・I 始まり、Bメロは V で止まる案を少し優先
    final rules = _rulesFor(section);
    if (rules?.preferFirst?.contains(b.first) ?? false) score += 0.5;
    if (rules?.preferLastDominant == true && b.last == 'V') score += 0.6;
    // 最近出したものに似ていたら下げる
    for (final r in _recent.reversed.take(30)) {
      if (r == p.signature) score -= 1.5;
    }
    return score;
  }

  /// 着地の型（最後の2コードの並びで分類）。セクション指定時に返す案を散らすために使う
  String _cadenceOf(GenProgression p) {
    final b = p.bases;
    if (b.isEmpty) return 'なし';
    if (b.length >= 2) {
      if (b[b.length - 2] == 'iii' && b.last == 'vi') return 'iii→vi';
      if (b[b.length - 2] == 'IV' && b.last == 'I') return '変終止';
    }
    return switch (b.last) {
      'I' => 'I 解決',
      'vi' => 'vi 解決',
      'V' => '半終止',
      _ => 'その他',
    };
  }

  double _similarity(GenProgression a, GenProgression b) {
    Set<String> grams(List<String> x) => {for (var i = 0; i + 1 < x.length; i++) '${x[i]}>${x[i + 1]}', ...x};
    final ga = grams(a.bases), gb = grams(b.bases);
    final inter = ga.intersection(gb).length;
    return inter / math.max(1, ga.union(gb).length);
  }

  T? _choose<T>(Map<T, double> weights) {
    final total = weights.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return null;
    var r = rng.nextDouble() * total;
    for (final e in weights.entries) {
      r -= e.value;
      if (r <= 0) return e.key;
    }
    return weights.keys.last;
  }
}

/// 曲のキーの長調の主音（短調なら平行調：短3度上）
int majorRootOf(Scale scale, {required bool minor}) => minor ? (scale.root + 3) % 12 : scale.root;

/// そのスケールの曲を、進行生成の物差し（長調のローマ数字）で扱うときの長調の主音と、短調として扱うか。
/// 生成の物差しは長調／短調の2通りしかないので、新しいスケールは一番近い物差しに寄せる：
/// ・メジャー／ミクソリディアン／メジャーペンタは、そのまま長調として（主音は同じ）
/// ・短調系（ナチュラル／ハーモニック／マイナーペンタ）とドリアンは、平行調の長調として（主音は短3度上。
///   ドリアンの主音は平行調の中で ii ではなく vi になるが、短調の曲として中心が合う方を取る）
({int majorRoot, bool minorKey}) genFrameOf(Scale scale) {
  final kind = scale.kind;
  final minorKey = kind.tonicMinor;
  return (majorRoot: majorRootOf(scale, minor: minorKey), minorKey: minorKey);
}
