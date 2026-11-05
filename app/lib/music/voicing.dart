// 置いたコードをいじる道具の計算（画面に依存しない純粋な関数）。
// 道具は「選んでいるノート」に効く。音の高さの変え方を PitchEdit（どの音を何に変えるか・何を足すか）で表し、
// 画面側はそれを選んだノートに当てはめて、1回の編集（1回の Undo）として書き換える。
import 'dart:math' as math;

import 'chords.dart';
import 'scale.dart';

/// 置き直すノート1つぶん
class NoteSpec {
  const NoteSpec(this.tick, this.length, this.pitch, [this.velocity = 0.8]);
  final int tick;
  final int length;
  final int pitch;
  final double velocity;

  @override
  String toString() => 'NoteSpec($tick, $length, $pitch)';
}

/// 音の高さの変え方。remap：元の音 → 新しい音（null なら消す）。add：コードを鳴らすたびに足す音
class PitchEdit {
  const PitchEdit({this.remap = const {}, this.add = const []});
  final Map<int, int?> remap;
  final List<int> add;

  bool get isEmpty => remap.isEmpty && add.isEmpty;
}

/// コードの音を「ベース」と「上の音」に分ける。一番下の音が次の音から5度以上離れていればベースとみなす
({int? bass, List<int> upper}) splitBass(Iterable<int> pitches) {
  final list = pitches.toSet().toList()..sort();
  if (list.length >= 4 && list[1] - list[0] >= 7) return (bass: list[0], upper: list.sublist(1));
  return (bass: null, upper: list);
}

bool _inRange(int p) => p >= 0 && p <= 127;

/// 転回：上へ（一番下の音を1オクターブ上へ）、下へ（一番上の音を1オクターブ下へ）。ベースはそのまま
PitchEdit invert(Iterable<int> pitches, {required bool up}) {
  final s = splitBass(pitches);
  if (s.upper.length < 2) return const PitchEdit();
  if (up) {
    final low = s.upper.first;
    return _inRange(low + 12) ? PitchEdit(remap: {low: low + 12}) : const PitchEdit();
  }
  final high = s.upper.last;
  final to = high - 12;
  if (!_inRange(to) || (s.bass != null && to <= s.bass!)) return const PitchEdit();
  return PitchEdit(remap: {high: to});
}

/// 上の音が1オクターブに収まっているか（閉じた形）
bool isClosed(Iterable<int> pitches) {
  final u = splitBass(pitches).upper;
  return u.length < 2 || u.last - u.first < 12;
}

/// 広げる（真ん中の音を1オクターブ上へ）⇔ 閉じる（上の音を一番下の音から1オクターブの中へ）
PitchEdit spreadOrClose(Iterable<int> pitches) {
  final u = splitBass(pitches).upper;
  if (u.length < 3) return const PitchEdit();
  if (isClosed(pitches)) {
    final mid = u[1];
    return _inRange(mid + 12) ? PitchEdit(remap: {mid: mid + 12}) : const PitchEdit();
  }
  final base = u.first;
  final remap = <int, int?>{};
  final used = <int>{base};
  for (final p in u.skip(1)) {
    var q = base + (p - base) % 12;
    if (q == base) q += 12;
    if (used.contains(q)) {
      remap[p] = null; // 重なる音は消す
      continue;
    }
    used.add(q);
    if (q != p) remap[p] = q;
  }
  return PitchEdit(remap: remap);
}

/// [pc] の音で、[below] より下にある一番近い高さ
int _pcBelow(int pc, int below) {
  final base = below - 1;
  return base - ((base - pc) % 12 + 12) % 12;
}

/// ベースを足す：押すたびに なし → 根音 → 3度 → 5度 → なし（分数コードもここで作る）
PitchEdit cycleBass(Iterable<int> pitches) {
  final info = analyzeChord(pitches);
  if (info == null) return const PitchEdit();
  final s = splitBass(pitches);
  final third = info.rel.contains(3) ? 3 : (info.rel.contains(4) ? 4 : (info.rel.contains(5) ? 5 : 2));
  final fifth = info.rel.contains(6) ? 6 : (info.rel.contains(8) ? 8 : 7);
  final order = [info.root, (info.root + third) % 12, (info.root + fifth) % 12];
  final current = s.bass;
  final i = current == null ? -1 : order.indexOf(current % 12);
  final int? nextPc = current == null ? order[0] : (i >= 0 && i < order.length - 1 ? order[i + 1] : null);
  final remap = <int, int?>{};
  final add = <int>[];
  if (current != null) remap[current] = null;
  if (nextPc != null) {
    final p = _pcBelow(nextPc, s.upper.first - 6); // 上の音から少なくとも5度ほど下
    if (_inRange(p)) add.add(p);
  }
  return PitchEdit(remap: remap, add: add);
}

