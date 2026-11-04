// 進行をえらぶシート：スタイルを選んで（おまかせも可）、押すたびに違う4案から選ぶ。
// クリップに置いてあるコードを読んで、入れる場所の前後に自然につながる案を出す。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../model/project.dart';
import '../music/chords.dart';
import '../music/progression_gen.dart';
import '../music/progressions.dart' show voiceProgression;
import '../music/scale.dart';
import '../music/voicing.dart';
import '../ui/theme.dart';

/// 進行のシート。入れたノートの ID を返す（入れなければ null）。[markerTick] はピアノロールの ▶（クリップ内、0 なら無し）
Future<List<int>?> showProgressionSheet(
  BuildContext context, {
  required SongController song,
  required ClipData clip,
  required Scale scale,
  required bool minor,
  int markerTick = 0,
  PlacementData? placement,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.background,
    showDragHandle: true,
    builder: (context) =>
        _ProgressionSheet(song: song, clip: clip, scale: scale, minor: minor, markerTick: markerTick, placement: placement),
  );
}

/// クリップに置いてあるコード（同時に鳴り始める3音以上を1つのコードとみなす）
class PlacedChord {
  const PlacedChord(this.tick, this.end, this.info);
  final int tick, end;
  final ChordInfo info;
}

List<PlacedChord> placedChords(ClipData clip) {
  final byTick = <int, List<NoteData>>{};
  for (final n in clip.notes) {
    byTick.putIfAbsent(n.tick, () => []).add(n);
  }
  final out = <PlacedChord>[];
  for (final e in byTick.entries) {
    if (e.value.length < 3) continue;
    final info = analyzeChord(e.value.map((n) => n.pitch));
    if (info == null) continue;
    out.add(PlacedChord(e.key, e.value.map((n) => n.tick + n.length).reduce(math.max), info));
  }
  out.sort((a, b) => a.tick.compareTo(b.tick));
  return out;
}

enum _Place { head, afterLast, marker }

class _ProgressionSheet extends StatefulWidget {
  const _ProgressionSheet(
      {required this.song,
      required this.clip,
      required this.scale,
      required this.minor,
      required this.markerTick,
      this.placement});

  final SongController song;
  final ClipData clip;
  final Scale scale;
  final bool minor;
  final int markerTick;
  final PlacementData? placement; // このクリップの置き場所（前後のパターンを探すため）

  @override
  State<_ProgressionSheet> createState() => _ProgressionSheetState();
}

class _ProgressionSheetState extends State<_ProgressionSheet> {
  final _gen = ProgressionGenerator();
  late final int _majorRoot = majorRootOf(widget.scale, minor: widget.minor);
  late final List<PlacedChord> _placed = placedChords(widget.clip);

  String? _styleId; // null ならおまかせ（案ごとにスタイルもランダム）
  int _bars = 4;
  _Place _place = _Place.head;
  ChordRhythm _rhythm = ChordRhythm.block;

  List<GenProgression> _props = const [];
  final List<List<GenProgression>> _history = [];
  int _selected = 0;
  final Set<int> _locked = {}; // 選んでいる案の中で固定したコード（何番目か）
  final List<Timer> _timers = [];

  SongController get song => widget.song;
  int get _ppq => ticksPerBeat;
  int get _tpb => song.project.ticksPerBar;

