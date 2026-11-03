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

/// 指でなぞっている操作の種類
enum _DragKind { scroll, move, resizeEnd, resizeStart, clipLength, marquee }

/// なぞっている間の状態（指を離したら1つの編集コマンドにする）。位置はロールの中身の座標
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

/// ② ノート入力（縦ピアノロール）。時間は下へ、音の高さは右へ。全音域を横スクロールで見る。
///
/// 指の操作：
/// ・何もないところをなぞる → 縦横にスクロール。タップ → ノートを置く
/// ・ノートをタップ → 選んで上下につまみを出す。つまみで長さ、真ん中を掴んで移動、長押しで削除
/// ・何もないところを長押ししてなぞる → 範囲選択
/// ・クリップの終わりの線のつまみ → 小節を増やす・減らす
class PianoRollScreen extends StatefulWidget {
  const PianoRollScreen({super.key, required this.song, required this.placementId});

  final SongController song;
  final int placementId;

  @override
  State<PianoRollScreen> createState() => _PianoRollScreenState();
}

class _PianoRollScreenState extends State<PianoRollScreen> with SingleTickerProviderStateMixin {
  static const double _minColWidth = 22;
  static const double _maxColWidth = 110;
  static const double _minRowHeight = 10;
  static const double _maxRowHeight = 160;

  // ピンチで変わる縮尺（横：列の幅、縦：行の高さの倍率）
  double _colWidth = 46;
  double _rowZoom = 1;

  // ピンチ中の状態
  bool _zooming = false;
  double _zoomBaseCol = 46;
  double _zoomBaseRow = 1;
  double _zoomFocalPitchX = 0; // 指の間にある位置（列の単位）
  double _zoomFocalRow = 0; // 指の間にある位置（行の単位）
  static const double _labelWidth = 24;
  static const double _keyboardHeight = 64;
  static const double _bottomRoom = 160; // クリップの終わりのつまみを下へ引くための余白

  final _h = ScrollController(); // ロールの横
  final _hKeys = ScrollController(); // 鍵盤の横（ロールに合わせる）
  final _v = ScrollController(); // ロールの縦
  final _playhead = ValueNotifier<int?>(null); // クリップ先頭からの tick。再生していないときは null
  final _playing = ValueNotifier<bool>(false);
  (int, int)? _loop; // いま繰り返している範囲（曲頭からの tick）
  late final Ticker _ticker;

  int _step = ticksPerBeat ~/ 2; // 1/8
  bool _chromatic = false;
  final Set<int> _selection = {};
  _Drag? _drag;
  bool _centered = false; // 開いたときに一度だけノートのある音域へスクロールする

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
    if (pl != null) song.previewTrack(pl.trackId);
    _h.addListener(() {
      if (_hKeys.hasClients && _hKeys.offset != _h.offset) _hKeys.jumpTo(_h.offset);
    });
    _ticker = createTicker((_) {
      _playhead.value = _localPlayhead();
      _playing.value = song.engine.isPlaying;
    })
      ..start();
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
    _playing.dispose();
    if (_loop != null) song.clearLoop(); // アレンジに戻ったら曲全体のループに
    _h.dispose();
    _hKeys.dispose();
    _v.dispose();
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
        final track = project.track(pl.trackId);
        final label = clipLabels(project)[clip.id] ?? '';
        _followLoop(pl, clip);

        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(track, label, pl, scale, clip),
                _toolbar(clip),
                Expanded(child: _roll(clip, scale, track)),
                _bottomControls(pl, clip),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- ヘッダーと道具 -----------------------------------------------------------

