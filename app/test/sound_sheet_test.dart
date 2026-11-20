import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/kits/kit_store.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/sound/sound_sheet.dart';
import 'package:mobiledaw/ui/theme.dart';

// Phase 3.5（サウンドシート再編）の検証：フェイクの SoundSheetActions で
// シートの中身（SoundSheetContent）を pump し、
//  - エフェクト チェーンが折りたたみ無しで常時見える（スクロール操作なし）
//  - 音色画面に ExpansionTile が存在しない
//  - 詳細ページがセグメントで切り替わり、各ページに主要ノブが出る
// ことを見る。エンジン（FFI）は使わない。
class _FakeActions implements SoundSheetActions {
  _FakeActions(this.project, this.kits);

  @override
  final ProjectData project;
  @override
  final KitStore kits;

  final ChangeNotifier _changes = ChangeNotifier();
  final List<int> addedUnitTypes = [];
  final Map<String, double> soundWrites = {};

  @override
  Listenable get changes => _changes;
  @override
  bool get canUndo => false;
  @override
  bool get canRedo => false;
  @override
  void undo() {}
  @override
  void redo() {}
  @override
  void beginGesture() {}
  @override
  void endGesture() {}
  @override
  bool setSound(int trackId, int paramId, double value) {
    soundWrites['$trackId/$paramId'] = value;
    return true;
  }

  @override
  void setSounds(int trackId, Map<int, double> values) {}
  @override
  void previewTrack(int trackId) {}
  @override
  void auditionChord(List<int> notes) {}
  @override
  void auditionSequence(List<List<int>> chords, {Duration each = const Duration(milliseconds: 600)}) {}
  @override
  void audition(int pitch, {double velocity = 0.8}) {}
  @override
  bool setTrackKit(int trackId, String kitId) => true;
  @override
  bool setTrackSampler(int trackId, String kitId, String soundName, int rootNote, double gain, double start) => true;
  @override
  bool setTrackSamplerParam(int trackId, int paramId, double value) => true;
  @override
  bool addFxUnit(int trackId, int unitType) {
    addedUnitTypes.add(unitType);
    return true;
  }

  @override
  bool removeFxUnit(int trackId, int unitIndex) => true;
  @override
  bool moveFxUnit(int trackId, int fromIndex, int toIndex) => true;
  @override
  bool setFxUnitEnabled(int trackId, int unitIndex, bool enabled) => true;
  @override
  bool setFxUnitParam(int trackId, int unitIndex, int paramId, double value) => true;
}

String _projectJson(List<String> tracks) => '''
{
  "format": "mobiledaw-project", "version": 1, "tempo": 120.0,
  "timeSig": [4, 4], "key": {"root": 0, "scale": "major"},
  "tracks": [${tracks.join(',')}],
  "clips": [], "placements": []
}
''';

const _analogTrack = '''
{
  "id": "0000000000000001", "name": "Pad", "color": "ffc8f25a",
  "instrument": {"type": "synth", "params": {}},
  "fx": {},
  "fxChain": [
    {"type": "granular", "enabled": true, "params": {"granular": 0.6}},
    {"type": "reverb", "enabled": true, "params": {"reverb": 0.4}}
  ],
  "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
}
''';

const _wavetableTrack = '''
{
  "id": "0000000000000002", "name": "Lead", "color": "ff35c4b5",
  "instrument": {"type": "synth", "params": {"wtTable": 1.0}},
  "fx": {},
  "fxChain": [
    {"type": "delay", "enabled": true, "params": {"delay": 0.3}}
  ],
  "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
}
''';

const _samplerTrack = '''
{
  "id": "0000000000000003", "name": "Cloud", "color": "ff7fb2f0",
  "instrument": {
    "type": "sampler",
    "sampler": {
      "kit": "bounce-demo", "sound": "Phrase", "rootNote": 60, "gain": 1.0, "start": 0.0,
      "granular": {"enabled": 1.0, "sizeMs": 300.0, "density": 55.0}
    },
    "params": {}
  },
  "fx": {},
  "fxChain": [
    {"type": "shimmer", "enabled": true, "params": {"shimmer": 0.5}}
  ],
  "mixer": {"gain": 0.8, "pan": 0, "mute": false, "solo": false}
}
''';

Widget _harness(_FakeActions actions, TrackData track, {Widget? granularizeSection}) {
  return MaterialApp(
    theme: buildDawTheme(),
    home: Scaffold(
      body: SoundSheetContent(
        actions: actions,
        track: track,
        onBrowseKit: () {},
        onOpenMixer: () {},
        granularizeSection: granularizeSection,
      ),
    ),
  );
}

_FakeActions _actionsFor(String trackJson, {String? filesDir}) {
  final project = ProjectData.fromJson(jsonDecode(_projectJson([trackJson])) as Map<String, Object?>);
  return _FakeActions(project, KitStore(filesDir ?? Directory.systemTemp.path));
}

