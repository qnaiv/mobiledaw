import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../model/project.dart';
import '../music/scale.dart';
import '../piano_roll/piano_roll_screen.dart';
import '../ui/theme.dart';
import '../update/update_banner.dart';
import 'demo_song.dart';
import '../export/export_sheet.dart';
import '../kits/kit_gate.dart';
import '../kits/kits_screen.dart';
import '../project/projects_screen.dart';
import '../sound/sound_sheet.dart';
import 'mixer_sheet.dart';
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
    // 起動時に開いた曲のキットがなければ、ダウンロードするか聞く（やめたら新しい曲にする）
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkKitsOfOpenSong());
  }

  Future<void> _checkKitsOfOpenSong() async {
    if (!mounted) return;
    final ids = {for (final t in song.project.tracks) if (t.isKit) t.kitId};
    if (missingKits(song.kits, ids).isEmpty) return;
    if (!await ensureKits(context, song, ids)) song.newSong();
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
      isScrollControlled: true, // 項目が多いので、画面に入りきらなければスクロール
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('保存'),
              subtitle: const Text('編集すると自動でも保存されます'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.save_as_outlined),
              title: const Text('別名で保存'),
              onTap: () => Navigator.pop(context, 'saveAs'),
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('曲の一覧'),
              subtitle: const Text('開く・新しい曲・複製・名前を変える・削除'),
              onTap: () => Navigator.pop(context, 'projects'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('書き出し'),
              subtitle: const Text('WAV（まとめて・トラックごと）・MIDI'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: const Text('ドラムキット'),
              subtitle: const Text('キットを探す・ダウンロード・削除'),
              onTap: () => Navigator.pop(context, 'kits'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('トラックを追加'),
              enabled: song.canAddTrack,
              onTap: () => Navigator.pop(context, 'track'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('ミキサー（音量バランス）'),
              onTap: () => Navigator.pop(context, 'mixer'),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: Text('テンポ（${song.project.tempo.round()} BPM）'),
              onTap: () => Navigator.pop(context, 'tempo'),
            ),
            for (final demo in DemoSong.values)
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text('デモ曲：${demoLabel(demo)}'),
                subtitle: Text('新しい曲として一覧に入ります（ドラムは ${demoKitName(demo)}）'),
                onTap: () => Navigator.pop(context, 'demo:${demo.name}'),
              ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('音出しテスト'),
              onTap: () => Navigator.pop(context, 'soundcheck'),
            ),
          ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'save':
        song.saveNow(force: true);
        _toast(song.saveError ?? '「${song.project.title}」を保存しました');
      case 'saveAs':
        final title = await askSongTitle(context,
            title: '別名で保存', initial: '${song.project.title} のコピー', ok: '保存');
        if (title != null) {
          song.saveAs(title);
          _toast('「$title」として保存しました（今はこちらを開いています）');
        }
      case 'projects':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectsScreen(song: song)));
      case 'export':
        await showExportSheet(context, song);
      case 'kits':
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KitsScreen(song: song)));
      case 'track':
        song.addTrack();
      case 'mixer':
        await showMixerSheet(context, song);
      case 'tempo':
        await _editTempo();
      case final String a when a.startsWith('demo:'):
        final demo = DemoSong.values.byName(a.substring(5));
        final kits = await kitsInDemo(demo);
        if (!mounted) return;
        if (!await ensureKits(context, song, kits)) return;
        await song.loadDemo(demo);
      case 'soundcheck':
        widget.onOpenSoundCheck();
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                // 曲名をタップで名前を変える
                GestureDetector(
                  onTap: () async {
                    final title = await askSongTitle(context, title: '曲の名前', initial: p.title);
                    if (title != null) song.renameSong(title);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 14, color: DawColors.muted),
                    ],
                  ),
                ),
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

  /// 選んだクリップの伸縮つまみの真ん中（下端の中央）
  Offset gripCenter(int col, PlacementData pl) => Offset(colX(col) + colWidth / 2, barY(pl.endBar) - 2);
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.song, required this.position});

  final SongController song;
  final ValueNotifier<int> position;

  @override
  State<_Timeline> createState() => _TimelineState();
}

enum _ArrDragKind { scroll, resize, move, duplicate }

/// アレンジ画面でなぞっている間の状態（y は中身の座標）
class _ArrDrag {
  _ArrDrag(this.kind, this.placement, this.startY) : currentY = startY;

  final _ArrDragKind kind;
  final PlacementData? placement;
  final double startY;
  double currentY;

  int get deltaBars => ((currentY - startY) / _Grid.rowHeight).round();

  /// 指を離したときの結果（伸縮なら新しい長さ、移動・複製なら新しい開始小節）
  int get resultBars => switch (kind) {
        _ArrDragKind.resize => math.max(1, placement!.lengthBars + deltaBars),
        _ArrDragKind.move || _ArrDragKind.duplicate => math.max(0, placement!.startBar + deltaBars),
        _ArrDragKind.scroll => 0,
      };
}

