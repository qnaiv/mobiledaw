// プロジェクトの書き出し／取り込み（設計：Windows 版とのファイル互換）。
// 1プロジェクト＝ .qdaw フォルダ一式を zip にまとめた .mdawproj ファイル。
// 中身の project.json は内部保存形式そのままで、独自の変換はしない。
// zip の先頭には manifest.json（形式・版・曲名・書き出し日時・書き出し元ビルド）を置く。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'library.dart';

/// ファイルの拡張子（中身は通常の zip）
const projectFileExtension = 'mdawproj';

/// .mdawproj の形式バージョン。互換を壊す変更をしたら上げる
const projectFormatVersion = 1;

/// manifest.json の format フィールド
const _formatTag = 'mdawproj';

/// 取り込みできないファイルだったときの理由（利用者向け文言を持つ）
class ProjectTransferException implements Exception {
  const ProjectTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// manifest.json の中身
class ProjectManifest {
  const ProjectManifest({
    required this.version,
    required this.title,
    required this.exportedAt,
    required this.appBuild,
  });

  final int version;
  final String title;
  final DateTime exportedAt;
  final int appBuild; // 書き出し元アプリのビルド番号（手元ビルドは 0）

  Map<String, Object?> toJson() => {
        'format': _formatTag,
        'version': version,
        'app': 'mobiledaw',
        'appBuild': appBuild,
        'title': title,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
      };

  /// 読めなければ null（manifest が無い・壊れている zip は project.json 側で判断する）
  static ProjectManifest? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    if (j['format'] != _formatTag) return null;
    return ProjectManifest(
      version: j['version'] is int ? j['version']! as int : 0,
      title: j['title'] is String ? j['title']! as String : '',
      exportedAt: DateTime.tryParse(j['exportedAt'] is String ? j['exportedAt']! as String : '') ?? DateTime.utc(1970),
      appBuild: j['appBuild'] is int ? j['appBuild']! as int : 0,
    );
  }
}

/// [library] の [id] のプロジェクトを .mdawproj として [target] に書く。
/// .qdaw フォルダ内の全ファイル（project.json と、同梱ファイルがあればそれも）を含む。
Future<File> writeProjectFile({
  required ProjectLibrary library,
  required String id,
  required File target,
  int appBuild = 0,
  DateTime? now,
}) async {
  final jsonPath = library.pathFor(id);
  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) {
    throw const ProjectTransferException('プロジェクトの保存データが見つかりません');
  }
  final dir = jsonFile.parent;
  final title = ProjectLibrary.readTitle(jsonPath);
  final manifest = ProjectManifest(
    version: projectFormatVersion,
    title: title,
    exportedAt: now ?? DateTime.now(),
    appBuild: appBuild,
  );

  final archive = Archive();
  final manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
  archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  final files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final rel = f.path.substring(dir.path.length).replaceAll(Platform.pathSeparator, '/').replaceFirst(RegExp(r'^/'), '');
    if (rel.isEmpty || rel == 'manifest.json') continue; // こちらの manifest を正とする
    final bytes = await f.readAsBytes();
    archive.addFile(ArchiveFile(rel, bytes.length, bytes));
  }
  final zipBytes = ZipEncoder().encode(archive)!;
  await target.parent.create(recursive: true);
  await target.writeAsBytes(zipBytes, flush: true);
  return target;
}

/// .mdawproj のバイト列から manifest を読む（無ければ null）
ProjectManifest? readProjectManifest(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    return null;
  }
  for (final f in archive) {
    if (f.isFile && f.name == 'manifest.json') {
      try {
        return ProjectManifest.fromJson(jsonDecode(utf8.decode(f.content as List<int>)));
      } on Object {
        return null;
      }
    }
  }
  return null;
}