void main() {
  testWidgets('アナログ：チェーンがスクロールなしで見え、折りたたみが無い', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final actions = _actionsFor(_analogTrack);
    final track = actions.project.tracks.single;
    await tester.pumpWidget(_harness(actions, track));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 折りたたみは音色画面に存在しない
    expect(find.byType(ExpansionTile), findsNothing);
    // チェーン見出し・ユニットカード・追加導線が（スクロール操作なしで）画面内にある
    for (final label in ['エフェクト チェーン', 'グラニュラー', 'リバーブ', 'ユニットを追加']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: label);
      final rect = tester.getRect(finder);
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(2600), reason: label);
    }
    // 並び順：チェーン → 大きいつまみ → 詳細ページ
    final chainY = tester.getTopLeft(find.text('エフェクト チェーン')).dy;
    final macroY = tester.getTopLeft(find.text('大きいつまみ')).dy;
    final detailY = tester.getTopLeft(find.text('DETAIL')).dy;
    expect(chainY, lessThan(macroY));
    expect(macroY, lessThan(detailY));
    // パンプ・センドも常時表示（旧「詳しく：パンプ・センド」の置き換え）
    expect(find.text('パンプ・センド'), findsOneWidget);
  });

  testWidgets('アナログ：詳細ページがセグメントで切り替わる', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final actions = _actionsFor(_analogTrack);
    final track = actions.project.tracks.single;
    await tester.pumpWidget(_harness(actions, track));
    await tester.pump();

    // 初期ページは「音源」：オシレーター系ノブと FM 節が見える
    expect(find.text('オシレーター'), findsOneWidget);
    expect(find.text('FM・フォルマント'), findsOneWidget);

    await tester.tap(find.text('フィルター'));
    await tester.pump();
    expect(find.text('キートラック'), findsOneWidget);

    await tester.tap(find.text('エンベロープ'));
    await tester.pump();
    expect(find.text('音色の音量'), findsOneWidget);

    await tester.tap(find.text('LFO'));
    await tester.pump();
    expect(find.text('明るさへ'), findsOneWidget);
    expect(find.text('正弦'), findsOneWidget);

    await tester.tap(find.text('演奏'));
    await tester.pump();
    expect(find.text('グライド'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('ウェーブテーブル：主面とチェーンと詳細ページが出る', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final actions = _actionsFor(_wavetableTrack);
    final track = actions.project.tracks.single;
    await tester.pumpWidget(_harness(actions, track));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('WAVETABLE'), findsOneWidget);
    expect(find.text('エフェクト チェーン'), findsOneWidget);
    expect(find.text('ディレイ'), findsOneWidget);
    // 音源ページ（初期）：ユニゾン系ノブ＋FM 節
    expect(find.text('ブレンド'), findsOneWidget);
    expect(find.text('FM・フォルマント'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('サンプラー：波形とグラニュラー節とチェーンが常時表示', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 素材キットを端末内にある体にする（kit.json だけ用意。波形は読めなければ見本になる）
    // ※ testWidgets 内では非同期 IO が進まないため同期 IO で用意する
    final dir = Directory.systemTemp.createTempSync('mdaw_sound_sheet_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final kitDir = Directory('${dir.path}/kits/bounce-demo');
    kitDir.createSync(recursive: true);
    File('${kitDir.path}/kit.json').writeAsStringSync(jsonEncode({
      'name': 'バウンス素材',
      'version': 1,
      'sounds': [
        {'name': 'Phrase', 'file': 'phrase.wav', 'note': 60, 'gain': 1.0},
      ],
    }));
    final actions = _actionsFor(_samplerTrack, filesDir: dir.path);
    final track = actions.project.tracks.single;
    await tester.pumpWidget(_harness(actions, track));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('SAMPLER'), findsOneWidget);
    expect(find.text('グラニュラー（素材全体を粒で鳴らす）'), findsOneWidget);
    expect(find.text('読み位置の動き'), findsOneWidget);
    expect(find.text('全体を這う'), findsOneWidget);
    // Phase 2.6: 往復（ピンポン）モードとプリセットが主面に出る
    expect(find.text('往復（ピンポン）'), findsOneWidget);
    expect(find.text('アンビエント・クラウド'), findsOneWidget);
    expect(find.text('フローズン・ドローン'), findsOneWidget);
    expect(find.text('霧（粒の輪郭と溶け具合）'), findsOneWidget);
    expect(find.text('広がり（位置の散らばり）'), findsOneWidget);
    // 細かいパラメータは「細かく調整」を開くまで出ない
    expect(find.text('読み位置（素材全体の割合）'), findsNothing);
    expect(find.text('細かく調整'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1)); // グラニュラー節の2つ目のスイッチ＝細かく調整
    await tester.pump();
    expect(find.text('読み位置（素材全体の割合）'), findsOneWidget);
    expect(find.text('フリーズ（読み位置を凍らせる）'), findsOneWidget);
    expect(find.text('エフェクト チェーン'), findsOneWidget);
    expect(find.text('シマーリバーブ'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('グラニュラー化節はサンプラー以外でのみ末尾に出る（Phase 2.6）', (tester) async {
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const marker = Text('グラニュラー化マーカー');
    final analogActions = _actionsFor(_analogTrack);
    await tester.pumpWidget(_harness(analogActions, analogActions.project.tracks.single, granularizeSection: marker));
    await tester.pump();
    expect(find.text('グラニュラー化マーカー'), findsOneWidget);

    final samplerActions = _actionsFor(_samplerTrack);
    await tester.pumpWidget(_harness(samplerActions, samplerActions.project.tracks.single, granularizeSection: marker));
    await tester.pump();
    expect(find.text('グラニュラー化マーカー'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