/// 根音の高さ（上の音の中の根音。なければ一番下の音以下の根音）
int _rootPitch(List<int> upper, int root) {
  for (final p in upper) {
    if (p % 12 == root) return p;
  }
  return _pcBelow(root, upper.first + 1);
}

/// キーの中で、根音から何度目かの音までの半音数（キーの外の根音なら [fallback]）
int _scaleInterval(Scale scale, int root, int steps, int fallback) {
  final iv = scale.intervals;
  final n = iv.length;
  final idx = iv.indexOf((root - scale.root + 12) % 12);
  if (idx < 0) return fallback;
  int at(int i) => iv[i % n] + 12 * (i ~/ n);
  return at(idx + steps) - at(idx);
}

/// 7th の付け外し（キーの中の7度。キーの外のコードは短7度）
PitchEdit toggleSeventh(Iterable<int> pitches, Scale scale) {
  final info = analyzeChord(pitches);
  if (info == null) return const PitchEdit();
  final u = splitBass(pitches).upper;
  if (info.hasSeventh) {
    return PitchEdit(remap: {
      for (final p in u)
        if ((p - info.root + 12) % 12 == 10 || (p - info.root + 12) % 12 == 11) p: null,
    });
  }
  final seventh = _scaleInterval(scale, info.root, 6, 10);
  var p = _rootPitch(u, info.root) + seventh;
  while (p > u.last + 12) {
    p -= 12;
  }
  while (u.contains(p)) {
    p += 12;
  }
  return _inRange(p) ? PitchEdit(add: [p]) : const PitchEdit();
}

/// sus4（[to]=5）・sus2（[to]=2）の付け外し。3度の音を置き換え、もう一度押すと3度に戻す
PitchEdit toggleSus(Iterable<int> pitches, Scale scale, {required int to}) {
  final info = analyzeChord(pitches);
  if (info == null) return const PitchEdit();
  final remap = <int, int?>{};
  final hasIt = to == 5 ? info.hasSus4 : info.hasSus2;
  for (final p in splitBass(pitches).upper) {
    final r = (p - info.root + 12) % 12;
    if (!hasIt && (r == 3 || r == 4)) remap[p] = p - r + to;
    if (hasIt && r == to) {
      final third = _scaleInterval(scale, info.root, 2, 4);
      remap[p] = p - r + third;
    }
  }
  return PitchEdit(remap: remap);
}

/// add9 の付け外し（根音の1オクターブと2度上）
PitchEdit toggleNinth(Iterable<int> pitches) {
  final info = analyzeChord(pitches);
  if (info == null) return const PitchEdit();
  final u = splitBass(pitches).upper;
  if (info.hasNinth) {
    return PitchEdit(remap: {
      for (final p in u)
        if ((p - info.root + 12) % 12 == 2) p: null,
    });
  }
  var p = _rootPitch(u, info.root) + 14;
  while (u.contains(p)) {
    p += 12;
  }
  return _inRange(p) ? PitchEdit(add: [p]) : const PitchEdit();
}

/// 上の音を、前のコードから一番動かない形（転回とオクターブ）に寄せる
PitchEdit voiceLead(Iterable<int> previous, Iterable<int> current) {
  final prev = splitBass(previous).upper;
  final cur = splitBass(current).upper;
  if (prev.isEmpty || cur.length < 2) return const PitchEdit();
  final prevCenter = prev.reduce((a, b) => a + b) / prev.length;

  double cost(List<int> cand) {
    if (cand.length == prev.length) {
      var c = 0;
      for (var i = 0; i < cand.length; i++) {
        c += (cand[i] - prev[i]).abs();
      }
      return c.toDouble();
    }
    final center = cand.reduce((a, b) => a + b) / cand.length;
    return (center - prevCenter).abs() * cand.length;
  }

  // 今の形から上下に何回か転回した形を候補にする
  List<int> rotate(List<int> v, bool up) {
    final s = [...v]..sort();
    if (up) {
      s[0] += 12;
    } else {
      s[s.length - 1] -= 12;
    }
    return s..sort();
  }

  var best = [...cur]..sort();
  var bestCost = cost(best);
  for (final up in [true, false]) {
    var v = [...cur]..sort();
    for (var k = 0; k < cur.length * 2; k++) {
      v = rotate(v, up);
      if (!v.every(_inRange)) break;
      final c = cost(v);
      if (c < bestCost) {
        bestCost = c;
        best = v;
      }
    }
  }
  final sorted = [...cur]..sort();
  final remap = <int, int?>{};
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i] != best[i]) remap[sorted[i]] = best[i];
  }
  return PitchEdit(remap: remap);
}

