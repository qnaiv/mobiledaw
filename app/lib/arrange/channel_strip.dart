// チャンネルストリップ：ミキサーの1列分（トラック／マスター）。
// 読み書きはコールバックで受けるので、テストでは偽のコールバックで pump できる。
// レベルメーターは ValueListenable<double>（線形ピーク）を受け、タイマー側が
// 減衰込みの値を流す。コアのピークは「読んでから最大値」の保持だけ。
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sound/sound_params.dart';
import '../sound/widgets/param_knob.dart';
import '../ui/theme.dart';

/// 音量（倍率）を dB の文字に
String gainLabel(double gain) {
  if (gain <= 0.0005) return '-∞ dB';
  final db = 20 * math.log(gain) / math.ln10;
  return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
}

String panLabel(double pan) {
  final v = (pan * 100).round();
  if (v == 0) return 'C';
  return v < 0 ? 'L${-v}' : 'R$v';
}

/// メーター表示値の更新：コアから読んだピークと、減衰した前回値の大きい方。
/// 50ms ごとに呼ぶ前提（約1秒で 5% まで落ちる）。
double nextMeterLevel(double rawPeak, double previous) {
  final decayed = previous * 0.86;
  return rawPeak > decayed ? rawPeak : decayed;
}

/// 細い縦のレベルメーター。level は線形ピーク（1.0 = 0dBFS、超えたら赤）
class PeakMeterBar extends StatelessWidget {
  const PeakMeterBar({super.key, required this.level, this.width = 7, this.height = 132});

  final ValueListenable<double> level;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, v, _) => CustomPaint(
        size: Size(width, height),
        painter: _MeterPainter(v),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter(this.level);
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = DawColors.panel,
    );
    final frac = level.clamp(0.0, 1.0);
    if (frac <= 0.001) return;
    // グラデーションは全体の高さで作り、下から frac 分だけ塗る（色が縮まないように）
    final grad = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xFF58C472), Color(0xFF58C472), Color(0xFFE8C85A), Color(0xFFF2555A)],
      stops: [0.0, 0.62, 0.82, 0.97],
    );
    final fill = Rect.fromLTWH(0, size.height * (1 - frac), size.width, size.height * frac);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fill, const Radius.circular(2)),
      Paint()..shader = grad.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MeterPainter old) => old.level != level;
}

/// 縦フェーダー。ドラッグ中は自分の値を保持する（ParamKnob と同じ流儀）。
/// ダブルタップで onReset（既定値に戻す）。
class VerticalFader extends StatefulWidget {
  const VerticalFader({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onReset,
    this.height = 132,
    this.width = 34,
  });

  final double value, min, max;
  final Color color;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final VoidCallback? onReset;
  final double height;
  final double width;

  @override
  State<VerticalFader> createState() => _VerticalFaderState();
}

class _VerticalFaderState extends State<VerticalFader> {
  double? _dragValue;
  double _startValue = 0;
  double _startY = 0;

  double get _value => (_dragValue ?? widget.value).clamp(widget.min, widget.max).toDouble();
  double get _unit => widget.max == widget.min ? 0 : (_value - widget.min) / (widget.max - widget.min);

  void _startDrag(DragStartDetails d) {
    _startValue = _value;
    _startY = d.globalPosition.dy;
    _dragValue = _startValue;
    widget.onChangeStart?.call();
  }

  void _updateDrag(DragUpdateDetails d) {
    // フェーダーの高さいっぱいの移動で全域。上へ引くと増える
    final range = widget.max - widget.min;
    final v = (_startValue + (_startY - d.globalPosition.dy) / widget.height * range)
        .clamp(widget.min, widget.max)
        .toDouble();
    setState(() => _dragValue = v);
    widget.onChanged(v);
  }

  void _endDrag(DragEndDetails _) {
    final v = _value;
    setState(() => _dragValue = null);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.onReset,
      onVerticalDragStart: _startDrag,
      onVerticalDragUpdate: _updateDrag,
      onVerticalDragEnd: _endDrag,
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _FaderPainter(unit: _unit, color: widget.color),
      ),
    );
  }
}

class _FaderPainter extends CustomPainter {
  const _FaderPainter({required this.unit, required this.color});
  final double unit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const pad = 8.0; // つまみの半分だけ上下に余白
    final top = pad;
    final bottom = size.height - pad;
    final y = bottom - (bottom - top) * unit;
    // レール
    canvas.drawLine(
      Offset(cx, top),
      Offset(cx, bottom),
      Paint()
        ..color = DawColors.line
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // 値のある側
    if (unit > 0.001) {
      canvas.drawLine(
        Offset(cx, y),
        Offset(cx, bottom),
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    // 目盛り（中央）
    canvas.drawLine(
      Offset(cx - 7, (top + bottom) / 2),
      Offset(cx + 7, (top + bottom) / 2),
      Paint()
        ..color = DawColors.muted.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    // つまみ
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: size.width - 4, height: 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(thumb, Paint()..color = DawColors.text);
    canvas.drawRRect(
      thumb,
      Paint()
        ..color = DawColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(cx - 9, y),
      Offset(cx + 9, y),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FaderPainter old) => old.unit != unit || old.color != color;
}

class _StripToggle extends StatelessWidget {
  const _StripToggle({required this.label, required this.on, required this.onColor, required this.onTap});

  final String label;
  final bool on;
  final Color onColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? onColor : DawColors.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? onColor : DawColors.line),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: on ? DawColors.background : DawColors.muted)),
      ),
    );
  }
}

