import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobiledaw/project/library.dart';
import 'package:mobiledaw/project/project_transfer.dart';

void main() {
  late Directory tmp;
  late ProjectLibrary libA;
  late ProjectLibrary libB;

  const projectJson = '{"format":"mobiledaw-project","version":1,"title":"往復テスト曲","tracks":[]}';
  final sampleBytes = [0, 1, 2, 3, 250, 251, 252];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mdaw_transfer');
    libA = ProjectLibrary('${tmp.path}/a');
    libB = ProjectLibrary('${tmp.path}/b');
    // A 側にプロジェクトを1つ作る（project.json ＋ 同梱ファイル）
    final f = File(libA.pathFor('song-a'))..createSync(recursive: true);
    f.writeAsStringSync(projectJson);
    final sample = File('${f.parent.path}/samples/demo.wav');
    sample.parent.createSync(recursive: true);
    sample.writeAsBytesSync(sampleBytes);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<List<int>> exportA() async {
    final out = File('${tmp.path}/out.mdawproj');
    await writeProjectFile(library: libA, id: 'song-a', target: out, appBuild: 42, now: DateTime.utc(2026, 11, 12, 3, 0));
    return out.readAsBytesSync();
  }

  test('zip の中身：manifest と project.json と同梱ファイル', () async {
    final bytes = await exportA();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = [for (final f in archive) if (f.isFile) f.name];
    expect(names, containsAll(['manifest.json', 'project.json', 'samples/demo.wav']));

    final manifest = readProjectManifest(bytes);
    expect(manifest, isNotNull);
    expect(manifest!.version, projectFormatVersion);
    expect(manifest.title, '往復テスト曲');
    expect(manifest.appBuild, 42);
    expect(manifest.exportedAt, DateTime.utc(2026, 11, 12, 3, 0));

    final pj = archive.firstWhere((f) => f.name == 'project.json');
    expect(utf8.decode(pj.content as List<int>), projectJson);
  });

  test('ラウンドトリップ：取り込んだプロジェクトは同一になる', () async {
    final bytes = await exportA();
    final entry = importProjectArchive(libB, bytes);
    expect(entry.title, '往復テスト曲');
    expect(File(entry.path).readAsStringSync(), projectJson);
    expect(File('${File(entry.path).parent.path}/samples/demo.wav').readAsBytesSync(), sampleBytes);
    expect(libB.list().map((e) => e.id), contains(entry.id));

    // 取り込んだものをさらに書き出しても project.json は変わらない
    final out2 = File('${tmp.path}/out2.mdawproj');
    await writeProjectFile(library: libB, id: entry.id, target: out2);
    final archive2 = ZipDecoder().decodeBytes(out2.readAsBytesSync());
    final pj2 = archive2.firstWhere((f) => f.name == 'project.json');
    expect(utf8.decode(pj2.content as List<int>), projectJson);
  });

  test('同名は「（取り込み）」を付けて取り込む', () async {
    final bytes = await exportA();
    final first = importProjectArchive(libB, bytes);
    final second = importProjectArchive(libB, bytes);
    final third = importProjectArchive(libB, bytes);
    expect(first.title, '往復テスト曲');
    expect(second.title, '往復テスト曲（取り込み）');
    expect(third.title, '往復テスト曲（取り込み2）');
    expect(ProjectLibrary.readTitle(second.path), '往復テスト曲（取り込み）');
    // 中身の title 以外は同一
    final j = jsonDecode(File(third.path).readAsStringSync()) as Map<String, Object?>;
    expect(j['tracks'], isEmpty);
  });

  test('壊れたファイル・project.json の無い zip・新しい形式版は弾く', () async {
    expect(() => importProjectArchive(libB, [1, 2, 3]), throwsA(isA<ProjectTransferException>()));

    final noProject = Archive()..addFile(ArchiveFile('readme.txt', 3, [1, 2, 3]));
    expect(() => importProjectArchive(libB, ZipEncoder().encode(noProject)!),
        throwsA(isA<ProjectTransferException>()));

    final future = Archive();
    final mb = utf8.encode(jsonEncode(
        {'format': 'mdawproj', 'version': projectFormatVersion + 1, 'title': 'x', 'exportedAt': '2027-01-01T00:00:00Z', 'appBuild': 1}));
    future.addFile(ArchiveFile('manifest.json', mb.length, mb));
    final pb = utf8.encode(projectJson);
    future.addFile(ArchiveFile('project.json', pb.length, pb));
    expect(() => importProjectArchive(libB, ZipEncoder().encode(future)!),
        throwsA(isA<ProjectTransferException>()));
    expect(libB.list(), isEmpty);
  });

  test('フォルダごと zip された形も取り込める／パストラバーサルは書き込まない', () async {
    final a = Archive();
    final pb = utf8.encode(projectJson);
    a.addFile(ArchiveFile('song-x.qdaw/project.json', pb.length, pb));
    final evil = utf8.encode('evil');
    a.addFile(ArchiveFile('../evil.txt', evil.length, evil));
    final entry = importProjectArchive(libB, ZipEncoder().encode(a)!);
    expect(entry.title, '往復テスト曲');
    expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
    expect(File('${Directory(entry.path).parent.path}/evil.txt').existsSync(), isFalse);
  });
}
