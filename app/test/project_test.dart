import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/model/project.dart';

// コアの projectToJson が書く形（core/src/project_json.cpp）
const _json = '''
{
  "format": "mobiledaw-project",
  "version": 1,
  "tempo": 96.0,
  "timeSig": [4, 4],
  "key": {"root": 0, "scale": "minor"},
  "tracks": [
    {
      "id": "8000000000000001",
      "name": "Bass",
      "color": "ffc8f25a",
      "instrument": {"type": "synth", "params": {"cutoffHz": 1200.0, "resonance": 0.9}},
      "mixer": {"gain": 0.7, "pan": -0.5, "mute": false, "solo": true}
    }
  ],
  "clips": [
    {
      "id": "00000000000000aa",
      "trackId": "8000000000000001",
      "lengthTicks": 3840,
      "notes": [
        {"id": "00000000000000b1", "tick": 0, "length": 480, "pitch": 48, "velocity": 0.9},
        {"id": "ffffffffffffffff", "tick": 960, "length": 240, "pitch": 51, "velocity": 0.5}
      ]
    }
  ],
  "placements": [
    {"id": "00000000000000c1", "clipId": "00000000000000aa", "trackId": "8000000000000001", "startBar": 0, "lengthBars": 1},
    {"id": "00000000000000c2", "clipId": "00000000000000aa", "trackId": "8000000000000001", "startBar": 2, "lengthBars": 1}
  ]
}
''';

void main() {
  test('ids round-trip through 64 bits, including the top bit', () {
    for (final s in ['0000000000000001', '8000000000000001', 'ffffffffffffffff', '7fffffffffffffff']) {
      expect(formatId(parseId(s)), s);
    }
    expect(parseId('ffffffffffffffff'), -1);
    expect(parseId('nope'), 0);
    expect(parseId(null), 0);
  });

  test('parses the project written by the core', () {
    final p = ProjectData.parse(_json);
    expect(p.tempo, 96.0);
    expect(p.ticksPerBar, 3840);
    expect(p.lengthBars, 3);

    final track = p.tracks.single;
    expect(formatId(track.id), '8000000000000001');
    expect(track.name, 'Bass');
    expect(track.color, 0xffc8f25a);
    expect(track.synth['cutoffHz'], 1200.0);
    expect(track.mixer.pan, -0.5);
    expect(track.mixer.solo, isTrue);

    final clip = p.clip(parseId('00000000000000aa'))!;
    expect(clip.notes.length, 2);
    expect(clip.notes[1].id, -1);
    expect(clip.notes[1].endTick, 1200);

    expect(p.placementsOn(track.id).length, 2);
    expect(p.placementAt(track.id, 2)?.id, parseId('00000000000000c2'));
    expect(p.placementAt(track.id, 1), isNull);
  });

  test('missing or broken fields fall back to defaults', () {
    final p = ProjectData.parse('{"tracks": [{"id": 5}], "clips": "x"}');
    expect(p.tempo, 120);
    expect(p.tracks.single.id, 0);
    expect(p.clips, isEmpty);
    expect(p.lengthBars, 0);
  });
}
