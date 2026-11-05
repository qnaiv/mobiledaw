/// スケールの種類。プロジェクトには [id] の文字列で保存される
/// （"key": {"root": 0, "scale": "dorian"} の形）。昔の "major" / "minor" はそのまま。
class ScaleKind {
  const ScaleKind({
    required this.id,
    required this.label,
    required this.description,
    required this.intervals,
    this.tonicMinor = false,
    this.parentId,
  });

  /// 保存名（JSON の "scale" に入る）
  final String id;

  /// 画面に出す名前
  final String label;

  /// どんな場面向きか（一言）
  final String description;

  /// ルートからの半音数（昇順、0 から始まる）
  final List<int> intervals;

  /// 主音が短調的か（短調の5番目を長三和音にする・進行生成で短調として扱う、の目印）
  final bool tonicMinor;

  /// ペンタトニックの親スケール（コードは親のダイアトニックから、ルートがスケール内にあるものだけ出す）
  final String? parentId;
}

/// 選べるスケール（シートに出る順）
const scaleKinds = <ScaleKind>[
  ScaleKind(
    id: 'major',
    label: 'メジャー',
    description: '基本の明るいスケール',
    intervals: [0, 2, 4, 5, 7, 9, 11],
  ),
  ScaleKind(
    id: 'minor',
    label: 'ナチュラルマイナー',
    description: '基本の暗いスケール。Lo-fiやR&Bの土台',
    intervals: [0, 2, 3, 5, 7, 8, 10],
    tonicMinor: true,
  ),
  ScaleKind(
    id: 'dorian',
    label: 'ドリアン',
    description: '少し明るいマイナー。ハウス／ファンク向き',
    intervals: [0, 2, 3, 5, 7, 9, 10],
    tonicMinor: true,
  ),
  ScaleKind(
    id: 'mixolydian',
    label: 'ミクソリディアン',
    description: '少し渋いメジャー。ロック／ブルース／EDMのドロップに',
    intervals: [0, 2, 4, 5, 7, 9, 10],
  ),
  ScaleKind(
    id: 'harmonicMinor',
    label: 'ハーモニックマイナー',
    description: '終わりの音が強いマイナー。Vが作れて締まる',
    intervals: [0, 2, 3, 5, 7, 8, 11],
    tonicMinor: true,
  ),
  ScaleKind(
    id: 'majorPentatonic',
    label: 'メジャーペンタトニック',
    description: '外しにくい5音。メロディ作りの近道',
    intervals: [0, 2, 4, 7, 9],
    parentId: 'major',
  ),
  ScaleKind(
    id: 'minorPentatonic',
    label: 'マイナーペンタトニック',
    description: '渋くて歌いやすい5音。フレーズ作りに',
    intervals: [0, 3, 5, 7, 10],
    tonicMinor: true,
    parentId: 'minor',
  ),
];

/// 保存名からスケールの種類を引く。知らない名前は昔の扱い（major 以外は minor）に合わせて minor
ScaleKind scaleKindOf(String id) {
  for (final k in scaleKinds) {
    if (k.id == id) return k;
  }
  return scaleKinds[1]; // minor
}

/// そのスケール（音の並び）から種類を引く。合うものが無ければ minor
ScaleKind kindOfScale(Scale scale) {
  bool same(List<int> a, List<int> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);
  for (final k in scaleKinds) {
    if (same(k.intervals, scale.intervals)) return k;
  }
  return scaleKinds[1]; // minor
}

/// スケールとノート名。音程は常に MIDI の絶対値で持ち、
/// 「スケール外を畳む」は表示側でこのクラスを通して行う。
class Scale {
  const Scale(this.root, this.intervals);

  /// 種類とルートから作る
  factory Scale.of(int root, ScaleKind kind) => Scale(root, kind.intervals);

  /// ルート音（0 = C … 11 = B）
  final int root;

  /// ルートからの半音数（昇順、0 から始まる）
  final List<int> intervals;

  static const minorIntervals = [0, 2, 3, 5, 7, 8, 10];
  static const majorIntervals = [0, 2, 4, 5, 7, 9, 11];

  /// このスケールの種類
  ScaleKind get kind => kindOfScale(this);

  bool contains(int midiNote) => intervals.contains((midiNote - root) % 12);

  /// 指定オクターブのスケール音を、上のルートまで含めて返す（短調なら8音）。
  /// octave は MIDI 慣習（C4 = 60 → octave 4）。
  List<int> notesFrom(int octave) {
    final base = (octave + 1) * 12 + root;
    return [for (final i in intervals) base + i, base + 12];
  }
}

const _flatNames = ['C', 'D♭', 'D', 'E♭', 'E', 'F', 'G♭', 'G', 'A♭', 'A', 'B♭', 'B'];

String noteName(int midiNote, {bool withOctave = false}) {
  final name = _flatNames[midiNote % 12];
  if (!withOctave) return name;
  return '$name${midiNote ~/ 12 - 1}';
}
