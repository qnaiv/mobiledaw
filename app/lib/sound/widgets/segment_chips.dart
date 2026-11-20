// セグメント選択：横並びチップで整数値を1つ選ぶ（音価・モード切替用）。
import 'package:flutter/material.dart';

import '../../ui/theme.dart';

class SegmentChips extends StatelessWidget {
  const SegmentChips({
    super.key,
    required this.options,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final List<(int, String)> options;
  final int selected;
  final Color color;
  final void Function(int value) onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (value, label) in options)
          InkWell(
            onTap: () => onSelected(value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: value == selected ? color : Colors.transparent,
                border: Border.all(color: value == selected ? color : DawColors.line),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: value == selected ? FontWeight.w700 : FontWeight.w400,
                      color: value == selected ? const Color(0xFF111214) : DawColors.text)),
            ),
          ),
      ],
    );
  }
}
