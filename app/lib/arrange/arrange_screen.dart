import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../model/project.dart';
import '../music/scale.dart';
import '../piano_roll/piano_roll_screen.dart';
import '../ui/theme.dart';
import '../update/update_banner.dart';
import 'song_controller.dart';
import 'timeline_math.dart';

/// ① アレンジ（縦タイムライン）。時間は下へ流れ、トラックは横に並ぶ。
class ArrangeScreen extends StatefulWidget {
  const ArrangeScreen({super.key, required this.song, required this.onOpenSoundCheck});

  final SongController song;
  final VoidCallback onOpenSoundCheck;

  @override
  State<ArrangeScreen> createState() => _ArrangeScreenState();
}

class _ArrangeScreenState extends State<ArrangeScreen> with SingleTickerProviderStateMixin {
  /// 再生位置（tick）と再生中かどうか。画面のフレームごとにエンジンから読む
  final _position = ValueNotifier<int>(0);
  final _playing = ValueNotifier<bool>(false);
  late final Ticker _ticker;

  SongController get song => widget.song;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _position.value = song.engine.positionTicks;
      _playing.value = song.engine.isPlaying;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    _playing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: song,
      builder: (context, _) {
        final p = song.project;
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(song: song, onMenu: _openMenu),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: UpdateBanner()),
                Expanded(child: _Timeline(song: song, position: _position)),
                _SelectionBar(song: song),
                _Transport(song: song, position: _position, playing: _playing, ticksPerBar: p.ticksPerBar),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DawColors.panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('トラックを追加'),
              enabled: song.canAddTrack,
              onTap: () => Navigator.pop(context, 'track'),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text('テンポ（${song.project.tempo.round()} BPM）'),
              onTap: () => Navigator.pop(context, 'tempo'),
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('デモ曲を入れる'),
              subtitle: const Text('今の曲は置き換わります（Undo で戻せます）'),
              onTap: () => Navigator.pop(context, 'demo'),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('新しい曲'),
              subtitle: const Text('今の曲は消えます'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('音出しテスト'),
              onTap: () => Navigator.pop(context, 'soundcheck'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'track':
        song.addTrack();
      case 'tempo':
        await _editTempo();
      case 'demo':
        song.loadDemo();
      case 'new':
        if (await _confirm('新しい曲にしますか？', '今の曲は消え、元に戻せません。')) song.newSong();
      case 'soundcheck':
        widget.onOpenSoundCheck();
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('新しくする')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _editTempo() async {
    var bpm = song.project.tempo.roundToDouble();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('テンポ ${bpm.round()} BPM'),
          content: Slider(
            value: bpm,
            min: 40,
            max: 240,
            divisions: 200,
            onChanged: (v) => setLocal(() => bpm = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('やめる')),
            FilledButton(onPressed: () => Navigator.pop(context, bpm), child: const Text('決める')),
          ],
        ),
      ),
    );
    if (result != null) song.setTempo(result);
  }
}

/// クリップの中身を縦ピアノロールで開く
void openPianoRoll(BuildContext context, SongController song, int placementId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PianoRollScreen(song: song, placementId: placementId)),
  );
}

// ---- ヘッダー ------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.song, required this.onMenu});

  final SongController song;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final p = song.project;
    final key = '${noteName(p.keyRoot)} ${p.scale}';
    final error = song.saveError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('untitled 01', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  error ?? '${p.tempo.round()} BPM · $key · ${p.timeSigNumerator}/${p.timeSigDenominator}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: error != null ? DawColors.danger : DawColors.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          _SquareButton(icon: Icons.menu, label: 'メニュー', onPressed: onMenu),
        ],
      ),
    );
  }
}

// ---- タイムライン ----------------------------------------------------------------

/// 列と行の寸法（描画とタップ判定で共通に使う）
class _Grid {
  _Grid({required double width, required this.trackCount})
      : columns = math.max(trackCount, 4),
        colWidth = (width - labelWidth - gap * math.max(trackCount, 4)) / math.max(trackCount, 4);

  static const double labelWidth = 36;
  static const double gap = 6;
  static const double rowHeight = 40; // 1小節

  final int trackCount;
  final int columns;
  final double colWidth;

  double colX(int i) => labelWidth + gap + i * (colWidth + gap);
  double barY(int bar) => bar * rowHeight;

  int? colAt(double x) {
    if (x < labelWidth + gap) return null;
    final i = ((x - labelWidth - gap) / (colWidth + gap)).floor();
    return i >= 0 && i < trackCount ? i : null;
  }