/// 指の操作：
/// ・何もないところ・選んでいないクリップをなぞる → スクロール
/// ・タップ → 選ぶ。選んでいるクリップをもう一度タップ → 中身（ピアノロール）を開く。空きマスのタップ → クリップを置く
/// ・選んだクリップの下のつまみを上下に → 伸ばす・縮める
/// ・選んだクリップの真ん中を上下に → 移動
/// ・クリップを長押ししてなぞる → 複製を置く
class _TimelineState extends State<_Timeline> {
  final _scroll = ScrollController();
  _ArrDrag? _drag;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(grid, _content(d.localPosition)),
                  onPanStart: (d) => _onPanStart(grid, _content(d.localPosition)),
                  onPanUpdate: (d) => _onDragMove(d.delta.dy),
                  onPanEnd: (d) => _onDragEnd(d.velocity),
                  onPanCancel: () => setState(() => _drag = null),
                  onLongPressStart: (d) => _onLongPressStart(grid, _content(d.localPosition)),
                  onLongPressMoveUpdate: (d) => _onLongPressMove(_content(d.localPosition)),
                  onLongPressEnd: (_) => _onDragEnd(Velocity.zero),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const NeverScrollableScrollPhysics(), // スクロールは自前（編集のなぞりと分けるため）
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
                                startBar: song.startTick ~/ p.ticksPerBar,
                                selectedId: _drag?.kind == _ArrDragKind.scroll || _drag == null
                                    ? song.selectedPlacementId
                                    : null,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _DragPainter(project: p, grid: grid, drag: _drag),
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

  Offset _content(Offset viewport) => Offset(viewport.dx, viewport.dy + _offset);

  PlacementData? _hitPlacement(_Grid grid, Offset at) {
    final col = grid.colAt(at.dx);
    if (col == null) return null;
    final p = widget.song.project;
    return p.placementAt(p.tracks[col].id, grid.barAt(at.dy));
  }

  void _onTap(_Grid grid, Offset at) {
    final song = widget.song;
    final p = song.project;
    final col = grid.colAt(at.dx);
    final bar = grid.barAt(at.dy);
    if (at.dx < _Grid.labelWidth + _Grid.gap) {
      // 左の小節番号：ここから再生する（再生中ならすぐ飛ぶ）
      if (bar < math.max(p.lengthBars, 1)) song.setStartBar(bar);
      return;
    }
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

  void _onPanStart(_Grid grid, Offset at) {
    final sel = widget.song.selected;
    if (sel != null) {
      final col = widget.song.project.tracks.indexWhere((t) => t.id == sel.trackId);
      if (col >= 0) {
        final grip = grid.gripCenter(col, sel);
        if ((at - grip).distance <= 28) {
          setState(() => _drag = _ArrDrag(_ArrDragKind.resize, sel, at.dy));
          return;
        }
      }
      if (_hitPlacement(grid, at)?.id == sel.id) {
        setState(() => _drag = _ArrDrag(_ArrDragKind.move, sel, at.dy));
        return;
      }
    }
    _drag = _ArrDrag(_ArrDragKind.scroll, null, at.dy);
  }

  void _onLongPressStart(_Grid grid, Offset at) {
    final hit = _hitPlacement(grid, at);
    if (hit == null) return;
    HapticFeedback.mediumImpact();
    widget.song.select(hit.id);
    setState(() => _drag = _ArrDrag(_ArrDragKind.duplicate, hit, at.dy));
  }

  void _onLongPressMove(Offset at) {
    final d = _drag;
    if (d == null || d.kind != _ArrDragKind.duplicate) return;
    final bars = d.resultBars;
    setState(() => d.currentY = at.dy);
    if (d.resultBars != bars) HapticFeedback.selectionClick();
  }

  void _onDragMove(double dy) {
    final d = _drag;
    if (d == null) return;
    if (d.kind == _ArrDragKind.scroll) {
      if (_scroll.hasClients) {
        _scroll.jumpTo((_scroll.offset - dy).clamp(0, _scroll.position.maxScrollExtent).toDouble());
      }
      return;
    }
    final bars = d.resultBars;
    setState(() => d.currentY += dy);
    if (d.resultBars != bars) HapticFeedback.selectionClick(); // 1小節動くごとにコツッと
  }

  void _onDragEnd(Velocity velocity) {
    final d = _drag;
    setState(() => _drag = null);
    if (d == null) return;
    final song = widget.song;
    final pl = d.placement;
    var ok = true;
    switch (d.kind) {
      case _ArrDragKind.scroll:
        final v = velocity.pixelsPerSecond.dy;
        if (_scroll.hasClients && v.abs() > 200) {
          final to = (_scroll.offset - v * 0.3).clamp(0, _scroll.position.maxScrollExtent).toDouble();
          _scroll.animateTo(to, duration: const Duration(milliseconds: 450), curve: Curves.decelerate);
        }
      case _ArrDragKind.resize:
        if (d.resultBars != pl!.lengthBars) ok = song.resizeClip(pl.clipId, d.resultBars);
      case _ArrDragKind.move:
        if (d.resultBars != pl!.startBar) ok = song.movePlacementTo(pl.id, d.resultBars);
      case _ArrDragKind.duplicate:
        if (d.resultBars != pl!.startBar) ok = song.duplicateTo(pl.clipId, d.resultBars);
    }
    if (!ok) HapticFeedback.heavyImpact(); // ほかのクリップとぶつかる
  }
}

/// なぞっている途中の見た目（伸縮・移動・複製の行き先と吹き出し）
class _DragPainter extends CustomPainter {
  _DragPainter({required this.project, required this.grid, required this.drag});

