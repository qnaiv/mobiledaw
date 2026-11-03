import 'package:flutter/material.dart';

import '../music/chords.dart';
import '../music/voicing.dart';
import '../ui/theme.dart';

/// 選んだコードのすぐ下（または上）に浮かぶ道具の帯（案A）
class ChordToolsBar extends StatelessWidget {
  const ChordToolsBar({
    super.key,
    required this.info,
    required this.closed,
    required this.bassLabel,
    required this.onInvert,
    required this.onSpread,
    required this.onBass,
    required this.onLead,
    required this.onSeventh,
    required this.onSus,
    required this.onNinth,
    required this.onRhythm,
  });

  static const double height = 94;

  final ChordInfo info;
  final bool closed;
  final String bassLabel;
  final void Function(bool up) onInvert;
  final VoidCallback onSpread;
  final VoidCallback onBass;
  final VoidCallback onLead;
  final VoidCallback onSeventh;
  final void Function(int to) onSus;
  final VoidCallback onNinth;
  final void Function(ChordRhythm rhythm) onRhythm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DawColors.panel,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF4A4F58)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('${info.name}  ${info.inversion}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  _Chip(label: '↑転回', onTap: () => onInvert(true)),
                  _Chip(label: '↓転回', onTap: () => onInvert(false)),
                  _Chip(label: closed ? '広げる' : '閉じる', onTap: onSpread),
                  _Chip(label: 'ベース $bassLabel', onTap: onBass),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(label: '寄せる', onTap: onLead),
                  _Chip(label: '7th', active: info.hasSeventh, onTap: onSeventh),
                  _Chip(label: 'sus4', active: info.hasSus4, onTap: () => onSus(5)),
                  _Chip(label: 'sus2', active: info.hasSus2, onTap: () => onSus(2)),
                  _Chip(label: 'add9', active: info.hasNinth, onTap: onNinth),
                  PopupMenuButton<ChordRhythm>(
                    tooltip: 'リズムにする',
                    color: DawColors.panel,
                    onSelected: onRhythm,
                    itemBuilder: (context) => [
                      for (final r in ChordRhythm.values) PopupMenuItem(value: r, child: Text(rhythmLabel(r))),
                    ],
                    child: const _ChipBody(label: 'リズム ▾', active: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: _ChipBody(label: label, active: active),
      ),
    );
  }
}

class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? DawColors.text : DawColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? DawColors.text : DawColors.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          color: active ? DawColors.background : DawColors.text,
        ),
      ),
    );
  }
}