/// トラック1本分のストリップ。
/// センドは SoundParam 経由（従来の読み書き経路と同じ）。
class ChannelStrip extends StatelessWidget {
  const ChannelStrip({
    super.key,
    required this.name,
    required this.color,
    required this.selected,
    required this.dimmed,
    required this.gain,
    required this.pan,
    required this.mute,
    required this.solo,
    required this.sendReverbParam,
    required this.sendReverb,
    required this.sendDelayParam,
    required this.sendDelay,
    required this.peak,
    required this.onSelect,
    required this.onRename,
    required this.onGainChanged,
    this.onGainStart,
    this.onGainEnd,
    required this.onPanChanged,
    required this.onSendChanged,
    this.onKnobStart,
    this.onKnobEnd,
    required this.onMuteToggle,
    required this.onSoloToggle,
  });

  final String name;
  final Color color;
  final bool selected;

  /// ミュート中、または他のソロで鳴らない状態（薄く表示）
  final bool dimmed;
  final double gain; // 0〜2
  final double pan; // -1〜1
  final bool mute;
  final bool solo;
  final SoundParam sendReverbParam;
  final double sendReverb;
  final SoundParam sendDelayParam;
  final double sendDelay;

  /// 減衰込みの表示用ピーク（線形）
  final ValueListenable<double> peak;

  final VoidCallback onSelect;
  final VoidCallback onRename;
  final ValueChanged<double> onGainChanged;
  final VoidCallback? onGainStart;
  final ValueChanged<double>? onGainEnd;

  final ValueChanged<double> onPanChanged;

  /// センド量の変更（param, 値）
  final void Function(SoundParam param, double value) onSendChanged;
  final VoidCallback? onKnobStart;
  final ValueChanged<double>? onKnobEnd;
  final VoidCallback onMuteToggle;
  final VoidCallback onSoloToggle;

  static const double stripWidth = 100;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        width: stripWidth,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: DawColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : DawColors.line, width: selected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 色＋名前（タップで選択、鉛筆で名前変更）
            InkWell(
              onTap: onSelect,
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  InkWell(
                    onTap: onRename,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.edit, size: 13, color: DawColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // パン
            ParamKnob(
              label: 'パン',
              valueText: panLabel(pan),
              unit: (pan + 1) / 2,
              color: color,
              size: 44,
              onChangeStart: onKnobStart,
              onChangeEnd: onKnobEnd,
              onReset: () => onPanChanged(0),
              onChanged: (u) => onPanChanged(u * 2 - 1),
            ),
            const SizedBox(height: 6),
            // センド2つ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SendKnob(param: sendReverbParam, value: sendReverb, label: 'REV', color: color, strip: this),
                _SendKnob(param: sendDelayParam, value: sendDelay, label: 'DLY', color: color, strip: this),
              ],
            ),
            const SizedBox(height: 8),
            // フェーダー＋メーター
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PeakMeterBar(level: peak),
                const SizedBox(width: 5),
                VerticalFader(
                  value: gain,
                  min: 0,
                  max: 2,
                  color: color,
                  onChanged: onGainChanged,
                  onChangeStart: onGainStart,
                  onChangeEnd: onGainEnd,
                  onReset: () => onGainChanged(1),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(gainLabel(gain),
                style: const TextStyle(fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StripToggle(label: 'M', on: mute, onColor: DawColors.danger, onTap: onMuteToggle),
                _StripToggle(label: 'S', on: solo, onColor: DawColors.accent, onTap: onSoloToggle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SendKnob extends StatelessWidget {
  const _SendKnob({required this.param, required this.value, required this.label, required this.color, required this.strip});

  final SoundParam param;
  final double value;
  final String label;
  final Color color;
  final ChannelStrip strip;

  @override
  Widget build(BuildContext context) {
    return ParamKnob(
      label: label,
      valueText: param.format(value),
      unit: param.toUnit(value),
      color: color,
      size: 34,
      onChangeStart: strip.onKnobStart,
      onChangeEnd: strip.onKnobEnd,
      onReset: () => strip.onSendChanged(param, param.def),
      onChanged: (u) => strip.onSendChanged(param, param.fromUnit(u)),
    );
  }
}

/// マスターのストリップ（右端固定）。音量フェーダー＋メーターだけの簡易表示。
/// 仕上げ（グルー等）はミキサーシート下部のカードで変える。
class MasterStrip extends StatelessWidget {
  const MasterStrip({
    super.key,
    required this.gain,
    required this.peak,
    required this.onGainChanged,
    this.onGainStart,
    this.onGainEnd,
  });

  final double gain; // 0.5〜6
  final ValueListenable<double> peak;
  final ValueChanged<double> onGainChanged;
  final VoidCallback? onGainStart;
  final ValueChanged<double>? onGainEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: DawColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DawColors.accent.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.volume_up, size: 14, color: DawColors.accent),
              SizedBox(width: 4),
              Expanded(
                child: Text('マスター',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 高さはトラック側と揃えない（並べる側が下揃えでフェーダー位置を合わせる）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PeakMeterBar(level: peak),
              const SizedBox(width: 5),
              VerticalFader(
                value: gain,
                min: 0.5,
                max: 6,
                color: DawColors.accent,
                onChanged: onGainChanged,
                onChangeStart: onGainStart,
                onChangeEnd: onGainEnd,
                onReset: () => onGainChanged(3.2),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(gainLabel(gain),
              style: const TextStyle(fontSize: 11, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 6),
          const SizedBox(height: 28), // M/S の段の分
        ],
      ),
    );
  }
}
