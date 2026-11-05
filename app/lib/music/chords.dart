// コードの計算（理論を知らなくても使えるように、キーの中のコードだけを扱う）。
// ・キーで自然に使える7つのコード（ダイアトニック）と、それぞれの雰囲気の言葉
// ・あるコードの次に合うコード（よく使われるつながりの順）
// ・置いたノートからコード名を判定
import 'scale.dart';

class Chord {
  const Chord({
    required this.degree,
    required this.root,
    required this.intervals,
    required this.seventh,
    required this.mood,
    this.extensions = const [],
    this.roman = '',
  });

  /// コード一覧の中で何番目か（0〜）
  final int degree;

  /// 度数表記（I・ii・♭VII など）。ダイアトニックと借用コードに付く
  final String roman;

  /// 根音（0 = C … 11 = B）
  final int root;

  /// 根音からの半音数（3和音）
  final List<int> intervals;

  /// 根音から7度の音までの半音数
  final int seventh;

  /// 雰囲気の目安（理論の代わり）
  final String mood;

  /// 3和音に足す音（7th・9th など、根音からの半音数）
  final List<int> extensions;

  String get name =>
      extensions.isEmpty ? '${noteName(root)}${_quality(intervals)}' : (chordNameOf(pitchesNear(60)) ?? '${noteName(root)}${_quality(intervals)}');

  /// 7thを足したときの名前
  String get seventhName => '${noteName(root)}${_seventhQuality(intervals, seventh)}';

  /// ロールに置く音。[nearPitch] 以下で一番近い根音から積む。[withSeventh] なら7度も足す
  List<int> pitchesNear(int nearPitch, {bool withSeventh = false}) {
    var base = nearPitch - ((nearPitch - root) % 12);
    if (base < 0) base += 12;
    final notes = [
      for (final i in intervals) base + i,
      for (final e in extensions) base + e,
      if (withSeventh && !extensions.any((e) => e % 12 == seventh % 12)) base + seventh,
    ]..sort();
    return notes.where((p) => p >= 0 && p <= 127).toList();
  }
}

String _quality(List<int> iv) => switch ((iv[1], iv[2])) {
      (4, 7) => '',
      (3, 7) => 'm',
      (3, 6) => '°',
      (4, 8) => '+',
      _ => '',
    };

String _seventhQuality(List<int> iv, int seventh) => switch ((iv[1], iv[2], seventh)) {
      (4, 7, 10) => '7',
      (4, 7, 11) => 'M7',
      (3, 7, 10) => 'm7',
      (3, 7, 11) => 'mM7',
      (3, 6, 10) => 'm7♭5',
      (3, 6, 9) => 'dim7',
      _ => '${_quality(iv)}7',
    };

const _majorMoods = ['落ち着く', 'やさしい', '切ない', '広がる', '戻りたい', '暗め', '不安'];
const _minorMoods = ['落ち着く', '不安', '明るい', '切ない', '戻りたい', '広がる', '進む'];
const _dorianMoods = ['落ち着く', 'やさしい', '明るい', '進む', '切ない', '不安', '広がる'];
const _mixoMoods = ['落ち着く', 'やさしい', '不安', '広がる', '切ない', '暗め', '進む'];
const _harmonicMoods = ['落ち着く', '不安', '妖しい', '切ない', '戻りたい', '広がる', '緊張'];

List<String> _moodsFor(ScaleKind kind) => switch (kind.id) {
      'major' => _majorMoods,
      'dorian' => _dorianMoods,
      'mixolydian' => _mixoMoods,
      'harmonicMinor' => _harmonicMoods,
      _ => _minorMoods,
    };

/// 主音 [tonicRoot] から見た度数表記（長調の位置を物差しに、スケール外のルートには ♭・♯ を付ける。
/// 短調で ♭VI・♭VII と書く、進行プリセットと同じ流儀）。長和音は大文字、短和音は小文字、減は °、増は +
String romanLabel(int rootPc, int tonicRoot, List<int> intervals, {String suffix = ''}) {
  const names = ['I', '♭II', 'II', '♭III', 'III', 'IV', '♯IV', 'V', '♭VI', 'VI', '♭VII', 'VII'];
  final semis = (rootPc - tonicRoot + 12) % 12;
  var s = names[semis];
  final third = intervals.length > 1 ? intervals[1] : 4;
  final fifth = intervals.length > 2 ? intervals[2] : 7;
  if (third == 3) s = s.toLowerCase();
  if (third == 3 && fifth == 6) s = '$s°';
  if (third == 4 && fifth == 8) s = '$s+';
  return '$s$suffix';
}

