import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/project/library.dart';

void main() {
  late Directory tmp;
  late ProjectLibrary lib;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mdaw_lib');
    lib = ProjectLibrary(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String id, String title) {
    final f = File(lib.pathFor(id))..createSync(recursive: true);
    f.writeAsStringSync(jsonEncode({'format': 'mobiledaw-project', 'version': 1, 'title': title}));
  }

  test('list, rename, duplicate, delete, last opened', () {
    expect(lib.list(), isEmpty);
    expect(lib.idOf(lib.initialPath()), startsWith('song-'));

    write('untitled-01', '');
    write('b', 'ボカロ曲');
    expect(lib.list().map((e) => e.title), containsAll(['無題の曲', 'ボカロ曲']));
    expect(lib.idOf(lib.pathFor('b')), 'b');
    expect(lib.idOf('/somewhere/else/project.json'), isNull);

    lib.rename('b', '  サビ案  ');
    expect(ProjectLibrary.readTitle(lib.pathFor('b')), 'サビ案');

    final copy = lib.duplicate('b');
    expect(ProjectLibrary.readTitle(lib.pathFor(copy)), 'サビ案 のコピー');
    expect(lib.list().length, 3);

    lib.lastOpened = 'b';
    expect(lib.initialPath(), lib.pathFor('b'));
    lib.delete('b');
    expect(lib.lastOpened, isNull);
    expect(lib.list().length, 2);
    expect(File(lib.initialPath()).existsSync(), isTrue); // 残っている曲を開く
  });

  test('safe file names', () {
    expect(safeFileName('a/b:c?'), 'a_b_c_');
    expect(safeFileName('   '), 'song');
    expect(safeFileName('kawaii フューチャーベース'), 'kawaii フューチャーベース');
  });
}
