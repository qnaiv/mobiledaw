import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/mdaw_ffi.dart';
import '../model/project.dart';
import '../piano_roll/automation_params.dart';
import '../music/voicing.dart';
import '../kits/kit_store.dart';
import '../project/library.dart';
import 'demo_song.dart';
import 'timeline_math.dart';
import 'wake_lock.dart';

/// 画面とコアのあいだ。編集はコアに頼み、変わったら読み直して画面に知らせる。
/// 編集後 2 秒操作がなければ自動で保存する（バックグラウンドに回るときは [saveNow]）。
class SongController extends ChangeNotifier {
  SongController(this.engine,
      {required this.library, required this.kits, required String projectPath, WakeLock? wakeLock})
      : _projectPath = projectPath,
        project = engine.project {
    _version = engine.projectVersion;
    _playbackWake = PlaybackWakeLock(lock: wakeLock ?? const WakelockPlusWakeLock(), isPlaying: () => engine.isPlaying);
  }

  static const autosaveDelay = Duration(seconds: 2);

  /// 新しいトラックの色（画面案の4色から順に）
  static const trackColors = [0xFFF28C38, 0xFF5AA9F2, 0xFFC8F25A, 0xFFE879C6, 0xFF9A7CF2, 0xFF5AD6C0];

  final MdawEngine engine;
  final ProjectLibrary library;
  final KitStore kits;
  String _projectPath;

  /// 再生中は画面を眠らせない（自然終了でも外れるよう見張り付き）
  late final PlaybackWakeLock _playbackWake;

