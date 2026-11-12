// アプリ内アップデート。
// CI は main に push するたびに GitHub のリリース（タグ build-<番号>）へ mobiledaw.apk を置く。
// アプリは最新リリースの番号と自分のビルド番号を比べ、新しければダウンロードしてインストーラーに渡す。
// 署名鍵が毎回同じなので、アンインストールせずに上書きでインストールできる。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// CI が --dart-define=MDAW_BUILD=<実行番号> で埋め込む。手元のビルドでは 0
const int currentBuild = int.fromEnvironment('MDAW_BUILD');

const String _repo = 'qnaiv/mobiledaw';
const String _apkName = 'mobiledaw.apk';
const MethodChannel _channel = MethodChannel('mobiledaw/updater'); // MainActivity と揃える

class UpdateInfo {
  const UpdateInfo({required this.build, required this.apkUrl, required this.notes, required this.size});

  final int build;
  final String apkUrl;
  final String notes; // コミットメッセージの1行目など
  final int size; // バイト

  /// GitHub の「最新リリース」API の応答から読む。必要なものが無ければ null
  static UpdateInfo? fromRelease(Map<String, Object?> json) {
    final tag = json['tag_name'];
    final match = tag is String ? RegExp(r'^build-(\d+)$').firstMatch(tag) : null;
    if (match == null) return null;
    final assets = json['assets'] is List ? json['assets']! as List<Object?> : const <Object?>[];
    for (final a in assets.whereType<Map<String, Object?>>()) {
      final url = a['browser_download_url'];
      if (a['name'] == _apkName && url is String) {
        final body = json['body'];
        return UpdateInfo(
          build: int.parse(match.group(1)!),
          apkUrl: url,
          notes: body is String ? body.trim() : '',
          size: a['size'] is int ? a['size']! as int : 0,
        );
      }
    }
    return null;
  }
}

/// インストールを始められたか
enum InstallResult { started, needsPermission, failed }

class Updater {
  Updater({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  /// 新しい版があればその情報、無ければ（または確かめられなければ）null。
  /// アップデートは APK のインストールなので Android だけ。Windows などでは
  /// リリースに mobiledaw.apk があっても絶対に拾わない（チャネルも無い）。
  Future<UpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final req = await _client
          .getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
          .timeout(const Duration(seconds: 10));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'mobiledaw-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      final info = decoded is Map<String, Object?> ? UpdateInfo.fromRelease(decoded) : null;
      return info != null && info.build > currentBuild ? info : null;
    } on Object {
      return null; // オフラインなど。アップデートの確認は黙って諦める
    }
  }

  /// APK をダウンロードしてファイルの場所を返す。[onProgress] は 0〜1
  Future<String> download(UpdateInfo info, {void Function(double progress)? onProgress}) async {
    final dir = await _channel.invokeMethod<String>('updatesDir');
    if (dir == null) throw StateError('保存先を用意できませんでした');
    // 古いダウンロードは消しておく
    for (final f in Directory(dir).listSync().whereType<File>()) {
      f.deleteSync();
    }
    final file = File('$dir/mobiledaw-${info.build}.apk');

    final req = await _client.getUrl(Uri.parse(info.apkUrl)); // GitHub はファイル置き場へリダイレクトする
    req.headers.set(HttpHeaders.userAgentHeader, 'mobiledaw-app');
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('ダウンロードに失敗しました（${res.statusCode}）');
    }
    final total = res.contentLength > 0 ? res.contentLength : info.size;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    return file.path;
  }

  Future<InstallResult> install(String apkPath) async {
    final r = await _channel.invokeMethod<String>('installApk', {'path': apkPath});
    return switch (r) {
      'started' => InstallResult.started,
      'needsPermission' => InstallResult.needsPermission,
      _ => InstallResult.failed,
    };
  }
}
