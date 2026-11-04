import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/export/midi.dart';
import 'package:mobiledaw/model/project.dart';

ProjectData _project() => ProjectData.parse(jsonEncode({
      'title': 'テスト',
      'tempo': 150,
      'timeSig': [4, 4],
      'tracks': [
        {'id': '0000000000000001', 'name': 'Keys', 'color': 'ffffffff', 'instrument': {'params': {}}},
      ],
      'clips': [
        {
          'id': '0000000000000002',
          'trackId': '0000000000000001',
          'lengthTicks': 3840,
          'notes': [
            {'id': '0000000000000003', 'tick': 0, 'length': 960, 'pitch': 60, 'velocity': 1.0},
            {'id': '0000000000000004', 'tick': 1920, 'length': 960, 'pitch': 64, 'velocity': 0.5},
          ],
        },
      ],
      'placements': [
        // 2小節の配置に1小節のクリップ → 2回くり返す
        {'id': '0000000000000005', 'clipId': '0000000000000002', 'trackId': '0000000000000001', 'startBar': 1, 'lengthBars': 2},
      ],
    }));

void main() {
  test('header, tempo and notes', () {
    final bytes = buildMidi(_project());
    expect(ascii.decode(bytes.sublist(0, 4)), 'MThd');
    final view = ByteData.sublistView(bytes);
    expect(view.getUint16(8), 1); // タイプ1
    expect(view.getUint16(10), 2); // テンポのトラック＋Keys
    expect(view.getUint16(12), 960);

    // テンポ 150 BPM = 400000 µs/拍
    final s = bytes.toList();
    final tempoAt = _indexOf(s, [0xFF, 0x51, 0x03]);
    expect(tempoAt, greaterThan(0));
    expect((s[tempoAt + 3] << 16) | (s[tempoAt + 4] << 8) | s[tempoAt + 5], 400000);

    // ノートオンは 4回（2音 × 2回）。最初は 2小節目の頭（delta = 3840）
    final noteOns = <int>[];
    for (var i = 0; i + 2 < s.length; i++) {
      if (s[i] == 0x90 && (s[i + 1] == 60 || s[i + 1] == 64) && s[i + 2] > 0) noteOns.add(s[i + 2]);
    }
    expect(noteOns, [127, 64, 127, 64]);
    final keys = _indexOf(s, utf8.encode('Keys'));
    expect(keys, greaterThan(0));
  });
}

int _indexOf(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = hay[i + j] == needle[j];
    }
    if (ok) return i;
  }
  return -1;
}