/// スケールの各音の上に三和音（と7度）を積んでコードを作る。
/// ナチュラルマイナーの5番目は、戻る力が強い長三和音（ポップスでよく使う形）にする
List<Chord> _stackChords(Scale scale, ScaleKind kind) {
  final iv = scale.intervals;
  final n = iv.length;
  int step(int i) => iv[i % n] + 12 * (i ~/ n);
  final moods = _moodsFor(kind);
  return [
    for (var d = 0; d < n; d++)
      () {
        final root = step(d);
        var third = step(d + 2) - root;
        final fifth = step(d + 4) - root;
        var seventh = step(d + 6) - root;
        if (kind.id == 'minor' && d == 4) {
          third = 4; // G（Gm ではなく）
          seventh = 10; // G7
        }
        final intervals = [0, third, fifth];
        final rootPc = (scale.root + root) % 12;
        return Chord(
          degree: d,
          root: rootPc,
          intervals: intervals,
          seventh: seventh,
          mood: moods[d % moods.length],
          roman: romanLabel(rootPc, scale.root, intervals),
        );
      }(),
  ];
}

/// そのスケールで自然に使えるコード。
/// ペンタトニックは親スケールのダイアトニックのうち、根音がスケールの中にあるものだけ
List<Chord> scaleChords(Scale scale) {
  final kind = scale.kind;
  final parentId = kind.parentId;
  if (parentId == null) return _stackChords(scale, kind);
  final parent = scaleKindOf(parentId);
  final all = _stackChords(Scale.of(scale.root, parent), parent);
  var pos = 0;
  return [
    for (final c in all)
      if (scale.contains(c.root))
        Chord(
          degree: pos++,
          root: c.root,
          intervals: c.intervals,
          seventh: c.seventh,
          mood: c.mood,
          extensions: c.extensions,
          roman: c.roman,
        ),
  ];
}

/// キーで自然に使えるコード（scaleChords と同じ。昔の呼び名）
List<Chord> diatonicChords(Scale scale, {required bool minor}) => scaleChords(scale);

/// そのコードの次に合うコード（キーの中の番号、合う順に3つ）
List<int> suggestNext(int degree, {required bool minor}) {
  const major = [
    [3, 4, 5], // I → IV V vi
    [4, 3, 0], // ii → V IV I
    [5, 3, 1], // iii → vi IV ii
    [4, 0, 1], // IV → V I ii
    [0, 5, 3], // V → I vi IV
    [3, 1, 4], // vi → IV ii V
    [0, 2, 5], // vii° → I iii vi
  ];
  const minorTable = [
    [5, 3, 6], // i → VI iv VII
    [4, 0, 6], // ii° → V i VII
    [5, 3, 6], // III → VI iv VII
    [4, 0, 6], // iv → V i VII
    [0, 5, 3], // V → i VI iv
    [6, 0, 3], // VI → VII i iv
    [2, 0, 5], // VII → III i VI
  ];
  return (minor ? minorTable : major)[degree.clamp(0, 6)];
}

const _dorianNext = [
  [3, 6, 4], // i → IV VII v
  [4, 0, 6], // ii → v i VII
  [6, 5, 3], // III → VII vi° IV
  [4, 6, 0], // IV → v VII i
  [0, 3, 6], // v → i IV VII
  [0, 4, 2], // vi° → i v III
  [0, 2, 5], // VII → i III vi°
];

const _mixoNext = [
  [3, 6, 4], // I → IV ♭VII v
  [4, 3, 0], // ii → v IV I
  [0, 5, 3], // iii° → I vi IV
  [0, 4, 1], // IV → I v ii
  [0, 6, 3], // v → I ♭VII IV
  [3, 4, 1], // vi → IV v ii
  [0, 3, 4], // ♭VII → I IV v
];

const _harmonicNext = [
  [4, 3, 5], // i → V iv VI
  [4, 0, 6], // ii° → V i vii°
  [5, 4, 3], // III+ → VI V iv
  [4, 0, 5], // iv → V i VI
  [0, 5, 3], // V → i VI iv
  [6, 0, 4], // VI → vii° i V
  [0, 2, 5], // vii° → i III+ VI
];

