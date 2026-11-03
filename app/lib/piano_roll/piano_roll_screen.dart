import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../arrange/song_controller.dart';
import '../arrange/timeline_math.dart';
import '../model/project.dart';
import '../music/scale.dart';
import '../ui/scale_keyboard.dart';
import '../ui/theme.dart';
import 'roll_math.dart';

enum _Tool { pen, select }

enum _DragKind { create, move, resize, marquee }

/// 指でなぞっている間の状態（指を離したら1つの編集コマンドにする）
class _Drag {
  _Drag({required this.kind, required this.start, this.ids = const [], this.anchorPitch = 0, this.anchorCol = 0})
      : current = start;

  final _DragKind kind;
  final Offset start;
  Offset current;
  final List<int> ids; // move / resize の対象
  final int anchorPitch; // move で掴んだノートの音程
  final int anchorCol; // move で掴んだノートの列
  int lastAuditioned = -1;
}

/// ② ノート入力（縦ピアノロール）。時間は下へ、音の高さは右へ。下に試聴鍵盤。
class PianoRollScreen extends StatefulWidget {
  const PianoRollScreen({super.key, required this.song, required this.placementId});

  final SongController song;
  final int placementId;

  @override
  State<PianoRollScreen> createState() => _PianoRollScreenState();
}

