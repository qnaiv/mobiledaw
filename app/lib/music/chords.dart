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
  });

  /// キーの中で何番目か（0〜6）
  final int degree;

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

/// キーで自然に使える7つのコード。短調の5番目は、戻る力が強い長三和音（ポップスでよく使う形）にする
List<Chord> diatonicChords(Scale scale, {required bool minor}) {
  final iv = scale.intervals;
  int step(int i) => iv[i % 7] + 12 * (i ~/ 7);
  return [
    for (var d = 0; d < 7; d++)
      () {
        final root = step(d);
        var third = step(d + 2) - root;
        final fifth = step(d + 4) - root;
        var seventh = step(d + 6) - root;
        if (minor && d == 4) {
          third = 4; // G（Gm ではなく）
          seventh = 10; // G7
        }
        return Chord(
          degree: d,
          root: (scale.root + root) % 12,
          intervals: [0, third, fifth],
          seventh: seventh,
          mood: (minor ? _minorMoods : _majorMoods)[d],
        );
      }(),
  ];
}

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
