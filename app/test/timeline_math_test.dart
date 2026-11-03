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
}