  Widget _header(TrackData? track, String label, PlacementData pl, Scale scale, ClipData clip) {
    final key = '${noteName(scale.root)} ${song.project.scale}';
    final bars = (clip.lengthTicks / song.project.ticksPerBar).ceil();
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
                  '$bars小節（小節 ${pl.startBar + 1}–${pl.endBar}）· ${_chromatic ? '全音表示' : '$key のみ表示'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DawColors.muted),
                ),
              ],
            ),
          ),
          _RoundIcon(icon: Icons.undo, label: '元に戻す', onPressed: song.canUndo ? song.undo : null),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.redo, label: 'やり直す', onPressed: song.canRedo ? song.redo : null),
        ],
      ),
    );
  }

  /// 選んでいるノートがあれば数と削除、なければ操作のヒント
  Widget _toolbar(ClipData clip) {
    final ids = _selection.toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              ids.isEmpty
                  ? 'タップで置く · ノートをタップでつまみ · 長押しなぞりで範囲選択 · 2本指で縮尺'
                  : '選んだノート ${ids.length} 個 · つまみで長さ、真ん中で移動',
              maxLines: 2,
              style: const TextStyle(fontSize: 11, color: DawColors.muted),
            ),
          ),
          if (ids.isNotEmpty) ...[
            IconButton(
              tooltip: '選択をやめる',
              onPressed: () => setState(_selection.clear),
              icon: const Icon(Icons.close, size: 20),
            ),
            IconButton(
              tooltip: '選んだノートを削除',
              onPressed: () {
                song.deleteNotes(clip.id, ids);
                setState(_selection.clear);
              },
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  /// このクリップの範囲（最初の1回ぶん）
  (int, int) _clipRange(PlacementData pl, ClipData clip) {
    final start = pl.startBar * song.project.ticksPerBar;
    return (start, start + clip.lengthTicks);
  }

  /// ループ再生中にクリップの長さが変わったら、繰り返す範囲も合わせる
  void _followLoop(PlacementData pl, ClipData clip) {
    final loop = _loop;
    if (loop == null) return;
    final range = _clipRange(pl, clip);
    if (range != loop) {
      _loop = range;
      song.engine.setLoop(range.$1, range.$2);
    }
  }

  void _togglePlay(PlacementData pl, ClipData clip) {
    if (song.engine.isPlaying) {
      song.engine.stopPlayback();
      return;
    }
    final range = _clipRange(pl, clip);
    _loop = range;
    song.playLoop(range.$1, range.$2);
  }

  Widget _bottomControls(PlacementData pl, ClipData clip) {
    final step = gridSteps.indexOf(_step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          // このクリップだけをループ再生（他のトラックも一緒に鳴る）
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 44,
              child: ValueListenableBuilder<bool>(
                valueListenable: _playing,
                builder: (context, playing, _) => FilledButton.icon(
                  onPressed: () => _togglePlay(pl, clip),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(playing ? Icons.stop : Icons.repeat),
                  label: Text(playing ? '止める' : 'ループ再生', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ValueButton(
              caption: 'グリッド',
              value: gridLabel(_step),
              onTap: () => setState(() => _step = gridSteps[(step + 1) % gridSteps.length]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ValueButton(
              caption: '全音表示',
              value: _chromatic ? 'ON' : 'OFF',
              onTap: () {
                // 表示を切り替えても、いま見ている音のあたりを保つ
                final center = _centerPitch();
                setState(() {
                  _chromatic = !_chromatic;
                  _pendingCenterPitch = center;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- ロール本体 ---------------------------------------------------------------

  RollGeometry? _g;
  double _viewportWidth = 0;
  int? _pendingCenterPitch;

  int? _centerPitch() {
    final g = _g;
    if (g == null || !_h.hasClients) return null;
    final col = g.colAt(_h.offset + _viewportWidth / 2);
    return col == null ? null : g.columns[col];
  }

  Widget _roll(ClipData clip, Scale scale, TrackData? track) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFF16181B), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final viewportW = box.maxWidth - _labelWidth;
          final viewportH = box.maxHeight - _keyboardHeight - 6;
          final rows = math.max(1, (clip.lengthTicks + _step - 1) ~/ _step);
          final rowHeight = _rowHeightFor(viewportH, rows);
          final g = RollGeometry(
            columns: rollColumns(scale, chromatic: _chromatic),
            colWidth: _colWidth,
            step: _step,
            rowHeight: rowHeight,
            lengthTicks: clip.lengthTicks,
          );
          _g = g;
          _viewportWidth = viewportW;
          _scheduleCentering(clip, scale, g, viewportW);
          final color = track != null ? Color(track.color) : DawColors.lead;

          return Stack(
            children: [
              // 小節・拍の目盛り（縦スクロールに合わせて動く）
              Positioned(
                left: 0,
                top: 0,
                width: _labelWidth,
                height: viewportH,
                child: CustomPaint(
                  painter: _LabelPainter(g: g, v: _v, ticksPerBar: song.project.ticksPerBar),
                ),
              ),
              // ロール
              Positioned(
                left: _labelWidth,
                top: 0,
                right: 0,
                height: viewportH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(clip, g, _toContent(d.localPosition)),
                  onLongPressStart: (d) => _onLongPressStart(clip, g, _toContent(d.localPosition)),
                  onLongPressMoveUpdate: (d) => _onLongPressMove(_toContent(d.localPosition)),
                  onLongPressEnd: (_) => _onLongPressEnd(clip, g),
                  // 1本指はなぞり（スクロール・編集）、2本指はピンチで縮尺
                  onScaleStart: (d) {
                    if (d.pointerCount >= 2) {
                      _startZoom(g, d.localFocalPoint);
                    } else {
                      _onPanStart(clip, g, _toContent(d.localFocalPoint));
                    }
                  },
                  onScaleUpdate: (d) {
                    if (d.pointerCount >= 2) {
                      if (!_zooming) _startZoom(g, d.localFocalPoint);
                      _updateZoom(d, viewportH, clip);
                    } else if (!_zooming) {
                      _onPanUpdate(g, d.localFocalPoint, d.focalPointDelta);
                    }
                  },
                  onScaleEnd: (d) {
                    if (_zooming) {
                      _zooming = false;
                      return;
                    }
                    _onPanEnd(clip, g, d.velocity);
                  },
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(), // スクロールは自前（編集のなぞりと分けるため）
                    child: SizedBox(
                      width: g.width,
                      height: viewportH,
                      child: SingleChildScrollView(
                        controller: _v,
                        physics: const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: g.width,
                          height: g.height + _bottomRoom,
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
                              h: _h,
                              viewportWidth: viewportW,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 試聴鍵盤（ロールと一緒に横へ動く）
              Positioned(
                left: _labelWidth,
                right: 0,
                bottom: 0,
                height: _keyboardHeight,
                child: SingleChildScrollView(
                  controller: _hKeys,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: g.width,
                    height: _keyboardHeight,
                    child: ScaleKeyboard(
                      notes: g.columns,
                      rootPitchClass: scale.root,
                      onNoteOn: (note, velocity) => song.engine.noteOn(note, velocity),
                      onNoteOff: (note) => song.engine.noteOff(note),
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

  /// 開いたとき（と全音表示を切り替えたとき）に、見せたい音のあたりへ横スクロールする
  void _scheduleCentering(ClipData clip, Scale scale, RollGeometry g, double viewportW) {
    int? pitch = _pendingCenterPitch;
    if (!_centered) {
      final oct = bestOctave(clip, scale);
      pitch = (oct + 1) * 12 + scale.root + 6; // そのオクターブの真ん中あたり
    }
    if (pitch == null) return;
    _centered = true;
    _pendingCenterPitch = null;
    final target = g.scrollToCenter(pitch, viewportW);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_h.hasClients) _h.jumpTo(target.clamp(0, _h.position.maxScrollExtent).toDouble());
    });
  }

  double _rowHeightFor(double viewportH, int rows) =>
      ((viewportH / rows).clamp(24.0, 44.0) * _rowZoom).clamp(_minRowHeight, _maxRowHeight).toDouble();

  /// ピンチの始まり：指の間にある位置を覚えておく（拡大・縮小してもそこが指の間に残るように）
  void _startZoom(RollGeometry g, Offset focal) {
    // なぞりの途中で2本目の指が来たら、なぞりは取り消す
    if (_drag != null) setState(() => _drag = null);
    _zooming = true;
    _zoomBaseCol = _colWidth;
    _zoomBaseRow = _rowZoom;
    _zoomFocalPitchX = (focal.dx + (_h.hasClients ? _h.offset : 0)) / g.colWidth;
    _zoomFocalRow = (focal.dy + (_v.hasClients ? _v.offset : 0)) / g.rowHeight;
  }

  void _updateZoom(ScaleUpdateDetails d, double viewportH, ClipData clip) {
    final col = (_zoomBaseCol * d.horizontalScale).clamp(_minColWidth, _maxColWidth).toDouble();
    final zoom = (_zoomBaseRow * d.verticalScale).clamp(0.25, 6.0).toDouble();
    if (col == _colWidth && zoom == _rowZoom) return;
    setState(() {
      _colWidth = col;
      _rowZoom = zoom;
    });
    // 描き直したあとで、指の間の位置が動かないようにスクロールを合わせる
    final rows = math.max(1, (clip.lengthTicks + _step - 1) ~/ _step);
    final rowH = _rowHeightFor(viewportH, rows);
    final focal = d.localFocalPoint;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_h.hasClients) {
        final x = _zoomFocalPitchX * col - focal.dx;
        _h.jumpTo(x.clamp(0, _h.position.maxScrollExtent).toDouble());
      }
      if (_v.hasClients) {
        final y = _zoomFocalRow * rowH - focal.dy;
        _v.jumpTo(y.clamp(0, _v.position.maxScrollExtent).toDouble());
      }
    });
  }

  Offset _toContent(Offset viewport) =>
      Offset(viewport.dx + (_h.hasClients ? _h.offset : 0), viewport.dy + (_v.hasClients ? _v.offset : 0));

  void _scrollBy(double dx, double dy) {
    if (_h.hasClients) _h.jumpTo((_h.offset - dx).clamp(0, _h.position.maxScrollExtent).toDouble());
    if (_v.hasClients) _v.jumpTo((_v.offset - dy).clamp(0, _v.position.maxScrollExtent).toDouble());
  }

  /// 指を離したあとも少し流れる（慣性）
  void _fling(Velocity velocity) {
    final v = velocity.pixelsPerSecond;
    const curve = Curves.decelerate;
    const duration = Duration(milliseconds: 450);
    if (_h.hasClients && v.dx.abs() > 200) {
      final to = (_h.offset - v.dx * 0.3).clamp(0, _h.position.maxScrollExtent).toDouble();
      _h.animateTo(to, duration: duration, curve: curve);
    }
    if (_v.hasClients && v.dy.abs() > 200) {
      final to = (_v.offset - v.dy * 0.3).clamp(0, _v.position.maxScrollExtent).toDouble();
      _v.animateTo(to, duration: duration, curve: curve);
    }
  }

  // ---- 操作 ---------------------------------------------------------------------

  Iterable<NoteData> _selectedNotes(ClipData clip) => clip.notes.where((n) => _selection.contains(n.id));

  bool _onClipEndHandle(RollGeometry g, Offset at) {
    final hx = (_h.hasClients ? _h.offset : 0) + _viewportWidth / 2;
    return (at.dy - g.height).abs() <= 26 && (at.dx - hx).abs() <= 40;
  }

  void _onTap(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit != null) {
      setState(() {
        _selection
          ..clear()
          ..add(hit.id);
      });
      song.audition(hit.pitch, velocity: hit.velocity);
      return;
    }
    final col = g.colAt(at.dx);
    if (col == null || at.dy >= g.height) {
      setState(_selection.clear);
      return;
    }
    // 何もないところ：ノートを置いて選ぶ（すぐつまみで伸ばせる）
    final tick = g.tickAt(at.dy);
    final pitch = g.columns[col];
    final id = song.addNote(clip.id, tick: tick, length: math.min(_step, clip.lengthTicks - tick), pitch: pitch);
    song.audition(pitch);
    setState(() {
      _selection.clear();
      if (id != 0) _selection.add(id);
    });
  }

  void _onLongPressStart(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit != null) {
      HapticFeedback.mediumImpact();
      final ids = _selection.contains(hit.id) ? _selection.toList() : [hit.id];
      song.deleteNotes(clip.id, ids);
      setState(() => _selection.removeAll(ids));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _drag = _Drag(kind: _DragKind.marquee, start: at));
  }

  void _onLongPressMove(Offset at) {
    final d = _drag;
    if (d == null || d.kind != _DragKind.marquee) return;
    setState(() => d.current = at);
  }

  void _onLongPressEnd(ClipData clip, RollGeometry g) {
    final d = _drag;
    if (d == null || d.kind != _DragKind.marquee) return;
    final ids = notesInRect(clip, g, d.start.dx, d.start.dy, d.current.dx, d.current.dy);
    setState(() {
      _drag = null;
      _selection
        ..clear()
        ..addAll(ids);
    });
  }

  void _onPanStart(ClipData clip, RollGeometry g, Offset at) {
    // 1. 選んでいるノートのつまみ
    final handle = handleAt(_selectedNotes(clip), g, at.dx, at.dy);
    if (handle != null) {
      setState(() => _drag = _Drag(
            kind: handle.handle == NoteHandle.end ? _DragKind.resizeEnd : _DragKind.resizeStart,
            start: at,
            ids: _selection.toList(),
          ));
      return;
    }
    // 2. クリップの終わりのつまみ
    if (_onClipEndHandle(g, at)) {
      setState(() => _drag = _Drag(kind: _DragKind.clipLength, start: at));
      return;
    }
    // 3. ノートの真ん中 → 移動（選んでいるノートなら全部一緒に）
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit != null) {
      if (!_selection.contains(hit.id)) {
        _selection
          ..clear()
          ..add(hit.id);
      }
      setState(() => _drag = _Drag(
            kind: _DragKind.move,
            start: at,
            ids: _selection.toList(),
            anchorPitch: hit.pitch,
            anchorCol: g.columnOf(hit.pitch) ?? 0,
          ));
      return;
    }
    // 4. 何もないところ → スクロール
    _drag = _Drag(kind: _DragKind.scroll, start: at);
  }

  void _onPanUpdate(RollGeometry g, Offset viewportPos, Offset delta) {
    final d = _drag;
    if (d == null) return;
    if (d.kind == _DragKind.scroll) {
      _scrollBy(delta.dx, delta.dy);
      return;
    }
    d.current = _toContent(viewportPos);
    if (d.kind == _DragKind.move) {
      final pitch = d.anchorPitch + _deltaPitch(d, g);
      if (pitch != d.lastAuditioned && pitch != d.anchorPitch) {
        d.lastAuditioned = pitch;
        song.audition(pitch);
      }
    }
    setState(() {});
  }

  void _onPanEnd(ClipData clip, RollGeometry g, Velocity velocity) {
    final d = _drag;
    setState(() => _drag = null);
    if (d == null) return;
    switch (d.kind) {
      case _DragKind.scroll:
        _fling(velocity);
      case _DragKind.move:
        {
          final dt = _deltaTicks(d, g);
          final dp = _deltaPitch(d, g);
          if (dt != 0 || dp != 0) song.moveNotes(clip.id, d.ids, deltaTicks: dt, deltaPitch: dp);
        }
      case _DragKind.resizeEnd:
        {
          final dt = _deltaTicks(d, g);
          if (dt != 0) song.resizeNotes(clip.id, d.ids, dt);
        }
      case _DragKind.resizeStart:
        {
          final notes = clip.notes.where((n) => d.ids.contains(n.id));
          final dt = clampStartDelta(notes, _deltaTicks(d, g), g.step);
          if (dt != 0) song.trimNotesStart(clip.id, d.ids, dt);
        }
      case _DragKind.clipLength:
        {
          final bars = _draggedBars(d, g, clip);
          final current = (clip.lengthTicks / song.project.ticksPerBar).ceil();
          if (bars != current && !song.resizeClip(clip.id, bars)) {
            HapticFeedback.heavyImpact();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('下のクリップとぶつかるので伸ばせません')));
          }
        }
      case _DragKind.marquee:
        break; // 長押しの方で扱う
    }
  }

  /// 縦の移動量をグリッド単位に丸めた tick
  int _deltaTicks(_Drag d, RollGeometry g) {
    final raw = (d.current.dy - d.start.dy) / g.rowHeight;
    return raw.round() * g.step;
  }

  /// 横の移動量を音程差に（掴んだノートが入る列の音に合わせる）
  int _deltaPitch(_Drag d, RollGeometry g) {
    final col = g.colAt(d.current.dx.clamp(0, g.width - 1).toDouble());
    if (col == null || col == d.anchorCol) return 0;
    return g.columns[col] - d.anchorPitch;
  }

  /// クリップの終わりのつまみを引いた先の小節数（1〜64）
  int _draggedBars(_Drag d, RollGeometry g, ClipData clip) {
    final tpb = song.project.ticksPerBar;
    final endTick = clip.lengthTicks + (d.current.dy - d.start.dy) / g.rowHeight * g.step;
    return (endTick / tpb).round().clamp(1, 64);
  }
}

// ---- 描画 -----------------------------------------------------------------------

class _LabelPainter extends CustomPainter {
  _LabelPainter({required this.g, required this.v, required this.ticksPerBar}) : super(repaint: v);

  final RollGeometry g;
  final ScrollController v;
  final int ticksPerBar;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = v.hasClients ? v.offset : 0.0;
    canvas.clipRect(Offset.zero & size);
    for (var tick = 0; tick < g.lengthTicks; tick += ticksPerBeat) {
      final y = g.tickY(tick) - offset;
      if (y < -20 || y > size.height) continue;
      final isBar = tick % ticksPerBar == 0;
      final tp = TextPainter(
        text: TextSpan(
          text: isBar ? '${tick ~/ ticksPerBar + 1}' : '·',
          style: TextStyle(
            color: isBar ? DawColors.text : DawColors.muted,
            fontSize: isBar ? 11 : 10,
            fontWeight: isBar ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, y + 3));
    }
  }

  @override
  bool shouldRepaint(_LabelPainter old) => old.g != g;
}

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
    required this.h,
    required this.viewportWidth,
  }) : super(repaint: Listenable.merge([playhead, h]));

  final ClipData clip;
  final RollGeometry g;
  final Scale scale;
  final int ticksPerBar;
  final Color noteColor;
  final Set<int> selection;
  final _Drag? drag;
  final ValueNotifier<int?> playhead;
  final ScrollController h;
  final double viewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // ルート音（C など）とスケール外（全音表示のとき）の列に色をつける。オクターブの境目に線
    for (var c = 0; c < g.columns.length; c++) {
      final p = g.columns[c];
      final isRoot = p % 12 == scale.root;
      if (isRoot) {
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height), Paint()..color = const Color(0xFF1C1F23));
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, 1, g.height), Paint()..color = const Color(0xFF3A3E46));
      } else if (!scale.contains(p)) {
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height), Paint()..color = const Color(0xFF121315));
      }
    }

    // 横線：小節（明）、拍（中）、グリッド（暗）
    for (var r = 0; r <= g.rows; r++) {
      final tick = r * g.step;
      final isBar = tick % ticksPerBar == 0;
      final isBeat = tick % ticksPerBeat == 0;
      canvas.drawRect(
        Rect.fromLTWH(0, g.tickY(tick), g.width, isBar ? 1.5 : 1),
        Paint()..color = isBar ? const Color(0xFF4A4F58) : (isBeat ? const Color(0xFF2A2D33) : const Color(0xFF1F2125)),
      );
    }

    final d = drag;
    final moving = d != null && (d.kind == _DragKind.move || d.kind == _DragKind.resizeEnd || d.kind == _DragKind.resizeStart)
        ? d.ids.toSet()
        : <int>{};
    final dyTicks = d == null ? 0 : ((d.current.dy - d.start.dy) / g.rowHeight).round() * g.step;

    // ノート
    for (final n in clip.notes) {
      final col = g.columnOf(n.pitch);
      if (col == null) continue;
      _note(canvas, col, n.tick, n.length,
          fill: noteColor.withValues(alpha: moving.contains(n.id) ? 0.3 : 1),
          outline: selection.contains(n.id) && !moving.contains(n.id) ? DawColors.text : null);
    }

    // なぞっている途中の見た目
    if (d != null) {
      switch (d.kind) {
        case _DragKind.move:
          final col = g.colAt(d.current.dx.clamp(0, g.width - 1).toDouble());
          final dp = col == null || col == d.anchorCol ? 0 : g.columns[col] - d.anchorPitch;
          for (final n in clip.notes.where((n) => d.ids.contains(n.id))) {
            final c = g.columnOf(n.pitch + dp);
            if (c != null) _note(canvas, c, n.tick + dyTicks, n.length, fill: noteColor, outline: DawColors.text);
          }
        case _DragKind.resizeEnd:
          for (final n in clip.notes.where((n) => d.ids.contains(n.id))) {
            final c = g.columnOf(n.pitch);
            if (c != null) {
              _note(canvas, c, n.tick, math.max(60, n.length + dyTicks), fill: noteColor, outline: DawColors.text);
            }
          }
        case _DragKind.resizeStart:
          final notes = clip.notes.where((n) => d.ids.contains(n.id)).toList();
          final dt = clampStartDelta(notes, dyTicks, g.step);
          for (final n in notes) {
            final c = g.columnOf(n.pitch);
            if (c != null) _note(canvas, c, n.tick + dt, n.length - dt, fill: noteColor, outline: DawColors.text);
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
        case _DragKind.scroll:
        case _DragKind.clipLength:
          break;
      }
    }

    // 選んでいるノートのつまみ（動かしている最中は出さない）
    if (moving.isEmpty) {
      for (final n in clip.notes.where((n) => selection.contains(n.id))) {
        if (g.columnOf(n.pitch) == null) continue;
        for (final hnd in NoteHandle.values) {
          final p = handlePoint(n, g, hnd);
          _grip(canvas, Offset(p.x, p.y));
        }
      }
    }

    // クリップの終わり：線と、引っぱるつまみ（いま見ている範囲の真ん中）
    final endY = d?.kind == _DragKind.clipLength ? g.height + (d!.current.dy - d.start.dy) : g.height;
    canvas.drawRect(Rect.fromLTWH(0, g.height, g.width, size.height - g.height),
        Paint()..color = DawColors.background.withValues(alpha: 0.55));
    canvas.drawRect(Rect.fromLTWH(0, endY - 1, g.width, 2), Paint()..color = DawColors.accent.withValues(alpha: 0.8));
    final hx = (h.hasClients ? h.offset : 0) + viewportWidth / 2;
    final pill = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(hx, endY), width: 64, height: 22),
        const Radius.circular(11));
    canvas.drawRRect(pill, Paint()..color = DawColors.accent);
    final barsText = d?.kind == _DragKind.clipLength
        ? '${((g.lengthTicks + (d!.current.dy - d.start.dy) / g.rowHeight * g.step) / ticksPerBar).round().clamp(1, 64)}小節'
        : '↕ 小節';
    _text(canvas, barsText, Offset(hx, endY), color: DawColors.background, size: 11, bold: true, center: true);

    // 再生位置
    final ph = playhead.value;
    if (ph != null) {
      canvas.drawRect(Rect.fromLTWH(0, g.tickY(ph) - 1, g.width, 2), Paint()..color = DawColors.text);
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

  void _grip(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 9, Paint()..color = DawColors.text);
    canvas.drawCircle(c, 5, Paint()..color = DawColors.background);
  }

  void _text(Canvas canvas, String s, Offset at,
      {required Color color, required double size, bool bold = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(_RollPainter old) => true; // 指で動かしている間は毎回描き直す
}

// ---- 小さな部品 -------------------------------------------------------------------

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