  /// 開いている曲の project.json
  String get projectPath => _projectPath;
  String? get projectId => library.idOf(_projectPath);

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
    } else {
      engine.newProject();
    }
    library.lastOpened = projectId;
    _startTick = 0;
    _refresh(force: true);
  }

  // ---- 曲の一覧・保存 ------------------------------------------------------------

  /// 一覧の別の曲に切り替える（今の曲は保存してから）
  void openProject(String id) {
    if (id == projectId) return;
    saveNow();
    engine.stopPlayback();
    _playbackWake.stopped();
    engine.clearLoop();
    _projectPath = library.pathFor(id);
    selectedPlacementId = null;
    open();
  }

  /// 新しい曲を一覧に作って開く
  void newSong({String title = '無題の曲'}) {
    saveNow();
    engine.stopPlayback();
    _playbackWake.stopped();
    engine.clearLoop();
    _projectPath = library.pathFor(library.newId());
    engine.newProject();
    _startFresh(title);
  }

  /// 名前をつけて、今の中身を新しい曲として保存し、そちらを開く（元の曲は最後に保存した状態で残る）
  void saveAs(String title) {
    saveNow();
    _projectPath = library.pathFor(library.newId());
    engine.setProjectTitle(title.trim());
    library.lastOpened = projectId;
    _refresh(force: true);
    saveNow(force: true);
  }

  /// 開いている曲の名前を変える（Undo できる）
  bool renameSong(String title) => _edit(() => engine.setProjectTitle(title.trim()));

  /// 新しく作った曲を、名前だけ入れて保存し、読み直す（Undo の履歴を空にするため）
  void _startFresh(String title) {
    engine.setProjectTitle(title);
    try {
      File(projectPath).parent.createSync(recursive: true);
      engine.saveProject(projectPath);
      engine.loadProject(projectPath);
      saveError = null;
    } on Object catch (e) {
      saveError = '保存できませんでした：$e';
    }
    selectedPlacementId = null;
    library.lastOpened = projectId;
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

  bool renameTrack(int trackId, String name) => _edit(() => engine.renameTrack(trackId, name.trim()));

  // ---- ミキサー・音色 ----------------------------------------------------------

  bool _gesture = false;

  /// スライダーを触り始めた。離すまでの変更を1つの Undo にまとめる
  void beginGesture() {
    if (_gesture) return;
    _gesture = true;
    engine.beginEditGroup();
  }

  void endGesture() {
    if (!_gesture) return;
    _gesture = false;
    engine.endEditGroup();
    _refresh(force: true); // Undo ボタンの状態を更新
  }

  /// トラックの音源をドラムキットにする（空ならシンセに戻す）。Undo できる
  bool setTrackKit(int trackId, String kitId) => _edit(() => engine.setTrackKit(trackId, kitId));

  /// トラックの楽器をサンプラーにする（kitId が空ならサンプラーをやめる）。Undo できる。
  /// 引数はトラックの現在値から組み立てて渡す（設定一式の差し替えのため）
  bool setTrackSampler(int trackId, String kitId, String soundName, int rootNote, double gain, double start) =>
      _edit(() => engine.setTrackSampler(trackId, kitId, soundName, rootNote, gain, start));

  /// キットをダウンロード・削除したあと：コアに読み直してもらい、画面も描き直す
  void kitsChanged() {
    engine.reloadKits();
    notifyListeners();
  }

  /// 音色・エフェクトの値を1つ変える（MdawParam の ID）
  bool setSound(int trackId, int paramId, double value) =>
      _edit(() => engine.setTrackParam(trackId, paramId, value));

  /// 音色・エフェクトをまとめて変える（プリセット・大きいつまみ）。1つの Undo
  void setSounds(int trackId, Map<int, double> values) {
    if (values.isEmpty) return;
    _edit(() => engine.editGroup(() {
          for (final e in values.entries) {
            engine.setTrackParam(trackId, e.key, e.value);
          }
        }));
  }

  /// クリップのオートメーション：[paramId] のレーンを丸ごと差し替える（Undo できる）。
  /// [points] は (tick, 値) の組。空ならレーンを消す
  bool setClipAutomation(int clipId, int paramId, List<(int, double)> points) =>
      _edit(() => engine.setClipAutomation(clipId, paramId, points));

  // ---- オートメーションのコピペ（アレンジ画面の選択バーから） ---------------------

  List<AutomationLaneData>? _automationClipboard;

  /// コピーしたオートメーションがあるか（貼り付けボタンの有効・無効に使う）
  bool get hasAutomationClipboard => _automationClipboard?.isNotEmpty ?? false;

  /// クリップのレーン一式を覚える（コピー）。レーンが無ければ false
  bool copyAutomation(int clipId) {
    final clip = project.clip(clipId);
    if (clip == null || clip.automation.isEmpty) return false;
    _automationClipboard = copyAutomationLanes(clip);
    notifyListeners(); // 貼り付けボタンが押せるようになる
    return true;
  }

  /// 覚えたレーン一式をクリップへ貼る。対象のレーンは丸ごと差し替えで、1つの Undo。
  /// クリップの長さが違う場合の切り詰め等はコア側の正規化に任せる
  bool pasteAutomation(int clipId) {
    final clipboard = _automationClipboard;
    final clip = project.clip(clipId);
    if (clipboard == null || clipboard.isEmpty || clip == null) return false;
    return _applyAutomationPlan(clipId, automationPastePlan(current: clip.automation, clipboard: clipboard));
  }

  /// クリップのレーンを全部消す（1つの Undo）
  bool clearAutomation(int clipId) {
    final clip = project.clip(clipId);
    if (clip == null || clip.automation.isEmpty) return false;
    return _applyAutomationPlan(clipId, automationClearPlan(clip.automation));
  }

  bool _applyAutomationPlan(int clipId, AutomationPlan plan) {
    if (plan.isEmpty) return false;
    return _edit(() => engine.editGroup(() {
          var ok = true;
          for (final (paramId, points) in plan) {
            ok = engine.setClipAutomation(clipId, paramId, points) && ok;
          }
          return ok;
        }));
  }

  /// 指定したものだけ変える（他は今の値のまま）
  bool setMixer(int trackId, {double? gain, double? pan, bool? mute, bool? solo}) {
    final t = project.track(trackId);
    if (t == null) return false;
    final m = t.mixer;
    return _edit(() => engine.setTrackMixer(trackId,
        gain: gain ?? m.gain, pan: pan ?? m.pan, mute: mute ?? m.mute, solo: solo ?? m.solo));
  }

  /// デモ曲を開く。取り込み先はデモごとに固定の ID なので、開くたびに一覧へ増えない。
  /// 既に取り込んであれば（編集してあっても）それを開き、無ければ同梱 JSON を書き出して開く
  Future<void> loadDemo(DemoSong demo) async {
    saveNow();
    engine.stopPlayback();
    _playbackWake.stopped();
    engine.clearLoop();
    final id = demoProjectId(demo);
    final path = library.pathFor(id);
    try {
      final existed = library.createIfMissing(id, await rootBundle.loadString(demoAsset(demo)));
      engine.loadProject(path);
      _projectPath = path;
      if (!existed) {
        if (engine.setProjectTitle(demoTitle(demo))) saveNow(force: true);
        engine.loadProject(path); // 履歴を空に
      }
    } on Object catch (e) {
      saveError = 'デモ曲を読めませんでした：$e';
    }
    selectedPlacementId = null;
    library.lastOpened = projectId;
    _refresh(force: true);
  }

  bool setTempo(double bpm) => _edit(() => engine.setTempo(bpm));

  /// 曲のキーとスケールを変える（Undo できる）
  bool setKey(int root, String scale) => _edit(() => engine.setKey(root, scale));

  void undo() => _edit(engine.undo);
  void redo() => _edit(engine.redo);

  // ---- トラックとクリップ -------------------------------------------------------

  // 上限はコアの Project::kMaxTracks と合わせる
  bool get canAddTrack => project.tracks.length < 32;

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

  /// コードの音をまとめて置く（1つの Undo）。置けたノートの ID を返す
  List<int> addChord(int clipId, {required int tick, required int length, required List<int> pitches}) {
    return _edit(() => engine.editGroup(() => [
          for (final p in pitches) engine.addNote(clipId, tick: tick, length: length, pitch: p),
        ].where((id) => id != 0).toList()));
  }

  /// 選んだノートを消して、[notes] を置き直す（1つの Undo）。置いたノートの ID を返す
  List<int> replaceNotes(int clipId, List<int> deleteIds, List<NoteSpec> notes) {
    final clip = project.clip(clipId);
    if (clip == null) return const [];
    return _edit(() => engine.editGroup(() {
          if (deleteIds.isNotEmpty) engine.deleteNotes(clipId, deleteIds);
          return [
            for (final n in notes)
              if (n.tick >= 0 && n.tick < clip.lengthTicks && n.pitch >= 0 && n.pitch <= 127)
                engine.addNote(clipId,
                    tick: n.tick, length: n.length.clamp(1, clip.lengthTicks - n.tick), pitch: n.pitch, velocity: n.velocity),
          ].where((id) => id != 0).toList();
        }));
  }

  /// コード進行を [startTick] から [lengthTicks] の間に入れる（1つの Undo）。足りなければクリップを伸ばす
  /// （最大64小節）。[replace] なら入れる範囲にあるノートを先に消す。[notes] の tick はクリップの頭から
  List<int> insertProgression(int clipId, List<NoteSpec> notes,
      {required int lengthTicks, required bool replace, int startTick = 0}) {
    final clip = project.clip(clipId);
    if (clip == null) return const [];
    final tpb = project.ticksPerBar;
    final end = startTick + lengthTicks;
    final neededBars = math.min((end + tpb - 1) ~/ tpb, 64);
    final currentBars = (clip.lengthTicks + tpb - 1) ~/ tpb;
    return _edit(() => engine.editGroup(() {
          if (neededBars > currentBars) engine.setClipLength(clipId, neededBars);
          if (replace) {
            final ids = [for (final n in clip.notes) if (n.tick >= startTick && n.tick < end) n.id];
            if (ids.isNotEmpty) engine.deleteNotes(clipId, ids);
          }
          final maxLen = math.max(clip.lengthTicks, neededBars * tpb);
          return [
            for (final n in notes)
              if (n.tick < maxLen)
                engine.addNote(clipId,
                    tick: n.tick, length: n.length.clamp(1, maxLen - n.tick), pitch: n.pitch, velocity: n.velocity),
          ].where((id) => id != 0).toList();
        }));
  }

  /// 試聴：コードを順に鳴らす（[each] ごとに次のコード）
  void auditionSequence(List<List<int>> chords, {Duration each = const Duration(milliseconds: 600)}) {
    for (var i = 0; i < chords.length; i++) {
      Timer(each * i, () => auditionChord(chords[i]));
    }
  }

  /// コードを短く鳴らす
  void auditionChord(List<int> pitches) {
    for (final p in pitches) {
      engine.noteOn(p, 0.7);
    }
    Timer(const Duration(milliseconds: 450), () {
      for (final p in pitches) {
        engine.noteOff(p);
      }
    });
  }

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

  int _startTick = 0;

  /// 再生を始める位置（tick）。アレンジ画面の小節番号をタップで変える
  int get startTick => _startTick;

  /// [bar] 小節目の頭から再生するようにする。再生中ならすぐそこへ飛ぶ
  void setStartBar(int bar) {
    final last = math.max(project.lengthBars, 1) - 1;
    _startTick = bar.clamp(0, last) * project.ticksPerBar;
    engine.seek(_startTick);
    notifyListeners();
  }

  /// アレンジ画面の再生：曲全体をループ。始まりと止めたあとは [startTick]
  void togglePlay() {
    if (engine.isPlaying) {
      engine.stopPlayback();
      _playbackWake.stopped();
      engine.seek(_startTick); // 止めたら再生を始めた位置に戻る
    } else {
      engine.clearLoop();
      engine.seek(_startTick);
      engine.play();
      _playbackWake.started();
    }
  }

  /// ピアノロールの再生：そのクリップの範囲だけを繰り返す（他のトラックも一緒に鳴る）。
  /// [from] を渡すとそこから始める（2周目からは範囲の頭から）
  void playLoop(int startTick, int endTick, {int? from}) {
    engine.setLoop(startTick, endTick);
    if (from != null) engine.seek(from);
    engine.play();
    _playbackWake.started();
  }

  /// 範囲ループをやめて曲全体に戻す（止まっていれば曲頭へ）
  void clearLoop() => engine.clearLoop();

  /// 先頭へ：再生を始める位置も曲の頭に戻す
  void rewind() {
    _startTick = 0;
    engine.seek(0);
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackWake.dispose();
    saveNow();
    super.dispose();
  }
}