class _PianoRollScreenState extends State<PianoRollScreen> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _playhead = ValueNotifier<int?>(null); // クリップ先頭からの tick。再生していないときは null
  late final Ticker _ticker;

  _Tool _tool = _Tool.pen;
  int _step = ticksPerBeat ~/ 2; // 1/8
  int _octave = 4;
  bool _chromatic = false;
  final Set<int> _selection = {};
  _Drag? _drag;

  SongController get song => widget.song;

  PlacementData? get _placement {
    for (final pl in song.project.placements) {
      if (pl.id == widget.placementId) return pl;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final pl = _placement;
    final clip = pl == null ? null : song.clip(pl.clipId);
    if (pl != null && clip != null) {
      _octave = bestOctave(clip, scaleOf(song.project));
      song.previewTrack(pl.trackId);
    }
    _ticker = createTicker((_) => _playhead.value = _localPlayhead())..start();
  }

  int? _localPlayhead() {
    final pl = _placement;
    if (pl == null || !song.engine.isPlaying) return null;
    final clip = song.clip(pl.clipId);
    if (clip == null || clip.lengthTicks <= 0) return null;
    final tpb = song.project.ticksPerBar;
    final pos = song.engine.positionTicks - pl.startBar * tpb;
    if (pos < 0 || pos >= pl.lengthBars * tpb) return null;
    return pos % clip.lengthTicks;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _playhead.dispose();
    _scroll.dispose();
    song.engine.allNotesOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: song,
      builder: (context, _) {
        final pl = _placement;
        final clip = pl == null ? null : song.clip(pl.clipId);
        if (pl == null || clip == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: DawColors.background),
            body: const Center(child: Text('このクリップはもうありません', style: TextStyle(color: DawColors.muted))),
          );
        }
        _selection.removeWhere((id) => clip.notes.every((n) => n.id != id));
        final project = song.project;
        final scale = scaleOf(project);
        final columns = rollColumns(scale, _octave, chromatic: _chromatic);
        final track = project.track(pl.trackId);
        final label = clipLabels(project)[clip.id] ?? '';
        final (below, above) = hiddenNotes(clip, columns);

        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(track, label, pl, scale),
                _toolbar(clip),
                Expanded(child: _roll(clip, columns, scale, track)),
                if (below + above > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      [
                        if (above > 0) '↑ 上のオクターブに $above 個',
                        if (below > 0) '↓ 下のオクターブに $below 個',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: DawColors.muted),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24 + RollGeometry.labelWidth, 8, 24, 0),
                  child: SizedBox(
                    height: 64,
                    child: ScaleKeyboard(
                      notes: columns,
                      rootPitchClass: scale.root,
                      onNoteOn: (note, velocity) => song.engine.noteOn(note, velocity),
                      onNoteOff: (note) => song.engine.noteOff(note),
                    ),
                  ),
                ),
                _bottomControls(columns),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- ヘッダーと道具 -----------------------------------------------------------

  Widget _header(TrackData? track, String label, PlacementData pl, Scale scale) {
    final key = '${noteName(scale.root)} ${song.project.scale}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'アレンジへ戻る',
            icon: const Icon(Icons.chevron_left),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: DawColors.panel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: DawColors.line),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${track?.name ?? ''} · クリップ $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '小節 ${pl.startBar + 1}–${pl.endBar} · ${_chromatic ? '全音表示' : '$key のみ表示'}',
                  style: const TextStyle(fontSize: 12, color: DawColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(ClipData clip) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _ToolChip(
            icon: Icons.edit_outlined,
            label: 'ペン',
            active: _tool == _Tool.pen,
            onTap: () => setState(() {
              _tool = _Tool.pen;
              _selection.clear();
            }),
          ),
          const SizedBox(width: 6),
          _ToolChip(
            icon: Icons.highlight_alt,
            label: '選択',
            active: _tool == _Tool.select,
            onTap: () => setState(() => _tool = _Tool.select),
          ),
          const Spacer(),
          if (_selection.isNotEmpty)
            _RoundIcon(
              icon: Icons.delete_outline,
              label: '選んだノートを削除',
              onPressed: () {
                song.deleteNotes(clip.id, _selection.toList());
                setState(_selection.clear);
              },
            ),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.undo, label: '元に戻す', onPressed: song.canUndo ? song.undo : null),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.redo, label: 'やり直す', onPressed: song.canRedo ? song.redo : null),
        ],
      ),
    );
  }

  Widget _bottomControls(List<int> columns) {
    final step = gridSteps.indexOf(_step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _ValueButton(
              caption: 'グリッド',
              value: gridLabel(_step),
              onTap: () => setState(() => _step = gridSteps[(step + 1) % gridSteps.length]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                _RoundIcon(
                  icon: Icons.remove,
                  label: 'オクターブを下げる',
                  onPressed: _octave > 0 ? () => setState(() => _octave--) : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('オクターブ', style: TextStyle(fontSize: 10, color: DawColors.muted)),
                      Text(noteName(columns.first, withOctave: true),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                _RoundIcon(
                  icon: Icons.add,
                  label: 'オクターブを上げる',
                  onPressed: _octave < 8 ? () => setState(() => _octave++) : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ValueButton(
              caption: '全音表示',
              value: _chromatic ? 'ON' : 'OFF',
              onTap: () => setState(() => _chromatic = !_chromatic),
            ),
          ),
        ],
      ),
    );
  }

  // ---- ロール本体 ---------------------------------------------------------------

  Widget _roll(ClipData clip, List<int> columns, Scale scale, TrackData? track) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFF16181B), borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, box) {
          final rows = math.max(1, (clip.lengthTicks + _step - 1) ~/ _step);
          final rowHeight = (box.maxHeight / rows).clamp(22.0, 44.0).toDouble();
          final g = RollGeometry(
            width: box.maxWidth,
            columns: columns,
            step: _step,
            rowHeight: rowHeight,
            lengthTicks: clip.lengthTicks,
          );
          final color = track != null ? Color(track.color) : DawColors.lead;
          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scroll,
                physics: const NeverScrollableScrollPhysics(), // ロールの上のドラッグは編集に使う
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(clip, g, d.localPosition),
                  onLongPressStart: (d) => _onLongPress(clip, g, d.localPosition),
                  onPanStart: (d) => _onPanStart(clip, g, d.localPosition),
                  onPanUpdate: (d) => _onPanUpdate(clip, g, d.localPosition),
                  onPanEnd: (_) => _onPanEnd(clip, g),
                  onPanCancel: () => setState(() => _drag = null),
                  child: SizedBox(
                    width: box.maxWidth,
                    height: g.height,
                    child: CustomPaint(
                      painter: _RollPainter(
                        clip: clip,
                        g: g,
                        scale: scale,
                        ticksPerBar: song.project.ticksPerBar,
                        noteColor: color,
                        selection: Set.of(_selection),
                        drag: _drag,
                        playhead: _playhead,
                      ),
                    ),
                  ),
                ),
              ),
              // 左の目盛りの帯をなぞるとスクロール
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: RollGeometry.labelWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) {
                    if (!_scroll.hasClients) return;
                    final max = _scroll.position.maxScrollExtent;
                    _scroll.jumpTo((_scroll.offset - d.delta.dy).clamp(0.0, max).toDouble());
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- 操作 ---------------------------------------------------------------------

  void _onTap(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (_tool == _Tool.select) {
      setState(() {
        if (hit == null) {
          _selection.clear();
        } else if (!_selection.remove(hit.id)) {
          _selection.add(hit.id);
        }
      });
      if (hit != null) song.audition(hit.pitch, velocity: hit.velocity);
      return;
    }
    if (hit != null) {
      song.audition(hit.pitch, velocity: hit.velocity);
      return;
    }
    final col = g.colAt(at.dx);
    if (col == null) return;
    final tick = g.tickAt(at.dy);
    final pitch = g.columns[col];
    song.addNote(clip.id, tick: tick, length: math.min(_step, clip.lengthTicks - tick), pitch: pitch);
    song.audition(pitch);
  }

  void _onLongPress(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit == null) return;
    HapticFeedback.mediumImpact();
    final ids = _selection.contains(hit.id) ? _selection.toList() : [hit.id];
    song.deleteNotes(clip.id, ids);
    setState(() => _selection.removeAll(ids));
  }

  void _onPanStart(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit != null) {
      // 選択ツールで選んでいるノートを掴んだら、選んでいるもの全部を動かす
      final ids = _tool == _Tool.select && _selection.contains(hit.id) ? _selection.toList() : [hit.id];
      if (_tool == _Tool.select && !_selection.contains(hit.id)) {
        _selection
          ..clear()
          ..add(hit.id);
      }
      final kind = isNearBottom(hit, g, at.dy) ? _DragKind.resize : _DragKind.move;
      setState(() => _drag = _Drag(
            kind: kind,
            start: at,
            ids: ids,
            anchorPitch: hit.pitch,
            anchorCol: g.columnOf(hit.pitch) ?? 0,
          ));
      return;
    }
    if (_tool == _Tool.select) {
      setState(() => _drag = _Drag(kind: _DragKind.marquee, start: at));
      return;
    }
    final col = g.colAt(at.dx);
    if (col == null) return;
    song.audition(g.columns[col]);
    setState(() => _drag = _Drag(kind: _DragKind.create, start: at));
  }

  void _onPanUpdate(ClipData clip, RollGeometry g, Offset at) {
    final drag = _drag;
    if (drag == null) return;
    drag.current = at;
    if (drag.kind == _DragKind.move) {
      final pitch = drag.anchorPitch + _deltaPitch(drag, g);
      if (pitch != drag.lastAuditioned && pitch != drag.anchorPitch) {
        drag.lastAuditioned = pitch;
        song.audition(pitch);
      }
    }
    setState(() {});
  }

  void _onPanEnd(ClipData clip, RollGeometry g) {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;
    switch (drag.kind) {
      case _DragKind.create:
        {
          final col = g.colAt(drag.start.dx);
          if (col == null) return;
          final (tick, length) = _createSpan(drag, g);
          song.addNote(clip.id, tick: tick, length: length, pitch: g.columns[col]);
        }
      case _DragKind.move:
        {
          final dt = _deltaTicks(drag, g);
          final dp = _deltaPitch(drag, g);
          if (dt != 0 || dp != 0) song.moveNotes(clip.id, drag.ids, deltaTicks: dt, deltaPitch: dp);
        }
      case _DragKind.resize:
        {
          final dt = _deltaTicks(drag, g);
          if (dt != 0) song.resizeNotes(clip.id, drag.ids, dt);
        }
      case _DragKind.marquee:
        {
          final ids = notesInRect(clip, g, drag.start.dx, drag.start.dy, drag.current.dx, drag.current.dy);
          setState(() => _selection
            ..clear()
            ..addAll(ids));
        }
    }
  }

  /// 縦の移動量をグリッド単位に丸めた tick
  int _deltaTicks(_Drag d, RollGeometry g) {
    final raw = (d.current.dy - d.start.dy) / g.rowHeight;
    return raw.round() * g.step;
  }

  /// 横の移動量を音程差に（掴んだノートが入る列の音に合わせる）
  int _deltaPitch(_Drag d, RollGeometry g) {
    final col = g.colAt(d.current.dx.clamp(RollGeometry.labelWidth, g.width - 1).toDouble());
    if (col == null || col == d.anchorCol) return 0;
    return g.columns[col] - d.anchorPitch;
  }

  /// 置きながら伸ばしたノートの位置と長さ
  (int, int) _createSpan(_Drag d, RollGeometry g) {
    final tick = g.tickAt(d.start.dy);
    final endTick = g.tickAt(math.max(d.start.dy, d.current.dy)) + g.step;
    return (tick, math.max(g.step, endTick - tick).clamp(1, g.lengthTicks - tick));
  }
}

