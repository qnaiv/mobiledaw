// ドラムキットの置き場（設計：バックログ「ドラムキット」）。
// キットは APK に入れず、GitHub の main にある kits/ からダウンロードして filesDir/kits/<id>/ に置く。
// 一覧は kits/index.json（tools/kits/build_index.py で作る）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _repo = 'qnaiv/mobiledaw';
const _branch = 'main';
String _rawUrl(String path) => 'https://raw.githubusercontent.com/$_repo/$_branch/kits/$path';

class KitSoundInfo {
  const KitSoundInfo(this.name, this.note);
  final String name;
  final int note;
}

/// ダウンロードできるキット（index.json の1行）
class RemoteKit {
  const RemoteKit({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.license,
    required this.description,
    required this.sounds,
    required this.size,
    required this.files,
  });

  final String id, name, author, license, description;
  final int version, sounds, size;
  final List<({String path, int size})> files;

  static RemoteKit? fromJson(Object? j) {
    if (j is! Map<String, Object?> || j['id'] is! String) return null;
    final files = <({String path, int size})>[];
    for (final f in (j['files'] is List<Object?> ? j['files']! as List<Object?> : const <Object?>[])) {
      if (f is Map<String, Object?> && f['path'] is String) {
        files.add((path: f['path']! as String, size: f['size'] is num ? (f['size']! as num).toInt() : -1));
      }
    }
    String str(String k) => j[k] is String ? j[k]! as String : '';
    int intOf(String k) => j[k] is num ? (j[k]! as num).toInt() : 0;
    return RemoteKit(
      id: j['id']! as String,
      name: str('name').isEmpty ? j['id']! as String : str('name'),
      version: intOf('version'),
      author: str('author'),
      license: str('license'),
      description: str('description'),
      sounds: intOf('sounds'),
      size: intOf('size'),
      files: files,
    );
  }
}

/// ダウンロード済みのキット（filesDir/kits/<id>/kit.json）
class InstalledKit {
  const InstalledKit({required this.id, required this.name, required this.version, required this.sounds});
  final String id, name;
  final int version;
  final List<KitSoundInfo> sounds; // 音程の低い順

  List<int> get notes => [for (final s in sounds) s.note];
  Map<int, String> get labels => {for (final s in sounds) s.note: s.name};
}

class KitStore {
  KitStore(String filesDir, {HttpClient? client})
      : root = Directory('$filesDir/kits'),
        _client = client ?? HttpClient();

  final Directory root;
  final HttpClient _client;
  final _installed = <String, InstalledKit?>{};

  static final _idRe = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');

  File get _cachedIndex => File('${root.path}/index.json');

  // ---- ダウンロード済み -----------------------------------------------------------

  InstalledKit? installed(String id) {
    if (!_idRe.hasMatch(id)) return null;
    return _installed.putIfAbsent(id, () => _readInstalled(id));
  }

  List<InstalledKit> installedKits() {
    if (!root.existsSync()) return const [];
    final out = <InstalledKit>[];
    for (final d in root.listSync().whereType<Directory>()) {
      final id = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final k = installed(id);
      if (k != null) out.add(k);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  InstalledKit? _readInstalled(String id) {
    final f = File('${root.path}/$id/kit.json');
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map<String, Object?>) return null;
      final sounds = <KitSoundInfo>[];
      final list = j['sounds'] is List<Object?> ? j['sounds']! as List<Object?> : const <Object?>[];
      for (var i = 0; i < list.length; i++) {
        final s = list[i];
        if (s is! Map<String, Object?>) continue;
        final note = s['note'] is num ? (s['note']! as num).toInt().clamp(0, 127) : 36 + i;
        final name = s['name'] is String ? s['name']! as String : (s['file'] is String ? s['file']! as String : '$note');
        if (!sounds.any((x) => x.note == note)) sounds.add(KitSoundInfo(name, note));
      }
      sounds.sort((a, b) => a.note.compareTo(b.note));
      return InstalledKit(
        id: id,
        name: j['name'] is String ? j['name']! as String : id,
        version: j['version'] is num ? (j['version']! as num).toInt() : 1,
        sounds: sounds,
      );
    } on Object {
      return null;
    }
  }

  void delete(String id) {
    if (!_idRe.hasMatch(id)) return;
    final d = Directory('${root.path}/$id');
    if (d.existsSync()) d.deleteSync(recursive: true);
    _installed.remove(id);
  }

  // ---- ダウンロードできるもの ------------------------------------------------------

  /// 前回取ってきた一覧（オフラインでも出せるように）
  List<RemoteKit> cachedRemote() {
    try {
      return _parseIndex(_cachedIndex.readAsStringSync());
    } on Object {
      return const [];
    }
  }

  /// GitHub から一覧を取ってくる。失敗したら例外
  Future<List<RemoteKit>> fetchRemote() async {
    final body = utf8.decode(await _get(_rawUrl('index.json')));
    final kits = _parseIndex(body);
    root.createSync(recursive: true);
    _cachedIndex.writeAsStringSync(body);
    return kits;
  }

  static List<RemoteKit> _parseIndex(String body) {
    final j = jsonDecode(body);
    if (j is! Map<String, Object?> || j['kits'] is! List<Object?>) throw const FormatException('index.json の形が違います');
    return [
      for (final k in j['kits']! as List<Object?>)
        if (RemoteKit.fromJson(k) case final RemoteKit kit when _idRe.hasMatch(kit.id)) kit,
    ];
  }

  /// キットをダウンロードする（一時フォルダに全部そろってから置き換える）。[onProgress] は 0〜1
  Future<void> download(RemoteKit kit, {void Function(double)? onProgress}) async {
    final tmp = Directory('${root.path}/.${kit.id}.part');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync(recursive: true);
    final total = kit.files.fold<int>(0, (a, f) => a + (f.size > 0 ? f.size : 0));
    var done = 0;
    try {
      for (final f in kit.files) {
        if (f.path.split('/').any((s) => s == '..' || s.isEmpty)) throw FormatException('おかしなファイル名: ${f.path}');
        final url = _rawUrl('${kit.id}/${f.path.split('/').map(Uri.encodeComponent).join('/')}');
        final bytes = await _get(url);
        if (f.size >= 0 && bytes.length != f.size) throw StateError('${f.path} の大きさが合いません');
        final out = File('${tmp.path}/${f.path}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(bytes);
        done += bytes.length;
        if (total > 0) onProgress?.call(done / total);
      }
      final dest = Directory('${root.path}/${kit.id}');
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      tmp.renameSync(dest.path);
      _installed.remove(kit.id);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      rethrow;
    }
  }

  Future<List<int>> _get(String url) async {
    final req = await _client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
    req.headers.set(HttpHeaders.userAgentHeader, 'mobiledaw-app');
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('ダウンロードできませんでした（${res.statusCode}）', uri: Uri.parse(url));
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  }
}
