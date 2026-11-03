/// スケールとノート名。音程は常に MIDI の絶対値で持ち、
/// 「スケール外を畳む」は表示側でこのクラスを通して行う。
class Scale {
  const Scale(this.root, this.intervals);

  /// ルート音（0 = C … 11 = B）
  final int root;

  /// ルートからの半音数（昇順、0 から始まる）
  final List<int> intervals;

  static const minorIntervals = [0, 2, 3, 5, 7, 8, 10];
  static const majorIntervals = [0, 2, 4, 5, 7, 9, 11];

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