// ---- 描画 -----------------------------------------------------------------------

class _RollPainter extends CustomPainter {
  _RollPainter({
    required this.clip,
    required this.g,
    required this.scale,
    required this.ticksPerBar,
    required this.noteColor,
    required this.selection,
    required this.drag,
    required this.playhead,
  }) : super(repaint: playhead);

  final ClipData clip;
  final RollGeometry g;
  final Scale scale;
  final int ticksPerBar;
  final Color noteColor;
  final Set<int> selection;
  final _Drag? drag;
  final ValueNotifier<int?> playhead;

  @override
  void paint(Canvas canvas, Size size) {
    // ルート音とスケール外（全音表示のとき）の列に色をつける
    for (var c = 0; c < g.columns.length; c++) {
      final p = g.columns[c];
      final isRoot = p % 12 == scale.root;
      final inScale = scale.contains(p);
      if (!isRoot && inScale) continue;
      canvas.drawRect(
        Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height),
        Paint()..color = isRoot ? const Color(0xFF1C1F23) : const Color(0xFF131416),
      );
    }

    // 横線：小節（明）、拍（中）、グリッド（暗）。左に小節番号
    for (var r = 0; r <= g.rows; r++) {
      final tick = r * g.step;
      final y = g.tickY(tick);
      final isBar = tick % ticksPerBar == 0;
      final isBeat = tick % ticksPerBeat == 0;
      canvas.drawRect(
        Rect.fromLTWH(RollGeometry.labelWidth, y, g.width - RollGeometry.labelWidth, 1),
        Paint()..color = isBar ? const Color(0xFF3A3E46) : (isBeat ? const Color(0xFF2A2D33) : const Color(0xFF1F2125)),
      );
      if (r < g.rows && (isBar || isBeat)) {
        _label(canvas, isBar ? '${tick ~/ ticksPerBar + 1}' : '·', Offset(2, y + 3));
      }
    }