  int barAt(double y) => (y / rowHeight).floor();
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.song, required this.position});

  final SongController song;
  final ValueNotifier<int> position;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final p = song.project;
    final rows = math.max(16, p.lengthBars + 8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          final grid = _Grid(width: box.maxWidth, trackCount: p.tracks.length);
          return Column(
            children: [
              _TrackHeader(song: song, grid: grid),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onTap(grid, d.localPosition),
                    child: SizedBox(
                      height: rows * _Grid.rowHeight,
                      width: box.maxWidth,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _GridPainter(
                                project: p,
                                grid: grid,
                                rows: rows,
                                labels: clipLabels(p),
                                selectedId: song.selectedPlacementId,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _PlayheadPainter(
                                  position: widget.position,
                                  ticksPerBar: p.ticksPerBar,
                                  loopEndBar: math.max(p.lengthBars, 1),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onTap(_Grid grid, Offset at) {
    final song = widget.song;
    final p = song.project;
    final col = grid.colAt(at.dx);
    final bar = grid.barAt(at.dy);
    if (col == null) {
      song.select(null);
      return;
    }
    final track = p.tracks[col];
    final hit = p.placementAt(track.id, bar);
    if (hit != null) {
      if (song.selectedPlacementId == hit.id) {
        openPianoRoll(context, song, hit.id); // 選んでいるクリップをもう一度タップで中身を開く
      } else {
        song.select(hit.id);
      }
    } else if (song.selectedPlacementId != null) {
      song.select(null); // 選択中ならまず外すだけ（うっかり置かないように）
    } else {
      HapticFeedback.selectionClick();
      song.createClipAt(track.id, bar);
    }
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({required this.song, required this.grid});

  final SongController song;
  final _Grid grid;

  @override
  Widget build(BuildContext context) {
    final tracks = song.project.tracks;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 6,
            width: _Grid.labelWidth,
            height: 44,
            child: IconButton(
              tooltip: 'トラックを追加',
              padding: EdgeInsets.zero,
              onPressed: song.canAddTrack ? song.addTrack : null,
              icon: const Icon(Icons.add, size: 20),
            ),
          ),
          for (var i = 0; i < tracks.length; i++)
            Positioned(
              left: grid.colX(i),
              width: grid.colWidth,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: Color(tracks[i].color), shape: BoxShape.circle),
                    ),
                    const SizedBox(height: 4),
                    Text(tracks[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const Text('シンセ', style: TextStyle(fontSize: 10, color: DawColors.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.project,
    required this.grid,
    required this.rows,
    required this.labels,
    required this.selectedId,
  });

  final ProjectData project;
  final _Grid grid;
  final int rows;
  final Map<int, String> labels;
  final int? selectedId;

  static const _inset = 3.0; // 行と行のすき間の半分

  @override
  void paint(Canvas canvas, Size size) {
    final emptyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = DawColors.line;
    final tpb = project.ticksPerBar;
    final songEnd = project.lengthBars;

    for (var bar = 0; bar < rows; bar++) {
      final y = grid.barY(bar);
      // 小節番号。曲の範囲（ループする範囲）は明るく
      _text(canvas, (bar + 1).toString().padLeft(2, '0'), Offset(0, y + _Grid.rowHeight / 2 - 7),
          color: bar < math.max(songEnd, 1) ? DawColors.muted : DawColors.line, size: 11);

      for (var i = 0; i < project.tracks.length; i++) {
        final track = project.tracks[i];
        final rect = Rect.fromLTWH(grid.colX(i), y + _inset, grid.colWidth, _Grid.rowHeight - _inset * 2);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        final pl = project.placementAt(track.id, bar);
        if (pl == null) {
          canvas.drawRRect(rrect.deflate(0.5), emptyPaint);
          continue;
        }
        canvas.drawRRect(rrect, Paint()..color = Color(track.color));
        final clip = project.clip(pl.clipId);
        if (clip != null) _miniNotes(canvas, rect, clip, pl, bar, tpb);
        if (bar == pl.startBar) {
          _text(canvas, labels[pl.clipId] ?? '', rect.topLeft + const Offset(5, 3),
              color: DawColors.background, size: 10, bold: true);
        }
      }
    }

    // 選んでいるクリップを白い枠で囲む（配置の全体）
    final sel = selectedId;
    if (sel != null) {
      for (final pl in project.placements.where((pl) => pl.id == sel)) {
        final i = project.tracks.indexWhere((t) => t.id == pl.trackId);
        if (i < 0) continue;
        final rect = Rect.fromLTRB(grid.colX(i), grid.barY(pl.startBar) + _inset, grid.colX(i) + grid.colWidth,
            grid.barY(pl.endBar) - _inset);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = DawColors.text,
        );
      }
    }
  }

  /// セルの中にノートを小さく描く。縦が時間（下へ）、横が音の高さ
  void _miniNotes(Canvas canvas, Rect cell, ClipData clip, PlacementData pl, int bar, int tpb) {
    if (clip.notes.isEmpty) return;
    var lo = 127, hi = 0;
    for (final n in clip.notes) {
      lo = math.min(lo, n.pitch);
      hi = math.max(hi, n.pitch);
    }
    final span = math.max(hi - lo, 12);
    final area = cell.deflate(5);
    final paint = Paint()..color = DawColors.background.withValues(alpha: 0.55);
    for (final n in notesInBar(clip, pl, bar, tpb)) {
      final x = area.left + (n.pitch - lo) / span * (area.width - 4);
      final top = area.top + n.tick / tpb * area.height;
      final h = math.max(2.0, math.min(n.length, tpb - n.tick) / tpb * area.height);
      canvas.drawRect(Rect.fromLTWH(x, top, 4, h), paint);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {required Color color, required double size, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.project != project || old.selectedId != selectedId || old.grid.colWidth != grid.colWidth || old.rows != rows;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter({required this.position, required this.ticksPerBar, required this.loopEndBar})
      : super(repaint: position);

  final ValueNotifier<int> position;
  final int ticksPerBar;
  final int loopEndBar;

  @override
  void paint(Canvas canvas, Size size) {
    final y = position.value / ticksPerBar * _Grid.rowHeight;
    final paint = Paint()..color = DawColors.text;
    canvas.drawRect(Rect.fromLTWH(_Grid.labelWidth, y - 1, size.width - _Grid.labelWidth, 2), paint);
    final tri = Path()
      ..moveTo(_Grid.labelWidth - 10, y - 7)
      ..lineTo(_Grid.labelWidth, y)
      ..lineTo(_Grid.labelWidth - 10, y + 7)
      ..close();
    canvas.drawPath(tri, paint);
    // ループの終わり
    final endY = loopEndBar * _Grid.rowHeight;
    canvas.drawRect(Rect.fromLTWH(_Grid.labelWidth, endY - 1, size.width - _Grid.labelWidth, 2),
        Paint()..color = DawColors.accent.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.ticksPerBar != ticksPerBar || old.loopEndBar != loopEndBar;
}

// ---- 選んだクリップの操作 --------------------------------------------------------

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.song});

  final SongController song;

  @override
  Widget build(BuildContext context) {
    final sel = song.selected;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(12)),
      child: sel == null
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text('空いているマスをタップでクリップを置く · タップで選び、もう一度タップで中身を開く',
                  style: TextStyle(fontSize: 12, color: DawColors.muted)),
            )
          : Row(
              children: [
                _BarAction(icon: Icons.copy_all_outlined, label: '下に複製', onPressed: song.duplicateSelected),
                _BarAction(
                  icon: Icons.arrow_upward,
                  label: '上へ',
                  onPressed: sel.startBar > 0 ? () => _move(song, -1) : null,
                ),
                _BarAction(icon: Icons.arrow_downward, label: '下へ', onPressed: () => _move(song, 1)),
                _BarAction(
                  icon: Icons.unfold_less,
                  label: '縮める',
                  onPressed: sel.lengthBars > 1 ? () => _resize(song, -1) : null,
                ),
                _BarAction(icon: Icons.unfold_more, label: '伸ばす', onPressed: () => _resize(song, 1)),
                _BarAction(icon: Icons.delete_outline, label: '削除', onPressed: song.deleteSelected),
                _BarAction(icon: Icons.piano, label: 'ノート', onPressed: () => openPianoRoll(context, song, sel.id)),
              ],
            ),
    );
  }

  void _resize(SongController song, int delta) {
    if (!song.resizeSelected(delta)) HapticFeedback.heavyImpact(); // 下のクリップとぶつかる
  }

  void _move(SongController song, int delta) {
    if (!song.moveSelected(delta)) HapticFeedback.heavyImpact(); // ほかのクリップとぶつかる
  }
}

class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null ? DawColors.line : DawColors.text;
    return Expanded(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- 再生操作 -----------------------------------------------------------------

class _Transport extends StatelessWidget {
  const _Transport({required this.song, required this.position, required this.playing, required this.ticksPerBar});

  final SongController song;
  final ValueNotifier<int> position;
  final ValueNotifier<bool> playing;
  final int ticksPerBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          _SquareButton(icon: Icons.skip_previous, label: '先頭へ', onPressed: song.rewind),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: ListenableBuilder(
                listenable: Listenable.merge([position, playing]),
                builder: (context, _) => FilledButton(
                  onPressed: song.togglePlay,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(playing.value ? Icons.stop : Icons.play_arrow, semanticLabel: playing.value ? '止める' : '再生'),
                      const SizedBox(width: 8),
                      Text(formatPosition(position.value, ticksPerBar),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SquareButton(icon: Icons.undo, label: '元に戻す', onPressed: song.canUndo ? song.undo : null),
          const SizedBox(width: 10),
          _SquareButton(icon: Icons.redo, label: 'やり直す', onPressed: song.canRedo ? song.redo : null),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: DawColors.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: DawColors.line),
      ),
    );
  }
}