  @override
  void initState() {
    super.initState();
    // 置いてあるコードがあれば「最後のコードの次」、▶ があればそこを最初の候補に
    if (widget.markerTick > 0) {
      _place = _Place.marker;
    } else if (_placed.isNotEmpty) {
      _place = _Place.afterLast;
    }
    _props = _make(null);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  // ---- 入れる場所と前後 ----

  int get _startTick => switch (_place) {
        _Place.head => 0,
        _Place.marker => widget.markerTick,
        // 最後のコードの終わり（拍の頭にそろえる）
        _Place.afterLast => _placed.isEmpty ? 0 : ((_placed.last.end + _ppq - 1) ~/ _ppq) * _ppq,
      };

  int get _lengthTicks => _bars * _tpb;

  /// 同じトラックで、このパターンのすぐ前・すぐ後に置いてあるパターン（アレンジ画面で上・下）
  late final ClipData? _prevClip = _neighbor(before: true);
  late final ClipData? _nextClip = _neighbor(before: false);

  ClipData? _neighbor({required bool before}) {
    final pl = widget.placement;
    if (pl == null) return null;
    PlacementData? best;
    for (final o in song.project.placementsOn(pl.trackId)) {
      if (o.id == pl.id) continue;
      if (before && o.endBar <= pl.startBar && (best == null || o.endBar > best.endBar)) best = o;
      if (!before && o.startBar >= pl.endBar && (best == null || o.startBar < best.startBar)) best = o;
    }
    // 何小節も離れている（間が空いている）ものは、つながっていないとみなす
    if (best == null) return null;
    final gap = before ? pl.startBar - best.endBar : best.startBar - pl.endBar;
    return gap <= 1 ? song.project.clip(best.clipId) : null;
  }

  /// 入れる場所の前後のコード（表示名, 長調の中の位置, どこから）
  ({(String, String, String)? before, (String, String, String)? after}) _neighbors() {
    final start = _startTick, end = start + _lengthTicks;
    PlacedChord? before, after;
    for (final c in _placed) {
      if (c.tick < start) before = c;
      if (c.tick >= end && after == null) after = c;
    }
    (String, String, String) of(PlacedChord c, String where) => (c.info.name, baseOf(c.info, _majorRoot), where);
    var b = before != null ? of(before, '直前') : null;
    var a = after != null ? of(after, 'この後') : null;
    // クリップの中に無ければ、前のパターンの最後のコード
    if (b == null && _prevClip != null) {
      final prev = placedChords(_prevClip);
      if (prev.isNotEmpty) b = of(prev.last, '前のパターン');
    }
    // 入れる範囲がクリップの終わりまで届くなら、次のパターンの最初のコード
    if (a == null && end >= widget.clip.lengthTicks && _nextClip != null) {
      final next = placedChords(_nextClip);
      if (next.isNotEmpty) a = of(next.first, '次のパターン');
    }
    // それも無ければ、クリップの頭（ループして戻る先）
    if (a == null && _placed.isNotEmpty && _placed.first.tick < start) a = of(_placed.first, 'ループの頭');
    return (before: b, after: a);
  }

  GenContext get _context {
    final n = _neighbors();
    return GenContext(before: n.before?.$2, after: n.after?.$3 == 'ループの頭' ? null : n.after?.$2,
        loopHead: n.after?.$3 == 'ループの頭' ? n.after?.$2 : null);
  }

  String _contextLine() {
    final n = _neighbors();
    final left = n.before != null ? '${n.before!.$3} ${n.before!.$1} → ' : '';
    final right = n.after != null ? ' → ${n.after!.$3} ${n.after!.$1}' : ' → 頭に戻ってループ';
    return '$left［ここに入れる］$right';
  }

  // ---- 作る ----

  /// 4案作る。[base] を渡すと、その案の固定したコードと長さの並びを残す
  List<GenProgression> _make(GenProgression? base) {
    final style = _styleId == null ? null : styleById(_styleId!);
    final locked = <int, GenChord>{};
    if (base != null) {
      var pos = 0;
      for (var i = 0; i < base.chords.length; i++) {
        if (_locked.contains(i)) locked[pos] = base.chords[i];
        pos += base.chords[i].beats;
      }
    }
    return _gen.generate(
      style: style ?? base?.style,
      bars: _bars,
      minorKey: widget.minor,
      context: _context,
      keepRhythmOf: base?.chords,
      locked: locked,
    );
  }

  void _regenerate({bool keepLocks = true}) {
    final base = keepLocks && _locked.isNotEmpty && _props.isNotEmpty ? _props[_selected] : null;
    final props = _make(base);
    setState(() {
      if (_props.isNotEmpty) _history.add(_props);
      if (_history.length > 20) _history.removeAt(0);
      _props = props;
      _selected = 0;
      if (base == null) _locked.clear();
    });
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() {
      _props = _history.removeLast();
      _selected = 0;
      _locked.clear();
    });
  }

  List<Chord> _chordsOf(GenProgression p) => [for (final c in p.chords) realize(c, _majorRoot)].whereType<Chord>().toList();

  void _listen(GenProgression p) {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final voiced = voiceProgression(_chordsOf(p));
    // 試聴は少し速め（1拍 0.15〜0.35 秒）
    final beatMs = (60000 / song.project.tempo).clamp(150, 350).toInt();
    var at = 0;
    for (var i = 0; i < voiced.length && i < p.chords.length; i++) {
      final pitches = voiced[i];
      _timers.add(Timer(Duration(milliseconds: at), () => song.auditionChord(pitches)));
      at += p.chords[i].beats * beatMs;
    }
  }