    final d = drag;
    final moving = d != null && (d.kind == _DragKind.move || d.kind == _DragKind.resize) ? d.ids.toSet() : <int>{};

    // ノート
    for (final n in clip.notes) {
      final col = g.columnOf(n.pitch);
      if (col == null) continue;
      final selected = selection.contains(n.id);
      final faded = moving.contains(n.id);
      _note(canvas, col, n.tick, n.length,
          fill: noteColor.withValues(alpha: faded ? 0.3 : 1), outline: selected ? DawColors.text : null);
    }

    // なぞっている途中の見た目
    if (d != null) {
      final dyTicks = ((d.current.dy - d.start.dy) / g.rowHeight).round() * g.step;
      switch (d.kind) {
        case _DragKind.create:
          final startCol = g.colAt(d.start.dx);
          if (startCol != null) {
            final tick = g.tickAt(d.start.dy);
            final end = g.tickAt(math.max(d.start.dy, d.current.dy)) + g.step;
            _note(canvas, startCol, tick, math.max(g.step, end - tick), fill: noteColor.withValues(alpha: 0.7));
          }
        case _DragKind.move:
          final col = g.colAt(d.current.dx.clamp(RollGeometry.labelWidth, g.width - 1).toDouble());
          final dp = col == null || col == d.anchorCol ? 0 : g.columns[col] - d.anchorPitch;
          for (final n in clip.notes.where((n) => d.ids.contains(n.id))) {
            final c = g.columnOf(n.pitch + dp);
            if (c != null) {
              _note(canvas, c, n.tick + dyTicks, n.length, fill: noteColor, outline: DawColors.text);
            }
          }
        case _DragKind.resize:
          for (final n in clip.notes.where((n) => d.ids.contains(n.id))) {
            final c = g.columnOf(n.pitch);
            if (c != null) {
              _note(canvas, c, n.tick, math.max(ticksPerBeat ~/ 16, n.length + dyTicks),
                  fill: noteColor, outline: DawColors.text);
            }
          }
        case _DragKind.marquee:
          final rect = Rect.fromPoints(d.start, d.current);
          canvas.drawRect(rect, Paint()..color = DawColors.text.withValues(alpha: 0.08));
          canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = DawColors.text.withValues(alpha: 0.6),
          );
      }
    }

    // 再生位置
    final ph = playhead.value;
    if (ph != null) {
      canvas.drawRect(
        Rect.fromLTWH(RollGeometry.labelWidth, g.tickY(ph) - 1, g.width - RollGeometry.labelWidth, 2),
        Paint()..color = DawColors.text,
      );
    }
  }

  void _note(Canvas canvas, int col, int tick, int length, {required Color fill, Color? outline}) {
    final rect = Rect.fromLTRB(
      g.colX(col) + 2,
      g.tickY(tick) + 1,
      g.colX(col) + g.colWidth - 2,
      g.tickY(tick + length) - 1,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = fill);
    if (outline != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = outline,
      );
    }
  }

  void _label(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(color: DawColors.muted, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_RollPainter old) => true; // 指で動かしている間は毎回描き直す
}

// ---- 小さな部品 -------------------------------------------------------------------

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? DawColors.accent : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: active ? DawColors.accent : DawColors.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? DawColors.background : DawColors.text),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? DawColors.background : DawColors.text,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        side: const BorderSide(color: DawColors.line),
      ),
    );
  }
}

class _ValueButton extends StatelessWidget {
  const _ValueButton({required this.caption, required this.value, required this.onTap});

  final String caption;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DawColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DawColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(caption, style: const TextStyle(fontSize: 10, color: DawColors.muted)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