/// .mdawproj（または project.json を含む zip）を取り込み、新しいプロジェクトとして登録する。
/// 同じ名前の曲が既にある場合は「（取り込み）」「（取り込み2）」…を付けて別名にする。
/// 取り込めないファイルは [ProjectTransferException] を投げる。
ProjectEntry importProjectArchive(ProjectLibrary library, List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const ProjectTransferException('ファイルが壊れているか、zip 形式ではありません');
  }

  // manifest があれば形式と版を確認する（無い zip は project.json の有無だけで判断）
  ArchiveFile? manifestFile;
  ArchiveFile? projectFile;
  for (final f in archive) {
    if (!f.isFile) continue;
    if (f.name == 'manifest.json') manifestFile = f;
    if (f.name == 'project.json') projectFile = f;
  }
  var prefix = '';
  if (projectFile == null) {
    // フォルダごと zip された形（<何か>/project.json）も受け付ける
    for (final f in archive) {
      if (f.isFile && f.name.endsWith('/project.json')) {
        projectFile = f;
        prefix = f.name.substring(0, f.name.length - 'project.json'.length);
        break;
      }
    }
  }
  if (projectFile == null) {
    throw const ProjectTransferException('プロジェクトのデータ（project.json）が入っていません');
  }
  if (manifestFile != null) {
    final m = ProjectManifest.fromJson(_tryJson(manifestFile));
    if (m == null) {
      throw const ProjectTransferException('対応していない形式のファイルです');
    }
    if (m.version > projectFormatVersion) {
      throw const ProjectTransferException('新しいバージョンのアプリで書き出されたファイルです。アプリを更新してください');
    }
  }

  // project.json が JSON オブジェクトとして読めることを先に確認する
  final projectBytes = projectFile.content as List<int>;
  final decoded = _tryJsonBytes(projectBytes);
  if (decoded is! Map<String, Object?>) {
    throw const ProjectTransferException('プロジェクトのデータが読めませんでした');
  }

  // 同名の曲があれば取り込み名を決める（project.json の title を書き換える）
  var title = decoded['title'] is String && (decoded['title']! as String).trim().isNotEmpty
      ? (decoded['title']! as String).trim()
      : '無題の曲';
  final existing = {for (final e in library.list()) e.title};
  var writeBytes = projectBytes;
  if (existing.contains(title)) {
    var candidate = '$title（取り込み）';
    for (var i = 2; existing.contains(candidate); i++) {
      candidate = '$title（取り込み$i）';
    }
    title = candidate;
    decoded['title'] = title;
    writeBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(decoded));
  }

  // 新しい ID のフォルダへ展開する。パストラバーサル（.. や絶対パス）は書き込まない
  final id = library.newId();
  final dir = Directory('${library.root.path}/$id.qdaw');
  try {
    dir.createSync(recursive: true);
    for (final f in archive) {
      if (!f.isFile) continue;
      if (prefix.isNotEmpty && !f.name.startsWith(prefix)) continue;
      final rel = prefix.isEmpty ? f.name : f.name.substring(prefix.length);
      if (rel.isEmpty || rel == 'manifest.json') continue;
      if (!_isSafeRelativePath(rel)) continue;
      final out = File('${dir.path}/$rel');
      if (rel == 'project.json') {
        out.writeAsBytesSync(writeBytes, flush: true);
      } else {
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(f.content as List<int>, flush: true);
      }
    }
    if (!File('${dir.path}/project.json').existsSync()) {
      throw const ProjectTransferException('プロジェクトのデータが読めませんでした');
    }
  } on ProjectTransferException {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    rethrow;
  } on Object {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    throw const ProjectTransferException('取り込みに失敗しました');
  }

  return ProjectEntry(id: id, path: library.pathFor(id), title: title, updated: File(library.pathFor(id)).lastModifiedSync());
}

Object? _tryJson(ArchiveFile f) {
  try {
    return jsonDecode(utf8.decode(f.content as List<int>));
  } on Object {
    return null;
  }
}

Object? _tryJsonBytes(List<int> bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on Object {
    return null;
  }
}

/// zip 内の相対パスとして安全か（.. ・絶対パス・ドライブ指定を弾く）
bool _isSafeRelativePath(String rel) {
  if (rel.startsWith('/') || rel.contains('\\') || rel.contains(':')) return false;
  for (final seg in rel.split('/')) {
    if (seg == '..' || seg.isEmpty) return false;
  }
  return true;
}