/// PitchEdit を選んだノートに当てはめる。足す音は、コードを鳴らすたび（同じ時刻の組ごと）に足す
List<NoteSpec> applyPitchEdit(List<NoteSpec> notes, PitchEdit edit) {
  final out = <NoteSpec>[];
  for (final n in notes) {
    if (edit.remap.containsKey(n.pitch)) {
      final to = edit.remap[n.pitch];
      if (to != null) out.add(NoteSpec(n.tick, n.length, to, n.velocity));
    } else {
      out.add(n);
    }
  }
  if (edit.add.isNotEmpty) {
    final strikes = <int, NoteSpec>{};
    for (final n in notes) {
      final s = strikes[n.tick];
      if (s == null || n.length > s.length) strikes[n.tick] = n;
    }
    for (final s in strikes.values) {
      for (final p in edit.add) {
        if (!out.any((o) => o.tick == s.tick && o.pitch == p)) out.add(NoteSpec(s.tick, s.length, p, s.velocity));
      }
    }
  }
  out.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.pitch.compareTo(b.pitch));
  return out;
}

// ---- リズムにする ----------------------------------------------------------------

enum ChordRhythm { block, eighth, sixteenth, arpUp, arpUpDown, strum, syncopated }

String rhythmLabel(ChordRhythm r) => switch (r) {
      ChordRhythm.block => 'ベタ',
      ChordRhythm.eighth => '8分で刻む',
      ChordRhythm.sixteenth => '16分で刻む',
      ChordRhythm.arpUp => 'アルペジオ ↑',
      ChordRhythm.arpUpDown => 'アルペジオ ↑↓',
      ChordRhythm.strum => 'ストローク',
      ChordRhythm.syncopated => 'シンコペ',
    };

/// コードの音を [start] から [length] の間でリズムにする。ベース（あれば）はずっと伸ばす
List<NoteSpec> rhythmize(Iterable<int> pitches,
    {required int start, required int length, required ChordRhythm rhythm, double velocity = 0.8, int ppq = 960}) {
  final s = splitBass(pitches);
  final upper = s.upper;
  final end = start + length;
  final out = <NoteSpec>[if (s.bass != null) NoteSpec(start, length, s.bass!, velocity)];
  if (upper.isEmpty || length <= 0) return out;
  int clampLen(int t, int len) => math.max(1, math.min(len, end - t));

  switch (rhythm) {
    case ChordRhythm.block:
      for (final p in upper) {
        out.add(NoteSpec(start, length, p, velocity));
      }
    case ChordRhythm.eighth:
    case ChordRhythm.sixteenth:
      final step = rhythm == ChordRhythm.eighth ? ppq ~/ 2 : ppq ~/ 4;
      for (var t = start, i = 0; t < end; t += step, i++) {
        final v = i % (rhythm == ChordRhythm.eighth ? 2 : 4) == 0 ? velocity : velocity * 0.8;
        for (final p in upper) {
          out.add(NoteSpec(t, clampLen(t, step * 9 ~/ 10), p, v));
        }
      }
    case ChordRhythm.arpUp:
    case ChordRhythm.arpUpDown:
      final seq = rhythm == ChordRhythm.arpUp
          ? upper
          : [...upper, ...upper.reversed.skip(1).take(math.max(0, upper.length - 2))];
      final step = ppq ~/ 4;
      for (var t = start, i = 0; t < end; t += step, i++) {
        out.add(NoteSpec(t, clampLen(t, step), seq[i % seq.length], velocity));
      }
    case ChordRhythm.strum:
      const gap = 40; // 弦をなでるようにずらす（tick）
      for (var i = 0; i < upper.length; i++) {
        final t = start + i * gap;
        if (t < end) out.add(NoteSpec(t, end - t, upper[i], velocity));
      }
    case ChordRhythm.syncopated:
      final sixteenth = ppq ~/ 4;
      const hits = [0, 3, 6, 10, 12]; // 1小節（16分×16）の中で鳴らす位置
      for (var bar = start; bar < end; bar += sixteenth * 16) {
        for (var h = 0; h < hits.length; h++) {
          final t = bar + hits[h] * sixteenth;
          if (t >= end) break;
          final next = h + 1 < hits.length ? hits[h + 1] : 16;
          for (final p in upper) {
            out.add(NoteSpec(t, clampLen(t, (next - hits[h]) * sixteenth - 20), p, h == 0 ? velocity : velocity * 0.85));
          }
        }
      }
  }
  out.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.pitch.compareTo(b.pitch));
  return out;
}