  Future<void> _insert() async {
    if (_props.isEmpty) return;
    final p = _props[_selected];
    final chords = _chordsOf(p);
    final voiced = voiceProgression(chords);
    final start = _startTick;
    final notes = <NoteSpec>[];
    var t = start;
    for (var i = 0; i < voiced.length && i < p.chords.length; i++) {
      final len = p.chords[i].beats * _ppq;
      notes.addAll(rhythmize(voiced[i], start: t, length: len, rhythm: _rhythm));
      t += len;
    }
    final length = t - start;
    var replace = false;
    if (widget.clip.notes.any((n) => n.tick >= start && n.tick < start + length)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('もうノートがあります'),
          content: const Text('入れる範囲にあるノートをどうしますか？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('やめる')),
            TextButton(onPressed: () => Navigator.pop(context, 'overlay'), child: const Text('重ねる')),
            FilledButton(onPressed: () => Navigator.pop(context, 'replace'), child: const Text('置き換える')),
          ],
        ),
      );
      if (choice == null) return;
      replace = choice == 'replace';
    }
    final ids = song.insertProgression(widget.clip.id, notes, lengthTicks: length, replace: replace, startTick: start);
    if (mounted) Navigator.pop(context, ids);
  }

  // ---- 画面 ----

  @override
  Widget build(BuildContext context) {
    final startBar = _startTick / _tpb + 1;
    final where = switch (_place) {
      _Place.head => 'クリップの頭',
      _Place.afterLast => '最後のコードの次',
      _Place.marker => '▶の位置',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('進行をえらぶ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${noteName(widget.scale.root)} ${widget.minor ? 'minor' : 'major'} に合わせて移調ずみ · 押すたびに違う案',
                    style: const TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(height: 10),
                _label('スタイル'),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _styleChip(null, 'おまかせ 🎲'),
                      for (final s in genStyles) _styleChip(s.id, s.name),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final b in [4, 8])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$b小節'),
                          selected: _bars == b,
                          onSelected: (_) {
                            _bars = b;
                            _regenerate(keepLocks: false);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _label('入れる場所'),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _placeChip(_Place.head, 'クリップの頭'),
                  if (_placed.isNotEmpty) _placeChip(_Place.afterLast, '最後のコードの次'),
                  if (widget.markerTick > 0) _placeChip(_Place.marker, '▶の位置'),
                ]),
                const SizedBox(height: 6),
                Text(_contextLine(), style: const TextStyle(fontSize: 12, color: DawColors.accent)),
                const SizedBox(height: 10),
                for (var i = 0; i < _props.length; i++) _card(i),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _regenerate,
                        icon: const Icon(Icons.casino_outlined),
                        label: Text(_locked.isEmpty ? 'ほかの案' : 'ほかの案（固定したコードは残す）'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: '前の案に戻る',
                      onPressed: _history.isEmpty ? null : _back,
                      icon: const Icon(Icons.undo),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _label('リズム'),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final r in ChordRhythm.values)
                    ChoiceChip(label: Text(rhythmLabel(r)), selected: _rhythm == r, onSelected: (_) => setState(() => _rhythm = r)),
                ]),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _props.isEmpty ? null : _insert,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text('$where（${startBar % 1 == 0 ? startBar.toInt() : startBar.toStringAsFixed(2)}小節目）から $_bars小節 入れる',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: const TextStyle(fontSize: 12, color: DawColors.muted)),
      );

  Widget _styleChip(String? id, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: _styleId == id,
          onSelected: (_) {
            _styleId = id;
            _regenerate(keepLocks: false);
          },
        ),
      );

  Widget _placeChip(_Place p, String label) => ChoiceChip(
        label: Text(label),
        selected: _place == p,
        onSelected: (_) {
          _place = p;
          _regenerate(keepLocks: false);
        },
      );

  Widget _card(int i) {
    final p = _props[i];
    final selected = i == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: DawColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? DawColors.accent : DawColors.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              if (_selected != i) _locked.clear();
              _selected = i;
            });
            _listen(p);
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('案${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [if (_styleId == null) p.style.name, ...p.tags.toSet()].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: DawColors.muted),
                      ),
                    ),
                    if (selected) const Icon(Icons.volume_up, size: 16, color: DawColors.accent),
                  ],
                ),
                const SizedBox(height: 6),
                // コードを長さの割合で並べる（8小節は2段）
                for (final row in _rows(p))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        for (final (index, c) in row)
                          Expanded(
                            flex: c.beats,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: _chordCell(i, index, c, selected),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (selected)
                  const Text('コードをタップで固定 →「ほかの案」で残りだけ作り直す',
                      style: TextStyle(fontSize: 10, color: DawColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 4小節ごとの段（何番目のコードか、コード）
  List<List<(int, GenChord)>> _rows(GenProgression p) {
    final rows = <List<(int, GenChord)>>[[]];
    var beats = 0;
    for (var i = 0; i < p.chords.length; i++) {
      if (beats >= 16 && rows.last.isNotEmpty) {
        rows.add([]);
        beats = 0;
      }
      rows.last.add((i, p.chords[i]));
      beats += p.chords[i].beats;
    }
    return rows;
  }

  Widget _chordCell(int card, int index, GenChord c, bool selected) {
    final locked = selected && _locked.contains(index);
    return GestureDetector(
      onTap: selected
          ? () => setState(() => _locked.contains(index) ? _locked.remove(index) : _locked.add(index))
          : null,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: locked ? DawColors.accent : DawColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: locked ? DawColors.accent : DawColors.line),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(chordName(c, _majorRoot),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: locked ? DawColors.background : DawColors.text)),
          ),
        ),
      ),
    );
  }
}
