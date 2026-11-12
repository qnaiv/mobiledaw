import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';
import 'package:mobiledaw/showcase/showcase_notes.dart';

// 4/4・ticksPerBar = 3840 のプロジェクトを組み立てる
TrackData _track(int id, {bool kit = false, bool mute = false, bool solo = false}) => TrackData(
      id: id,
      name: 'T$id',
      color: 0,
      synth: const {},
      kitId: kit ? 'future-bass-pro' : '',
      mixer: MixerData(mute: mute, solo: solo),
    );

NoteData _note(int id, int tick, int length, int pitch) =>
    NoteData(id: id, tick: tick, length: length, pitch: pitch, velocity: 0.8);

ClipData _clip(int id, int trackId, int lengthTicks, List<NoteData> notes) =>
    ClipData(id: id, trackId: trackId, lengthTicks: lengthTicks, notes: notes);

PlacementData _pl(int id, int clipId, int trackId, int startBar, [int lengthBars = 1]) =>
    PlacementData(id: id, clipId: clipId, trackId: trackId, startBar: startBar, lengthBars: lengthBars);

ProjectData _project({required List<TrackData> tracks, required List<ClipData> clips, required List<PlacementData> placements}) =>
    ProjectData(
      tempo: 120,
      timeSigNumerator: 4,
      timeSigDenominator: 4,
      keyRoot: 0,
      scale: 'minor',
      tracks: tracks,
      clips: clips,
      placements: placements,
    );

