import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/kits/kit_gate.dart';
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

  test('kits used in a project, and which are missing', () {
    final json = jsonEncode({
      'tracks': [
        {'instrument': {'type': 'synth'}},
        {'instrument': {'type': 'kit', 'kit': 'future-bass'}},
        {'instrument': {'type': 'kit', 'kit': 'future-bass'}},
        {'instrument': {'type': 'kit', 'kit': 'trap'}},
      ],
    });
    expect(kitsInProjectJson(json)..sort(), ['future-bass', 'trap']);
    expect(kitsInProjectJson('broken'), isEmpty);
    final store = KitStore(tmp.path);
    final d = Directory('${tmp.path}/kits/trap')..createSync(recursive: true);
    File('${d.path}/kit.json').writeAsStringSync(jsonEncode({'name': 'Trap', 'sounds': [{'file': 'a.wav'}]}));
    expect(missingKits(store, ['future-bass', 'trap']), ['future-bass']);
  });

  test('bundled demo uses the future-bass kit', () {
    final f = File('assets/demos/future_bass.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['future-bass']);
  });

  test('bundled kawaii2 demo uses the future-bass-pro kit', () {
    final f = File('assets/demos/kawaii2.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['future-bass-pro']);
  });

  test('bundled house demo uses the house kit', () {
    final f = File('assets/demos/house.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['house']);
  });

  test('bundled lofi demo uses the lofi-boombap kit', () {
    final f = File('assets/demos/lofi.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['lofi-boombap']);
  });

  test('bundled rnb demo uses the acoustic-live kit', () {
    final f = File('assets/demos/rnb.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['acoustic-live']);
  });

  test('bundled technopop demo uses the house kit', () {
    final f = File('assets/demos/technopop.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['house']);
  });

  test('bundled rock demo uses the acoustic-live kit', () {
    final f = File('assets/demos/rock.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['acoustic-live']);
  });

  test('bundled buruaka demos use future-bass-pro and the oneshot kit', () {
    for (final name in ['buruaka.json', 'buruaka_inst.json']) {
      final f = File('assets/demos/$name');
      if (!f.existsSync()) return;
      expect(kitsInProjectJson(f.readAsStringSync()), containsAll(['future-bass-pro', 'kawaii-oneshots']));
    }
  });

  test('bundled electronica demo uses the future-bass-pro kit', () {
    final f = File('assets/demos/electronica.json');
    if (!f.existsSync()) return;
    expect(kitsInProjectJson(f.readAsStringSync()), ['future-bass-pro']);
  });
}