/// そのスケールのコード一覧（[scaleChords]）の中で、[position] の次に合うコード（位置の並び、合う順に最大3つ）
List<int> suggestNextForScale(Scale scale, int position) {
  final kind = scale.kind;
  switch (kind.id) {
    case 'major':
      return suggestNext(position, minor: false);
    case 'minor':
      return suggestNext(position, minor: true);
    case 'dorian':
      return _dorianNext[position.clamp(0, 6)];
    case 'mixolydian':
      return _mixoNext[position.clamp(0, 6)];
    case 'harmonicMinor':
      return _harmonicNext[position.clamp(0, 6)];
  }
  // ペンタトニック：親スケールの表を、残っているコードの位置に読み替える
  final parent = scaleKindOf(kind.parentId ?? 'major');
  final all = _stackChords(Scale.of(scale.root, parent), parent);
  final kept = [for (var d = 0; d < all.length; d++) if (scale.contains(all[d].root)) d];
  if (position < 0 || position >= kept.length) return const [];
  final next = suggestNext(kept[position], minor: parent.tonicMinor);
  final out = [for (final d in next) if (kept.contains(d)) kept.indexOf(d)];
  return out.isEmpty ? [0] : out;
}

/// 置いてあるノートを調べた結果
class ChordInfo {
  const ChordInfo({required this.root, required this.suffix, required this.bass, required this.pcs});

  final int root; // 根音（0〜11）
  final String suffix; // m・7・sus4 など
  final int bass; // 一番下の音（0〜11）
  final Set<int> pcs; // 含まれる音（0〜11）

  String get name {
    final n = '${noteName(root)}$suffix';
    return bass == root ? n : '$n/${noteName(bass)}';
  }

  /// 根音から見た半音数の集合
  Set<int> get rel => {for (final p in pcs) (p - root + 12) % 12};

  bool get hasSeventh => rel.contains(10) || rel.contains(11);
  bool get hasSus4 => rel.contains(5) && !rel.contains(3) && !rel.contains(4);
  bool get hasSus2 => rel.contains(2) && !rel.contains(3) && !rel.contains(4);
  bool get hasNinth => rel.contains(2) && (rel.contains(3) || rel.contains(4));

  /// 転回の状態（一番下の音が根音から何度か）
  String get inversion {
    if (bass == root) return '基本形';
    return switch ((bass - root + 12) % 12) {
      3 || 4 || 2 || 5 => '第1転回',
      6 || 7 || 8 => '第2転回',
      9 || 10 || 11 => '第3転回',
      _ => '分数',
    };
  }
}

const _templates = <String, List<int>>{
  '': [0, 4, 7],
  'm': [0, 3, 7],
  '°': [0, 3, 6],
  '+': [0, 4, 8],
  'sus4': [0, 5, 7],
  'sus2': [0, 2, 7],
  '7': [0, 4, 7, 10],
  'M7': [0, 4, 7, 11],
  'm7': [0, 3, 7, 10],
  'mM7': [0, 3, 7, 11],
  'm7♭5': [0, 3, 6, 10],
  'dim7': [0, 3, 6, 9],
  '7sus4': [0, 5, 7, 10],
  'add9': [0, 2, 4, 7],
  'm(add9)': [0, 2, 3, 7],
  '9': [0, 2, 4, 7, 10],
  'M9': [0, 2, 4, 7, 11],
  'm9': [0, 2, 3, 7, 10],
};

/// 置いてあるノートの音からコードを判定する。コードでなければ null
ChordInfo? analyzeChord(Iterable<int> pitches) {
  final list = pitches.toList()..sort();
  if (list.length < 3) return null;
  final pcs = {for (final p in list) p % 12};
  if (pcs.length < 3) return null;
  final bass = list.first % 12;
  // 一番下の音を根音とみなせるものを優先し、だめなら他の音を根音として試す（転回形）
  final roots = [bass, ...list.map((p) => p % 12).where((p) => p != bass)];
  for (final root in roots) {
    final rel = {for (final p in pcs) (p - root + 12) % 12};
    for (final entry in _templates.entries) {
      final t = entry.value.toSet();
      if (t.length == rel.length && t.containsAll(rel)) {
        return ChordInfo(root: root, suffix: entry.key, bass: bass, pcs: pcs);
      }
    }
  }
  return null;
}

/// 置いてあるノートの音からコード名を判定する（例：A♭、Cm7、A♭/C）。コードでなければ null
String? chordNameOf(Iterable<int> pitches) => analyzeChord(pitches)?.name;
