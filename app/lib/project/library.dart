// 曲の一覧（設計：バックログ「プロジェクトの保存・読み込み（複数の曲）」）。
// 保存先は filesDir/projects/<id>.qdaw/project.json。曲の名前は project.json の title に持つ。
// 最後に開いた曲は projects/lib.json に覚えておき、次の起動でそれを開く。
import 'dart:convert';
import 'dart:io';

class ProjectEntry {
  const ProjectEntry({required this.id, required this.path, required this.title, required this.updated});

  final String id;
  final String path; // project.json
  final String title;
  final DateTime updated;
}

class ProjectLibrary {
  ProjectLibrary(String filesDir) : root = Directory('$filesDir/projects');

  final Directory root;

  File get _meta => File('${root.path}/lib.json');

  String pathFor(String id) => '${root.path}/$id.qdaw/project.json';

  /// [id] の曲ファイルが無ければ [contents] で作る。既にあれば中身には触らない。
  /// 戻り値は「既にあったかどうか」（デモ曲の取り込みで使う）
  bool createIfMissing(String id, String contents) {
    final file = File(pathFor(id));
    if (file.existsSync()) return true;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return false;
  }

  /// project.json のパスから ID を取り出す（一覧の外のパスなら null）
  String? idOf(String path) {
    final dir = File(path).parent;
    final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (dir.parent.path != root.path || !name.endsWith('.qdaw')) return null;
    return name.substring(0, name.length - '.qdaw'.length);
  }

  /// 新しい曲の ID（時刻から作る。重なったら番号をつける）
  String newId() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = 'song-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var id = base;
    for (var i = 2; Directory('${root.path}/$id.qdaw').existsSync(); i++) {
      id = '$base-$i';
    }
    return id;
  }

  /// 作った曲。新しく保存した順
  List<ProjectEntry> list() {
    if (!root.existsSync()) return const [];
    final out = <ProjectEntry>[];
    for (final dir in root.listSync().whereType<Directory>()) {
      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!name.endsWith('.qdaw')) continue;
      final file = File('${dir.path}/project.json');
      if (!file.existsSync()) continue;
      out.add(ProjectEntry(
        id: name.substring(0, name.length - '.qdaw'.length),
        path: file.path,
        title: readTitle(file.path),
        updated: file.lastModifiedSync(),
      ));
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  static String readTitle(String path) {
    try {
      final j = jsonDecode(File(path).readAsStringSync());
      if (j is Map<String, Object?> && j['title'] is String && (j['title']! as String).trim().isNotEmpty) {
        return j['title']! as String;
      }
    } on Object {
      // 読めないファイルは名前なしで並べる
    }
    return '無題の曲';
  }

  /// 開いていない曲の名前を変える（開いている曲は SongController.renameSong で Undo できる形に）
  void rename(String id, String title) {
    final file = File(pathFor(id));
    final j = jsonDecode(file.readAsStringSync());
    if (j is! Map<String, Object?>) return;
    j['title'] = title.trim();
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(j));
  }

  /// 曲を丸ごと複製する。新しい ID を返す
  String duplicate(String id, {String? title}) {
    final copy = newId();
    final from = Directory('${root.path}/$id.qdaw');
    final to = Directory('${root.path}/$copy.qdaw')..createSync(recursive: true);
    for (final e in from.listSync(recursive: true)) {
      final rel = e.path.substring(from.path.length);
      if (e is Directory) {
        Directory('${to.path}$rel').createSync(recursive: true);
      } else if (e is File) {
        e.copySync('${to.path}$rel');
      }
    }
    rename(copy, title ?? '${readTitle(pathFor(id))} のコピー');
    return copy;
  }

  void delete(String id) {
    final dir = Directory('${root.path}/$id.qdaw');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    if (lastOpened == id) lastOpened = null;
  }

  String? get lastOpened {
    try {
      final j = jsonDecode(_meta.readAsStringSync());
      return j is Map<String, Object?> && j['lastOpened'] is String ? j['lastOpened']! as String : null;
    } on Object {
      return null;
    }
  }

  set lastOpened(String? id) {
    try {
      root.createSync(recursive: true);
      _meta.writeAsStringSync(jsonEncode({'lastOpened': id}));
    } on Object {
      // 覚えられなくても困らない（次の起動で一番新しい曲を開く）
    }
  }

  /// 起動時に開く曲：最後に開いた曲 → 一番新しい曲 → 新しい ID
  String initialPath() {
    final last = lastOpened;
    if (last != null && File(pathFor(last)).existsSync()) return pathFor(last);
    final all = list();
    if (all.isNotEmpty) return all.first.path;
    return pathFor(newId());
  }
}

/// ファイル名に使えない文字を置き換える
String safeFileName(String name) {
  final s = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  return s.isEmpty ? 'song' : (s.length > 60 ? s.substring(0, 60) : s);
}
