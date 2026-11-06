import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/arrange/timeline_math.dart';
import 'package:mobiledaw/model/project.dart';

ProjectData _project({required List<PlacementData> placements, List<ClipData> clips = const []}) => ProjectData(
      tempo: 120,
      timeSigNumerator: 4,
      timeSigDenominator: 4,
      keyRoot: 0,
      scale: 'minor',
      tracks: const [
        TrackData(id: 1, name: 'A', color: 0, synth: {}, mixer: MixerData()),
        TrackData(id: 2, name: 'B', color: 0, synth: {}, mixer: MixerData()),
      ],
      clips: clips,
      placements: placements,
    );

PlacementData _pl(int id, int clip, int track, int start, [int len = 1]) =>
    PlacementData(id: id, clipId: clip, trackId: track, startBar: start, lengthBars: len);

void main() {
  test('position shows bar.beat.sixteenth from 1', () {
    expect(formatPosition(0, 3840), '1.1.1');
    expect(formatPosition(960, 3840), '1.2.1');
    expect(formatPosition(240, 3840), '1.1.2');
    expect(formatPosition(3840 * 4 + 960 * 3 + 720, 3840), '5.4.4');
    expect(formatPosition(-5, 3840), '1.1.1');
  });

  test('clips are lettered from the top, then left to right', () {
    final p = _project(placements: [
      _pl(10, 300, 2, 0),
      _pl(11, 100, 1, 0),
      _pl(12, 200, 1, 2),
      _pl(13, 100, 1, 4), // 複製は同じ名前
    ]);
    final labels = clipLabels(p);
    expect(labels[100], 'A');
    expect(labels[300], 'B');
    expect(labels[200], 'C');
  });

  test('next free bar skips over clips on the same track', () {
    final p = _project(placements: [_pl(1, 1, 1, 0, 2), _pl(2, 1, 1, 2, 2), _pl(3, 2, 2, 4)]);
    expect(nextFreeBar(p, 1, 0, 2), 4);
    expect(nextFreeBar(p, 1, 5, 1), 5);
    expect(nextFreeBar(p, 2, 3, 2), 5); // 3〜4 は 4 にぶつかる
  });

  test('adjacent placements of the same clip are joined into one block', () {
    final groups = joinedClipGroups([
      _pl(3, 100, 1, 4, 2),
      _pl(1, 100, 1, 0, 2),
      _pl(2, 100, 1, 2, 2), // 0-2, 2-4, 4-6 と隙間なく並ぶ
      _pl(4, 100, 1, 7), // 1小節空くので別ブロック
      _pl(5, 200, 1, 8), // 違うクリップなので別ブロック
    ]);
    expect(groups.length, 3);
    expect(groups[0].map((p) => p.id), [1, 2, 3]);
    expect(groups[1].map((p) => p.id), [4]);
    expect(groups[2].map((p) => p.id), [5]);
  });

  test('overlapping or out-of-order placements are not joined', () {
    final groups = joinedClipGroups([
      _pl(1, 100, 1, 0, 3), // 0-3
      _pl(2, 100, 1, 2, 2), // 2 から始まる（重なっている）のでつながらない
      _pl(3, 100, 1, 4), // 2 の終わり 4 にくっつく
    ]);
    expect(groups.length, 2);
    expect(groups[0].map((p) => p.id), [1]);
    expect(groups[1].map((p) => p.id), [2, 3]);
  });

  test('zoom keeps the bar height within 16..120dp', () {
    expect(barHeightForZoom(1), 40);
    expect(barHeightForZoom(2), 80);
    expect(barHeightForZoom(3), 120);
    expect(barHeightForZoom(10), 120); // 上限
    expect(barHeightForZoom(0.4), 16);
    expect(barHeightForZoom(0.1), 16); // 下限
  });

  test('zoom keeps the column width within 28..320dp', () {
    expect(colWidthForZoom(60, 1), 60);
    expect(colWidthForZoom(60, 2), 120);
    expect(colWidthForZoom(60, 0.3), 28); // 下限（60*0.3=18 → 28）
    expect(colWidthForZoom(90, 4), 320); // 上限（90*4=360 → 320）
    expect(colWidthForZoom(90, 10), 320); // 倍率自体も 4 で止まる
  });

  test('notes are split per bar and repeated when the placement is longer', () {
    const clip = ClipData(id: 1, trackId: 1, lengthTicks: 3840, notes: [
      NoteData(id: 1, tick: 0, length: 480, pitch: 60, velocity: 1),
      NoteData(id: 2, tick: 1920, length: 480, pitch: 64, velocity: 1),
    ]);
    final pl = _pl(1, 1, 1, 3, 2); // 1小節のクリップを2小節ぶん
    final second = notesInBar(clip, pl, 4, 3840).toList();
    expect(second.map((n) => n.tick), [0, 1920]);
    expect(second.map((n) => n.pitch), [60, 64]);
  });

  test('loop range is normalized from either drag direction', () {
    expect(loopRangeBars(8, 15, 56), (start: 8, end: 16));
    expect(loopRangeBars(15, 8, 56), (start: 8, end: 16)); // 逆向きでも同じ
    expect(loopRangeBars(3, 3, 56), (start: 3, end: 4)); // 1小節だけ
  });

  test('loop range is clamped to the song length', () {
    expect(loopRangeBars(-2, 100, 56), (start: 0, end: 56));
    expect(loopRangeBars(60, 70, 56), (start: 55, end: 56));
    expect(loopRangeBars(0, 5, 0), (start: 0, end: 1)); // 長さ0でも最低1小節
  });

  test('loop range converts to engine ticks', () {
    expect(loopRangeTicks(8, 16, 3840), (startTick: 8 * 3840, endTick: 16 * 3840));
    expect(loopRangeTicks(0, 1, 3840), (startTick: 0, endTick: 3840));
  });

  test('follow does nothing while the head is visible', () {
    expect(followScrollTarget(headY: 100, offset: 0, viewportHeight: 300, maxExtent: 2000), isNull);
    expect(followScrollTarget(headY: 299, offset: 0, viewportHeight: 300, maxExtent: 2000), isNull);
    expect(followScrollTarget(headY: 0, offset: 0, viewportHeight: 300, maxExtent: 2000), isNull);
  });

  test('follow pages to the head when it leaves the viewport', () {
    // 下端からはみ出した
    expect(followScrollTarget(headY: 300, offset: 0, viewportHeight: 300, maxExtent: 2000), 300);
    expect(followScrollTarget(headY: 640, offset: 0, viewportHeight: 300, maxExtent: 2000), 640);
    // ループで先頭へ戻った（ヘッドが画面より上）
    expect(followScrollTarget(headY: 40, offset: 600, viewportHeight: 300, maxExtent: 2000), 40);
    // 末尾ではスクロール量の上限に収める
    expect(followScrollTarget(headY: 5000, offset: 0, viewportHeight: 300, maxExtent: 2000), 2000);
  });

  test('edge scroll is still in the middle and fastest at the very edge', () {
    final mid = edgeScrollVelocity(posX: 100, posY: 200, width: 200, height: 400);
    expect(mid.dx, 0);
    expect(mid.dy, 0);
    final corner = edgeScrollVelocity(posX: 0, posY: 400, width: 200, height: 400);
    expect(corner.dx, -420);
    expect(corner.dy, 420);
    // 端から半分（24px）入ったところでは半分の速さ
    final half = edgeScrollVelocity(posX: 24, posY: 376, width: 200, height: 400);
    expect(half.dx, -210);
    expect(half.dy, 210);
    // 画面の外にはみ出しても上限を超えない
    final out = edgeScrollVelocity(posX: -30, posY: 999, width: 200, height: 400);
    expect(out.dx, -420);
    expect(out.dy, 420);
  });
}
