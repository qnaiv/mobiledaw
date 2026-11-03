import 'package:flutter/material.dart';

import '../music/scale.dart';
import 'theme.dart';

/// 縦ピアノロールの下に置く試聴用の鍵盤（スケール音だけ横一列）。
///
/// GestureDetector はタップかどうかの判定で発音が遅れるので、Listener で
/// 指が触れた瞬間に鳴らす。複数の指に対応し、指を滑らせると隣の音に移る。
class ScaleKeyboard extends StatefulWidget {
  const ScaleKeyboard({
    super.key,
    required this.notes,
    required this.rootPitchClass,
    required this.onNoteOn,
    required this.onNoteOff,
  });

  final List<int> notes;
  final int rootPitchClass;
  final void Function(int note, double velocity) onNoteOn;
  final void Function(int note) onNoteOff;

  @override
  State<ScaleKeyboard> createState() => _ScaleKeyboardState();
}

class _ScaleKeyboardState extends State<ScaleKeyboard> {
  /// 指（pointer id）ごとに押さえているノート
  final Map<int, int> _held = {};

  int? _noteAt(Offset local, Size size) {
    if (local.dx < 0 || local.dx >= size.width || local.dy < 0 || local.dy >= size.height) return null;
    final index = (local.dx / size.width * widget.notes.length).floor();
    return widget.notes[index.clamp(0, widget.notes.length - 1)];
  }

  /// 鍵盤の上の方を押すと弱く、下の方ほど強く鳴る
  double _velocityAt(Offset local, Size size) => (0.45 + 0.55 * (local.dy / size.height)).clamp(0.2, 1.0);

  void _press(int pointer, int note, double velocity) {
    _held[pointer] = note;
    widget.onNoteOn(note, velocity);
    setState(() {});
  }

  void _release(int pointer) {
    final note = _held.remove(pointer);
    if (note == null) return;
    // 他の指が同じ音を押さえていれば止めない
    if (!_held.containsValue(note)) widget.onNoteOff(note);
    setState(() {});
  }

  @override
  void didUpdateWidget(ScaleKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // オクターブが変わったら押さえている音を離す
    // （この直後に build されるので setState は不要）
    if (oldWidget.notes.first != widget.notes.first) {
      for (final pointer in _held.keys.toList()) {
        final note = _held.remove(pointer)!;
        if (!_held.containsValue(note)) oldWidget.onNoteOff(note);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final note = _noteAt(e.localPosition, size);
          if (note != null) _press(e.pointer, note, _velocityAt(e.localPosition, size));
        },
        onPointerMove: (e) {
          final note = _noteAt(e.localPosition, size);
          final current = _held[e.pointer];
          if (note == current) return;
          if (current != null) _release(e.pointer);
          if (note != null) _press(e.pointer, note, _velocityAt(e.localPosition, size));
        },
        onPointerUp: (e) => _release(e.pointer),
        onPointerCancel: (e) => _release(e.pointer),
        child: Row(
          children: [
            for (final note in widget.notes)
              Expanded(
                child: _Key(
                  label: noteName(note, withOctave: note % 12 == widget.rootPitchClass),
                  isRoot: note % 12 == widget.rootPitchClass,
                  isDown: _held.containsValue(note),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.isRoot, required this.isDown});

  final String label;
  final bool isRoot;
  final bool isDown;

  @override
  Widget build(BuildContext context) {
    final bg = isDown ? DawColors.lead : (isRoot ? DawColors.line : DawColors.panel);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 40),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDown ? DawColors.lead : DawColors.line),
        ),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          label,
          style: TextStyle(
            color: isDown ? DawColors.background : DawColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
