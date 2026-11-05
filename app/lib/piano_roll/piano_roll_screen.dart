import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../arrange/song_controller.dart';
import '../arrange/timeline_math.dart';
import '../model/project.dart';
import '../music/chords.dart';
import '../music/progressions.dart';
import '../music/voicing.dart';
import '../music/scale.dart';
import '../sound/sound_params.dart';
import '../ui/scale_keyboard.dart';
import '../ui/theme.dart';
import 'automation_params.dart';
import 'chord_tools.dart';
import 'key_scale_sheet.dart';
import 'progression_sheet.dart';
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
  int _startInClip = 0;
  final _rollKey = GlobalKey(); // コードをドラッグで置くとき、画面の位置をロールの位置に直すため
  ({int tick, int length, List<int> pitches, String label})? _dropAt; // ドラッグ中の置き先（薄く出す） // 再生を始める位置（クリップの頭からの tick）。左の目盛りをタップで変える
  late final Ticker _ticker;

  int _step = ticksPerBeat ~/ 2; // 1/8
  bool _chromatic = false;

  // オートメーションモード（ノートと切り替え。ロール全幅にカーブを描いて編集する）
  bool _autoMode = false;
  String _autoParamKey = 'gain'; // 編集中のレーンのパラメータキー
  List<(int, double)> _autoPoints = const []; // 編集中レーンの点（コアの正規化済みを読み直す）
  int? _autoSel; // 触っている・選んでいる点の番号
  int? _autoDragIndex; // ドラッグ中の点の番号（無ければ縦スクロール）
  bool _autoDragMoved = false;

  // コード入力モード
  bool _chordMode = false;
  int _chordDegree = 0; // 選んでいるコード（キーの中の番号）
  int? _borrowedSel; // 選んでいる借用コード（借用一覧の中の番号。無ければ null）
  bool _seventh = false; // 7thを足す
  int _chordLenIndex = 0; // 置く長さ（_chordLengths の何番目か）
  List<int> _suggest = const []; // 次に合うコード（合う順。ボタンの順位バッジ用）
  Chord? _prevChord; // 直前に置いたコード本体（雰囲気別サジェストの元）
  List<NextChordGroup> _nextGroups = const []; // 直前のコードから自然に続く候補（雰囲気ごと）
  Chord? _pickedChord; // サジェストから選んだコード（次にタップで置くもの。通常の選択より優先）

  // ノートの貼り付け待ち（コピー後に「貼り付け」を押すと、次にタップした場所へ貼る）
  bool _pasteReady = false;
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
        if (_autoMode) _syncAuto(clip);

        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(track, label, pl, scale, clip),
                _toolbar(clip),
                if (_autoMode) _autoParamBar(clip),
                Expanded(child: _roll(clip, scale, track)),
                if (_chordMode && !_autoMode) _chordPanel(scale, clip),
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
    final key = '${noteName(scale.root)} ${scale.kind.label}';
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
                  '$bars小節（小節 ${pl.startBar + 1}–${pl.endBar}）· '
                  '${track != null && track.isKit ? 'ドラムキット：${song.kits.installed(track.kitId)?.name ?? '${track.kitId}（未ダウンロード）'}' : _chromatic ? '全音表示' : '$key のみ表示'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DawColors.muted),
                ),
              ],
            ),
          ),
          // キーとスケール（タップで選択シート）
          Material(
            color: const Color(0xFF123A3F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: const BorderSide(color: Color(0xFF1F5A61)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => showKeyScaleSheet(context, song: song),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text('$key ▾',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF5AD6C0))),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.undo, label: '元に戻す', onPressed: song.canUndo ? song.undo : null),
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.redo, label: 'やり直す', onPressed: song.canRedo ? song.redo : null),
        ],
      ),
    );
  }

  /// ノート／オートメーションのモード切替。あとは選んでいるノートがあれば数と削除、なければ操作のヒント
  Widget _toolbar(ClipData clip) {
    final ids = _selection.toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _modeToggle(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _autoMode
                  ? 'タップで点を追加 · ドラッグで移動 · 長押しで削除'
                  : _pasteReady
                      ? '貼る場所をタップ（コピーした ${song.noteClipboardCount} 個のノート）· もう一度押すとやめる'
                      : ids.isEmpty
                          ? (_chordMode
                              ? 'コードを選んでタップで置く · ノートをタップで選ぶ · 2本指で縮尺'
                              : 'タップで置く · タップで選ぶ · 長押しで移動 · 何もない所を長押しで範囲選択')
                          : '選んだノート ${ids.length} 個 · つまみで長さ · 掴んで移動 · 右のボタンでコピー／削除',
              maxLines: 2,
              style: const TextStyle(fontSize: 11, color: DawColors.muted),
            ),
          ),
          if (!_autoMode && song.hasNoteClipboard)
            IconButton(
              tooltip: _pasteReady ? '貼り付けをやめる' : 'コピーしたノートを貼り付け（タップした場所へ）',
              onPressed: () => setState(() {
                _pasteReady = !_pasteReady;
                if (_pasteReady) _chordMode = false; // 貼り付けのタップとコード配置が混ざらないように
              }),
              style: _pasteReady
                  ? IconButton.styleFrom(backgroundColor: DawColors.accent, foregroundColor: DawColors.background)
                  : null,
              icon: const Icon(Icons.content_paste, size: 20),
            ),
          if (!_autoMode && ids.isNotEmpty) ...[
            IconButton(
              tooltip: '選んだノートをコピー',
              onPressed: () {
                if (song.copyNotes(clip.id, ids)) HapticFeedback.selectionClick();
              },
              icon: const Icon(Icons.content_copy, size: 20),
            ),
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

  // ---- オートメーションモード ---------------------------------------------------

  static const _autoColor = Color(0xFF9A7CF2); // カーブの紫

  /// ノート／オートメーションの切替（ツールバーの左端）
  Widget _modeToggle() {
    Widget seg(String label, bool active, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? _autoColor : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? const Color(0xFFFFFFFF) : DawColors.muted)),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: DawColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DawColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('ノート', !_autoMode, () => _setAutoMode(false)),
          seg('オートメーション', _autoMode, () => _setAutoMode(true)),
        ],
      ),
    );
  }

  void _setAutoMode(bool on) {
    if (on == _autoMode) return;
    setState(() {
      _autoMode = on;
      _pasteReady = false;
      _drag = null;
      _autoSel = null;
      _autoDragIndex = null;
      if (on) {
        final pl = _placement;
        final clip = pl == null ? null : song.clip(pl.clipId);
        if (clip != null) _loadAutoLane(clip);
      }
    });
  }

  /// 編集中レーンの点をクリップから読み直す（コアの正規化済みの形になる）
  void _loadAutoLane(ClipData clip) {
    _autoPoints = [...clip.automationLane(_autoParamKey)?.points ?? const <(int, double)>[]];
    _autoSel = null;
  }

  /// Undo や外部の変更でレーンが変わっていたら合わせる（ドラッグ中は触らない）
  void _syncAuto(ClipData clip) {
    if (_autoDragIndex != null) return;
    final lane = clip.automationLane(_autoParamKey)?.points ?? const <(int, double)>[];
    if (!_samePoints(lane, _autoPoints)) _loadAutoLane(clip);
  }

  bool _samePoints(List<(int, double)> a, List<(int, double)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  SoundParam? get _autoParam => automationParamFor(_autoParamKey);

  /// 編集をコアへ確定する（1回の呼び出し = 1つの Undo）。確定後は正規化済みを読み直す
  void _commitAuto(int clipId) {
    final param = _autoParam;
    if (param == null) return;
    final sorted = [..._autoPoints]..sort((a, b) => a.$1.compareTo(b.$1));
    song.setClipAutomation(clipId, param.id, sorted);
    final fresh = song.clip(clipId);
    if (fresh != null) _loadAutoLane(fresh);
  }

  /// 対象パラメータのチップ（代表6種＋このクリップに既にレーンがあるもの）と、選んだ点の値
  Widget _autoParamBar(ClipData clip) {
    final params = <SoundParam>[...automationTargets];
    for (final lane in clip.automation) {
      final p = automationParamFor(lane.param);
      if (p != null && params.every((t) => t.key != p.key)) params.add(p);
    }
    final param = _autoParam;
    final sel = _autoSel;
    final readout = param == null
        ? ''
        : (sel != null && sel < _autoPoints.length)
            ? '${param.label}：${param.format(_autoPoints[sel].$2)}'
            : '${_autoPoints.length} 点';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(color: DawColors.panel, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in params)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: p.key == _autoParamKey ? _autoColor : DawColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: const BorderSide(color: DawColors.line),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() {
                            _autoParamKey = p.key;
                            _loadAutoLane(clip);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Text(automationShortLabel(p.key),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: p.key == _autoParamKey ? const Color(0xFFFFFFFF) : DawColors.text)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(readout,
                style: const TextStyle(fontSize: 11, color: DawColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
          ),
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
    final from = _startInClip.clamp(0, clip.lengthTicks - 1);
    song.playLoop(range.$1, range.$2, from: range.$1 + from);
  }

  /// 左の目盛りをタップ：その拍から再生する（再生中ならすぐ飛ぶ）。もう一度同じ所なら頭に戻す
  void _setStartAt(RollGeometry g, double y) {
    final pl = _placement;
    final clip = pl == null ? null : song.clip(pl.clipId);
    if (pl == null || clip == null) return;
    final offset = _v.hasClients ? _v.offset : 0.0;
    final tick = ((y + offset) / g.rowHeight * g.step).floor();
    var beat = (tick ~/ ticksPerBeat * ticksPerBeat).clamp(0, clip.lengthTicks - 1);
    if (beat == _startInClip) beat = 0;
    setState(() => _startInClip = beat);
    if (song.engine.isPlaying) song.engine.seek(_clipRange(pl, clip).$1 + beat);
  }

  // ---- コード入力 -------------------------------------------------------------

  List<Chord> _chords(Scale scale) => scaleChords(scale);

  /// ドラッグのデータ（ダイアトニックは番号そのまま、借用コードは 1000 + 番号）からコードを引く
  Chord _resolveChord(Scale scale, int data) =>
      data >= 1000 ? borrowedChords(scale)[data - 1000].chord : _chords(scale)[data];

  /// 置く長さの選択肢（tick と表示名）
  List<(int, String)> get _chordLengths {
    final tpb = song.project.ticksPerBar;
    return [(tpb, '1小節'), (tpb ~/ 2, '2拍'), (ticksPerBeat, '1拍'), (_step, 'グリッド')];
  }

  void _selectChord(Scale scale, int degree) {
    setState(() {
      _chordDegree = degree;
      _borrowedSel = null;
      _pickedChord = null;
    });
    final chord = _chords(scale)[degree];
    song.auditionChord(chord.pitchesNear(_centerPitch() ?? 60, withSeventh: _seventh));
  }

  void _selectBorrowed(Scale scale, int index) {
    setState(() {
      _borrowedSel = index;
      _pickedChord = null;
    });
    final chord = borrowedChords(scale)[index].chord;
    song.auditionChord(chord.pitchesNear(_centerPitch() ?? 60, withSeventh: _seventh));
  }

  /// サジェストの候補を選ぶ（次にロールをタップしたときに置くコードにする）
  void _selectSuggestion(Chord chord) {
    setState(() => _pickedChord = chord);
    song.auditionChord(chord.pitchesNear(_centerPitch() ?? 60));
  }

  /// サジェストの候補かどうか・選んでいる候補か（チップの見た目用）
  bool _isPicked(Chord c) {
    final p = _pickedChord;
    return p != null &&
        p.root == c.root &&
        listEquals(p.intervals, c.intervals) &&
        listEquals(p.extensions, c.extensions);
  }

  /// ボタンのコードを、[nearPitch] に一番近い根音から積んだ音。どこに置いてもボタン名どおりのコード
  /// （Cm7 なら必ず C が一番下）。高さは置いた列の近くのオクターブ
  List<int> _chordPitches(Chord chord, int nearPitch) {
    var root = nearPitch - ((nearPitch - chord.root) % 12);
    if (nearPitch - root > 6) root += 12; // 下より上の根音のほうが近い
    root = math.min(math.max(root, chord.root % 12), 115);
    return chord.pitchesNear(root, withSeventh: _seventh);
  }

  String _chordLabel(Chord c) => _seventh ? c.seventhName : c.name;

  void _placeChord(ClipData clip, int tick, int nearPitch, {int? degree}) {
    final scale = scaleOf(song.project);
    // degree はドラッグのデータ（借用は 1000 + 番号）。無ければサジェストで選んだコード、
    // それも無ければ今選んでいるコード
    final Chord chord;
    if (degree != null) {
      chord = _resolveChord(scale, degree);
    } else if (_pickedChord != null) {
      chord = _pickedChord!;
    } else {
      chord = _resolveChord(scale, _borrowedSel != null ? 1000 + _borrowedSel! : _chordDegree);
    }
    final pitches = _chordPitches(chord, nearPitch);
    final length = math.min(_chordLengths[_chordLenIndex].$1, clip.lengthTicks - tick);
    final ids = song.addChord(clip.id, tick: tick, length: length, pitches: pitches);
    song.auditionChord(pitches);
    setState(() {
      _selection
        ..clear()
        ..addAll(ids);
      // 置いたコードから自然に続く候補（雰囲気ごと）を出す。借用コードを置いたときも出す
      _prevChord = chord;
      _nextGroups = nextChordSuggestions(chord, scale);
      if (chord.degree >= 0 && chord.degree < _chords(scale).length) {
        // ボタンの順位バッジ（ダイアトニックの流れ）は従来どおり
        _suggest = suggestNextForScale(scale, chord.degree);
        _chordDegree = chord.degree;
      } else {
        // 借用コードを置いたら、順位バッジは消す（グループ別サジェストは上に出ている）
        _suggest = const [];
      }
      _dropAt = null;
    });
  }

  /// 画面の位置（ドラッグの指の位置）→ ロールの中の (tick, 高さ)。ロールの外なら null
  (int, int)? _dropTarget(RollGeometry g, Offset global) {
    final box = _rollKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    final local = box.globalToLocal(global);
    if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) return null;
    final at = _toContent(local);
    final col = g.colAt(at.dx);
    if (col == null || at.dy >= g.height) return null;
    return (g.tickAt(at.dy), g.columns[col]);
  }

  void _onChordDragMove(ClipData clip, RollGeometry g, int degree, Offset global) {
    final t = _dropTarget(g, global);
    if (t == null) {
      if (_dropAt != null) setState(() => _dropAt = null);
      return;
    }
    final chord = _resolveChord(scaleOf(song.project), degree);
    final next = (
      tick: t.$1,
      length: math.min(_chordLengths[_chordLenIndex].$1, clip.lengthTicks - t.$1),
      pitches: _chordPitches(chord, t.$2),
      label: _chordLabel(chord),
    );
    final cur = _dropAt;
    if (cur != null && cur.tick == next.tick && listEquals(cur.pitches, next.pitches)) return;
    setState(() => _dropAt = next);
  }

  void _onChordDrop(ClipData clip, RollGeometry g, int degree, Offset global) {
    final t = _dropTarget(g, global);
    if (t == null) {
      setState(() => _dropAt = null);
      return;
    }
    _placeChord(clip, t.$1, t.$2, degree: degree);
  }

  /// 選んでいるノートと、それがコードならその情報
  ({List<NoteData> notes, List<int> pitches, ChordInfo? info}) _selectedChord(ClipData clip) {
    final notes = clip.notes.where((n) => _selection.contains(n.id)).toList();
    final pitches = {for (final n in notes) n.pitch}.toList()..sort();
    return (notes: notes, pitches: pitches, info: pitches.length >= 3 ? analyzeChord(pitches) : null);
  }

  List<Widget> _chordToolsOverlay(ClipData clip, RollGeometry g, double viewportH) {
    final sel = _selectedChord(clip);
    final info = sel.info;
    if (info == null) return const [];
    final minTick = sel.notes.map((n) => n.tick).reduce(math.min);
    final maxEnd = sel.notes.map((n) => n.endTick).reduce(math.max);
    final bass = splitBass(sel.pitches).bass;
    return [
      AnimatedBuilder(
        animation: _v,
        builder: (context, child) {
          final off = _v.hasClients ? _v.offset : 0.0;
          var top = g.tickY(maxEnd) - off + 6;
          if (top + ChordToolsBar.height > viewportH) top = g.tickY(minTick) - off - ChordToolsBar.height - 6;
          top = top.clamp(4.0, math.max(4.0, viewportH - ChordToolsBar.height - 4)).toDouble();
          return Positioned(left: _labelWidth + 6, right: 6, top: top, child: child!);
        },
        child: ChordToolsBar(
          info: info,
          closed: isClosed(sel.pitches),
          bassLabel: bass == null ? 'なし' : noteName(bass),
          onInvert: (up) => _applyEdit(clip, invert(sel.pitches, up: up)),
          onSpread: () => _applyEdit(clip, spreadOrClose(sel.pitches)),
          onBass: () => _applyEdit(clip, cycleBass(sel.pitches)),
          onLead: () => _leadToPrevious(clip, sel.notes, sel.pitches, minTick),
          onSeventh: () => _applyEdit(clip, toggleSeventh(sel.pitches, scaleOf(song.project))),
          onSus: (to) => _applyEdit(clip, toggleSus(sel.pitches, scaleOf(song.project), to: to)),
          onNinth: () => _applyEdit(clip, toggleNinth(sel.pitches)),
          onRhythm: (r) => _rhythmize(clip, sel.notes, sel.pitches, r),
        ),
      ),
    ];
  }

  List<NoteSpec> _specsOf(List<NoteData> notes) =>
      [for (final n in notes) NoteSpec(n.tick, n.length, n.pitch, n.velocity)];

  /// 選んだノートの音の高さを書き換える（1回の Undo）。新しいノートを選び直して鳴らす
  void _applyEdit(ClipData clip, PitchEdit edit) {
    if (edit.isEmpty) {
      HapticFeedback.heavyImpact(); // それ以上は動かせない
      return;
    }
    final notes = clip.notes.where((n) => _selection.contains(n.id)).toList();
    final next = applyPitchEdit(_specsOf(notes), edit);
    _replaceSelection(clip, notes, next);
  }

  void _replaceSelection(ClipData clip, List<NoteData> old, List<NoteSpec> next) {
    final ids = song.replaceNotes(clip.id, [for (final n in old) n.id], next);
    setState(() {
      _selection
        ..clear()
        ..addAll(ids);
    });
    if (next.isNotEmpty) {
      final first = next.map((n) => n.tick).reduce(math.min);
      song.auditionChord({for (final n in next) if (n.tick == first) n.pitch}.toList());
    }
  }

  /// 前のコード（選んだノートより前で、一番近い時刻に3音以上鳴っているもの）に寄せる
  void _leadToPrevious(ClipData clip, List<NoteData> notes, List<int> pitches, int minTick) {
    final before = <int, List<int>>{};
    for (final n in clip.notes) {
      if (_selection.contains(n.id) || n.tick >= minTick) continue;
      (before[n.tick] ??= []).add(n.pitch);
    }
    final ticks = before.keys.where((t) => before[t]!.length >= 3).toList()..sort();
    if (ticks.isEmpty) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('前にコードがないので寄せられません')));
      return;
    }
    _applyEdit(clip, voiceLead(before[ticks.last]!, pitches));
  }

  void _rhythmize(ClipData clip, List<NoteData> notes, List<int> pitches, ChordRhythm rhythm) {
    final start = notes.map((n) => n.tick).reduce(math.min);
    final end = notes.map((n) => n.endTick).reduce(math.max);
    final velocity = notes.map((n) => n.velocity).reduce(math.max);
    _replaceSelection(clip, notes,
        rhythmize(pitches, start: start, length: end - start, rhythm: rhythm, velocity: velocity));
  }

  Future<void> _openProgressions(ClipData clip, Scale scale) async {
    final ids = await showProgressionSheet(
      context,
      song: song,
      clip: clip,
      scale: scale,
      markerTick: _startInClip,
      placement: _placement,
    );
    if (ids == null || !mounted) return;
    setState(() {
      _selection
        ..clear()
        ..addAll(ids);
    });
  }

  /// 鍵盤の代わりに並ぶコードのボタン。置いた直後は次に合うコードが光る
  /// コードのボタン（ドラッグでロールへ置ける）。[data] がドラッグで運ぶ値
  Widget _dragChordButton({
    required int data,
    required String name,
    required String sub,
    required bool selected,
    required int rank,
    required VoidCallback onSelect,
    bool borrowed = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Draggable<int>(
          data: data,
          // 指の位置＝置く位置。見た目のチップは指に隠れないよう少し上に
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: onSelect,
          onDragEnd: (_) => setState(() => _dropAt = null),
          feedback: Transform.translate(
            offset: const Offset(-36, -64),
            child: _ChordDragChip(name: name),
          ),
          childWhenDragging: Opacity(
            opacity: 0.5,
            child: _ChordButton(name: name, mood: sub, selected: true, rank: 0, borrowed: borrowed, onTap: () {}),
          ),
          child: _ChordButton(
            name: name,
            mood: sub,
            selected: selected,
            rank: rank,
            borrowed: borrowed,
            onTap: onSelect,
          ),
        ),
      ),
    );
  }

  Widget _chordPanel(Scale scale, ClipData clip) {
    final chords = _chords(scale);
    final borrowed = borrowedChords(scale);
    final length = _chordLengths[_chordLenIndex];
    String label(Chord c) => _seventh ? c.seventhName : c.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _nextGroups.isNotEmpty && _prevChord != null
                      ? '${label(_prevChord!)} のあとにおすすめ（下の候補をタップで選ぶ）'
                      : 'コードをロールへドラッグして置く（選んでからタップでも置ける）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DawColors.muted),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _chordLenIndex = (_chordLenIndex + 1) % _chordLengths.length),
                child: Text('長さ ${length.$2}', style: const TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: () => _openProgressions(clip, scale),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('進行', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          // 直前のコードから自然に続く候補（雰囲気ごと。タップで選んで、ロールをタップで置く）
          if (_nextGroups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 46,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final group in _nextGroups) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 2),
                          child: Text(group.mood,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF5AD6C0))),
                        ),
                        for (final c in group.chords)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            child: _SuggestChip(
                              name: c.name,
                              sub: c.extensions.isNotEmpty
                                  ? '${c.roman} · 7th'
                                  : (c.roman.isNotEmpty ? c.roman : c.mood),
                              selected: _isPicked(c),
                              borrowed: c.degree < 0,
                              onTap: () => _selectSuggestion(c),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          // ダイアトニック（4つずつ並べる。最後の段の空きに 7th ボタン）
          for (var r = 0; r < chords.length; r += 4)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  for (final c in chords.skip(r).take(4))
                    _dragChordButton(
                      data: c.degree,
                      name: label(c),
                      sub: c.roman.isEmpty ? c.mood : '${c.roman} · ${c.mood}',
                      selected: _pickedChord == null && _borrowedSel == null && c.degree == _chordDegree,
                      rank: _suggest.indexOf(c.degree) + 1,
                      onSelect: () => _selectChord(scale, c.degree),
                    ),
                  if (r + 4 >= chords.length) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _ChordButton(
                          name: '7th',
                          mood: _seventh ? '足す' : '足さない',
                          selected: _seventh,
                          rank: 0,
                          onTap: () => setState(() => _seventh = !_seventh),
                        ),
                      ),
                    ),
                    for (var i = chords.length - r + 1; i < 4; i++) const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ),
          // 借用コード（キー外だけど定番の味付け。置き方は通常のコードと同じ）
          const Padding(
            padding: EdgeInsets.only(top: 10, left: 2),
            child: Text('借用コード', style: TextStyle(fontSize: 11, color: Color(0xFFF2D45A))),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                for (var i = 0; i < borrowed.length; i++)
                  _dragChordButton(
                    data: 1000 + i,
                    name: label(borrowed[i].chord),
                    sub: '${borrowed[i].chord.roman} · ${borrowed[i].origin}',
                    selected: _pickedChord == null && _borrowedSel == i,
                    rank: 0,
                    borrowed: true,
                    onSelect: () => _selectBorrowed(scale, i),
                  ),
                for (var i = borrowed.length; i < 4; i++) const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
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
            child: _autoMode
                ? _ValueButton(
                    caption: 'モード',
                    value: 'ノートへ',
                    onTap: () => _setAutoMode(false),
                  )
                : _ValueButton(
                    caption: 'コード',
                    value: _chordMode ? 'ON' : 'OFF',
                    highlighted: _chordMode,
                    onTap: () => setState(() {
                      _chordMode = !_chordMode;
                      _pasteReady = false;
                      _suggest = const [];
                      _prevChord = null;
                      _nextGroups = const [];
                      _pickedChord = null;
                    }),
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
    if (_autoMode) return _autoRoll(clip, scale, track);
    final kit = track != null && track.isKit ? song.kits.installed(track.kitId) : null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFF16181B), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final viewportW = box.maxWidth - _labelWidth;
          final keyboardH = _chordMode ? 0.0 : _keyboardHeight + 6;
          final viewportH = box.maxHeight - keyboardH;
          final rows = math.max(1, (clip.lengthTicks + _step - 1) ~/ _step);
          final rowHeight = _rowHeightFor(viewportH, rows);
          final g = RollGeometry(
            // ドラムキットのトラックは、キットに入っている音だけを列にする
            columns: kit != null && kit.sounds.isNotEmpty ? kit.notes : rollColumns(scale, chromatic: _chromatic),
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _setStartAt(g, d.localPosition.dy),
                  child: CustomPaint(
                    painter: _LabelPainter(
                        g: g, v: _v, ticksPerBar: song.project.ticksPerBar, startTick: _startInClip),
                  ),
                ),
              ),
              // ロール
              Positioned(
                left: _labelWidth,
                top: 0,
                right: 0,
                height: viewportH,
                child: DragTarget<int>(
                  // コードのボタンをドラッグしてきて、離した所（時間）に置く
                  onMove: (d) => _onChordDragMove(clip, g, d.data, d.offset),
                  onLeave: (_) => setState(() => _dropAt = null),
                  onAcceptWithDetails: (d) => _onChordDrop(clip, g, d.data, d.offset),
                  builder: (context, candidates, rejected) => Stack(
                    children: [
                      Positioned.fill(child: GestureDetector(
                  key: _rollKey,
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(clip, g, _toContent(d.localPosition)),
                  onLongPressStart: (d) => _onLongPressStart(clip, g, _toContent(d.localPosition)),
                  onLongPressMoveUpdate: (d) => _onLongPressMove(g, _toContent(d.localPosition)),
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
                              chromatic: _chromatic,
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
                )),
                      if (_dropAt case final drop?)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _ChordDropPainter(
                                g: g,
                                tick: drop.tick,
                                length: drop.length,
                                pitches: drop.pitches,
                                label: drop.label,
                                color: color,
                                hOffset: _h.hasClients ? _h.offset : 0,
                                vOffset: _v.hasClients ? _v.offset : 0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 選んだノートがコードなら、そのすぐ下（入らなければ上）に道具の帯を浮かべる（案A）
              if (_drag == null) ..._chordToolsOverlay(clip, g, viewportH),
              // 試聴鍵盤（ロールと一緒に横へ動く）。コード入力中はコードのボタンに置き換わる
              if (!_chordMode)
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
                      labels: kit?.labels,
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

  /// オートメーションモードのロール：横幅そのままに、ゴーストノートの上へカーブを描く。
  /// 縦（時間）はノートと同じ RollGeometry と同じ縦スクロール（_v）を使うので、
  /// ノートとカーブの時間位置がそのまま見比べられる。横は値（左 = 小さい）なので横スクロールはしない
  Widget _autoRoll(ClipData clip, Scale scale, TrackData? track) {
    final kit = track != null && track.isKit ? song.kits.installed(track.kitId) : null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFF16181B), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final viewportW = box.maxWidth - _labelWidth;
          final viewportH = box.maxHeight;
          final rows = math.max(1, (clip.lengthTicks + _step - 1) ~/ _step);
          final rowHeight = _rowHeightFor(viewportH, rows);
          final g = RollGeometry(
            // ゴーストノートの列はノートモードと同じ並びにする
            columns: kit != null && kit.sounds.isNotEmpty ? kit.notes : rollColumns(scale, chromatic: _chromatic),
            colWidth: _colWidth,
            step: _step,
            rowHeight: rowHeight,
            lengthTicks: clip.lengthTicks,
          );
          _g = g;
          _viewportWidth = viewportW;
          final color = track != null ? Color(track.color) : DawColors.lead;
          return Stack(
            children: [
              // 小節・拍の目盛り（ノートモードと共通）
              Positioned(
                left: 0,
                top: 0,
                width: _labelWidth,
                height: viewportH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _setStartAt(g, d.localPosition.dy),
                  child: CustomPaint(
                    painter: _LabelPainter(
                        g: g, v: _v, ticksPerBar: song.project.ticksPerBar, startTick: _startInClip),
                  ),
                ),
              ),
              // カーブの編集面
              Positioned(
                left: _labelWidth,
                top: 0,
                right: 0,
                height: viewportH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onAutoTap(clip, g, _autoContent(d.localPosition), viewportW),
                  onLongPressStart: (d) => _onAutoLongPress(clip, g, _autoContent(d.localPosition), viewportW),
                  onPanStart: (d) => _onAutoPanStart(g, _autoContent(d.localPosition), viewportW),
                  onPanUpdate: (d) => _onAutoPanUpdate(g, d, viewportW),
                  onPanEnd: (d) => _onAutoPanEnd(clip, d.velocity),
                  onPanCancel: () => _autoDragIndex = null,
                  child: SingleChildScrollView(
                    controller: _v,
                    physics: const NeverScrollableScrollPhysics(), // スクロールは自前（点のドラッグと分けるため）
                    child: SizedBox(
                      width: viewportW,
                      height: g.height + _bottomRoom,
                      child: CustomPaint(
                        painter: _AutoPainter(
                          clip: clip,
                          g: g,
                          scale: scale,
                          chromatic: _chromatic,
                          ticksPerBar: song.project.ticksPerBar,
                          noteColor: color,
                          curveColor: _autoColor,
                          param: _autoParam,
                          points: _autoPoints,
                          sel: _autoSel,
                          playhead: _playhead,
                          h: _h,
                        ),
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

  /// 編集面の座標（縦スクロールを足した中身の座標。横はそのまま = 値の位置）
  Offset _autoContent(Offset viewport) =>
      Offset(viewport.dx, viewport.dy + (_v.hasClients ? _v.offset : 0));

  /// その位置に一番近い点（指の太さを見込んで半径 28px まで）
  int? _autoPointAt(RollGeometry g, Offset at, double width) {
    final param = _autoParam;
    if (param == null) return null;
    int? best;
    var bestDist = 28.0;
    for (var i = 0; i < _autoPoints.length; i++) {
      final (tick, value) = _autoPoints[i];
      final dx = param.toUnit(value) * width - at.dx;
      final dy = g.tickY(tick) - at.dy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  /// タップ：近くに点があれば選ぶだけ、無ければその位置に点を追加して確定（1つの Undo）
  void _onAutoTap(ClipData clip, RollGeometry g, Offset at, double width) {
    final param = _autoParam;
    if (param == null || at.dy >= g.height) return;
    final hit = _autoPointAt(g, at, width);
    if (hit != null) {
      setState(() => _autoSel = hit);
      return;
    }
    final tick = g.tickAt(at.dy);
    final value = param.fromUnit(width <= 0 ? 0 : at.dx / width);
    setState(() {
      // 同じ tick の点は置き換え（コアの正規化と同じ「あと勝ち」）
      _autoPoints = [..._autoPoints.where((p) => p.$1 != tick), (tick, value)]
        ..sort((a, b) => a.$1.compareTo(b.$1));
      _autoSel = _autoPoints.indexWhere((p) => p.$1 == tick);
      _commitAuto(clip.id);
    });
  }

  /// 長押し：近くの点を消して確定（1つの Undo）
  void _onAutoLongPress(ClipData clip, RollGeometry g, Offset at, double width) {
    final hit = _autoPointAt(g, at, width);
    if (hit == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _autoDragIndex = null;
      _autoPoints = [..._autoPoints]..removeAt(hit);
      _autoSel = null;
      _commitAuto(clip.id);
    });
  }

  void _onAutoPanStart(RollGeometry g, Offset at, double width) {
    _autoDragMoved = false;
    final hit = _autoPointAt(g, at, width);
    if (hit != null) {
      setState(() {
        _autoDragIndex = hit;
        _autoSel = hit;
      });
    } else {
      _autoDragIndex = null; // 点を掴んでいないなぞりは縦スクロール
    }
  }

  void _onAutoPanUpdate(RollGeometry g, DragUpdateDetails d, double width) {
    final index = _autoDragIndex;
    final param = _autoParam;
    if (index == null || param == null) {
      if (_v.hasClients) {
        _v.jumpTo((_v.offset - d.delta.dy).clamp(0, _v.position.maxScrollExtent).toDouble());
      }
      return;
    }
    final at = _autoContent(d.localPosition);
    final tick = g.tickAt(at.dy);
    final value = param.fromUnit(width <= 0 ? 0 : at.dx / width);
    setState(() {
      _autoDragMoved = true;
      final next = [..._autoPoints];
      next[index] = (tick, value);
      // 同じ tick に重なった他の点は消す（あと勝ち）
      _autoPoints = [
        for (var i = 0; i < next.length; i++)
          if (i == index || next[i].$1 != tick) next[i],
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      _autoSel = _autoPoints.indexWhere((p) => p.$1 == tick);
    });
  }

  /// 指を離したら、点の移動を1回だけ確定する（シートと同じ確定タイミング）
  void _onAutoPanEnd(ClipData clip, Velocity velocity) {
    final index = _autoDragIndex;
    _autoDragIndex = null;
    if (index != null) {
      if (_autoDragMoved) _commitAuto(clip.id);
      return;
    }
    final v = velocity.pixelsPerSecond.dy;
    if (_v.hasClients && v.abs() > 200) {
      final to = (_v.offset - v * 0.3).clamp(0, _v.position.maxScrollExtent).toDouble();
      _v.animateTo(to, duration: const Duration(milliseconds: 450), curve: Curves.decelerate);
    }
  }

  /// 開いたとき（と全音表示を切り替えたとき）に、見せたい音のあたりへ横スクロールする
  void _scheduleCentering(ClipData clip, Scale scale, RollGeometry g, double viewportW) {
    int? pitch = _pendingCenterPitch;
    if (!_centered) {
      final oct = bestOctave(clip, scale);
      pitch = (oct + 1) * 12 + scale.root + 6; // そのオクターブの真ん中あたり
      if (!g.columns.contains(pitch) && g.columns.length < 40) {
        // ドラムキット：左端（キック）から見せる
        _centered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_h.hasClients) _h.jumpTo(0);
        });
        return;
      }
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
    // 貼り付け待ち：タップしたマス（tick・音程）にコピーの原点を合わせて貼る。
    // 貼り付けは続けてできる（やめるときは「貼り付け」ボタンをもう一度押す）
    if (_pasteReady && song.hasNoteClipboard) {
      final col = g.colAt(at.dx);
      if (col != null && at.dy < g.height) {
        final ids = song.pasteNotes(clip.id, anchorTick: g.tickAt(at.dy), anchorPitch: g.columns[col]);
        if (ids.isEmpty) {
          HapticFeedback.heavyImpact(); // はみ出して1つも貼れなかった
        } else {
          setState(() => _selection
            ..clear()
            ..addAll(ids));
          final fresh = song.clip(clip.id);
          final pasted = fresh?.notes.where((n) => ids.contains(n.id)).toList() ?? const [];
          if (pasted.isNotEmpty) {
            final first = pasted.map((n) => n.tick).reduce(math.min);
            song.auditionChord({for (final n in pasted) if (n.tick == first) n.pitch}.toList());
          }
        }
      }
      return;
    }
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
    final tick = g.tickAt(at.dy);
    final pitch = g.columns[col];
    if (_chordMode) {
      _placeChord(clip, tick, pitch);
      return;
    }
    // 何もないところ：ノートを置いて選ぶ（すぐつまみで伸ばせる）
    final id = song.addNote(clip.id, tick: tick, length: math.min(_step, clip.lengthTicks - tick), pitch: pitch);
    song.audition(pitch);
    setState(() {
      _selection.clear();
      if (id != 0) _selection.add(id);
    });
  }

  /// 長押し：ノートの上なら持ち上げて移動、何もないところなら範囲選択
  void _onLongPressStart(ClipData clip, RollGeometry g, Offset at) {
    final hit = noteAt(clip, g, at.dx, at.dy);
    if (hit != null) {
      HapticFeedback.mediumImpact();
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
    HapticFeedback.selectionClick();
    setState(() => _drag = _Drag(kind: _DragKind.marquee, start: at));
  }

  void _onLongPressMove(RollGeometry g, Offset at) {
    final d = _drag;
    if (d == null) return;
    d.current = at;
    if (d.kind == _DragKind.move) _auditionMove(d, g);
    setState(() {});
  }

  void _onLongPressEnd(ClipData clip, RollGeometry g) {
    final d = _drag;
    if (d == null) return;
    setState(() => _drag = null);
    if (d.kind == _DragKind.marquee) {
      final ids = notesInRect(clip, g, d.start.dx, d.start.dy, d.current.dx, d.current.dy);
      setState(() => _selection
        ..clear()
        ..addAll(ids));
    } else {
      _commit(d, clip, g);
    }
  }

  /// 動かしている間、行き先の音を鳴らす
  void _auditionMove(_Drag d, RollGeometry g) {
    final pitch = d.anchorPitch + _deltaPitch(d, g);
    if (pitch != d.lastAuditioned && pitch != d.anchorPitch) {
      d.lastAuditioned = pitch;
      song.audition(pitch);
    }
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
    if (d.kind == _DragKind.move) _auditionMove(d, g);
    setState(() {});
  }

  void _onPanEnd(ClipData clip, RollGeometry g, Velocity velocity) {
    final d = _drag;
    setState(() => _drag = null);
    if (d == null) return;
    if (d.kind == _DragKind.scroll) {
      _fling(velocity);
      return;
    }
    _commit(d, clip, g);
  }

  /// なぞり終わり：1つの編集コマンドにする
  void _commit(_Drag d, ClipData clip, RollGeometry g) {
    switch (d.kind) {
      case _DragKind.scroll:
        break;
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
  _LabelPainter({required this.g, required this.v, required this.ticksPerBar, required this.startTick})
      : super(repaint: v);

  final RollGeometry g;
  final ScrollController v;
  final int ticksPerBar;
  final int startTick; // 再生を始める拍（印をつける）

  @override
  void paint(Canvas canvas, Size size) {
    final offset = v.hasClients ? v.offset : 0.0;
    canvas.clipRect(Offset.zero & size);
    for (var tick = 0; tick < g.lengthTicks; tick += ticksPerBeat) {
      final y = g.tickY(tick) - offset;
      if (y < -20 || y > size.height) continue;
      final isBar = tick % ticksPerBar == 0;
      final isStart = tick == startTick && startTick > 0;
      if (isStart) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(1, y, size.width - 2, 18), const Radius.circular(5)),
            Paint()..color = DawColors.accent);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: isBar ? '${tick ~/ ticksPerBar + 1}' : (isStart ? '▶' : '·'),
          style: TextStyle(
            color: isStart ? DawColors.background : (isBar ? DawColors.text : DawColors.muted),
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
  bool shouldRepaint(_LabelPainter old) => old.g != g || old.startTick != startTick;
}

class _RollPainter extends CustomPainter {
  _RollPainter({
    required this.clip,
    required this.g,
    required this.scale,
    required this.chromatic,
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
  final bool chromatic; // 全音表示か（スケール内外の色分けはこのときだけ）
  final int ticksPerBar;
  final Color noteColor;
  final Set<int> selection;
  final _Drag? drag;
  final ValueNotifier<int?> playhead;
  final ScrollController h;
  final double viewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // 列の色分け。ルート音は目印の色と線、全音表示のときはスケール内を淡く色付け・スケール外を暗くする
    for (var c = 0; c < g.columns.length; c++) {
      final p = g.columns[c];
      final isRoot = p % 12 == scale.root;
      if (isRoot) {
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height), Paint()..color = const Color(0xFF1C1F23));
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, 1, g.height), Paint()..color = const Color(0xFF3A3E46));
      } else if (!scale.contains(p)) {
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height), Paint()..color = const Color(0xFF121315));
      } else if (chromatic) {
        canvas.drawRect(Rect.fromLTWH(g.colX(c), 0, g.colWidth, g.height), Paint()..color = const Color(0xFF182420));
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

    // 同じ時刻に3音以上あればコード名を出す（転回形なら A♭/C のように）
    final byTick = <int, List<NoteData>>{};
    for (final n in clip.notes) {
      (byTick[n.tick] ??= []).add(n);
    }
    for (final entry in byTick.entries) {
      if (entry.value.length < 3) continue;
      final name = chordNameOf(entry.value.map((n) => n.pitch));
      if (name == null) continue;
      final cols = entry.value.map((n) => g.columnOf(n.pitch)).whereType<int>();
      if (cols.isEmpty) continue;
      final x = g.colX(cols.reduce(math.min)) + 3;
      final y = g.tickY(entry.key) + 3;
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(color: DawColors.text, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tp.width + 10, tp.height + 2), const Radius.circular(7)),
        Paint()..color = DawColors.background.withValues(alpha: 0.85),
      );
      tp.paint(canvas, Offset(x + 5, y + 1));
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

/// オートメーションモードの描画：ノートと同じ背景・グリッドの上にゴーストノート（淡色）、
/// その上に選択中レーンのカーブ（横 = 値、縦 = ノートと同じ tick→y）。
/// ゴーストの横位置はノートモードの横スクロール（h）に合わせるので、モードを切り替えても音の位置がずれない
class _AutoPainter extends CustomPainter {
  _AutoPainter({
    required this.clip,
    required this.g,
    required this.scale,
    required this.chromatic,
    required this.ticksPerBar,
    required this.noteColor,
    required this.curveColor,
    required this.param,
    required this.points,
    required this.sel,
    required this.playhead,
    required this.h,
  }) : super(repaint: Listenable.merge([playhead, h]));

  final ClipData clip;
  final RollGeometry g;
  final Scale scale;
  final bool chromatic;
  final int ticksPerBar;
  final Color noteColor;
  final Color curveColor;
  final SoundParam? param;
  final List<(int, double)> points;
  final int? sel;
  final ValueNotifier<int?> playhead;
  final ScrollController h;

  @override
  void paint(Canvas canvas, Size size) {
    final hOff = h.hasClients ? h.offset : 0.0;

    // 列の背景（ノートモードと同じ色分け・同じ横位置）
    for (var c = 0; c < g.columns.length; c++) {
      final p = g.columns[c];
      final x = g.colX(c) - hOff;
      if (x + g.colWidth < 0 || x > size.width) continue;
      final isRoot = p % 12 == scale.root;
      if (isRoot) {
        canvas.drawRect(Rect.fromLTWH(x, 0, g.colWidth, g.height), Paint()..color = const Color(0xFF1C1F23));
        canvas.drawRect(Rect.fromLTWH(x, 0, 1, g.height), Paint()..color = const Color(0xFF3A3E46));
      } else if (!scale.contains(p)) {
        canvas.drawRect(Rect.fromLTWH(x, 0, g.colWidth, g.height), Paint()..color = const Color(0xFF121315));
      } else if (chromatic) {
        canvas.drawRect(Rect.fromLTWH(x, 0, g.colWidth, g.height), Paint()..color = const Color(0xFF182420));
      }
    }

    // 横線：小節（明）、拍（中）、グリッド（暗）。ノートモードと同じ
    for (var r = 0; r <= g.rows; r++) {
      final tick = r * g.step;
      final isBar = tick % ticksPerBar == 0;
      final isBeat = tick % ticksPerBeat == 0;
      canvas.drawRect(
        Rect.fromLTWH(0, g.tickY(tick), size.width, isBar ? 1.5 : 1),
        Paint()..color = isBar ? const Color(0xFF4A4F58) : (isBeat ? const Color(0xFF2A2D33) : const Color(0xFF1F2125)),
      );
    }

    // 値の目安（縦線：左 = 小さい値、右 = 大きい値）
    final guide = Paint()..color = DawColors.line.withValues(alpha: 0.5);
    for (final u in [0.25, 0.5, 0.75]) {
      canvas.drawRect(Rect.fromLTWH(u * size.width, 0, 1, g.height), guide);
    }

    // ゴーストノート（既存ノートを通常の音程・時間位置に淡色で）
    final ghost = Paint()..color = noteColor.withValues(alpha: 0.22);
    for (final n in clip.notes) {
      final col = g.columnOf(n.pitch);
      if (col == null) continue;
      final rect = Rect.fromLTRB(
        g.colX(col) - hOff + 2,
        g.tickY(n.tick) + 1,
        g.colX(col) - hOff + g.colWidth - 2,
        g.tickY(n.endTick) - 1,
      );
      if (rect.right < 0 || rect.left > size.width) continue;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), ghost);
    }

    // カーブ（x = パラメータの目盛りで正規化した値、y = ノートと同じ時間軸）
    final param = this.param;
    if (param != null && points.isNotEmpty) {
      double xOf(double v) => param.toUnit(v) * size.width;
      final path = Path()..moveTo(xOf(points.first.$2), g.tickY(points.first.$1));
      for (final p in points.skip(1)) {
        path.lineTo(xOf(p.$2), g.tickY(p.$1));
      }
      path.lineTo(xOf(points.last.$2), g.height); // 最後の点より後は値そのまま
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = curveColor.withValues(alpha: 0.25),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = curveColor,
      );
      for (var i = 0; i < points.length; i++) {
        final c = Offset(xOf(points[i].$2), g.tickY(points[i].$1));
        canvas.drawCircle(c, i == sel ? 7 : 5, Paint()..color = curveColor);
        if (i == sel) {
          canvas.drawCircle(
            c,
            7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = DawColors.text,
          );
        }
      }
      // 値域の目安（最小は左上、最大は右上）
      _text(canvas, param.format(param.min), const Offset(4, 4), color: DawColors.muted, size: 9);
      final maxLabel = param.format(param.max);
      final tp = TextPainter(
        text: TextSpan(text: maxLabel, style: const TextStyle(color: DawColors.muted, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 4, 4));
    }

    // クリップの終わり（線と下側のマスク。ノートモードと同じ見た目）
    canvas.drawRect(Rect.fromLTWH(0, g.height, size.width, size.height - g.height),
        Paint()..color = DawColors.background.withValues(alpha: 0.55));
    canvas.drawRect(Rect.fromLTWH(0, g.height - 1, size.width, 2), Paint()..color = DawColors.accent.withValues(alpha: 0.8));

    // 再生位置
    final ph = playhead.value;
    if (ph != null) {
      canvas.drawRect(Rect.fromLTWH(0, g.tickY(ph) - 1, size.width, 2), Paint()..color = DawColors.text);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {required Color color, required double size}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_AutoPainter old) => true; // 点を動かしている間は毎回描き直す
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
  const _ValueButton({required this.caption, required this.value, required this.onTap, this.highlighted = false});

  final String caption;
  final String value;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0xFF2E3A1A) : DawColors.panel,
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

/// ドラッグ中に指の上に出るコード名
class _ChordDragChip extends StatelessWidget {
  const _ChordDragChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DawColors.accent,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: DawColors.background)),
      ),
    );
  }
}

/// ドラッグ中、置かれるコードを薄く出す
class _ChordDropPainter extends CustomPainter {
  _ChordDropPainter({
    required this.g,
    required this.tick,
    required this.length,
    required this.pitches,
    required this.label,
    required this.color,
    required this.hOffset,
    required this.vOffset,
  });

  final RollGeometry g;
  final int tick, length;
  final List<int> pitches;
  final String label;
  final Color color;
  final double hOffset, vOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final y = g.tickY(tick) - vOffset;
    final h = math.max(g.tickY(length), 6.0);
    canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 2), Paint()..color = DawColors.accent);
    final fill = Paint()..color = color.withValues(alpha: 0.45);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final p in pitches) {
      final col = g.columnOf(p) ?? g.nearestColumn(p);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(g.colX(col) - hOffset + 1, y, g.colWidth - 2, h), const Radius.circular(4));
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: label, style: const TextStyle(color: DawColors.accent, fontSize: 13, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(4, y - tp.height - 2));
  }

  @override
  bool shouldRepaint(_ChordDropPainter old) =>
      old.tick != tick || old.length != length || !listEquals(old.pitches, pitches) || old.hOffset != hOffset || old.vOffset != vOffset;
}

/// サジェスト帯の候補チップ（横スクロールに載せるので幅は中身なり）。見分けは _ChordButton と揃える
class _SuggestChip extends StatelessWidget {
  const _SuggestChip({
    required this.name,
    required this.sub,
    required this.selected,
    required this.borrowed,
    required this.onTap,
  });

  final String name;
  final String sub;
  final bool selected;
  final bool borrowed; // 借用コード（金色で見分ける）
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? DawColors.background : DawColors.text;
    return Material(
      color: selected ? (borrowed ? _ChordButton._gold : DawColors.text) : (borrowed ? _ChordButton._goldBg : DawColors.background),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borrowed ? _ChordButton._goldLine : DawColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              Text(sub,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 9, color: selected ? DawColors.background : (borrowed ? _ChordButton._gold : DawColors.muted))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChordButton extends StatelessWidget {
  const _ChordButton({
    required this.name,
    required this.mood,
    required this.selected,
    required this.rank,
    required this.onTap,
    this.borrowed = false,
  });

  final String name;
  final String mood;
  final bool selected;
  final int rank; // 次のおすすめの順位（0 ならおすすめではない）
  final VoidCallback onTap;
  final bool borrowed; // 借用コード（金色で見分ける）

  static const _gold = Color(0xFFF2D45A);
  static const _goldLine = Color(0xFF8A6D1F);
  static const _goldBg = Color(0xFF221D10);

  @override
  Widget build(BuildContext context) {
    final recommended = rank > 0;
    final fg = selected ? DawColors.background : DawColors.text;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: selected ? (borrowed ? _gold : DawColors.text) : (borrowed ? _goldBg : DawColors.panel),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: recommended ? DawColors.accent : (borrowed ? _goldLine : DawColors.line),
              width: recommended ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                  Text(mood,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: selected ? DawColors.background : (borrowed ? _gold : DawColors.muted))),
                ],
              ),
            ),
          ),
        ),
        if (recommended)
          Positioned(
            top: -6,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: DawColors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('$rank',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: DawColors.background)),
            ),
          ),
        if (borrowed)
          Positioned(
            top: -6,
            left: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _goldLine, borderRadius: BorderRadius.circular(8)),
              child: const Text('借用',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFFFE9A3))),
            ),
          ),
      ],
    );
  }
}
