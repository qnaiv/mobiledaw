// キーとスケールをえらぶシート。ルート音とスケールを選んで「決める」で曲に反映する
// （ロールの列・コード候補・進行生成が全部そのスケールに合う）。反映は1回の編集（1回の Undo）。
import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../music/scale.dart';
import '../ui/theme.dart';

Future<void> showKeyScaleSheet(BuildContext context, {required SongController song}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.background,
    showDragHandle: true,
    builder: (context) => _KeyScaleSheet(song: song),
  );
}

class _KeyScaleSheet extends StatefulWidget {
  const _KeyScaleSheet({required this.song});

  final SongController song;

  @override
  State<_KeyScaleSheet> createState() => _KeyScaleSheetState();
}

class _KeyScaleSheetState extends State<_KeyScaleSheet> {
  late int _root = widget.song.project.keyRoot;
  late String _scaleId = widget.song.project.scale;

  ScaleKind get _kind => scaleKindOf(_scaleId);
  bool get _changed => _root != widget.song.project.keyRoot || _scaleId != widget.song.project.scale;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('キーとスケール', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('選ぶと、ロールの列・コード候補・進行生成が全部そのスケールに合います',
                    style: TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(height: 12),
                const Text('ルート音', style: TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 12; i++)
                      ChoiceChip(
                        label: Text(noteName(i)),
                        selected: _root == i,
                        onSelected: (_) => setState(() => _root = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('スケール', style: TextStyle(fontSize: 12, color: DawColors.muted)),
                const SizedBox(height: 6),
                for (final k in scaleKinds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: DawColors.panel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: _scaleId == k.id ? DawColors.accent : DawColors.line),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _scaleId = k.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                _scaleId == k.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                size: 18,
                                color: _scaleId == k.id ? DawColors.accent : DawColors.muted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(k.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    Text(k.description,
                                        style: const TextStyle(fontSize: 11, color: DawColors.muted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _changed
                      ? () {
                          widget.song.setKey(_root, _scaleId);
                          Navigator.pop(context);
                        }
                      : null,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text('${noteName(_root)} ${_kind.label} に決める',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
