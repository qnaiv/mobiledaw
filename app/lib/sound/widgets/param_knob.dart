// ノブ部品：縦ドラッグで回し、ダブルタップで既定値に戻す。
// 値は 0〜1 の unit で受け渡しし、値そのものの変換（対数など）は呼び出し側が
// SoundParam.toUnit / fromUnit で行う。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme.dart';

class ParamKnob extends StatefulWidget {
  const ParamKnob({
    super.key,
    required this.label,
    required this.valueText,
    required this.unit,
    required this.color,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onReset,
    this.size = 62,
  });

  final String label;
  final String valueText;

  /// 0〜1（SoundParam.toUnit の結果）
  final double unit;
  final Color color;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  /// ダブルタップで呼ばれる（既定値リセット用）
  final VoidCallback? onReset;
  final double size;

  @override
  State<ParamKnob> createState() => _ParamKnobState();
}

class _ParamKnobState extends State<ParamKnob> {
  double? _dragUnit;
  double _startUnit = 0;
  double _startY = 0;

  double get _unit => (_dragUnit ?? widget.unit).clamp(0.0, 1.0);

  void _startDrag(DragStartDetails d) {
    _startUnit = _unit;
    _startY = d.globalPosition.dy;
    _dragUnit = _startUnit;
    widget.onChangeStart?.call();
  }

  void _updateDrag(DragUpdateDetails d) {
    // 200px の縦移動で全域。上へ引くと増える
    final u = (_startUnit + (_startY - d.globalPosition.dy) / 200).clamp(0.0, 1.0);
    setState(() => _dragUnit = u);
    widget.onChanged(u);
  }

  void _endDrag(DragEndDetails _) {
    final u = _unit;
    setState(() => _dragUnit = null);
    widget.onChangeEnd?.call(u);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onReset,
          onVerticalDragStart: _startDrag,
          onVerticalDragUpdate: _updateDrag,
          onVerticalDragEnd: _endDrag,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: KnobDialPainter(unit: _unit, color: widget.color, dim: DawColors.muted),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: DawColors.muted)),
        Text(widget.valueText,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}

/// ノブの円盤だけを描く（-135°〜+135° の 270° スイープ）
class KnobDialPainter extends CustomPainter {
  const KnobDialPainter({required this.unit, required this.color, required this.dim});

  final double unit;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 3;
    // 円盤の地
    canvas.drawCircle(center, r, Paint()..color = DawColors.background);
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..color = DawColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: center, radius: r - 3.5);
    // 値の無い側の弧
    canvas.drawArc(
        rect,
        start + sweep * unit,
        sweep * (1 - unit),
        false,
        Paint()
          ..color = dim.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    // 値の弧
    if (unit > 0.001) {
      canvas.drawArc(
          rect,
          start,
          sweep * unit,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round);
    }
    // 針
    final a = start + sweep * unit;
    final p1 = center + Offset(math.cos(a), math.sin(a)) * (r * 0.45);
    final p2 = center + Offset(math.cos(a), math.sin(a)) * (r * 0.78);
    canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = DawColors.text
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(KnobDialPainter old) => old.unit != unit || old.color != color;
}
