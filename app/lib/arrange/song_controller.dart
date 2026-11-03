import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import 'demo_song.dart';
import 'timeline_math.dart';

/// 画面とコアのあいだ。編集はコアに頼み、変わったら読み直して画面に知らせる。
/// 編集後 2 秒操作がなければ自動で保存する（バックグラウンドに回るときは [saveNow]）。
class SongController extends ChangeNotifier {
  SongController(this.engine, {required this.projectPath}) : project = engine.project {
    _version = engine.projectVersion;
  }

  static const autosaveDelay = Duration(seconds: 2);

  /// 新しいトラックの色（画面案の4色から順に）
  static const trackColors = [0xFFF28C38, 0xFF5AA9F2, 0xFFC8F25A, 0xFFE879C6, 0xFF9A7CF2, 0xFF5AD6C0];

  final MdawEngine engine;
  final String projectPath;

  ProjectData project;
  int _version = 0;
  Timer? _saveTimer;

  /// 保存に失敗したときの理由（成功したら null に戻る）
  String? saveError;

  /// 選んでいる配置（クリップ）
  int? selectedPlacementId;

  PlacementData? get selected {
    final id = selectedPlacementId;
    if (id == null) return null;
    for (final pl in project.placements) {
      if (pl.id == id) return pl;
    }
    return null;
  }

  bool get canUndo => engine.canUndo;
  bool get canRedo => engine.canRedo;

  /// 保存してある曲を開く。無ければ・読めなければ新しい曲のまま
  void open() {
    if (File(projectPath).existsSync()) {
      try {
        engine.loadProject(projectPath);
      } on MdawFileException catch (e) {
        saveError = '保存した曲を読めませんでした：${e.message}';
      }
    }
    _refresh(force: true);
  }

  void _refresh({bool force = false}) {
    final v = engine.projectVersion;
    if (!force && v == _version) return;
    _version = v;
    project = engine.project;
    if (selected == null) selectedPlacementId = null;
    notifyListeners();
    _scheduleSave();
  }

  T _edit<T>(T Function() action) {
    final result = action();
    _refresh();
    return result;
  }

  // ---- 保存 -----------------------------------------------------------------

