import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/arrange/demo_song.dart';
import 'package:mobiledaw/project/library.dart';

// デモ曲の取り込み（SongController.loadDemo）が使う ID と createIfMissing の検証。
// loadDemo 自体はエンジン（FFI）が要るので、ここではライブラリ層で
// 「同じデモを何度取り込んでも一覧が増えず、編集が残る」ことを確かめる。
void main() {
  late Directory tmp;
  late ProjectLibrary lib;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mdaw_demo');
    lib = ProjectLibrary(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('デモの ID はデモごとに固定で、重ならない', () {
    for (final d in DemoSong.values) {
      expect(demoProjectId(d), 'demo-${d.name}');
    }
    expect(DemoSong.values.map(demoProjectId).toSet().length, DemoSong.values.length);
    // 通常の曲の ID（song-…）とは混ざらない
    expect(lib.idOf(lib.pathFor(demoProjectId(DemoSong.house))), 'demo-house');
  });

  test('同じデモを2回取り込んでも一覧は増えず、編集が残る', () {
    const bundled = '{"title":"デモ：ハウス","tracks":[]}';
    // 1回目：無ければ書き出す（loadDemo と同じ手順）
    expect(lib.createIfMissing(demoProjectId(DemoSong.house), bundled), isFalse);
    expect(lib.list().length, 1);

    // ユーザーがそのデモを編集した想定
    File(lib.pathFor(demoProjectId(DemoSong.house)))
        .writeAsStringSync('{"title":"デモ：ハウス","tracks":[],"edited":true}');

    // 2回目：既にあるので中身には触らない
    expect(lib.createIfMissing(demoProjectId(DemoSong.house), bundled), isTrue);
    expect(lib.list().length, 1);
    expect(lib.list().single.id, 'demo-house');
    expect(File(lib.pathFor(demoProjectId(DemoSong.house))).readAsStringSync(), contains('edited'));
  });

  test('別のデモは別の曲として入る', () {
    lib.createIfMissing(demoProjectId(DemoSong.house), '{}');
    lib.createIfMissing(demoProjectId(DemoSong.lofi), '{}');
    expect(lib.list().map((e) => e.id), containsAll(['demo-house', 'demo-lofi']));
  });
}
