import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../model/project.dart';
import '../music/chords.dart';
import '../music/progressions.dart';
import '../music/scale.dart';
import '../music/voicing.dart';
import '../ui/theme.dart';

/// 気分の進行・サイコロのシート。入れたノートの ID を返す（入れなければ null）
Future<List<int>?> showProgressionSheet(
  BuildContext context, {
  required SongController song,
  required ClipData clip,
  required Scale scale,
  required bool minor,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.background,
    showDragHandle: true,
    builder: (context) => _ProgressionSheet(song: song, clip: clip, scale: scale, minor: minor),
  );
}

class _ProgressionSheet extends StatefulWidget {
  const _ProgressionSheet({required this.song, required this.clip, required this.scale, required this.minor});

  final SongController song;
  final ClipData clip;
  final Scale scale;
  final bool minor;

  @override
  State<_ProgressionSheet> createState() => _ProgressionSheetState();
}

class _ProgressionSheetState extends State<_ProgressionSheet> {
  final _rng = math.Random();
  late final List<Chord> _diatonic = diatonicChords(widget.scale, minor: widget.minor);
  late final List<ProgressionPreset> _presets = widget.minor ? minorPresets : majorPresets;

  int? _preset = 0; // 選んでいる気分（null ならサイコロ）
  List<int> _dice = const [];
  final List<bool> _locked = [false, false, false, false];
  double _brightness = 0.5;
  double _surprise = 0.3;
  bool _perBar = true; // 1小節に1つ（false なら2拍に1つ）
  ChordRhythm _rhythm = ChordRhythm.block;

  SongController get song => widget.song;

  /// いま選んでいる進行のコード
  List<Chord> get _chords {
    final p = _preset;
    if (p != null) {
      return [for (final r in _presets[p].romans) chordFromRoman(r, widget.scale)].whereType<Chord>().toList();
    }
    return [for (final d in _dice) _diatonic[d]];
  }

  int get _slot => _perBar ? song.project.ticksPerBar : song.project.ticksPerBar ~/ 2;

  void _roll() {
    final degrees = rollProgression(
      minor: widget.minor,
      brightness: _brightness,
      surprise: _surprise,
      locked: [for (var i = 0; i < 4; i++) _locked[i] && _dice.length == 4 ? _dice[i] : null],
      rng: _rng,
      chords: _diatonic,
    );
    setState(() {
      _dice = degrees;
      _preset = null;
    });
    _listen();
  }

  void _listen() {
    final chords = _chords;
    if (chords.isEmpty) return;
    song.auditionSequence(voiceProgression(chords));
  }

  Future<void> _insert() async {
    final chords = _chords;
    if (chords.isEmpty) return;
    final slot = _slot;
    final length = slot * chords.length;
    final voiced = voiceProgression(chords);
    final notes = <NoteSpec>[
      for (var i = 0; i < voiced.length; i++) ...rhythmize(voiced[i], start: i * slot, length: slot, rhythm: _rhythm),
    ];
    var replace = false;
    if (widget.clip.notes.any((n) => n.tick < length)) {
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
    final ids = song.insertProgression(widget.clip.id, notes, lengthTicks: length, replace: replace);
    if (mounted) Navigator.pop(context, ids);
  }

  @override
  Widget build(BuildContext context) {
    final chords = _chords;
    final bars = (_slot * math.max(chords.length, 1) / song.project.ticksPerBar).ceil();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('進行をえらぶ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('${noteName(widget.scale.root)} ${widget.minor ? 'minor' : 'major'} に合わせて移調ずみ',
                    style: const TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(height: 10),
                _label('気分から選ぶ'),
                LayoutBuilder(builder: (context, box) {
                  final w = (box.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _presets.length; i++)
                        SizedBox(width: w, child: _presetCard(i)),
                    ],
                  );
                }),
                const SizedBox(height: 14),
                _label('サイコロで作る'),
                _slider('暗い', '明るい', _brightness, (v) => setState(() => _brightness = v)),
                _slider('安定', '意外', _surprise, (v) => setState(() => _surprise = v)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _diceCell(i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _roll,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(_dice.isEmpty ? '振る' : 'もう一度振る（固定した所は残る）'),
                ),
                const SizedBox(height: 14),
                _label('入れ方'),
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('1小節に1つ'), selected: _perBar, onSelected: (_) => setState(() => _perBar = true)),
                  ChoiceChip(label: const Text('2拍に1つ'), selected: !_perBar, onSelected: (_) => setState(() => _perBar = false)),
                ]),
                const SizedBox(height: 10),
                _label('リズム'),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final r in ChordRhythm.values)
                    ChoiceChip(label: Text(rhythmLabel(r)), selected: _rhythm == r, onSelected: (_) => setState(() => _rhythm = r)),
                ]),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: chords.isEmpty ? null : _listen,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('試聴'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: chords.isEmpty ? null : _insert,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: Text('クリップの頭から $bars小節 入れる', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
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

  Widget _presetCard(int i) {
    final p = _presets[i];
    final selected = _preset == i;
    final names = [for (final r in p.romans) chordFromRoman(r, widget.scale)?.name ?? r].join('  ');
    return Material(
      color: DawColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? DawColors.accent : DawColors.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _preset = i);
          _listen();
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(names, maxLines: 2, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              Text(p.mood, style: const TextStyle(fontSize: 11, color: DawColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(String left, String right, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(left, style: const TextStyle(fontSize: 12, color: DawColors.muted))),
        Expanded(child: Slider(value: value, onChanged: onChanged)),
        SizedBox(
          width: 36,
          child: Text(right, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: DawColors.muted)),
        ),
      ],
    );
  }

  Widget _diceCell(int i) {
    final has = _dice.length == 4;
    final locked = _locked[i];
    final name = has ? _diatonic[_dice[i]].name : '?';
    return Material(
      color: DawColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: locked ? DawColors.accent : DawColors.line, width: locked ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: has
            ? () => setState(() {
                  _locked[i] = !_locked[i];
                  _preset = null;
                })
            : null,
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text(locked ? '固定' : (has ? 'タップで固定' : ''),
                  style: TextStyle(fontSize: 10, color: locked ? DawColors.accent : DawColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