  void _scheduleSave() {
    if (!engine.isDirty) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, saveNow);
  }

  /// 未保存の変更があれば、すぐ保存する
  void saveNow({bool force = false}) {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!force && !engine.isDirty) return;
    try {
      File(projectPath).parent.createSync(recursive: true);
      engine.saveProject(projectPath);
      if (saveError != null) {
        saveError = null;
        notifyListeners();
      }
    } on Object catch (e) {
      saveError = '保存できませんでした：$e';
      notifyListeners();
    }
  }

  // ---- 曲全体 -----------------------------------------------------------------

  void newSong() {
    engine.stopPlayback();
    engine.newProject();
    selectedPlacementId = null;
    _refresh(force: true);
    saveNow(force: true); // 前の曲のファイルを上書きしておく
  }

  /// 確かめ用のデモ曲（4トラック・2小節を2回）。Undo 1回で消せる
  void loadDemo() {
    engine.stopPlayback();
    engine.newProject();
    buildDemoSong(engine);
    selectedPlacementId = null;
    _refresh(force: true);
    saveNow(force: true);
  }

  bool setTempo(double bpm) => _edit(() => engine.setTempo(bpm));

  void undo() => _edit(engine.undo);
  void redo() => _edit(engine.redo);

  // ---- トラックとクリップ -------------------------------------------------------

  bool get canAddTrack => project.tracks.length < 8;

  void addTrack() {
    if (!canAddTrack) return;
    final n = project.tracks.length;
    _edit(() => engine.addTrack('Track ${n + 1}', trackColors[n % trackColors.length]));
  }

  void select(int? placementId) {
    if (selectedPlacementId == placementId) return;
    selectedPlacementId = placementId;
    notifyListeners();
  }

  /// 空いているマスに1小節のクリップを置いて選ぶ
  void createClipAt(int trackId, int bar) {
    final (clip, placement) = _edit(() => engine.createClip(trackId, bar));
    if (clip != 0) select(placement);
  }

  /// 選んでいるクリップを、すぐ下の空いている所へ複製する
  void duplicateSelected() {
    final pl = selected;
    if (pl == null) return;
    final bar = nextFreeBar(project, pl.trackId, pl.endBar, pl.lengthBars);
    final id = _edit(() => engine.placeClip(pl.clipId, bar));
    if (id != 0) select(id);
  }

  /// 上下に動かす。ほかのクリップと重なるなら動かない（false）
  bool moveSelected(int deltaBars) {
    final pl = selected;
    if (pl == null || pl.startBar + deltaBars < 0) return false;
    return _edit(() => engine.movePlacement(pl.id, pl.startBar + deltaBars));
  }

  /// 配置を指定の小節へ動かす。ぶつかるなら false
  bool movePlacementTo(int placementId, int startBar) {
    if (startBar < 0) return false;
    return _edit(() => engine.movePlacement(placementId, startBar));
  }

  /// クリップの複製を指定の小節に置いて選ぶ。ぶつかるなら false
  bool duplicateTo(int clipId, int startBar) {
    if (startBar < 0) return false;
    final id = _edit(() => engine.placeClip(clipId, startBar));
    if (id == 0) return false;
    select(id);
    return true;
  }

  /// 選んでいるクリップを1小節伸ばす・縮める（複製も一緒に）。ぶつかる・1小節より短くなるなら false
  bool resizeSelected(int deltaBars) {
    final pl = selected;
    if (pl == null) return false;
    return resizeClip(pl.clipId, pl.lengthBars + deltaBars);
  }

  bool resizeClip(int clipId, int lengthBars) {
    if (lengthBars < 1) return false;
    return _edit(() => engine.setClipLength(clipId, lengthBars));
  }

  void deleteSelected() {
    final pl = selected;
    if (pl == null) return;
    _edit(() => engine.removePlacement(pl.id));
    selectedPlacementId = null;
    notifyListeners();
  }

  // ---- ノート（縦ピアノロールから） ---------------------------------------------

  ClipData? clip(int clipId) => project.clip(clipId);

  /// 置けたらノートの ID、置けなければ 0
  int addNote(int clipId, {required int tick, required int length, required int pitch, double velocity = 0.8}) =>
      _edit(() => engine.addNote(clipId, tick: tick, length: length, pitch: pitch, velocity: velocity));

  bool moveNotes(int clipId, List<int> ids, {int deltaTicks = 0, int deltaPitch = 0}) =>
      _edit(() => engine.moveNotes(clipId, ids, deltaTicks: deltaTicks, deltaPitch: deltaPitch));

  bool resizeNotes(int clipId, List<int> ids, int deltaTicks) =>
      _edit(() => engine.resizeNotes(clipId, ids, deltaTicks));

  bool deleteNotes(int clipId, List<int> ids) => _edit(() => engine.deleteNotes(clipId, ids));

  /// ノートの頭を動かす（終わりはそのまま）。移動と長さ変更を1つの Undo にまとめる
  bool trimNotesStart(int clipId, List<int> ids, int deltaTicks) {
    if (deltaTicks == 0) return false;
    return _edit(() => engine.editGroup(() =>
        engine.moveNotes(clipId, ids, deltaTicks: deltaTicks) && engine.resizeNotes(clipId, ids, -deltaTicks)));
  }

  /// 試聴鍵盤とノートを置いたときの音を、そのトラックの音色にする
  void previewTrack(int trackId) => engine.previewTrack(trackId);

  /// ノートを置いた・動かしたときに短く鳴らす
  void audition(int pitch, {double velocity = 0.8}) {
    engine.noteOn(pitch, velocity);
    Timer(const Duration(milliseconds: 180), () => engine.noteOff(pitch));
  }

  // ---- 再生 -----------------------------------------------------------------

  /// アレンジ画面の再生：曲全体をループ
  void togglePlay() {
    if (engine.isPlaying) {
      engine.stopPlayback();
    } else {
      engine.clearLoop();
      engine.play();
    }
  }

  /// ピアノロールの再生：そのクリップの範囲だけを繰り返す（他のトラックも一緒に鳴る）
  void playLoop(int startTick, int endTick) {
    engine.setLoop(startTick, endTick);
    engine.play();
  }

  /// 範囲ループをやめて曲全体に戻す（止まっていれば曲頭へ）
  void clearLoop() => engine.clearLoop();

  void rewind() {
    engine.seek(0);
  }

  @override
  void dispose() {
    saveNow();
    super.dispose();
  }
}
