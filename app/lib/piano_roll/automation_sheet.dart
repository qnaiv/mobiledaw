// オートメーション編集シート：ピアノロールのヘッダーから開く（クリップ単位の編集）。
// パラメータを選んで、タップでポイント追加・ドラッグで移動・長押しで削除。
// 確定はジェスチャーの終わりに1回だけ（= 1 Undo）。再生への適用はコア側
// （スナップショットに展開済みのポイント列をエンジンが補間する）。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../arrange/song_controller.dart';
import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../sound/sound_params.dart';
import '../ui/theme.dart';

Future<void> showAutomationSheet(BuildContext context, SongController song, int clipId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DawColors.panel,
    builder: (context) => _AutomationSheet(song: song, clipId: clipId),
  );
}

/// 編集できる対象。音量だけはシンセ/FX ではなくトラックの gain（専用 ID）
final _gainParam = const SoundParam(MdawParam.trackGain, 'gain', '音量', 0, 2, 1, unit: '%');

List<SoundParam> get _targets => [
      _gainParam,
      for (final key in ['cutoffHz', 'wtPos', 'masterGain', 'reverb', 'delay'])
        allSoundParams.firstWhere((p) => p.key == key),
    ];

class _AutomationSheet extends StatefulWidget {
  const _AutomationSheet({required this.song, required this.clipId});

  final SongController song;
  final int clipId;

  @override
  State<_AutomationSheet> createState() => _AutomationSheetState();
}

class _AutomationSheetState extends State<_AutomationSheet> {
  late SoundParam _target = _targets.first;
  List<(int, double)> _points = const [];
  int? _dragIndex; // ドラッグ中のポイント
  double? _lastValue; // 読み出し表示用（最後に触ったポイントの値）

  ClipData? get _clip => widget.song.clip(widget.clipId);

  @override
  void initState() {
    super.initState();
    _loadLane();
  }

  void _loadLane() {
    final lane = _clip?.automationLane(_target.key);
    _points = lane == null ? const [] : List.of(lane.points);
    _lastValue = _points.isEmpty ? null : _points.last.$2;
  }

  void _selectTarget(SoundParam p) {
    setState(() {
      _target = p;
      _dragIndex = null;
      _loadLane();
    });
  }

  /// 編集をコアへ確定する（1回 = 1 Undo）
  void _commit() {
    final sorted = List.of(_points)..sort((a, b) => a.$1.compareTo(b.$1));
    widget.song.setClipAutomation(widget.clipId, _target.id, sorted);
    _loadLane(); // コア側で整形された形（丸め・重複解消）にそろえる
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    if (clip == null) {
      return const SizedBox(height: 200, child: Center(child: Text('このクリップはもうありません')));
    }
    final project = widget.song.project;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('オートメーション', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (_points.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _points = const [];
                      _lastValue = null;
                      _commit();
                    }),
                    child: const Text('レーンを消す'),
                  ),
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in _targets)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: p.key == _target.key,
                    onSelected: (_) => _selectTarget(p),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _laneCanvas(clip, project.ticksPerBar),
            const SizedBox(height: 8),
            Text(
              _points.isEmpty
                  ? 'タップでポイントを追加。ポイントの前は今の音色・音量のままです'
                  : 'ドラッグで移動、長押しで削除。今の値：${_target.format(_lastValue ?? _points.last.$2)}',
              style: const TextStyle(fontSize: 12, color: DawColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _laneCanvas(ClipData clip, int ticksPerBar) {
    const height = 200.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Offset toOffset((int, double) pt) => Offset(
              pt.$1 / clip.lengthTicks * width,
              (1 - _target.toUnit(pt.$2)) * height,
            );
        (int, double) fromOffset(Offset o) {
          final snap = math.max(1, ticksPerBar ~/ 16);
          final tick = ((o.dx / width * clip.lengthTicks) / snap).round() * snap;
          return (
            tick.clamp(0, clip.lengthTicks),
            _target.fromUnit(1 - (o.dy / height).clamp(0.0, 1.0)),
          );
        }

        int? nearestIndex(Offset o) {
          var best = -1;
          var bestDist = 24.0; // ポイントに近いタップは移動として扱う
          for (var i = 0; i < _points.length; i++) {
            final d = (toOffset(_points[i]) - o).distance;
            if (d < bestDist) {
              bestDist = d;
              best = i;
            }
          }
          return best < 0 ? null : best;
        }

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: DawColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DawColors.line),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final near = nearestIndex(d.localPosition);
              if (near != null) {
                _dragIndex = near;
              } else {
                final pt = fromOffset(d.localPosition);
                setState(() {
                  _points = [..._points, pt]..sort((a, b) => a.$1.compareTo(b.$1));
                  _dragIndex = _points.indexOf(pt);
                  _lastValue = pt.$2;
                });
              }
            },
            onPanStart: (d) => _dragIndex ??= nearestIndex(d.localPosition),
            onPanUpdate: (d) {
              final i = _dragIndex;
              if (i == null) return;
              final pt = fromOffset(d.localPosition);
              setState(() {
                // 同じ tick に寄せたら既存の方を消す（コア側の「後勝ち」と同じ見え方に）
                _points = [
                  for (var j = 0; j < _points.length; j++)
                    if (j != i && _points[j].$1 != pt.$1) _points[j],
                  pt,
                ]..sort((a, b) => a.$1.compareTo(b.$1));
                _dragIndex = _points.indexOf(pt);
                _lastValue = pt.$2;
              });
            },
            onPanEnd: (_) {
              _dragIndex = null;
              setState(_commit);
            },
            onTapUp: (_) {
              if (_dragIndex != null) {
                _dragIndex = null;
                setState(_commit);
              }
            },
            onLongPressStart: (d) {
              final i = nearestIndex(d.localPosition);
              if (i == null) return;
              setState(() {
                _points = [..._points]..removeAt(i);
                _dragIndex = null;
                _commit();
              });
            },
            child: CustomPaint(
              size: Size(width, height),
              painter: _LanePainter(
                points: _points,
                toUnit: _target.toUnit,
                lengthTicks: clip.lengthTicks,
                ticksPerBar: ticksPerBar,
                selected: _dragIndex,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanePainter extends CustomPainter {
  const _LanePainter({
    required this.points,
    required this.toUnit,
    required this.lengthTicks,
    required this.ticksPerBar,
    required this.selected,
  });

  final List<(int, double)> points;
  final double Function(double) toUnit;
  final int lengthTicks;
  final int ticksPerBar;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = DawColors.line
      ..strokeWidth = 1;
    // 拍ごとの縦線
    final beat = ticksPerBar / 4;
    for (var t = beat; t < lengthTicks; t += beat) {
      final x = t / lengthTicks * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), grid);

    if (points.isEmpty) return;
    Offset at(int i) => Offset(
          points[i].$1 / lengthTicks * size.width,
          (1 - toUnit(points[i].$2)) * size.height,
        );
    final line = Paint()
      ..color = DawColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    path.lineTo(size.width, at(points.length - 1).dy); // 最後の値は右端まで保持
    canvas.drawPath(path, line);

    final dot = Paint()..color = DawColors.accent;
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(at(i), i == selected ? 7 : 5, dot);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.points != points || old.selected != selected || old.lengthTicks != lengthTicks;
}