  final ProjectData project;
  final _Grid grid;
  final _ArrDrag? drag;

  @override
  void paint(Canvas canvas, Size size) {
    final d = drag;
    final pl = d?.placement;
    if (d == null || pl == null || d.kind == _ArrDragKind.scroll) return;
    final col = project.tracks.indexWhere((t) => t.id == pl.trackId);
    if (col < 0) return;
    final color = Color(project.tracks[col].color);
    final (start, bars, text) = switch (d.kind) {
      _ArrDragKind.resize => (pl.startBar, d.resultBars, '${d.resultBars}小節'),
      _ArrDragKind.move => (d.resultBars, pl.lengthBars, '${d.resultBars + 1}小節目へ'),
      _ArrDragKind.duplicate => (d.resultBars, pl.lengthBars, '複製 → ${d.resultBars + 1}小節目'),
      _ArrDragKind.scroll => (0, 0, ''),
    };
    final rect = Rect.fromLTRB(grid.colX(col) - 2, grid.barY(start) + 1, grid.colX(col) + grid.colWidth + 2,
        grid.barY(start + bars) - 1);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.35));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = DawColors.text,
    );
    // 吹き出し
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: DawColors.background, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bubbleW = tp.width + 16;
    var bx = rect.center.dx - bubbleW / 2;
    bx = bx.clamp(0, math.max(0.0, size.width - bubbleW)).toDouble();
    final by = d.kind == _ArrDragKind.resize ? rect.bottom + 6 : rect.top - 30;
    final bubble = RRect.fromRectAndRadius(Rect.fromLTWH(bx, math.max(0.0, by), bubbleW, 24), const Radius.circular(12));
    canvas.drawRRect(bubble, Paint()..color = DawColors.text);
    tp.paint(canvas, Offset(bx + 8, math.max(0.0, by) + (24 - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_DragPainter old) => true;
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
              child: GestureDetector(
                onTap: () => showSoundSheet(context, song, tracks[i].id),
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
                    Text(
                        tracks[i].mixer.mute
                            ? 'ミュート'
                            : tracks[i].mixer.solo
                                ? 'ソロ'
                                : gainLabel(tracks[i].mixer.gain),
                        style: TextStyle(
                            fontSize: 10,
                            color: tracks[i].mixer.mute
                                ? DawColors.danger
                                : tracks[i].mixer.solo
                                    ? DawColors.accent
                                    : DawColors.muted)),
                  ],
                ),
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
    required this.startBar,
  });

  final ProjectData project;
  final _Grid grid;
  final int rows;
  final Map<int, String> labels;
  final int? selectedId;
  final int startBar; // 再生を始める小節（番号を明るく、左に印）

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
      // 小節番号。曲の範囲（ループする範囲）は明るく、再生を始める小節は印をつける
      final isStart = bar == startBar && startBar > 0;
      if (isStart) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(0, y + 6, _Grid.labelWidth - 4, _Grid.rowHeight - 12), const Radius.circular(6)),
            Paint()..color = DawColors.accent);
      }
      _text(canvas, (bar + 1).toString().padLeft(2, '0'), Offset(4, y + _Grid.rowHeight / 2 - 7),
          color: isStart
              ? DawColors.background
              : bar < math.max(songEnd, 1)
                  ? DawColors.muted
                  : DawColors.line,
          size: 11,
          bold: isStart);

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
        // 伸縮のつまみ（下端の中央）
        final grip = grid.gripCenter(i, pl);
        final pill = RRect.fromRectAndRadius(Rect.fromCenter(center: grip, width: 34, height: 16), const Radius.circular(8));
        canvas.drawRRect(pill, Paint()..color = DawColors.text);
        for (final dy in [-2.5, 2.5]) {
          canvas.drawRect(Rect.fromCenter(center: grip + Offset(0, dy), width: 14, height: 1.5),
              Paint()..color = DawColors.background);
        }
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
      old.project != project ||
      old.selectedId != selectedId ||
      old.grid.colWidth != grid.colWidth ||
      old.rows != rows ||
      old.startBar != startBar;
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
              child: Text('空きマスをタップで置く · タップで選んで下のつまみで伸縮、掴んで移動 · 長押しなぞりで複製 · もう一度タップで中身 · 左の小節番号をタップでそこから再生',
                  style: TextStyle(fontSize: 12, color: DawColors.muted)),
            )
          : Row(
              children: [
                _BarAction(icon: Icons.copy_all_outlined, label: '下に複製', onPressed: song.duplicateSelected),
                _BarAction(icon: Icons.delete_outline, label: '削除', onPressed: song.deleteSelected),
                _BarAction(icon: Icons.piano, label: 'ノート', onPressed: () => openPianoRoll(context, song, sel.id)),
              ],
            ),
    );
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