void main() {
  group('flatten', () {
    test('クリップは配置の中で繰り返され、絶対 tick になる', () {
      final p = _project(
        tracks: [_track(1)],
        clips: [
          _clip(10, 1, 1920, [_note(1, 0, 480, 60), _note(2, 960, 960, 64)]),
        ],
        placements: [_pl(100, 10, 1, 0)],
      );
      final r = flattenShowcaseNotes(p);
      expect(r.notes.map((n) => (n.startTick, n.endTick, n.pitch)).toList(), [
        (0, 480, 60),
        (960, 1920, 64),
        (1920, 2400, 60), // 2回目の繰り返し
        (2880, 3840, 64),
      ]);
      expect(r.totalTicks, 3840);
      expect(r.maxLengthTicks, 960);
    });

    test('繰り返しの置かれた先でも、同じクリップが別々の小節に展開される', () {
      final p = _project(
        tracks: [_track(1)],
        clips: [_clip(10, 1, 3840, [_note(1, 0, 480, 60)])],
        placements: [_pl(100, 10, 1, 0), _pl(101, 10, 1, 2)],
      );
      final r = flattenShowcaseNotes(p);
      expect(r.notes.map((n) => n.startTick).toList(), [0, 7680]);
      expect(r.totalTicks, 3 * 3840);
    });

    test('ノートはクリップの繰り返し境界で切れる', () {
      final p = _project(
        tracks: [_track(1)],
        clips: [_clip(10, 1, 3840, [_note(1, 3000, 2000, 50)])], // 3000+2000 はクリップ末尾を超える
        placements: [_pl(100, 10, 1, 1)],
      );
      final r = flattenShowcaseNotes(p);
      expect(r.notes.single.startTick, 3840 + 3000);
      expect(r.notes.single.endTick, 3840 + 3840);
    });

    test('ノートは配置の終わりでも切れる', () {
      final p = _project(
        tracks: [_track(1)],
        clips: [_clip(10, 1, 7680, [_note(1, 3000, 2000, 50)])], // 2小節クリップを1小節だけ置く
        placements: [_pl(100, 10, 1, 0, 1)],
      );
      final r = flattenShowcaseNotes(p);
      expect(r.notes.single.startTick, 3000);
      expect(r.notes.single.endTick, 3840);
    });

    test('トラック指定ではそのトラックだけ、ドラムには drum 印が付く', () {
      final p = _project(
        tracks: [_track(1), _track(2, kit: true)],
        clips: [
          _clip(10, 1, 3840, [_note(1, 0, 480, 60)]),
          _clip(11, 2, 3840, [_note(2, 0, 120, 36), _note(3, 960, 120, 38)]),
        ],
        placements: [_pl(100, 10, 1, 0), _pl(101, 11, 2, 0)],
      );
      final all = flattenShowcaseNotes(p);
      expect(all.notes.where((n) => n.drum).length, 2);
      expect(all.notes.firstWhere((n) => n.drum).trackIndex, 1);
      final drumsOnly = flattenShowcaseNotes(p, trackId: 2);
      expect(drumsOnly.notes.length, 2);
      expect(drumsOnly.notes.every((n) => n.trackId == 2 && n.drum), isTrue);
    });

    test('ミュートしたトラックは流れず、ソロがあるときはソロだけが流れる', () {
      final clips = [
        _clip(10, 1, 3840, [_note(1, 0, 480, 60)]),
        _clip(11, 2, 3840, [_note(2, 0, 480, 62)]),
      ];
      final placements = [_pl(100, 10, 1, 0), _pl(101, 11, 2, 0)];
      final muted = _project(tracks: [_track(1), _track(2, mute: true)], clips: clips, placements: placements);
      expect(flattenShowcaseNotes(muted).notes.map((n) => n.trackId).toList(), [1]);
      final soloed = _project(tracks: [_track(1), _track(2, solo: true)], clips: clips, placements: placements);
      expect(flattenShowcaseNotes(soloed).notes.map((n) => n.trackId).toList(), [2]);
    });

    test('配置が無い曲は totalTicks が1小節、ノートは空', () {
      final p = _project(tracks: [_track(1)], clips: const [], placements: const []);
      final r = flattenShowcaseNotes(p);
      expect(r.notes, isEmpty);
      expect(r.totalTicks, 3840);
      expect((r.minPitch, r.maxPitch), (48, 71));
    });
  });

  group('pitch range', () {
    RainNote rn(int pitch) => RainNote(startTick: 0, endTick: 480, pitch: pitch, trackIndex: 0, trackId: 1, drum: false, velocity: 0.8);

    test('前後2半音のパディングが付く', () {
      expect(showcasePitchRange([rn(40), rn(90)]), (38, 92));
    });

    test('幅が1オクターブ未満なら中央を保って広げる', () {
      // 実音域 60〜64 → パディング後 58〜66（幅8）→ 中央62で 57〜68（幅11）
      expect(showcasePitchRange([rn(60), rn(64)]), (57, 68));
    });

    test('高い音でも 127 を超えない', () {
      expect(showcasePitchRange([rn(120), rn(127)]), (116, 127));
    });

    test('低い音でも 0 を下回らない', () {
      expect(showcasePitchRange([rn(0), rn(5)]), (0, 11));
    });

    test('空ならデフォルト音域', () {
      expect(showcasePitchRange(const []), (48, 71));
    });
  });

  group('window', () {
    RainNote rn(int start, int end) =>
        RainNote(startTick: start, endTick: end, pitch: 60, trackIndex: 0, trackId: 1, drum: false, velocity: 0.8);
    final notes = [rn(0, 3840), rn(1000, 1200), rn(5000, 5200)];
    const maxLen = 3840;

    test('ウィンドウ手前から伸びる長いノートも拾う', () {
      expect(showcaseWindow(notes, maxLen, 2000, 3000).map((n) => n.startTick).toList(), [0]);
    });

    test('境界は [from, to) ：to ちょうどに始まるノートは含めない', () {
      expect(showcaseWindow(notes, maxLen, 0, 1000).map((n) => n.startTick).toList(), [0]);
    });

    test('from ちょうどに終わるノートは含めない', () {
      expect(showcaseWindow(notes, maxLen, 1200, 5000).map((n) => n.startTick).toList(), [0]);
    });

    test('空の入力・逆転した範囲は空', () {
      expect(showcaseWindow(const [], maxLen, 0, 1000), isEmpty);
      expect(showcaseWindow(notes, maxLen, 3000, 3000), isEmpty);
    });
  });

  group('clock', () {
    test('tick から秒と m:ss 表示', () {
      expect(showcaseTickToSeconds(960, 120), 0.5);
      expect(showcaseClock(3840, 120), '0:02');
      expect(showcaseClock(3840 * 30, 120), '1:00');
      expect(showcaseClock(0, 120), '0:00');
    });
  });
}
