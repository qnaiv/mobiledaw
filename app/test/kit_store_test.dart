import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/kits/kit_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mdaw_kits'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads installed kits sorted by note, ignores bad ids', () {
    final store = KitStore(tmp.path);
    final dir = Directory('${tmp.path}/kits/test-kit')..createSync(recursive: true);
    File('${dir.path}/kit.json').writeAsStringSync(jsonEncode({
      'name': 'Test',
      'version': 2,
      'sounds': [
        {'file': 'b.wav', 'name': 'Hat', 'note': 42},
        {'file': 'a.wav', 'name': 'Kick', 'note': 36},
        {'file': 'c.wav'}, // note なし → 36 + 2 = 38
      ],
    }));
    final kit = store.installed('test-kit')!;
    expect(kit.name, 'Test');
    expect(kit.version, 2);
    expect(kit.notes, [36, 38, 42]);
    expect(kit.labels[42], 'Hat');
    expect(store.installed('../etc'), isNull);
    expect(store.installedKits().map((k) => k.id), ['test-kit']);
    store.delete('test-kit');
    expect(store.installed('test-kit'), isNull);
  });

  // リポジトリの kits/index.json が読める（アプリが取ってくるのと同じもの）
  test('repository index parses', () {
    final file = File('../kits/index.json');
    if (!file.existsSync()) return;
    final store = KitStore(tmp.path);
    Directory('${tmp.path}/kits').createSync(recursive: true);
    file.copySync('${tmp.path}/kits/index.json');
    final kits = store.cachedRemote();
    expect(kits, isNotEmpty);
    for (final k in kits) {
      expect(k.files.first.path, 'kit.json');
      expect(k.size, greaterThan(0));
    }
  });
}
